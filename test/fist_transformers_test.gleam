import fist
import gleam/dict
import gleam/http.{Delete, Get, Post}
import gleam/http/request
import gleam/int
import gleam/list
import gleam/result
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// 1. Middleware com Short-Circuit (Early Return)
// Se o middleware decidir abortar, o handler original JAMAIS deve ser executado
pub fn middleware_short_circuit_test() {
  let auth_middleware = fn(next) {
    fn(req, ctx, params) {
      case request.get_header(req, "authorization") {
        Ok("Bearer secret") -> next(req, ctx, params)
        _ -> "401 Unauthorized"
      }
    }
  }

  let router =
    fist.new()
    |> fist.get("/protected", fn(_, _, _) {
      // Se este handler for executado sem token, o teste falha
      "sensitive data"
    })
    |> fist.wrap(auth_middleware)

  // Requisição sem token -> deve retornar 401 do middleware
  let req_unauth = request.new() |> request.set_path("/protected")
  fist.handle(router, req_unauth, Nil, fn() { "404" })
  |> should.equal("401 Unauthorized")

  // Requisição com token -> executa o handler e retorna os dados
  let req_auth =
    request.new()
    |> request.set_path("/protected")
    |> request.prepend_header("authorization", "Bearer secret")
  fist.handle(router, req_auth, Nil, fn() { "404" })
  |> should.equal("sensitive data")
}

// 2. Middleware modificando Request e Params antes de repassar ao handler
pub fn middleware_mutating_request_and_params_test() {
  let enrich_middleware = fn(next) {
    fn(req, ctx, params) {
      let enriched_req = request.prepend_header(req, "x-request-id", "req-123")
      let enriched_params = dict.insert(params, "injected", "present")
      next(enriched_req, ctx, enriched_params)
    }
  }

  let router =
    fist.new()
    |> fist.get("/audit/:id", fn(req, _, params) {
      let id = dict.get(params, "id") |> result.unwrap("")
      let injected = dict.get(params, "injected") |> result.unwrap("")
      let req_id = request.get_header(req, "x-request-id") |> result.unwrap("")
      id <> ":" <> injected <> ":" <> req_id
    })
    |> fist.wrap(enrich_middleware)

  let req = request.new() |> request.set_path("/audit/999")
  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("999:present:req-123")
}

// 3. fist.wrap deve envelopar rotas em múltiplos métodos HTTP simultâneos
pub fn wrap_multiple_http_methods_test() {
  let tag_middleware = fn(next) {
    fn(req, ctx, params) { "[" <> next(req, ctx, params) <> "]" }
  }

  let router =
    fist.new()
    |> fist.get("/items", fn(_, _, _) { "get_items" })
    |> fist.post("/items", fn(_, _, _) { "post_items" })
    |> fist.delete("/items/:id", fn(_, _, params) {
      "delete_" <> result.unwrap(dict.get(params, "id"), "")
    })
    |> fist.wrap(tag_middleware)

  let req_get =
    request.new() |> request.set_method(Get) |> request.set_path("/items")
  fist.handle(router, req_get, Nil, fn() { "404" })
  |> should.equal("[get_items]")

  let req_post =
    request.new() |> request.set_method(Post) |> request.set_path("/items")
  fist.handle(router, req_post, Nil, fn() { "404" })
  |> should.equal("[post_items]")

  let req_delete =
    request.new()
    |> request.set_method(Delete)
    |> request.set_path("/items/55")
  fist.handle(router, req_delete, Nil, fn() { "404" })
  |> should.equal("[delete_55]")
}

// 4. wrap e map_context preservam metadados (describe) em fist.inspect
pub fn wrap_and_map_context_preserve_metadata_test() {
  let dummy_mw = fn(next) { fn(req, ctx, params) { next(req, ctx, params) } }

  let router =
    fist.new()
    |> fist.get("/users", fn(_, _, _) { "users" })
    |> fist.describe("List all users")
    |> fist.get("/users/:id", fn(_, _, _) { "user" })
    |> fist.describe("Get single user")
    |> fist.wrap(dummy_mw)
    |> fist.map_context(fn(c: String) { c })

  let routes = fist.inspect(router)
  list.length(routes) |> should.equal(2)

  let assert Ok(list_route) = list.find(routes, fn(r) { r.path == "/users" })
  list_route.description |> should.equal("List all users")

  let assert Ok(get_route) = list.find(routes, fn(r) { r.path == "/users/:id" })
  get_route.description |> should.equal("Get single user")
  get_route.params |> should.equal(["id"])
}

