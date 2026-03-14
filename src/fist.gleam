import gleam/dict.{type Dict}
import gleam/http.{type Method, Delete, Get, Patch, Post, Put}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import gleam/string

pub type Route(req_body, res_body) {
  Route(
    method: Method,
    path_segments: List(String),
    handler: fn(Request(req_body), Dict(String, String)) -> Response(res_body),
  )
}

pub opaque type Router(req_body, res_body) {
  Router(routes: List(Route(req_body, res_body)))
}

pub fn new() -> Router(req_body, res_body) {
  Router(routes: [])
}

fn parse_path(path: String) -> List(String) {
  path
  |> string.split("/")
  |> list.filter(fn(s) { s != "" })
}

fn add_route(
  router: Router(req_body, res_body),
  method method: Method,
  path path: String,
  handler handler: fn(Request(req_body), Dict(String, String)) -> Response(res_body),
) -> Router(req_body, res_body) {
  let route = Route(
    method: method,
    path_segments: parse_path(path),
    handler: handler,
  )
  Router(routes: list.append(router.routes, [route]))
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

pub fn handle(
  router: Router(req_body, res_body),
  request: Request(req_body),
  not_found: fn() -> Response(res_body),
) -> Response(res_body) {
  let req_segments = parse_path(request.path)

  let matching_route =
    list.find_map(router.routes, fn(route) {
      let is_method_match = route.method == request.method
      case is_method_match {
        True -> {
          case match_segments(route.path_segments, req_segments, dict.new()) {
            Ok(params) -> Ok(#(route.handler, params))
            Error(_) -> Error(Nil)
          }
        }
        False -> Error(Nil)
      }
    })

  case matching_route {
    Ok(#(handler, params)) -> handler(request, params)
    Error(_) -> not_found()
  }
}

fn match_segments(
  route_segments: List(String),
  req_segments: List(String),
  params: Dict(String, String),
) -> Result(Dict(String, String), Nil) {
  case route_segments, req_segments {
    [], [] -> Ok(params)
    [":" <> name, ..rest_route], [value, ..rest_req] -> {
      let new_params = dict.insert(params, name, value)
      match_segments(rest_route, rest_req, new_params)
    }
    [s1, ..rest_route], [s2, ..rest_req] if s1 == s2 -> {
      match_segments(rest_route, rest_req, params)
    }
    _, _ -> Error(Nil)
  }
}
