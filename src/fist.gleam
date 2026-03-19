import gleam/dict.{type Dict}
import gleam/http.{type Method, Delete, Get, Patch, Post, Put}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// A node in the router tree, representing a route segment.
pub type Node(req_body, output) {
  Node(
    handler: Option(fn(Request(req_body), Dict(String, String)) -> output),
    static_children: Dict(String, Node(req_body, output)),
    dynamic_child: Option(#(String, Node(req_body, output))),
  )
}

/// A router that handles HTTP requests by matching routes and executing handlers.
pub opaque type Router(req_body, output) {
  Router(routes: Dict(Method, Node(req_body, output)))
}

/// Creates a new empty router.
pub fn new() -> Router(req_body, output) {
  Router(routes: dict.new())
}

/// Creates a new empty node.
fn empty_node() -> Node(req_body, output) {
  Node(handler: None, static_children: dict.new(), dynamic_child: None)
}

/// Parses a path string into a list of segments.
fn parse_path(path: String) -> List(String) {
  path
  |> string.split("/")
  |> list.filter(fn(s) { s != "" })
}

/// Inserts a route into the router.
fn insert_route(
  node: Node(req_body, output),
  segments: List(String),
  handler: fn(Request(req_body), Dict(String, String)) -> output,
) -> Node(req_body, output) {
  case segments {
    [] -> Node(..node, handler: Some(handler))
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

/// Inserts a route into the router.
pub fn route(
  router: Router(req_body, output),
  method method: Method,
  path path: String,
  handler handler: fn(Request(req_body), Dict(String, String)) -> output,
) -> Router(req_body, output) {
  let segments = parse_path(path)
  let root = dict.get(router.routes, method) |> result.unwrap(empty_node())
  let updated_root = insert_route(root, segments, handler)
  Router(routes: dict.insert(router.routes, method, updated_root))
}

/// Adds a GET route to the router.
pub fn get(
  router: Router(req_body, output),
  path path: String,
  to handler: fn(Request(req_body), Dict(String, String)) -> output,
) -> Router(req_body, output) {
  route(router, method: Get, path: path, handler: handler)
}

/// Adds a POST route to the router.
pub fn post(
  router: Router(req_body, output),
  path path: String,
  to handler: fn(Request(req_body), Dict(String, String)) -> output,
) -> Router(req_body, output) {
  route(router, method: Post, path: path, handler: handler)
}

/// Adds a PUT route to the router.
pub fn put(
  router: Router(req_body, output),
  path path: String,
  to handler: fn(Request(req_body), Dict(String, String)) -> output,
) -> Router(req_body, output) {
  route(router, method: Put, path: path, handler: handler)
}

/// Adds a DELETE route to the router.
pub fn delete(
  router: Router(req_body, output),
  path path: String,
  to handler: fn(Request(req_body), Dict(String, String)) -> output,
) -> Router(req_body, output) {
  route(router, method: Delete, path: path, handler: handler)
}

/// Adds a PATCH route to the router.
pub fn patch(
  router: Router(req_body, output),
  path path: String,
  to handler: fn(Request(req_body), Dict(String, String)) -> output,
) -> Router(req_body, output) {
  route(router, method: Patch, path: path, handler: handler)
}

fn find_route(
  node: Node(req_body, output),
  segments: List(String),
  params: Dict(String, String),
) -> Result(
  #(fn(Request(req_body), Dict(String, String)) -> output, Dict(String, String)),
  Nil,
) {
  case segments {
    [] -> {
      case node.handler {
        Some(handler) -> Ok(#(handler, params))
        None -> Error(Nil)
      }
    }
    [segment, ..rest] -> {
      // Tenta correspondência estática primeiro (prioridade)
      let static_match = case dict.get(node.static_children, segment) {
        Ok(child) -> find_route(child, rest, params)
        Error(Nil) -> Error(Nil)
      }

      case static_match {
        Ok(match) -> Ok(match)
        Error(Nil) -> {
          // Se não houver estática, tenta o filho dinâmico
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

/// Maps the output of all handlers in the router.
pub fn map(
  router: Router(req_body, a),
  with fun: fn(a) -> b,
) -> Router(req_body, b) {
  let new_routes =
    dict.map_values(router.routes, fn(_, node) { map_node(node, fun) })
  Router(routes: new_routes)
}

fn map_node(node: Node(req_body, a), fun: fn(a) -> b) -> Node(req_body, b) {
  let new_handler =
    option.map(node.handler, fn(h) { fn(req, params) { h(req, params) |> fun } })
  let new_static =
    dict.map_values(node.static_children, fn(_, child) { map_node(child, fun) })
  let new_dynamic =
    option.map(node.dynamic_child, fn(pair) {
      let #(name, child) = pair
      #(name, map_node(child, fun))
    })
  Node(new_handler, new_static, new_dynamic)
}

// --- Response Helpers ---

/// Creates a 200 OK response with the given body.
pub fn ok(body: body) -> Response(body) {
  response.new(200)
  |> response.set_body(body)
}

/// Creates a 200 OK response with the given string as body and text/plain content type.
pub fn text(body: String) -> Response(String) {
  response.new(200)
  |> response.set_body(body)
  |> response.prepend_header("content-type", "text/plain")
}

/// Creates a 200 OK response with the given string as body and application/json content type.
pub fn json(body: String) -> Response(String) {
  response.new(200)
  |> response.set_body(body)
  |> response.prepend_header("content-type", "application/json")
}

/// Creates a 302 Found redirect response.
pub fn redirect(to: String) -> Response(String) {
  response.new(302)
  |> response.set_body("")
  |> response.prepend_header("location", to)
}

pub fn handle(
  router: Router(req_body, output),
  request: Request(req_body),
  not_found: fn() -> output,
) -> output {
  let req_segments = parse_path(request.path)

  let matching_route = case dict.get(router.routes, request.method) {
    Ok(root) -> find_route(root, req_segments, dict.new())
    Error(Nil) -> Error(Nil)
  }

  case matching_route {
    Ok(#(handler, params)) -> handler(request, params)
    Error(_) -> not_found()
  }
}
