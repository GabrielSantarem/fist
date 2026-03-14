import fist
import gleam/http.{Get}
import gleam/http/request
import gleam/http/response
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn router_declaration_test() {
  let handler = fn(_req) {
    response.new(200)
    |> response.set_body("Hello!")
  }

  // Declarative declaration using pipes (chaining)
  let router =
    fist.new()
    |> fist.get("/", to: handler)
    |> fist.post("/data", to: handler)

  // Verify it handles a GET request to "/"
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/")
    |> request.set_body("") // Using String as body for easy testing
  
  let res = fist.handle(router, req, fn() { 
    response.new(404) |> response.set_body("Not Found") 
  })

  res.status
  |> should.equal(200)

  res.body
  |> should.equal("Hello!")
}

pub fn not_found_test() {
  let router = fist.new()

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/unknown")
    |> request.set_body("")

  let res = fist.handle(router, req, fn() { 
    response.new(404) |> response.set_body("Not Found") 
  })

  res.status
  |> should.equal(404)
}
