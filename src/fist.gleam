import gleam/dict.{type Dict}
import gleam/http.{type Method, Delete, Get, Patch, Post, Put}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Node(req_body, res_body) {
  Node(
    handler: Option(
      fn(Request(req_body), Dict(String, String)) -> Response(res_body),
    ),
    static_children: Dict(String, Node(req_body, res_body)),
    dynamic_child: Option(#(String, Node(req_body, res_body))),
  )
}

pub opaque type Router(req_body, res_body) {
  Router(routes: Dict(Method, Node(req_body, res_body)))
}

pub fn new() -> Router(req_body, res_body) {
  Router(routes: dict.new())
}

fn empty_node() -> Node(req_body, res_body) {
  Node(handler: None, static_children: dict.new(), dynamic_child: None)
}

fn parse_path(path: String) -> List(String) {
  path
  |> string.split("/")
  |> list.filter(fn(s) { s != "" })
}

fn insert_route(
  node: Node(req_body, res_body),
  segments: List(String),
  handler: fn(Request(req_body), Dict(String, String)) -> Response(res_body),
) -> Node(req_body, res_body) {
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

fn add_route(
  router: Router(req_body, res_body),
  method method: Method,
  path path: String,
  handler handler: fn(Request(req_body), Dict(String, String)) ->
    Response(res_body),
) -> Router(req_body, res_body) {
  let segments = parse_path(path)
  let root = dict.get(router.routes, method) |> result.unwrap(empty_node())
  let updated_root = insert_route(root, segments, handler)
  Router(routes: dict.insert(router.routes, method, updated_root))
}

pub fn get(
  router: Router(req_body, res_body),
  path path: String,
  to handler: fn(Request(req_body), Dict(String, String)) -> Response(res_body),
) -> Router(req_body, res_body) {
  add_route(router, method: Get, path: path, handler: handler)
}

pub fn post(
  router: Router(req_body, res_body),
  path path: String,
  to handler: fn(Request(req_body), Dict(String, String)) -> Response(res_body),
) -> Router(req_body, res_body) {
  add_route(router, method: Post, path: path, handler: handler)
}

pub fn put(
  router: Router(req_body, res_body),
  path path: String,
  to handler: fn(Request(req_body), Dict(String, String)) -> Response(res_body),
) -> Router(req_body, res_body) {
  add_route(router, method: Put, path: path, handler: handler)
}

pub fn delete(
  router: Router(req_body, res_body),
  path path: String,
  to handler: fn(Request(req_body), Dict(String, String)) -> Response(res_body),
) -> Router(req_body, res_body) {
  add_route(router, method: Delete, path: path, handler: handler)
}

pub fn patch(
  router: Router(req_body, res_body),
  path path: String,
  to handler: fn(Request(req_body), Dict(String, String)) -> Response(res_body),
) -> Router(req_body, res_body) {
  add_route(router, method: Patch, path: path, handler: handler)
}

fn find_route(
  node: Node(req_body, res_body),
  segments: List(String),
  params: Dict(String, String),
) -> Result(
  #(
    fn(Request(req_body), Dict(String, String)) -> Response(res_body),
    Dict(String, String),
  ),
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

pub fn handle(
  router: Router(req_body, res_body),
  request: Request(req_body),
  not_found: fn() -> Response(res_body),
) -> Response(res_body) {
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