// 5. Encadeamento composto de múltiplos fist.map
pub fn chained_map_composition_test() {
  let router =
    fist.new()
    |> fist.get("/calc", fn(_, _, _) { 5 })
    |> fist.map(fn(n) { n + 10 })
    |> fist.map(fn(n) { n * 2 })
    |> fist.map(fn(n) { "Result: " <> int.to_string(n) })

  let req = request.new() |> request.set_path("/calc")
  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("Result: 30")
}

// 6. Encadeamento composto de múltiplos fist.map_context (Contravariante)
pub type GlobalCtx {
  GlobalCtx(token: String, tenant: String)
}

pub type TenantCtx {
  TenantCtx(tenant: String)
}

pub type SimpleCtx {
  SimpleCtx(name: String)
}

pub fn chained_map_context_test() {
  // Handler requer SimpleCtx
  let router =
    fist.new()
    |> fist.get("/whoami", fn(_, ctx: SimpleCtx, _) { "hello " <> ctx.name })
    // Transforma SimpleCtx -> TenantCtx
    |> fist.map_context(fn(t: TenantCtx) { SimpleCtx(name: t.tenant) })
    // Transforma TenantCtx -> GlobalCtx
    |> fist.map_context(fn(g: GlobalCtx) { TenantCtx(tenant: g.tenant) })

  let req = request.new() |> request.set_path("/whoami")
  let global = GlobalCtx(token: "xyz", tenant: "acme_corp")

  fist.handle(router, req, global, fn() { "404" })
  |> should.equal("hello acme_corp")
}

// 7. Pipeline integrado: Rota dinâmica + 2 Middlewares + map_context + map
pub fn combined_transformations_pipeline_test() {
  let mw1 = fn(next) {
    fn(req, ctx, params) { "{" <> next(req, ctx, params) <> "}" }
  }
  let mw2 = fn(next) {
    fn(req, ctx, params) { "<" <> next(req, ctx, params) <> ">" }
  }

  let router =
    fist.new()
    |> fist.get("/org/:org_id/user/:user_id", fn(_, ctx_num: Int, params) {
      let org = result.unwrap(dict.get(params, "org_id"), "")
      let user = result.unwrap(dict.get(params, "user_id"), "")
      // Retorna Int
      int.to_string(ctx_num) <> ":" <> org <> ":" <> user
    })
    |> fist.wrap(mw2)
    |> fist.wrap(mw1)
    |> fist.map_context(fn(str: String) {
      // Converte contexto de String para Int
      result.unwrap(int.parse(str), 0)
    })
    |> fist.map(fn(s) { "OUT:" <> s })

  let req = request.new() |> request.set_path("/org/10/user/42")
  fist.handle(router, req, "99", fn() { "404" })
  |> should.equal("OUT:{<99:10:42>}")
}

// 8. Transformações em roteador vazio não devem quebrar novas rotas
pub fn empty_router_transformation_test() {
  let mw = fn(next) {
    fn(req, ctx, params) { "wrapped:" <> next(req, ctx, params) }
  }

  // Aplicar wrap num roteador sem rotas não deve crashar
  let empty_wrapped =
    fist.new()
    |> fist.wrap(mw)
    |> fist.map(fn(s) { s <> "!" })

  // E podemos registrar rotas normalmente após isso
  let router =
    empty_wrapped
    |> fist.get("/ping", fn(_, _, _) { "pong" })

  let req = request.new() |> request.set_path("/ping")
  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("pong")
}

// 9. describe após wrap ou mount não deve associar indevidamente a rotas anteriores
pub fn describe_after_wrap_and_mount_clears_pointer_test() {
  let sub =
    fist.new()
    |> fist.get("/sub_route", fn(_, _, _) { "sub" })

  let router =
    fist.new()
    |> fist.get("/target", fn(_, _, _) { "target" })
    |> fist.wrap(fn(next) { fn(req, ctx, p) { next(req, ctx, p) } })
    // Deve ser ignorado porque wrap limpou o last_added
    |> fist.describe("Ignored description")
    |> fist.mount("/mounted", sub, fn(c) { c })
    // Deve ser ignorado porque mount limpou o last_added
    |> fist.describe("Ignored mount description")

  let routes = fist.inspect(router)
  let assert Ok(target) = list.find(routes, fn(r) { r.path == "/target" })
  target.description |> should.equal("")
}
