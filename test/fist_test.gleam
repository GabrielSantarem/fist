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
