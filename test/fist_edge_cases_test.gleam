import fist
import gleam/http.{Get}
import gleam/http/request
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

fn middleware_a(next) {
  fn(req, ctx, params) { next(req, ctx, params) <> "A" }
}

fn middleware_b(next) {
  fn(req, ctx, params) { next(req, ctx, params) <> "B" }
}

pub fn hierarchical_middleware_test() {
  let admin_router =
    fist.new()
    |> fist.get("/dashboard", fn(_, _, _) { "dashboard" })
    |> fist.wrap(middleware_b)
  // Middleware B apenas para Admin

  let router =
    fist.new()
    |> fist.mount("/admin", admin_router, fn(c) { c })
    |> fist.wrap(middleware_a)
  // Middleware A para tudo o que já existe

  // 1. Rota admin deve ter A e B
  let req1 =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/admin/dashboard")
  fist.handle(router, req1, Nil, fn() { "404" })
  |> should.equal("dashboardBA")
  // Cebola: root -> B -> A

  // 2. Adicionando rota DEPOIS do wrap
  let root_router =
    router
    |> fist.get("/home", fn(_, _, _) { "home" })

  let req2 =
    request.new() |> request.set_method(Get) |> request.set_path("/home")
  fist.handle(root_router, req2, Nil, fn() { "404" })
  |> should.equal("home")
  // Sem A, como esperado na abordagem estática
}
