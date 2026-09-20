import fist
import gleam/http/request
import gleam/http/response
import gleam/list
import gleeunit/should
import support

/// Path Normalization Invariant:
/// Trailing slashes and redundant internal slashes must normalize to the same route target.
pub fn path_normalization_test() {
  let router =
    fist.new()
    |> fist.get("/api/v1/status", fn(_, _, _) { "ok" })

  let req1 = request.new() |> request.set_path("/api/v1/status/")
  let req2 = request.new() |> request.set_path("//api///v1/status")

  fist.handle(router, req1, Nil, fn() { "404" }) |> should.equal("ok")
  fist.handle(router, req2, Nil, fn() { "404" }) |> should.equal("ok")
}

/// Case Sensitivity Invariant:
/// Routes with differing casing must be matched independently and never conflated.
pub fn case_sensitivity_test() {
  let router =
    fist.new()
    |> fist.get("/Users", fn(_, _, _) { "upper" })
    |> fist.get("/users", fn(_, _, _) { "lower" })

  let req_upper = request.new() |> request.set_path("/Users")
  let req_lower = request.new() |> request.set_path("/users")

  fist.handle(router, req_upper, Nil, fn() { "404" }) |> should.equal("upper")
  fist.handle(router, req_lower, Nil, fn() { "404" }) |> should.equal("lower")
}

/// Dynamic Parameter Conflict Panic:
/// Registering conflicting dynamic parameter names at the same level panics immediately (fail-fast).
pub fn parameter_name_conflict_test() {
  support.rescue(fn() {
    fist.new()
    |> fist.get("/users/:id/profile", fn(_, _, _) { "profile" })
    |> fist.get("/users/:user_id/settings", fn(_, _, _) { "settings" })
  })
  |> should.be_error
}

/// Description Reset on Router Transformation:
/// Operations transforming the entire router (like map) clear the last_added pointer,
/// safely ignoring subsequent describe calls.
pub fn describe_after_map_failure_test() {
  let router =
    fist.new()
    |> fist.get("/data", fn(_, _, _) { "ok" })
    |> fist.map(fn(s) { s })
    |> fist.describe("This description will be ignored")

  let routes = fist.inspect(router)
  let assert Ok(route) = list.first(routes)
  route.description |> should.equal("")
}

/// Root Route Equivalence & Duplicate Collision:
/// Both empty string ("") and single slash ("/") map to the root Trie node;
/// registering both on the same router causes a duplicate route collision panic.
pub fn empty_path_root_test() {
  support.rescue(fn() {
    fist.new()
    |> fist.get("", fn(_, _, _) { "empty" })
    |> fist.get("/", fn(_, _, _) { "slash" })
  })
  |> should.be_error
}

pub type ApiResponse {
  Text(String)
  Json(String)
  Forbidden
}

/// Custom Algebraic Data Type (ADT) Return Handling:
/// Handlers can return domain ADTs which are subsequently transformed to HTTP responses via map.
pub fn adt_custom_return_type_test() {
  let router =
    fist.new()
    |> fist.get("/text", fn(_, _, _) { Text("plain") })
    |> fist.get("/json", fn(_, _, _) { Json("{\"status\":\"active\"}") })
    |> fist.get("/secret", fn(_, _, _) { Forbidden })
    |> fist.map(fn(res) {
      case res {
        Text(body) -> response.new(200) |> response.set_body(body)
        Json(json) ->
          response.new(200)
          |> response.set_header("content-type", "application/json")
          |> response.set_body(json)
        Forbidden -> response.new(403) |> response.set_body("Forbidden")
      }
    })

  let req = fn(path) { request.new() |> request.set_path(path) }

  let res_text =
    fist.handle(router, req("/text"), Nil, fn() {
      response.new(404) |> response.set_body("")
    })
  res_text.status |> should.equal(200)
  res_text.body |> should.equal("plain")

  let res_json =
    fist.handle(router, req("/json"), Nil, fn() {
      response.new(404) |> response.set_body("")
    })
  res_json.status |> should.equal(200)
  res_json.body |> should.equal("{\"status\":\"active\"}")
  response.get_header(res_json, "content-type")
  |> should.equal(Ok("application/json"))

  let res_secret =
    fist.handle(router, req("/secret"), Nil, fn() {
      response.new(404) |> response.set_body("")
    })
  res_secret.status |> should.equal(403)
  res_secret.body |> should.equal("Forbidden")
}
