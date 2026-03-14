import gleam/http.{type Method, Delete, Get, Patch, Post, Put}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list

pub type Route(req_body, res_body) {
  Route(
    method: Method,
    path: String,
    handler: fn(Request(req_body)) -> Response(res_body),
  )
}

pub opaque type Router(req_body, res_body) {
  Router(routes: List(Route(req_body, res_body)))
}

pub fn new() -> Router(req_body, res_body) {
  Router(routes: [])
}

fn add_route(
  router: Router(req_body, res_body),
  method method: Method,
  path path: String,
  handler handler: fn(Request(req_body)) -> Response(res_body),
) -> Router(req_body, res_body) {
  let route = Route(method: method, path: path, handler: handler)
  Router(routes: list.append(router.routes, [route]))
}

pub fn get(
  router: Router(req_body, res_body),
  path path: String,
  to handler: fn(Request(req_body)) -> Response(res_body),
) -> Router(req_body, res_body) {
  add_route(router, method: Get, path: path, handler: handler)
}

pub fn post(
  router: Router(req_body, res_body),
  path path: String,
  to handler: fn(Request(req_body)) -> Response(res_body),
) -> Router(req_body, res_body) {
  add_route(router, method: Post, path: path, handler: handler)
}

pub fn put(
  router: Router(req_body, res_body),
  path path: String,
  to handler: fn(Request(req_body)) -> Response(res_body),
) -> Router(req_body, res_body) {
  add_route(router, method: Put, path: path, handler: handler)
}

pub fn delete(
  router: Router(req_body, res_body),
  path path: String,
  to handler: fn(Request(req_body)) -> Response(res_body),
) -> Router(req_body, res_body) {
  add_route(router, method: Delete, path: path, handler: handler)
}

pub fn patch(
  router: Router(req_body, res_body),
  path path: String,
  to handler: fn(Request(req_body)) -> Response(res_body),
) -> Router(req_body, res_body) {
  add_route(router, method: Patch, path: path, handler: handler)
}

pub fn handle(
  router: Router(req_body, res_body),
  request: Request(req_body),
  not_found: fn() -> Response(res_body),
) -> Response(res_body) {
  let matching_route =
    list.find(router.routes, fn(r) {
      r.method == request.method && r.path == request.path
    })

  case matching_route {
    Ok(Route(handler: h, ..)) -> h(request)
    Error(_) -> not_found()
  }
}
