import gleam/dict.{type Dict}
import gleam/http.{type Method, Delete, Get, Patch, Post, Put}
import gleam/http/request.{type Request}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// --- TYPES ---

/// Encapsulates the handler logic and its metadata.
pub type Route(req_body, ctx, output) {
  Route(
    handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
    description: Option(String),
  )
}

/// A node in the router's internal Trie structure.
pub type Node(req_body, ctx, output) {
  Node(
    /// If this node represents the end of a valid path, it will have a Route object.
    route: Option(Route(req_body, ctx, output)),
    /// Static children are exact string matches (e.g., "users", "settings").
    static_children: Dict(String, Node(req_body, ctx, output)),
    /// A dynamic child is a wildcard parameter (e.g., ":id", ":slug").
    dynamic_child: Option(#(String, Node(req_body, ctx, output))),
  )
}

/// The main Router type.
pub opaque type Router(req_body, ctx, output) {
  Router(
    routes: Dict(Method, Node(req_body, ctx, output)),
    /// Tracks the last added route (Method, Segments) to support method chaining like `describe`.
    last_added: Option(#(Method, List(String))),
  )
}

/// Information about a registered route, used for introspection/documentation.
pub type RouteInfo {
  RouteInfo(
    method: Method,
    path: String,
    description: String,
    params: List(String),
  )
}

// --- CONSTRUCTORS ---

/// Creates a new, empty router.
pub fn new() -> Router(req_body, ctx, output) {
  Router(routes: dict.new(), last_added: None)
}

/// Helper to create an empty Trie node.
fn empty_node() -> Node(req_body, ctx, output) {
  Node(route: None, static_children: dict.new(), dynamic_child: None)
}

// --- INTERNAL LOGIC ---

/// Splits a path string into segments, ignoring empty strings.
fn parse_path(path: String) -> List(String) {
  path
  |> string.split("/")
  |> list.filter(fn(s) { s != "" })
}

/// Recursively inserts a route into the Trie.
fn insert_route(
  node: Node(req_body, ctx, output),
  segments: List(String),
  handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Node(req_body, ctx, output) {
  case segments {
    [] -> {
      // Create a new Route record, preserving existing description if updating (though usually new)
      let new_route = Route(handler: handler, description: None)
      Node(..node, route: Some(new_route))
    }

    [":" <> param_name, ..rest] -> {
      let child = case node.dynamic_child {
        Some(#(_, child_node)) -> child_node
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
fn update_description(
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
        // Should not happen if logic is correct
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
fn find_route(
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
      let static_match = case dict.get(node.static_children, segment) {
        Ok(child) -> find_route(child, rest, params)
        Error(Nil) -> Error(Nil)
      }

      case static_match {
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
    }
  }
}

// --- PUBLIC API (Route Definition) ---

/// Generic function to add a route for a specific method.
pub fn route(
  router: Router(req_body, ctx, output),
  method method: Method,
  path path: String,
  handler handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  let segments = parse_path(path)
  let root = dict.get(router.routes, method) |> result.unwrap(empty_node())
  let updated_root = insert_route(root, segments, handler)

  Router(
    routes: dict.insert(router.routes, method, updated_root),
    last_added: Some(#(method, segments)),
  )
}

/// Adds a description to the last added route.
/// This enables the chaining syntax: `|> fist.get(...) |> fist.describe("...")`
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

/// Adds a GET route to the router.
pub fn get(
  router: Router(req_body, ctx, output),
  path path: String,
  to handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  route(router, method: Get, path: path, handler: handler)
}

/// Adds a POST route to the router.
pub fn post(
  router: Router(req_body, ctx, output),
  path path: String,
  to handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  route(router, method: Post, path: path, handler: handler)
}

/// Adds a PUT route to the router.
pub fn put(
  router: Router(req_body, ctx, output),
  path path: String,
  to handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  route(router, method: Put, path: path, handler: handler)
}

/// Adds a DELETE route to the router.
pub fn delete(
  router: Router(req_body, ctx, output),
  path path: String,
  to handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  route(router, method: Delete, path: path, handler: handler)
}

/// Adds a PATCH route to the router.
pub fn patch(
  router: Router(req_body, ctx, output),
  path path: String,
  to handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  route(router, method: Patch, path: path, handler: handler)
}

// --- TRANSFORMATION ---

/// Transforms the context of the router using a mapping function.
/// This is the foundation for context polymorphism, allowing a sub-router
/// that expects a specific context to be used within a parent router with a different context.
pub fn map_context(
  router: Router(req_body, ctx_b, output),
  with mapper: fn(ctx_a) -> ctx_b,
) -> Router(req_body, ctx_a, output) {
  let new_routes =
    dict.map_values(router.routes, fn(_, node) {
      map_node_context(node, mapper)
    })
  Router(routes: new_routes, last_added: None)
}

fn map_node_context(
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

  Node(new_route, new_static, new_dynamic)
}

/// Transforms the output of the router using a mapping function.
pub fn map(
  router: Router(req_body, ctx, a),
  with fun: fn(a) -> b,
) -> Router(req_body, ctx, b) {
  let new_routes =
    dict.map_values(router.routes, fn(_, node) { map_node(node, fun) })
  Router(routes: new_routes, last_added: None)
}

fn map_node(
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

  Node(new_route, new_static, new_dynamic)
}

// --- COMPOSITION ---

/// Recursively merges two nodes. If both have a route, the second one (b) wins.
fn merge_nodes(
  a: Node(req, ctx, out),
  b: Node(req, ctx, out),
) -> Node(req, ctx, out) {
  let route = option.or(b.route, a.route)

  let static_children =
    dict.combine(a.static_children, b.static_children, merge_nodes)

  let dynamic_child = case a.dynamic_child, b.dynamic_child {
    Some(#(_, child_a)), Some(#(name_b, child_b)) -> {
      // Prefer the parameter name from the new tree (b)
      Some(#(name_b, merge_nodes(child_a, child_b)))
    }
    None, some_b -> some_b
    some_a, None -> some_a
  }

  Node(route, static_children, dynamic_child)
}

/// Creates a new tree from a list of segments that leads to the given sub-tree.
fn prefix_node(
  segments: List(String),
  sub_tree: Node(req, ctx, out),
) -> Node(req, ctx, out) {
  case segments {
    [] -> sub_tree
    [segment, ..rest] -> {
      let child = prefix_node(rest, sub_tree)
      let empty = empty_node()
      Node(..empty, static_children: dict.from_list([#(segment, child)]))
    }
  }
}

/// Mounts a sub-router at a specific prefix, transforming its context to match the parent.
/// This enables modular routing and context polymorphism.
pub fn mount(
  parent: Router(req, ctx_a, out),
  at prefix: String,
  sub sub_router: Router(req, ctx_b, out),
  transform mapper: fn(ctx_a) -> ctx_b,
) -> Router(req, ctx_a, out) {
  let sub_router = map_context(sub_router, mapper)
  let prefix_segments = parse_path(prefix)

  dict.to_list(sub_router.routes)
  |> list.fold(parent, fn(acc_router, method_pair) {
    let #(method, sub_tree) = method_pair
    let parent_root =
      dict.get(acc_router.routes, method) |> result.unwrap(empty_node())

    // Create a prefixed version of the sub_tree and merge it into parent
    let prefixed_sub_tree = prefix_node(prefix_segments, sub_tree)
    let merged_root = merge_nodes(parent_root, prefixed_sub_tree)

    Router(
      ..acc_router,
      routes: dict.insert(acc_router.routes, method, merged_root),
    )
  })
}

// --- EXECUTION ---

pub fn handle(
  router: Router(req_body, ctx, output),
  request: Request(req_body),
  context: ctx,
  not_found: fn() -> output,
) -> output {
  let req_segments = parse_path(request.path)

  let matching_route = case dict.get(router.routes, request.method) {
    Ok(root) -> find_route(root, req_segments, dict.new())
    Error(Nil) -> Error(Nil)
  }

  case matching_route {
    Ok(#(handler, params)) -> handler(request, context, params)
    Error(_) -> not_found()
  }
}

// --- INTROSPECTION ---

fn inspect_node(
  node: Node(req_body, ctx, output),
  method: Method,
  path_acc: List(String),
  params_acc: List(String),
) -> List(RouteInfo) {
  // 1. Current node info
  let current_info = case node.route {
    Some(r) -> [
      RouteInfo(
        method: method,
        path: "/" <> string.join(path_acc, "/"),
        description: option.unwrap(r.description, ""),
        params: params_acc,
      ),
    ]
    None -> []
  }

  // 2. Static children
  let static_infos =
    dict.to_list(node.static_children)
    |> list.flat_map(fn(pair) {
      let #(segment, child) = pair
      inspect_node(child, method, list.append(path_acc, [segment]), params_acc)
    })

  // 3. Dynamic child
  let dynamic_infos = case node.dynamic_child {
    Some(#(param_name, child)) -> {
      inspect_node(
        child,
        method,
        list.append(path_acc, [":" <> param_name]),
        list.append(params_acc, [param_name]),
      )
    }
    None -> []
  }

  list.flatten([current_info, static_infos, dynamic_infos])
}

/// Returns a list of all registered routes with their metadata.
/// Useful for generating documentation (OpenAPI) or debugging.
pub fn inspect(router: Router(req_body, ctx, output)) -> List(RouteInfo) {
  router.routes
  |> dict.to_list
  |> list.flat_map(fn(pair) {
    let #(method, root_node) = pair
    inspect_node(root_node, method, [], [])
  })
}
