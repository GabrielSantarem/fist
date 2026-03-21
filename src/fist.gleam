import gleam/dict.{type Dict}
import gleam/http.{type Method, Delete, Get, Patch, Post, Put}
import gleam/http/request.{type Request}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// --- TYPES ---

/// A node in the router's internal Trie structure.
/// This represents a single segment of a URL path.
///
/// Example: In the path `/users/:id`, there are two nodes:
/// 1. "users" (in static_children of root)
/// 2. ":id" (in dynamic_child of "users")
pub type Node(req_body, ctx, output) {
  Node(
    /// If this node represents the end of a valid path, it will have a handler.
    handler: Option(fn(Request(req_body), ctx, Dict(String, String)) -> output),
    /// Static children are exact string matches (e.g., "users", "settings").
    /// These are checked FIRST.
    static_children: Dict(String, Node(req_body, ctx, output)),
    /// A dynamic child is a wildcard parameter (e.g., ":id", ":slug").
    /// This is checked ONLY if no static match is found.
    /// The string in the tuple is the parameter name (e.g., "id").
    dynamic_child: Option(#(String, Node(req_body, ctx, output))),
  )
}

/// The main Router type.
/// It works as a wrapper around a dictionary mapping HTTP Methods to Root Nodes.
///
/// - `req_body`: The type of the HTTP request body.
/// - `ctx`: The custom context type passed to handlers.
/// - `output`: The return type of the handlers (e.g., Response, String).
pub opaque type Router(req_body, ctx, output) {
  Router(routes: Dict(Method, Node(req_body, ctx, output)))
}

// --- CONSTRUCTORS ---

/// Creates a new, empty router.
pub fn new() -> Router(req_body, ctx, output) {
  Router(routes: dict.new())
}

/// Helper to create an empty Trie node.
fn empty_node() -> Node(req_body, ctx, output) {
  Node(handler: None, static_children: dict.new(), dynamic_child: None)
}

// --- INTERNAL LOGIC ---

/// Splits a path string into segments, ignoring empty strings.
/// "/users//123" -> ["users", "123"]
fn parse_path(path: String) -> List(String) {
  path
  |> string.split("/")
  |> list.filter(fn(s) { s != "" })
}

/// Recursively inserts a route into the Trie.
/// Handles the distinction between static segments ("users") and dynamic ones (":id").
fn insert_route(
  node: Node(req_body, ctx, output),
  segments: List(String),
  handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Node(req_body, ctx, output) {
  case segments {
    // End of recursion: we reached the target node. Set the handler.
    [] -> Node(..node, handler: Some(handler))

    // Dynamic Segment (starts with ":")
    [":" <> param_name, ..rest] -> {
      let child = case node.dynamic_child {
        Some(#(_, child_node)) -> child_node
        None -> empty_node()
      }
      let updated_child = insert_route(child, rest, handler)
      // Note: We overwrite the param name if it was different, but that's expected behavior
      Node(..node, dynamic_child: Some(#(param_name, updated_child)))
    }

    // Static Segment
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

/// Recursively traverses the Trie to find a matching handler.
/// Implements priority logic: Static Match > Dynamic Match.
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
    // End of path: check if this node has a handler attached.
    [] -> {
      case node.handler {
        Some(handler) -> Ok(#(handler, params))
        None -> Error(Nil)
      }
    }

    [segment, ..rest] -> {
      // 1. Try to find a static child with the exact segment name.
      let static_match = case dict.get(node.static_children, segment) {
        Ok(child) -> find_route(child, rest, params)
        Error(Nil) -> Error(Nil)
      }

      case static_match {
        // If static match found (recursively), return it.
        Ok(match) -> Ok(match)

        // 2. If NO static match, check if there is a dynamic wildcard child.
        Error(Nil) -> {
          case node.dynamic_child {
            Some(#(param_name, child)) -> {
              // Capture the parameter (e.g., id="123")
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
  Router(routes: dict.insert(router.routes, method, updated_root))
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

/// Transforms the output of the router using a mapping function.
/// Useful for wrapping results, logging, or type conversion.
pub fn map(
  router: Router(req_body, ctx, a),
  with fun: fn(a) -> b,
) -> Router(req_body, ctx, b) {
  let new_routes =
    dict.map_values(router.routes, fn(_, node) { map_node(node, fun) })
  Router(routes: new_routes)
}

/// Helper to recursively map over the Trie nodes.
fn map_node(
  node: Node(req_body, ctx, a),
  fun: fn(a) -> b,
) -> Node(req_body, ctx, b) {
  // Map the handler if it exists
  let new_handler =
    option.map(node.handler, fn(h) {
      fn(req, ctx, params) { h(req, ctx, params) |> fun }
    })

  // Recursively map static children
  let new_static =
    dict.map_values(node.static_children, fn(_, child) { map_node(child, fun) })

  // Recursively map dynamic child
  let new_dynamic =
    option.map(node.dynamic_child, fn(pair) {
      let #(name, child) = pair
      #(name, map_node(child, fun))
    })

  Node(new_handler, new_static, new_dynamic)
}

// --- EXECUTION ---

/// Handles an incoming request using the defined router.
///
/// 1. Identifies the HTTP method.
/// 2. Parses the path.
/// 3. Traverses the Trie to find a matching handler.
/// 4. Executes the handler or the `not_found` fallback.
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
