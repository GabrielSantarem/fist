import fist
import gleam/dict
import gleam/http.{Delete, Get, Head, Options, Post, Put}
import gleam/http/request
import gleam/list
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

  let router =
    fist.new()
    |> fist.mount("/admin", admin_router, fn(c) { c })
    |> fist.wrap(middleware_a)

  // 1. Rota admin deve ter A e B
  let req1 =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/admin/dashboard")
  fist.handle(router, req1, Nil, fn() { "404" })
  |> should.equal("dashboardBA")

  // 2. Adicionando rota DEPOIS do wrap
  let root_router =
    router
    |> fist.get("/home", fn(_, _, _) { "home" })

  let req2 =
    request.new() |> request.set_method(Get) |> request.set_path("/home")
  fist.handle(root_router, req2, Nil, fn() { "404" })
  |> should.equal("home")
}

// 1. Decodificação de URL percent-encoding em parâmetros dinâmicos
pub fn url_percent_encoded_params_test() {
  let router =
    fist.new()
    |> fist.get("/search/:query", fn(_, _, params) {
      dict.get(params, "query") |> should.be_ok
    })
    |> fist.get("/user/:name", fn(_, _, params) {
      dict.get(params, "name") |> should.be_ok
    })

  // Espaço codificado como %20
  let req_space =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/search/gleam%20lang")
  fist.handle(router, req_space, Nil, fn() { "404" })
  |> should.equal("gleam lang")

  // Caracteres UTF-8 codificados (ex: João -> Jo%C3%A3o)
  let req_utf8 =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/user/Jo%C3%A3o")
  fist.handle(router, req_utf8, Nil, fn() { "404" })
  |> should.equal("João")

  // Sinal de mais codificado como %2B (ex: c++ -> c%2B%2B)
  let req_plus =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/search/c%2B%2B")
  fist.handle(router, req_plus, Nil, fn() { "404" })
  |> should.equal("c++")
}

// 2. Caminhos estáticos com caracteres codificados / UTF-8
pub fn url_percent_encoded_static_path_test() {
  let router =
    fist.new()
    |> fist.get("/café", fn(_, _, _) { "cafe ok" })

  // Requisição enviada com percent-encoding para o caractere 'é' (%C3%A9)
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/caf%C3%A9")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("cafe ok")
}

// 3. Limpeza defensiva de Query Strings e Fragments no caminho da requisição
pub fn query_string_and_fragment_in_path_test() {
  let router =
    fist.new()
    |> fist.get("/users", fn(_, _, _) { "users list" })
    |> fist.get("/users/:id", fn(_, _, params) {
      let id = dict.get(params, "id") |> should.be_ok
      "user " <> id
    })

  // Requisição com query string no path: /users?page=2&limit=50
  let req_query =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users?page=2&limit=50")
  fist.handle(router, req_query, Nil, fn() { "404" })
  |> should.equal("users list")

  // Requisição com fragment no path: /users#top
  let req_fragment =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users#top")
  fist.handle(router, req_fragment, Nil, fn() { "404" })
  |> should.equal("users list")

  // Rota dinâmica com query string
  let req_dynamic_query =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/42?active=true")
  fist.handle(router, req_dynamic_query, Nil, fn() { "404" })
  |> should.equal("user 42")
}

// 4. Backtracking profundo: rota estática parcial falha e faz fallback para ramo dinâmico
pub fn deep_backtracking_test() {
  let router =
    fist.new()
    |> fist.get("/projects/settings/general", fn(_, _, _) { "settings general" })
    |> fist.get("/projects/:project_id/members", fn(_, _, params) {
      let pid = dict.get(params, "project_id") |> should.be_ok
      "project " <> pid <> " members"
    })

  // "settings" bate com o primeiro segmento estático de /projects/settings/general,
  // mas o segundo segmento "members" não bate com "general".
  // O roteador deve fazer backtracking e casar com /projects/:project_id/members!
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/projects/settings/members")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("project settings members")
}

// 5. Rota dinâmica definida ANTES de rota estática (rota estática deve prevalecer)
pub fn dynamic_defined_before_static_test() {
  let router =
    fist.new()
    |> fist.get("/posts/:id", fn(_, _, params) {
      let id = dict.get(params, "id") |> should.be_ok
      "dynamic " <> id
    })
    |> fist.get("/posts/latest", fn(_, _, _) { "static latest" })

  let req_static =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/posts/latest")
  fist.handle(router, req_static, Nil, fn() { "404" })
  |> should.equal("static latest")

  let req_dynamic =
    request.new() |> request.set_method(Get) |> request.set_path("/posts/123")
  fist.handle(router, req_dynamic, Nil, fn() { "404" })
  |> should.equal("dynamic 123")
}

