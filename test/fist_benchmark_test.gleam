import fist
import gleam/http.{Get}
import gleam/http/request
import gleeunit/should

fn middleware(next) {
  fn(req, ctx, params) { next(req, ctx, params) <> "->traversed" }
}

pub fn wrap_performance_test() {
  let router =
    fist.new()
    |> fist.get("/ping", fn(_, _, _) { "pong" })
    // Aplica o middleware 5 vezes na travessia
    |> fist.wrap(middleware)
    |> fist.wrap(middleware)
    |> fist.wrap(middleware)
    |> fist.wrap(middleware)
    |> fist.wrap(middleware)

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/ping")

  // O resultado deve ter 5 camadas de "->traversed"
  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("pong->traversed->traversed->traversed->traversed->traversed")
}

pub fn group_middleware_test() {
  let router =
    fist.new()
    |> fist.group(at: "/api", with: [middleware], defining: fn(r) {
      r |> fist.get("/v1", fn(_, _, _) { "v1" })
    })

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/api/v1")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("v1->traversed")
}
