import fist
import gleam/http.{Get}
import gleam/http/request
import gleam/int
import gleeunit/should

// Tipos para testar o polimorfismo de contexto
pub type RootContext {
  RootContext(id: Int)
}

pub type SubContext {
  SubContext(name: String)
}

fn root_handler(_req, ctx: RootContext, _params) {
  "root-" <> int.to_string(ctx.id)
}

fn sub_handler(_req, ctx: SubContext, _params) {
  "sub-" <> ctx.name
}

pub fn mount_test() {
  let sub_router =
    fist.new()
    |> fist.get("/hello", sub_handler)

  let root_router =
    fist.new()
    |> fist.get("/status", root_handler)
    |> fist.mount("/api", sub_router, fn(ctx: RootContext) {
      SubContext(name: "transformed-" <> int.to_string(ctx.id))
    })

  // 1. Testa rota do root
  let req1 =
    request.new() |> request.set_method(Get) |> request.set_path("/status")
  fist.handle(root_router, req1, RootContext(id: 1), fn() { "404" })
  |> should.equal("root-1")

  // 2. Testa rota montada com contexto transformado
  let req2 =
    request.new() |> request.set_method(Get) |> request.set_path("/api/hello")
  fist.handle(root_router, req2, RootContext(id: 1), fn() { "404" })
  |> should.equal("sub-transformed-1")
}