// 6. Múltiplos parâmetros dinâmicos consecutivos (ex: /:lang/:region/:topic)
pub fn multiple_consecutive_dynamic_segments_test() {
  let router =
    fist.new()
    |> fist.get("/:lang/:region/:topic", fn(_, _, params) {
      let lang = dict.get(params, "lang") |> should.be_ok
      let region = dict.get(params, "region") |> should.be_ok
      let topic = dict.get(params, "topic") |> should.be_ok
      lang <> "/" <> region <> "/" <> topic
    })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/pt/br/gleam")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("pt/br/gleam")
}

// 7. Parâmetro dinâmico na raiz (ex: /:slug) coexistindo com a rota raiz ("/")
pub fn root_level_dynamic_route_test() {
  let router =
    fist.new()
    |> fist.get("/", fn(_, _, _) { "home" })
    |> fist.get("/:slug", fn(_, _, params) {
      let slug = dict.get(params, "slug") |> should.be_ok
      "page " <> slug
    })

  let req_root =
    request.new() |> request.set_method(Get) |> request.set_path("/")
  fist.handle(router, req_root, Nil, fn() { "404" })
  |> should.equal("home")

  let req_slug =
    request.new() |> request.set_method(Get) |> request.set_path("/about")
  fist.handle(router, req_slug, Nil, fn() { "404" })
  |> should.equal("page about")
}

// 8. Sobrescrita de rota (Route Overriding): registrar o mesmo método e path substitui o handler
pub fn route_overwriting_test() {
  let router =
    fist.new()
    |> fist.get("/endpoint", fn(_, _, _) { "version 1" })
    |> fist.get("/endpoint", fn(_, _, _) { "version 2" })

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/endpoint")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("version 2")
}

// 9. Valores com caracteres especiais em parâmetros dinâmicos (e-mails, UUIDs, pontos)
pub fn special_characters_in_parameter_values_test() {
  let router =
    fist.new()
    |> fist.get("/users/by-email/:email", fn(_, _, params) {
      let email = dict.get(params, "email") |> should.be_ok
      "email:" <> email
    })
    |> fist.get("/files/:filename", fn(_, _, params) {
      let file = dict.get(params, "filename") |> should.be_ok
      "file:" <> file
    })
    |> fist.get("/records/:uuid", fn(_, _, params) {
      let uuid = dict.get(params, "uuid") |> should.be_ok
      "uuid:" <> uuid
    })

  // E-mail com @ e +
  let req_email =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/by-email/user+tag@domain.co.uk")
  fist.handle(router, req_email, Nil, fn() { "404" })
  |> should.equal("email:user+tag@domain.co.uk")

  // Arquivo com extensão (.min.js)
  let req_file =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/files/bundle.min.js")
  fist.handle(router, req_file, Nil, fn() { "404" })
  |> should.equal("file:bundle.min.js")

  // UUID
  let req_uuid =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/records/550e8400-e29b-41d4-a716-446655440000")
  fist.handle(router, req_uuid, Nil, fn() { "404" })
  |> should.equal("uuid:550e8400-e29b-41d4-a716-446655440000")
}

// 10. Novos helpers HTTP: head e options
pub fn head_and_options_helpers_test() {
  let router =
    fist.new()
    |> fist.head("/health", fn(_, _, _) { "head-ok" })
    |> fist.options("/cors", fn(_, _, _) { "options-ok" })

  let req_head =
    request.new() |> request.set_method(Head) |> request.set_path("/health")
  fist.handle(router, req_head, Nil, fn() { "404" })
  |> should.equal("head-ok")

  let req_options =
    request.new() |> request.set_method(Options) |> request.set_path("/cors")
  fist.handle(router, req_options, Nil, fn() { "404" })
  |> should.equal("options-ok")
}

// 11. allowed_methods para suporte a 405 Method Not Allowed e CORS
pub fn allowed_methods_test() {
  let router =
    fist.new()
    |> fist.get("/items", fn(_, _, _) { "list" })
    |> fist.post("/items", fn(_, _, _) { "create" })
    |> fist.put("/items/:id", fn(_, _, _) { "update" })
    |> fist.delete("/items/:id", fn(_, _, _) { "delete" })

  let methods_items = fist.allowed_methods(router, "/items")
  list.contains(methods_items, Get) |> should.be_true
  list.contains(methods_items, Post) |> should.be_true
  list.contains(methods_items, Delete) |> should.be_false

  let methods_item_id = fist.allowed_methods(router, "/items/123")
  list.contains(methods_item_id, Put) |> should.be_true
  list.contains(methods_item_id, Delete) |> should.be_true
  list.contains(methods_item_id, Get) |> should.be_false

  let methods_unknown = fist.allowed_methods(router, "/unknown")
  methods_unknown |> should.equal([])
}

// 12. Método HTTP Customizado com fist.route (ex: WebDAV / HTTP PURGE)
pub fn custom_http_method_test() {
  let router =
    fist.new()
    |> fist.route(
      method: http.Other("PURGE"),
      path: "/cache/all",
      handler: fn(_, _, _) { "purged" },
    )

  let req =
    request.new()
    |> request.set_method(http.Other("PURGE"))
    |> request.set_path("/cache/all")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("purged")
}
