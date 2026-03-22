import fist
import gleam/dict
import gleam/http/request
import gleam/result
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// 1. Trailing Slash Normalization
// The router splits by "/" and filters empty strings, so "/users" and "/users/" should be identical.
pub fn trailing_slash_test() {
  let handler = fn(_req, _ctx, _params) { "ok" }

  let router =
    fist.new()
    |> fist.get("/users", to: handler)

  let req_slash = request.new() |> request.set_path("/users/")
  let req_no_slash = request.new() |> request.set_path("/users")

  fist.handle(router, req_slash, Nil, fn() { "404" }) |> should.equal("ok")
  fist.handle(router, req_no_slash, Nil, fn() { "404" }) |> should.equal("ok")
}

// 2. Multiple Slashes Normalization
// "//api///v1" should be treated as "/api/v1"
pub fn multiple_slashes_test() {
  let handler = fn(_req, _ctx, _params) { "ok" }

  let router =
    fist.new()
    |> fist.get("/api/v1", to: handler)

  let req = request.new() |> request.set_path("//api///v1")

  fist.handle(router, req, Nil, fn() { "404" }) |> should.equal("ok")
}

// 3. Case Sensitivity
// "/Users" should NOT match "/users" (standard HTTP router behavior unless specified otherwise)
pub fn case_sensitivity_test() {
  let handler = fn(_req, _ctx, _params) { "ok" }

  let router =
    fist.new()
    |> fist.get("/users", to: handler)

  let req = request.new() |> request.set_path("/Users")

  fist.handle(router, req, Nil, fn() { "404" }) |> should.equal("404")
}

// 4. Dynamic Parameter Conflict (Last Write Wins)
// Confirming behavior: If two dynamic routes are registered at the same level, the last one overwrites.
pub fn dynamic_conflict_test() {
  let h1 = fn(_req, _ctx, _params) { "h1" }
  let h2 = fn(_req, _ctx, params) {
    let slug = dict.get(params, "slug") |> result.unwrap("")
    "h2: " <> slug
  }

  let router =
    fist.new()
    |> fist.get("/items/:id", to: h1)
    |> fist.get("/items/:slug", to: h2)
  // Overwrites :id with :slug

  let req = request.new() |> request.set_path("/items/abc")

  // Should call h2 and parameter name should be "slug", not "id"
  fist.handle(router, req, Nil, fn() { "404" }) |> should.equal("h2: abc")
}

// 5. Special Characters in URL
// Parameters should capture special characters correctly.
pub fn special_chars_test() {
  let handler = fn(_req, _ctx, params) {
    dict.get(params, "tag") |> result.unwrap("")
  }

  let router = fist.new() |> fist.get("/tags/:tag", to: handler)

  // Note: Usually web servers decode URI components before passing to router,
  // but here we are testing raw string matching behavior of the router logic itself.
  let req = request.new() |> request.set_path("/tags/c++")

  fist.handle(router, req, Nil, fn() { "404" }) |> should.equal("c++")
}
