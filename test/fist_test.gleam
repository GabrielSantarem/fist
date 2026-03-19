import fist
import gleam/dict
import gleam/http.{Get}
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/result
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn dynamic_route_test() {
  let handler = fn(_req, params) {
    let name = dict.get(params, "name") |> result_unwrap("stranger")
    response.new(200)
    |> response.set_body("Hello, " <> name <> "!")
  }

  let router =
    fist.new()
    |> fist.get("/hello/:name", to: handler)

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/hello/tomate")
    |> request.set_body("")

  let res =
    fist.handle(router, req, fn() {
      response.new(404) |> response.set_body("Not Found")
    })

  res.status |> should.equal(200)
  res.body |> should.equal("Hello, tomate!")
}

pub fn nested_dynamic_route_test() {
  let handler = fn(_req, params) {
    let user_id = dict.get(params, "user_id") |> result_unwrap("0")
    let post_id = dict.get(params, "post_id") |> result_unwrap("0")
    response.new(200)
    |> response.set_body("User " <> user_id <> ", Post " <> post_id)
  }

  let router =
    fist.new()
    |> fist.get("/users/:user_id/posts/:post_id", to: handler)

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/123/posts/456")
    |> request.set_body("")

  let res =
    fist.handle(router, req, fn() { response.new(404) |> response.set_body("") })

  res.status |> should.equal(200)
  res.body |> should.equal("User 123, Post 456")
}

fn result_unwrap(res, default) {
  case res {
    Ok(v) -> v
    Error(_) -> default
  }
}

// Rota não encontrada deve retornar o fallback
pub fn not_found_test() {
  let router = fist.new()

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/nao/existe")
    |> request.set_body("")

  let res =
    fist.handle(router, req, fn() {
      response.new(404) |> response.set_body("Not Found")
    })

  res.status |> should.equal(404)
  res.body |> should.equal("Not Found")
}

// Método errado na rota certa deve retornar 404
pub fn wrong_method_test() {
  let router =
    fist.new()
    |> fist.get("/hello", to: fn(_req, _params) {
      response.new(200) |> response.set_body("ok")
    })

  let req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_path("/hello")
    |> request.set_body("")

  let res =
    fist.handle(router, req, fn() {
      response.new(404) |> response.set_body("Not Found")
    })

  res.status |> should.equal(404)
}

// Rota estática tem prioridade sobre rota dinâmica
pub fn static_takes_priority_over_dynamic_test() {
  let dynamic_handler = fn(_req, _params) {
    response.new(200) |> response.set_body("dynamic")
  }
  let static_handler = fn(_req, _params) {
    response.new(200) |> response.set_body("static")
  }

  let router =
    fist.new()
    |> fist.get("/users/:id", to: dynamic_handler)
    |> fist.get("/users/me", to: static_handler)

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/me")
    |> request.set_body("")

  let res =
    fist.handle(router, req, fn() { response.new(404) |> response.set_body("") })

  res.status |> should.equal(200)
  res.body |> should.equal("static")
}

// Mesma rota com métodos diferentes deve funcionar independente
pub fn same_path_different_methods_test() {
  let router =
    fist.new()
    |> fist.get("/items", to: fn(_req, _params) {
      response.new(200) |> response.set_body("get items")
    })
    |> fist.post("/items", to: fn(_req, _params) {
      response.new(201) |> response.set_body("created item")
    })

  let get_req =
    request.new()
    |> request.set_method(http.Get)
    |> request.set_path("/items")
    |> request.set_body("")

  let post_req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_path("/items")
    |> request.set_body("")

  fist.handle(router, get_req, fn() {
    response.new(404) |> response.set_body("")
  }).body
  |> should.equal("get items")

  fist.handle(router, post_req, fn() {
    response.new(404) |> response.set_body("")
  }).body
  |> should.equal("created item")
}

// Rota raiz "/"
pub fn root_route_test() {
  let router =
    fist.new()
    |> fist.get("/", to: fn(_req, _params) {
      response.new(200) |> response.set_body("root")
    })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/")
    |> request.set_body("")

  let res =
    fist.handle(router, req, fn() { response.new(404) |> response.set_body("") })

  res.status |> should.equal(200)
  res.body |> should.equal("root")
}

// Parâmetro ausente deve usar o fallback do result.unwrap
pub fn missing_param_fallback_test() {
  let handler = fn(_req, params) {
    let name = dict.get(params, "name") |> result_unwrap("stranger")
    response.new(200) |> response.set_body("Hello, " <> name <> "!")
  }

  // Rota sem :name, então o dict de params vai estar vazio
  let router =
    fist.new()
    |> fist.get("/hello", to: handler)

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/hello")
    |> request.set_body("")

  let res =
    fist.handle(router, req, fn() { response.new(404) |> response.set_body("") })

  res.body |> should.equal("Hello, stranger!")
}

