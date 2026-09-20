import fist
import gleam/http.{Get}
import gleam/http/request
import gleam/int
import gleam/string
import gleeunit/should

fn middleware(next) {
  fn(req, ctx, params) { next(req, ctx, params) <> "." }
}

/// Middleware Stress Test:
/// Evaluates dispatch performance and recursion stability across 10,000 stacked middleware layers.
pub fn heavy_middleware_stress_test() {
  let router =
    fist.new()
    |> fist.get("/ping", fn(_, _, _) { "pong" })
    |> int.range(from: 0, to: 10_000, with: _, run: fn(acc, _) {
      fist.wrap(acc, middleware)
    })

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/ping")

  let res = fist.handle(router, req, Nil, fn() { "404" })
  string.length(res) |> should.equal(10_004)
}

fn append_id(id: String) {
  fn(next) { fn(req, ctx, params) { next(req, ctx, params) <> id } }
}

/// Static Wrap Middleware Order:
/// Wrap applies onion layering where the most recently wrapped middleware is the outermost layer.
pub fn middleware_order_test() {
  let router =
    fist.new()
    |> fist.get("/order", fn(_, _, _) { "root" })
    |> fist.wrap(append_id("1"))
    |> fist.wrap(append_id("2"))

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/order")

  // Evaluated: append_id("2")(append_id("1")(handler())) -> "root12"
  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("root12")
}

fn check_auth(_req) -> Bool {
  False
}

fn auth_middleware(next) {
  fn(req, ctx, params) {
    case check_auth(req) {
      True -> next(req, ctx, params)
      False -> "Unauthorized"
    }
  }
}

/// Middleware Short-Circuiting Baseline:
/// Middleware returning early halts the pipeline before handler invocation.
pub fn middleware_short_circuit_test() {
  let router =
    fist.new()
    |> fist.get("/private", fn(_, _, _) { "Secret Data" })
    |> fist.wrap(auth_middleware)

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/private")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("Unauthorized")
}
