import fist/internal/path
import fist/internal/reverse
import fist/internal/types.{
  type DynamicBranch, type Node, type Router, DynamicBranch, Node, Route, Router,
  empty_node, new_router,
}
import gleam/dict.{type Dict}
import gleam/http.{type Method}
import gleam/http/request.{type Request}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

fn update_or_append_dynamic(
  branches: List(DynamicBranch(req_body, ctx, output)),
  param_name: String,
  rest: List(String),
  handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> List(DynamicBranch(req_body, ctx, output)) {
  case branches {
    [] -> {
      let child = insert_route(empty_node(), rest, handler)
      [DynamicBranch(param_name: param_name, guard: None, child: child)]
    }
    [branch, ..rest_branches] -> {
      case branch.param_name == param_name {
        True -> {
          let updated_child = insert_route(branch.child, rest, handler)
          [DynamicBranch(..branch, child: updated_child), ..rest_branches]
        }
        False -> {
          [
            branch,
            ..update_or_append_dynamic(rest_branches, param_name, rest, handler)
          ]
        }
      }
    }
  }
}

fn sort_dynamic_branches(
  branches: List(DynamicBranch(req, ctx, out)),
) -> List(DynamicBranch(req, ctx, out)) {
  let #(guarded, unguarded) =
    list.partition(branches, fn(b) {
      case b.guard {
        Some(_) -> True
        None -> False
      }
    })
  list.append(guarded, unguarded)
}

/// Recursively inserts a route into the Trie.
/// Panics if an identical route already exists or if a wildcard is placed non-terminally.
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
      let updated_children =
        update_or_append_dynamic(
          node.dynamic_children,
          param_name,
          rest,
          handler,
        )
        |> sort_dynamic_branches
      Node(..node, dynamic_children: updated_children)
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

    [":" <> param_name, ..rest] -> {
      let updated_children =
        list.map(node.dynamic_children, fn(branch) {
          case branch.param_name == param_name {
            True -> {
              let updated_child = update_description(branch.child, rest, desc)
              DynamicBranch(..branch, child: updated_child)
            }
            False -> branch
          }
        })
      Node(..node, dynamic_children: updated_children)
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

/// Recursively updates a dynamic branch to attach a guard predicate.
pub fn update_guard(
  node: Node(req_body, ctx, output),
  segments: List(String),
  target_param: String,
  predicate: fn(String) -> Bool,
) -> Node(req_body, ctx, output) {
  case segments {
    [] -> node

    [":" <> param_name, ..rest] -> {
      case param_name == target_param {
        True -> {
          let updated_children =
            list.map(node.dynamic_children, fn(branch) {
              case branch.param_name == target_param {
                True -> {
                  let new_guard = case branch.guard {
                    Some(prev) -> fn(s) { prev(s) && predicate(s) }
                    None -> predicate
                  }
                  DynamicBranch(..branch, guard: Some(new_guard))
                }
                False -> branch
              }
            })
            |> sort_dynamic_branches
          Node(..node, dynamic_children: updated_children)
        }
        False -> {
          let updated_children =
            list.map(node.dynamic_children, fn(branch) {
              case branch.param_name == param_name {
                True -> {
                  let updated_child =
                    update_guard(branch.child, rest, target_param, predicate)
                  DynamicBranch(..branch, child: updated_child)
                }
                False -> branch
              }
            })
            |> sort_dynamic_branches
          Node(..node, dynamic_children: updated_children)
        }
      }
    }

    [segment, ..rest] -> {
      case dict.get(node.static_children, segment) {
        Ok(child) -> {
          let updated = update_guard(child, rest, target_param, predicate)
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

fn find_dynamic_route(
  branches: List(DynamicBranch(req_body, ctx, output)),
  segment: String,
  rest: List(String),
  params: Dict(String, String),
) -> Result(
  #(
    fn(Request(req_body), ctx, Dict(String, String)) -> output,
    Dict(String, String),
  ),
  Nil,
) {
  case branches {
    [] -> Error(Nil)
    [branch, ..rest_branches] -> {
      let passes_guard = case branch.guard {
        Some(predicate) -> predicate(segment)
        None -> True
      }
      case passes_guard {
        False -> find_dynamic_route(rest_branches, segment, rest, params)
        True -> {
          let new_params = dict.insert(params, branch.param_name, segment)
          case find_route(branch.child, rest, new_params) {
            Ok(match) -> Ok(match)
            Error(Nil) ->
              find_dynamic_route(rest_branches, segment, rest, params)
          }
        }
      }
    }
  }
}

/// Recursively traverses the Trie to find a matching handler.
/// Follows strict precedence: Static > Dynamic with Guard > Dynamic Generic > Wildcard (*catch_all),
/// with full fallthrough and backtracking support.
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

      // 2. If static failed, try dynamic branches in priority order with fallthrough
      let dynamic_result = case static_result {
        Ok(match) -> Ok(match)
        Error(Nil) -> {
          find_dynamic_route(node.dynamic_children, segment, rest, params)
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

fn merge_single_branch(
  branches: List(DynamicBranch(req, ctx, out)),
  b_branch: DynamicBranch(req, ctx, out),
) -> List(DynamicBranch(req, ctx, out)) {
  case branches {
    [] -> [b_branch]
    [a_branch, ..rest_a] -> {
      case a_branch.param_name == b_branch.param_name {
        True -> {
          let merged_child = merge_nodes(a_branch.child, b_branch.child)
          let guard = case a_branch.guard, b_branch.guard {
            Some(g1), Some(g2) -> Some(fn(s) { g1(s) && g2(s) })
            Some(g), None -> Some(g)
            None, Some(g) -> Some(g)
            None, None -> None
          }
          [
            DynamicBranch(
              param_name: a_branch.param_name,
              guard: guard,
              child: merged_child,
            ),
            ..rest_a
          ]
        }
        False -> {
          [a_branch, ..merge_single_branch(rest_a, b_branch)]
        }
      }
    }
  }
}

fn merge_dynamic_children(
  a_branches: List(DynamicBranch(req, ctx, out)),
  b_branches: List(DynamicBranch(req, ctx, out)),
) -> List(DynamicBranch(req, ctx, out)) {
  case b_branches {
    [] -> a_branches
    [b_branch, ..rest_b] -> {
      let updated_a = merge_single_branch(a_branches, b_branch)
      merge_dynamic_children(updated_a, rest_b)
    }
  }
}

/// Recursively merges two nodes.
/// Static and dynamic branches merge cleanly, with full priority preservation.
pub fn merge_nodes(
  a: Node(req, ctx, out),
  b: Node(req, ctx, out),
) -> Node(req, ctx, out) {
  let route = case a.route, b.route {
    Some(_), Some(_) ->
      panic as "Route collision: cannot merge routers because a route is registered at the same path in both"
    None, some_b -> some_b
    some_a, None -> some_a
  }

  let static_children =
    dict.combine(a.static_children, b.static_children, merge_nodes)

  let dynamic_children =
    merge_dynamic_children(a.dynamic_children, b.dynamic_children)
    |> sort_dynamic_branches

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

  Node(route, static_children, dynamic_children, wildcard_child)
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
      let branch =
        DynamicBranch(param_name: param_name, guard: None, child: child)
      Node(..empty, dynamic_children: [branch])
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
    list.map(node.dynamic_children, fn(branch) {
      DynamicBranch(..branch, child: map_node_context(branch.child, mapper))
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
    list.map(node.dynamic_children, fn(branch) {
      DynamicBranch(..branch, child: map_node(branch.child, fun))
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
    list.map(node.dynamic_children, fn(branch) {
      DynamicBranch(..branch, child: wrap_node(branch.child, middleware))
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
  path_str: String,
  handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  let segments = path.parse_path(path_str)
  let root_node = dict.get(router.routes, method) |> result.unwrap(empty_node())
  let updated_root = insert_route(root_node, segments, handler)
  Router(
    routes: dict.insert(router.routes, method, updated_root),
    last_added: Some(#(method, segments)),
    named_routes: router.named_routes,
  )
}

pub fn describe(
  router: Router(req_body, ctx, output),
  desc: String,
) -> Router(req_body, ctx, output) {
  case router.last_added {
    Some(#(method, segments)) -> {
      case dict.get(router.routes, method) {
        Ok(root) -> {
          let updated_root = update_description(root, segments, desc)
          Router(
            routes: dict.insert(router.routes, method, updated_root),
            last_added: router.last_added,
            named_routes: router.named_routes,
          )
        }
        Error(_) -> router
      }
    }
    None -> router
  }
}

pub fn name(
  router: Router(req_body, ctx, output),
  route_name: String,
) -> Router(req_body, ctx, output) {
  reverse.name_route(router, route_name)
}

pub fn guard(
  router: Router(req_body, ctx, output),
  param_name: String,
  predicate: fn(String) -> Bool,
) -> Router(req_body, ctx, output) {
  case router.last_added {
    Some(#(method, segments)) -> {
      let has_param = list.contains(segments, ":" <> param_name)
      case has_param {
        False ->
          panic as string.concat([
              "Invalid guard: parameter ':",
              param_name,
              "' not found in the last added route path",
            ])
        True -> {
          case dict.get(router.routes, method) {
            Ok(root) -> {
              let updated_root =
                update_guard(root, segments, param_name, predicate)
              let updated_named =
                reverse.update_template_guard(
                  router.named_routes,
                  segments,
                  param_name,
                  predicate,
                )
              Router(
                routes: dict.insert(router.routes, method, updated_root),
                last_added: router.last_added,
                named_routes: updated_named,
              )
            }
            Error(_) -> router
          }
        }
      }
    }
    None ->
      panic as "Invalid guard: fist.guard must be called immediately after registering a route"
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
  Router(
    routes: new_routes,
    last_added: None,
    named_routes: router.named_routes,
  )
}

pub fn map(
  router: Router(req_body, ctx, a),
  fun: fn(a) -> b,
) -> Router(req_body, ctx, b) {
  let new_routes =
    dict.map_values(router.routes, fn(_, node) { map_node(node, fun) })
  Router(
    routes: new_routes,
    last_added: None,
    named_routes: router.named_routes,
  )
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

  let updated_named =
    reverse.mount_named_routes(
      parent.named_routes,
      sub_router.named_routes,
      prefix_segments,
    )
  Router(
    routes: mounted_router.routes,
    last_added: None,
    named_routes: updated_named,
  )
}

pub fn merge(
  a: Router(req, ctx, out),
  b: Router(req, ctx, out),
) -> Router(req, ctx, out) {
  let combined_routes = dict.combine(a.routes, b.routes, merge_nodes)
  let combined_named =
    reverse.merge_named_routes(a.named_routes, b.named_routes)
  Router(
    routes: combined_routes,
    last_added: None,
    named_routes: combined_named,
  )
}

pub fn wrap(
  router: Router(req, ctx, out),
  middleware: fn(fn(Request(req), ctx, Dict(String, String)) -> out) ->
    fn(Request(req), ctx, Dict(String, String)) -> out,
) -> Router(req, ctx, out) {
  let new_routes =
    dict.map_values(router.routes, fn(_, node) { wrap_node(node, middleware) })
  Router(
    routes: new_routes,
    last_added: None,
    named_routes: router.named_routes,
  )
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