pub fn response_helpers_test() {
  let router =
    fist.new()
    |> fist.get("/ok", to: fn(_, _) { fist.ok("ok") })
    |> fist.get("/text", to: fn(_, _) { fist.text("text") })
    |> fist.get("/json", to: fn(_, _) { fist.json("{\"a\":1}") })

  let req = fn(path) {
    request.new() |> request.set_method(Get) |> request.set_path(path)
  }

  let res_ok = fist.handle(router, req("/ok"), fn() { response.new(404) |> response.set_body("") })
  res_ok.status |> should.equal(200)
  res_ok.body |> should.equal("ok")

  let res_text = fist.handle(router, req("/text"), fn() { response.new(404) |> response.set_body("") })
  res_text.status |> should.equal(200)
  response.get_header(res_text, "content-type") |> should.equal(Ok("text/plain"))

  let res_json = fist.handle(router, req("/json"), fn() { response.new(404) |> response.set_body("") })
  response.get_header(res_json, "content-type") |> should.equal(Ok("application/json"))
}

pub fn map_test() {
  let router =
    fist.new()
    |> fist.get("/hello", to: fn(_, _) { "hello" })
    |> fist.map(fn(s) { "mapped " <> s })

  let req = request.new() |> request.set_method(Get) |> request.set_path("/hello")
  let res = fist.handle(router, req, fn() { "not found" })

  res |> should.equal("mapped hello")
}

pub type MyAnswer {
  Success(String)
  Failure
}

pub fn adt_return_test() {
  let router =
    fist.new()
    |> fist.get("/success", to: fn(_, _) { Success("yay") })
    |> fist.get("/fail", to: fn(_, _) { Failure })

  let req = fn(path) {
    request.new() |> request.set_method(Get) |> request.set_path(path)
  }

  fist.handle(router, req("/success"), fn() { Failure }) |> should.equal(Success("yay"))
  fist.handle(router, req("/fail"), fn() { Failure }) |> should.equal(Failure)
}

pub fn render_mist_test() {
  let res = fist.ok("hello")
  let mist_res = fist.render_mist(res)

  mist_res.status |> should.equal(200)
  // O corpo do mist_res é mist.ResponseData, difícil de comparar diretamente aqui sem importar mist e bytes_tree
  // Mas se compilou e executou render_mist sem pânico, já é um bom sinal.
}

// Teste de Mapeamento em Múltiplas Camadas
pub fn multi_layer_map_test() {
  let router =
    fist.new()
    |> fist.get("/double/:n", to: fn(_req, params) {
      // Retorna um Int
      let n =
        dict.get(params, "n")
        |> result.unwrap("0")
        |> int.parse
        |> result.unwrap(0)
      n * 2
    })
    // Camada 1: Converte Int -> String
    |> fist.map(fn(n) { "O resultado é " <> int.to_string(n) })
    // Camada 2: Converte String -> Response(String)
    |> fist.map(fist.ok)
    // Camada 3: Adiciona um Header customizado
    |> fist.map(fn(res) { response.prepend_header(res, "x-fist", "power") })

  let req =
    request.new() |> request.set_path("/double/21") |> request.set_method(Get)
  let res = fist.handle(router, req, fn() { fist.ok("not found") })

  res.body |> should.equal("O resultado é 42")
  res.status |> should.equal(200)
  response.get_header(res, "x-fist") |> should.equal(Ok("power"))
}

// Teste de Composição de Handlers (Pipeline de Middleware)
pub fn functional_pipeline_test() {
  // Uma função que simula um middleware de autenticação simples
  let with_auth = fn(handler: fn(request.Request(String), dict.Dict(String, String)) -> String) {
    fn(req, params) {
      case request.get_header(req, "authorization") {
        Ok("secret") -> handler(req, params)
        _ -> "Unauthorized"
      }
    }
  }

  let router =
    fist.new()
    |> fist.get("/secret", to: with_auth(fn(_, _) { "Top Secret Data" }))
    // Map pode ser usado para limpar o retorno (ex: uppercase)
    |> fist.map(string.uppercase)

  let req_no_auth =
    request.new() |> request.set_path("/secret") |> request.set_method(Get)
  fist.handle(router, req_no_auth, fn() { "" }) |> should.equal("UNAUTHORIZED")

  let req_auth =
    request.new()
    |> request.set_path("/secret")
    |> request.set_method(Get)
    |> request.set_header("authorization", "secret")

  fist.handle(router, req_auth, fn() { "" }) |> should.equal("TOP SECRET DATA")
}




