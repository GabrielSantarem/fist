import fist/internal/path
import fist/internal/types.{
  type Node, type Router, Node, Route, Router, empty_node, new_router,
}
import gleam/dict.{type Dict}
import gleam/http.{type Method}
import gleam/http/request.{type Request}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

/// Recursively inserts a route into the Trie.
/// Panics if an identical route already exists, if dynamic/wildcard names conflict,
/// or if a wildcard is placed non-terminally.
pub fn insert_route(
  node: Node(req_body, ctx, output),
  segments: List(String),
  handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Node(req_body, ctx, output) {
  case segments {
    [] -> {
      case node.route {
        Some(_) ->
          panic as "Route collision: duplicate route already registered for this method and path"
        None -> {
          let new_route = Route(handler: handler, description: None)
          Node(..node, route: Some(new_route))
        }
      }
    }

    ["*" <> raw_name, ..rest] -> {
      case rest {
        [_, ..] ->
          panic as string.concat([
              "Invalid route: wildcard '*",
              raw_name,
              "' must be the final segment of the path",
            ])
        [] -> {
          let param_name = case raw_name {
            "" -> "wildcard"
            _ -> raw_name
          }
          case node.wildcard_child {
            Some(#(existing_name, _)) ->
              panic as string.concat([
                  "Route collision: cannot register wildcard '*",
                  param_name,
                  "' because '*",
                  existing_name,
                  "' is already registered at this path level",
                ])
            None -> {
              let new_route = Route(handler: handler, description: None)
              Node(..node, wildcard_child: Some(#(param_name, new_route)))
            }
          }
        }
      }
    }

    [":" <> param_name, ..rest] -> {
      case param_name {
        "" ->
          panic as "Invalid route: dynamic parameter name cannot be empty (e.g. use ':id' instead of ':')"
        _ -> Nil
      }
      let child = case node.dynamic_child {
        Some(#(existing_name, child_node)) -> {
          case existing_name == param_name {
            True -> child_node
            False ->
              panic as string.concat([
                  "Route collision: cannot register dynamic segment ':",
                  param_name,
                  "' because ':",
                  existing_name,
                  "' is already registered at this path level",
                ])
          }
        }
        None -> empty_node()
      }
      let updated_child = insert_route(child, rest, handler)
      Node(..node, dynamic_child: Some(#(param_name, updated_child)))
    }

    [segment, ..rest] -> {
      let child =
        dict.get(node.static_children, segment) |> result.unwrap(empty_node())
      let updated_child = insert_route(child, rest, handler)
      Node(
        ..node,
        static_children: dict.insert(
          node.static_children,
          segment,
          updated_child,
        ),
      )
    }
  }
}

/// Recursively updates a specific route node to add a description.
pub fn update_description(
  node: Node(req_body, ctx, output),
  segments: List(String),
  desc: String,
) -> Node(req_body, ctx, output) {
  case segments {
    [] -> {
      case node.route {
        Some(r) ->
          Node(..node, route: Some(Route(..r, description: Some(desc))))
        None -> node
      }
    }

    ["*" <> _, ..] -> {
      case node.wildcard_child {
        Some(#(p, r)) -> {
          let updated_r = Route(..r, description: Some(desc))
          Node(..node, wildcard_child: Some(#(p, updated_r)))
        }
        None -> node
      }
    }

    [":" <> _, ..rest] -> {
      case node.dynamic_child {
        Some(#(p, child)) -> {
          let updated = update_description(child, rest, desc)
          Node(..node, dynamic_child: Some(#(p, updated)))
        }
        None -> node
      }
    }

    [segment, ..rest] -> {
      case dict.get(node.static_children, segment) {
        Ok(child) -> {
          let updated = update_description(child, rest, desc)
          Node(
            ..node,
            static_children: dict.insert(node.static_children, segment, updated),
          )
        }
        Error(_) -> node
      }
    }
  }
}

/// Recursively traverses the Trie to find a matching handler.
/// Follows strict precedence: Static > Dynamic (:param) > Wildcard (*catch_all),
/// with full backtracking support.
pub fn find_route(
  node: Node(req_body, ctx, output),
  segments: List(String),
  params: Dict(String, String),
) -> Result(
  #(
    fn(Request(req_body), ctx, Dict(String, String)) -> output,
    Dict(String, String),
  ),
  Nil,
) {
  case segments {
    [] -> {
      case node.route {
        Some(r) -> Ok(#(r.handler, params))
        None -> Error(Nil)
      }
    }

    [segment, ..rest] -> {
      // 1. Try static match
      let static_result = case dict.get(node.static_children, segment) {
        Ok(child) -> find_route(child, rest, params)
        Error(Nil) -> Error(Nil)
      }

      // 2. If static failed, try dynamic segment match (:param)
      let dynamic_result = case static_result {
        Ok(match) -> Ok(match)
        Error(Nil) -> {
          case node.dynamic_child {
            Some(#(param_name, child)) -> {
              let new_params = dict.insert(params, param_name, segment)
              find_route(child, rest, new_params)
            }
            None -> Error(Nil)
          }
        }
      }

      // 3. If dynamic match failed, backtrack to wildcard catch-all (*param)
      case dynamic_result {
        Ok(match) -> Ok(match)
        Error(Nil) -> {
          case node.wildcard_child {
            Some(#(param_name, route)) -> {
              let wildcard_val = string.join(segments, "/")
              let final_params = dict.insert(params, param_name, wildcard_val)
              Ok(#(route.handler, final_params))
            }
            None -> Error(Nil)
          }
        }
      }
    }
  }
}

/// Recursively merges two nodes.
/// Panics if both nodes define a route, if dynamic parameter names conflict,
/// or if wildcards conflict at the same level.
pub fn merge_nodes(
  a: Node(req, ctx, out),
  b: Node(req, ctx, out),
) -> Node(req, ctx, out) {
  let route = case a.route, b.route {
    Some(_), Some(_) ->
      panic as "Route collision: duplicate route found while merging routers"
    Some(r_a), None -> Some(r_a)
    None, Some(r_b) -> Some(r_b)
    None, None -> None
  }

  let static_children =
    dict.combine(a.static_children, b.static_children, merge_nodes)

  let dynamic_child = case a.dynamic_child, b.dynamic_child {
    Some(#(name_a, child_a)), Some(#(name_b, child_b)) -> {
      case name_a == name_b {
        True -> Some(#(name_a, merge_nodes(child_a, child_b)))
        False ->
          panic as string.concat([
              "Route collision: cannot merge dynamic segments ':",
              name_a,
              "' and ':",
              name_b,
              "' at the same path level",
            ])
      }
    }
    None, some_b -> some_b
    some_a, None -> some_a
  }

  let wildcard_child = case a.wildcard_child, b.wildcard_child {
    Some(#(name_a, _)), Some(#(name_b, _)) -> {
      panic as string.concat([
          "Route collision: cannot merge wildcards '*",
          name_a,
          "' and '*",
          name_b,
          "' at the same path level",
        ])
    }
    None, some_b -> some_b
    some_a, None -> some_a
  }

  Node(route, static_children, dynamic_child, wildcard_child)
}

/// Creates a new tree from a list of segments that leads to the given sub-tree.
/// Panics if a wildcard is placed in the prefix path or if dynamic parameter name is empty.
pub fn prefix_node(
  segments: List(String),
  sub_tree: Node(req, ctx, out),
) -> Node(req, ctx, out) {
  case segments {
    [] -> sub_tree
    ["*" <> param_name, ..] ->
      panic as string.concat([
          "Invalid prefix: wildcard '*",
          param_name,
          "' cannot be used in a route prefix",
        ])
    [":" <> param_name, ..rest] -> {
      case param_name {
        "" ->
          panic as "Invalid route: dynamic parameter name cannot be empty in prefix (e.g. use ':id' instead of ':')"
        _ -> Nil
      }
      let child = prefix_node(rest, sub_tree)
      let empty = empty_node()
      Node(..empty, dynamic_child: Some(#(param_name, child)))
    }
    [segment, ..rest] -> {
      let child = prefix_node(rest, sub_tree)
      let empty = empty_node()
      Node(..empty, static_children: dict.from_list([#(segment, child)]))
    }
  }
}

pub fn map_node_context(
  node: Node(req_body, ctx_b, output),
  mapper: fn(ctx_a) -> ctx_b,
) -> Node(req_body, ctx_a, output) {
  let new_route =
    option.map(node.route, fn(r) {
      let new_handler = fn(req, ctx_a, params) {
        r.handler(req, mapper(ctx_a), params)
      }
      Route(handler: new_handler, description: r.description)
    })

  let new_static =
    dict.map_values(node.static_children, fn(_, child) {
      map_node_context(child, mapper)
    })

  let new_dynamic =
    option.map(node.dynamic_child, fn(pair) {
      let #(name, child) = pair
      #(name, map_node_context(child, mapper))
    })

  let new_wildcard =
    option.map(node.wildcard_child, fn(pair) {
      let #(name, r) = pair
      let new_handler = fn(req, ctx_a, params) {
        r.handler(req, mapper(ctx_a), params)
      }
      #(name, Route(handler: new_handler, description: r.description))
    })

  Node(new_route, new_static, new_dynamic, new_wildcard)
}

pub fn map_node(
  node: Node(req_body, ctx, a),
  fun: fn(a) -> b,
) -> Node(req_body, ctx, b) {
  let new_route =
    option.map(node.route, fn(r) {
      let new_handler = fn(req, ctx, params) {
        r.handler(req, ctx, params) |> fun
      }
      Route(handler: new_handler, description: r.description)
    })

  let new_static =
    dict.map_values(node.static_children, fn(_, child) { map_node(child, fun) })

  let new_dynamic =
    option.map(node.dynamic_child, fn(pair) {
      let #(name, child) = pair
      #(name, map_node(child, fun))
    })

  let new_wildcard =
    option.map(node.wildcard_child, fn(pair) {
      let #(name, r) = pair
      let new_handler = fn(req, ctx, params) {
        r.handler(req, ctx, params) |> fun
      }
      #(name, Route(handler: new_handler, description: r.description))
    })

  Node(new_route, new_static, new_dynamic, new_wildcard)
}

pub fn wrap_node(
  node: Node(req, ctx, out),
  middleware: fn(fn(Request(req), ctx, Dict(String, String)) -> out) ->
    fn(Request(req), ctx, Dict(String, String)) -> out,
) -> Node(req, ctx, out) {
  let new_route =
    option.map(node.route, fn(r) {
      Route(handler: middleware(r.handler), description: r.description)
    })

  let new_static =
    dict.map_values(node.static_children, fn(_, child) {
      wrap_node(child, middleware)
    })

  let new_dynamic =
    option.map(node.dynamic_child, fn(pair) {
      let #(name, child) = pair
      #(name, wrap_node(child, middleware))
    })

  let new_wildcard =
    option.map(node.wildcard_child, fn(pair) {
      let #(name, r) = pair
      #(name, Route(handler: middleware(r.handler), description: r.description))
    })

  Node(new_route, new_static, new_dynamic, new_wildcard)
}

// --- OPERATIONS ON ROUTER ---

pub fn route(
  router: Router(req_body, ctx, output),
  method: Method,
  path: String,
  handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  let segments = path.parse_path(path)
  let root = dict.get(router.routes, method) |> result.unwrap(empty_node())
  let updated_root = insert_route(root, segments, handler)

  Router(
    routes: dict.insert(router.routes, method, updated_root),
    last_added: Some(#(method, segments)),
  )
}

pub fn describe(
  router: Router(req_body, ctx, output),
  description: String,
) -> Router(req_body, ctx, output) {
  case router.last_added {
    Some(#(method, segments)) -> {
      let root = dict.get(router.routes, method) |> result.unwrap(empty_node())
      let updated_root = update_description(root, segments, description)
      Router(..router, routes: dict.insert(router.routes, method, updated_root))
    }
    None -> router
  }
}

pub fn map_context(
  router: Router(req_body, ctx_b, output),
  mapper: fn(ctx_a) -> ctx_b,
) -> Router(req_body, ctx_a, output) {
  let new_routes =
    dict.map_values(router.routes, fn(_, node) {
      map_node_context(node, mapper)
    })
  Router(routes: new_routes, last_added: None)
}

pub fn map(
  router: Router(req_body, ctx, a),
  fun: fn(a) -> b,
) -> Router(req_body, ctx, b) {
  let new_routes =
    dict.map_values(router.routes, fn(_, node) { map_node(node, fun) })
  Router(routes: new_routes, last_added: None)
}

pub fn mount(
  parent: Router(req, ctx_a, out),
  prefix: String,
  sub_router: Router(req, ctx_b, out),
  mapper: fn(ctx_a) -> ctx_b,
) -> Router(req, ctx_a, out) {
  let sub_router = map_context(sub_router, mapper)
  let prefix_segments = path.parse_path(prefix)

  let mounted_router =
    dict.to_list(sub_router.routes)
    |> list.fold(parent, fn(acc_router, method_pair) {
      let #(method, sub_tree) = method_pair
      let parent_root =
        dict.get(acc_router.routes, method) |> result.unwrap(empty_node())

      let prefixed_sub_tree = prefix_node(prefix_segments, sub_tree)
      let merged_root = merge_nodes(parent_root, prefixed_sub_tree)

      Router(
        ..acc_router,
        routes: dict.insert(acc_router.routes, method, merged_root),
      )
    })

  Router(routes: mounted_router.routes, last_added: None)
}

pub fn merge(
  a: Router(req, ctx, out),
  b: Router(req, ctx, out),
) -> Router(req, ctx, out) {
  let combined_routes = dict.combine(a.routes, b.routes, merge_nodes)
  Router(routes: combined_routes, last_added: None)
}

pub fn wrap(
  router: Router(req, ctx, out),
  middleware: fn(fn(Request(req), ctx, Dict(String, String)) -> out) ->
    fn(Request(req), ctx, Dict(String, String)) -> out,
) -> Router(req, ctx, out) {
  let new_routes =
    dict.map_values(router.routes, fn(_, node) { wrap_node(node, middleware) })
  Router(routes: new_routes, last_added: None)
}

pub fn group(
  router: Router(req, ctx, out),
  prefix: String,
  middlewares: List(
    fn(fn(Request(req), ctx, Dict(String, String)) -> out) ->
      fn(Request(req), ctx, Dict(String, String)) -> out,
  ),
  build_sub_router: fn(Router(req, ctx, out)) -> Router(req, ctx, out),
) -> Router(req, ctx, out) {
  let sub_router =
    list.fold(
      list.reverse(middlewares),
      build_sub_router(new_router()),
      fn(acc_r, mw) { wrap(acc_r, mw) },
    )

  mount(router, prefix, sub_router, fn(c) { c })
}

pub fn handle(
  router: Router(req_body, ctx, output),
  request: Request(req_body),
  context: ctx,
  not_found: fn() -> output,
) -> output {
  let req_segments = path.parse_path(request.path)

  let matching_route = case dict.get(router.routes, request.method) {
    Ok(root) -> find_route(root, req_segments, dict.new())
    Error(Nil) -> Error(Nil)
  }

  case matching_route {
    Ok(#(handler, params)) -> handler(request, context, params)
    Error(_) -> not_found()
  }
}

pub fn allowed_methods(
  router: Router(req_body, ctx, output),
  path_str: String,
) -> List(Method) {
  let req_segments = path.parse_path(path_str)
  dict.to_list(router.routes)
  |> list.filter_map(fn(pair) {
    let #(method, root) = pair
    case find_route(root, req_segments, dict.new()) {
      Ok(_) -> Ok(method)
      Error(Nil) -> Error(Nil)
    }
  })
}
