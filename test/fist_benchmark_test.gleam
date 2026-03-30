import fist
import gleam/http.{Get}
import gleam/http/request
import gleam/int
import gleam/string
import gleeunit/should

fn middleware(next) {
  fn(req, ctx, params) { next(req, ctx, params) <> "." }
}

// 1. TESTE DE ESTRESSE: 100 middlewares
pub fn heavy_middleware_stress_test() {
  let router =
    fist.new()
    |> fist.get("/ping", fn(_, _, _) { "pong" })
    // De 0 a 100 (exclusivo) = 100 iterações exatas
    |> int.range(from: 0, to: 10_000, with: _, run: fn(acc, _) {
      fist.wrap(acc, middleware)
    })

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/ping")

  let res = fist.handle(router, req, Nil, fn() { "404" })
  string.length(res) |> should.equal(10_004)
}

// 2. TESTE DE ORDEM (Middleware Order)
fn append_id(id: String) {
  fn(next) { fn(req, ctx, params) { next(req, ctx, params) <> id } }
}

pub fn middleware_order_test() {
  let router =
    fist.new()
    |> fist.get("/order", fn(_, _, _) { "root" })
    |> fist.wrap(append_id("1"))
    |> fist.wrap(append_id("2"))

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/order")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("root12")
}

// Helper para evitar aviso de padrão inalcançável
fn check_auth(_req) -> Bool {
  False
}

// 3. TESTE DE SEGURANÇA: Early Return (Short-circuit)
fn auth_middleware(next) {
  fn(req, ctx, params) {
    case check_auth(req) {
      True -> next(req, ctx, params)
      False -> "Unauthorized"
    }
  }
}

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
