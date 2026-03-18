import fist
import gleam/dict
import gleam/http.{Get}
import gleam/http/request
import gleam/http/response
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
