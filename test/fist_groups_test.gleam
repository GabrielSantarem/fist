import fist
import gleam/dict
import gleam/http.{Get, Post}
import gleam/http/request
import gleam/int
import gleam/list
import gleeunit/should

// Tipos para testar o polimorfismo de contexto
pub type RootContext {
  RootContext(id: Int)
}

pub type SubContext {
  SubContext(name: String)
}

pub type DeepContext {
  DeepContext(depth: Int, name: String)
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

// Testa montagem de sub-router com prefixo dinâmico (:org_id)
pub fn dynamic_prefix_mount_test() {
  let sub_router =
    fist.new()
    |> fist.get("/members/:member_id", fn(_req, _ctx, params) {
      let org = dict.get(params, "org_id") |> should.be_ok
      let member = dict.get(params, "member_id") |> should.be_ok
      org <> ":" <> member
    })

  let root_router =
    fist.new()
    |> fist.mount("/orgs/:org_id", sub_router, fn(c) { c })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/orgs/acme/members/alice")

  fist.handle(root_router, req, Nil, fn() { "404" })
  |> should.equal("acme:alice")

  // Verifica inspeção de rota com prefixo dinâmico
  let routes = fist.inspect(root_router)
  let assert Ok(route_info) = list.first(routes)
  route_info.path |> should.equal("/orgs/:org_id/members/:member_id")
  route_info.params |> should.equal(["org_id", "member_id"])
}

// Testa uso básico do fist.group
pub fn group_basic_test() {
  let router =
    fist.new()
    |> fist.group(at: "/v1", with: [], defining: fn(r) {
      r
      |> fist.get("/users", fn(_, _, _) { "users_v1" })
      |> fist.post("/users", fn(_, _, _) { "created_v1" })
    })

  let req_get =
    request.new() |> request.set_method(Get) |> request.set_path("/v1/users")
  let req_post =
    request.new() |> request.set_method(Post) |> request.set_path("/v1/users")

  fist.handle(router, req_get, Nil, fn() { "404" })
  |> should.equal("users_v1")

  fist.handle(router, req_post, Nil, fn() { "404" })
  |> should.equal("created_v1")
}

// Testa que a ordem de execução dos middlewares em fist.group segue a ordem declarativa:
// O primeiro middleware da lista roda primeiro (lado externo da cebola).
pub fn group_middleware_execution_order_test() {
  let middleware_first = fn(next) {
    fn(req, ctx, params) {
      let res = next(req, ctx, params)
      "first(" <> res <> ")"
    }
  }

  let middleware_second = fn(next) {
    fn(req, ctx, params) {
      let res = next(req, ctx, params)
      "second(" <> res <> ")"
    }
  }

  let router =
    fist.new()
    |> fist.group(
      at: "/api",
      with: [middleware_first, middleware_second],
      defining: fn(r) { r |> fist.get("/data", fn(_, _, _) { "content" }) },
    )

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/api/data")

  // middleware_first envolve middleware_second, que envolve o handler:
  // handler -> "content"
  // second  -> "second(content)"
  // first   -> "first(second(content))"
  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("first(second(content))")
}

// Testa grupos aninhados com middlewares e prefixos combinados
pub fn nested_groups_test() {
  let mw_outer = fn(next) {
    fn(req, ctx, params) { next(req, ctx, params) <> "-outer" }
  }
  let mw_inner = fn(next) {
    fn(req, ctx, params) { next(req, ctx, params) <> "-inner" }
  }

  let router =
    fist.new()
    |> fist.group(at: "/api", with: [mw_outer], defining: fn(r1) {
      r1
      |> fist.group(at: "/v2", with: [mw_inner], defining: fn(r2) {
        r2 |> fist.get("/ping", fn(_, _, _) { "pong" })
      })
    })

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/api/v2/ping")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("pong-inner-outer")
}

// Testa fist.group com parâmetros dinâmicos no prefixo
pub fn group_with_dynamic_prefix_test() {
  let router =
    fist.new()
    |> fist.group(at: "/users/:user_id", with: [], defining: fn(r) {
      r
      |> fist.get("/profile", fn(_, _, params) {
        let uid = dict.get(params, "user_id") |> should.be_ok
        "profile of " <> uid
      })
      |> fist.get("/posts/:post_id", fn(_, _, params) {
        let uid = dict.get(params, "user_id") |> should.be_ok
        let pid = dict.get(params, "post_id") |> should.be_ok
        uid <> " post " <> pid
      })
    })

  let req1 =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/42/profile")
  fist.handle(router, req1, Nil, fn() { "404" })
  |> should.equal("profile of 42")

  let req2 =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/42/posts/99")
  fist.handle(router, req2, Nil, fn() { "404" })
  |> should.equal("42 post 99")
}

// Testa montagem de sub-roteador que contém rota raiz "/"
pub fn subrouter_with_root_route_mounted_test() {
  let sub =
    fist.new()
    |> fist.get("/", fn(_, _, _) { "sub root" })
    |> fist.get("/items", fn(_, _, _) { "sub items" })

  let router =
    fist.new()
    |> fist.get("/", fn(_, _, _) { "main root" })
    |> fist.mount("/admin", sub, fn(c) { c })

  // Rota raiz do sub-roteador vira "/admin" no roteador pai
  let req_admin =
    request.new() |> request.set_method(Get) |> request.set_path("/admin")
  fist.handle(router, req_admin, Nil, fn() { "404" })
  |> should.equal("sub root")

  // Com trailing slash "/admin/"
  let req_admin_slash =
    request.new() |> request.set_method(Get) |> request.set_path("/admin/")
  fist.handle(router, req_admin_slash, Nil, fn() { "404" })
  |> should.equal("sub root")

  // Sub item "/admin/items"
  let req_items =
    request.new() |> request.set_method(Get) |> request.set_path("/admin/items")
  fist.handle(router, req_items, Nil, fn() { "404" })
  |> should.equal("sub items")

  // Rota raiz do roteador pai intacta
  let req_main =
    request.new() |> request.set_method(Get) |> request.set_path("/")
  fist.handle(router, req_main, Nil, fn() { "404" })
  |> should.equal("main root")
}

// Testa montagem na raiz ("/" ou "") fundindo rotas
pub fn mount_at_root_test() {
  let sub =
    fist.new()
    |> fist.get("/extra", fn(_, _, _) { "extra" })

  let router =
    fist.new()
    |> fist.get("/original", fn(_, _, _) { "original" })
    |> fist.mount("/", sub, fn(c) { c })

  let req1 =
    request.new() |> request.set_method(Get) |> request.set_path("/original")
  fist.handle(router, req1, Nil, fn() { "404" })
  |> should.equal("original")

  let req2 =
    request.new() |> request.set_method(Get) |> request.set_path("/extra")
  fist.handle(router, req2, Nil, fn() { "404" })
  |> should.equal("extra")
}

// Testa múltiplos níveis de montagem com diferentes tipos de contexto
pub fn deeply_nested_mount_test() {
  let level3 =
    fist.new()
    |> fist.get("/leaf", fn(_req, ctx: DeepContext, _params) {
      "leaf:" <> ctx.name <> ":" <> int.to_string(ctx.depth)
    })

  let level2 =
    fist.new()
    |> fist.mount("/level3", level3, fn(ctx: SubContext) {
      DeepContext(depth: 3, name: ctx.name <> "-deep")
    })

  let root =
    fist.new()
    |> fist.mount("/level2", level2, fn(ctx: RootContext) {
      SubContext(name: "root-" <> int.to_string(ctx.id))
    })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/level2/level3/leaf")

  fist.handle(root, req, RootContext(id: 7), fn() { "404" })
  |> should.equal("leaf:root-7-deep:3")
}
