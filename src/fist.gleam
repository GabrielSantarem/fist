import gleam/http.{type Method}
import gleam/http/response.{type Response}
import mist.{type Connection}

pub opaque type Route(body) {
  Route(method: Method, path: String, handler: fn(Connection) -> Response(body))
}

pub type Router(body) {
  Router(routes: List(Route(body)))
}

pub fn new() -> Router(body) {
  Router(routes: [])
}

pub fn get(
  router: Router(body),
  path: String,
  handler: fn(Connection) -> Response(body),
) -> Router(body) {
  let route = Route(method: http.Get, path: path, handler: handler)
  Router(routes: [route, ..router.routes])
}
