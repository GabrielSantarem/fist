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

/// Dynamic Route Matching:
/// Single wildcard segment (:name) binds URL path tokens into params.
pub fn dynamic_route_test() {
  let handler = fn(_req, _ctx, params) {
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
    fist.handle(router, req, Nil, fn() {
      response.new(404) |> response.set_body("Not Found")
    })

  res.status |> should.equal(200)
  res.body |> should.equal("Hello, tomate!")
}

/// Multi-Segment Dynamic Routing:
/// Successive dynamic segments (:user_id and :post_id) are captured independently.
pub fn nested_dynamic_route_test() {
  let handler = fn(_req, _ctx, params) {
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
    fist.handle(router, req, Nil, fn() {
      response.new(404) |> response.set_body("")
    })

  res.status |> should.equal(200)
  res.body |> should.equal("User 123, Post 456")
}

fn result_unwrap(res, default) {
  case res {
    Ok(v) -> v
    Error(_) -> default
  }
}

/// Unmatched Path Fallback:
/// Requests matching no registered path dispatch to the fallback function.
pub fn not_found_test() {
  let router = fist.new()

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/nao/existe")
    |> request.set_body("")

  let res =
    fist.handle(router, req, Nil, fn() {
      response.new(404) |> response.set_body("Not Found")
    })

  res.status |> should.equal(404)
  res.body |> should.equal("Not Found")
}

/// Method Mismatch Fallback:
/// Requests matching an existing path but with an unregistered HTTP method invoke the fallback.
pub fn wrong_method_test() {
  let router =
    fist.new()
    |> fist.get("/hello", to: fn(_req, _ctx, _params) {
      response.new(200) |> response.set_body("ok")
    })

  let req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_path("/hello")
    |> request.set_body("")

  let res =
    fist.handle(router, req, Nil, fn() {
      response.new(404) |> response.set_body("Not Found")
    })

  res.status |> should.equal(404)
}

/// Static Route Precedence:
/// Exact static paths take precedence over conflicting wildcard dynamic paths.
pub fn static_takes_priority_over_dynamic_test() {
  let dynamic_handler = fn(_req, _ctx, _params) {
    response.new(200) |> response.set_body("dynamic")
  }
  let static_handler = fn(_req, _ctx, _params) {
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
    fist.handle(router, req, Nil, fn() {
      response.new(404) |> response.set_body("")
    })

  res.status |> should.equal(200)
  res.body |> should.equal("static")
}

/// Method Isolation Invariant:
/// Identical paths registered with different HTTP methods are segregated into distinct Trie trees.
pub fn same_path_different_methods_test() {
  let router =
    fist.new()
    |> fist.get("/items", to: fn(_req, _ctx, _params) {
      response.new(200) |> response.set_body("get items")
    })
    |> fist.post("/items", to: fn(_req, _ctx, _params) {
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

  fist.handle(router, get_req, Nil, fn() {
    response.new(404) |> response.set_body("")
  }).body
  |> should.equal("get items")

  fist.handle(router, post_req, Nil, fn() {
    response.new(404) |> response.set_body("")
  }).body
  |> should.equal("created item")
}

/// Root Route Dispatch:
/// Handlers mounted at the root path ("/") handle root requests cleanly.
pub fn root_route_test() {
  let router =
    fist.new()
    |> fist.get("/", to: fn(_req, _ctx, _params) {
      response.new(200) |> response.set_body("root")
    })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/")
    |> request.set_body("")

  let res =
    fist.handle(router, req, Nil, fn() {
      response.new(404) |> response.set_body("")
    })

  res.status |> should.equal(200)
  res.body |> should.equal("root")
}

/// Missing Parameter Fallback:
/// Accessing uncaptured parameter keys falls back gracefully via result unwrapping.
pub fn missing_param_fallback_test() {
  let handler = fn(_req, _ctx, params) {
    let name = dict.get(params, "name") |> result_unwrap("stranger")
    response.new(200) |> response.set_body("Hello, " <> name <> "!")
  }

  // Path has no :name dynamic segment, so params Dict is empty
  let router =
    fist.new()
    |> fist.get("/hello", to: handler)

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/hello")
    |> request.set_body("")

  let res =
    fist.handle(router, req, Nil, fn() {
      response.new(404) |> response.set_body("")
    })

  res.body |> should.equal("Hello, stranger!")
}

/// Functor Map Response Packaging:
/// fist.map transforms raw handler outputs into fully formed HTTP responses with headers.
pub fn response_mapper_test() {
  let router =
    fist.new()
    |> fist.get("/json", to: fn(_, _, _) { "{\"a\":1}" })
    |> fist.map(fn(body) {
      response.new(200)
      |> response.set_body(body)
      |> response.prepend_header("content-type", "application/json")
    })

  let req = fn(path) {
    request.new() |> request.set_method(Get) |> request.set_path(path)
  }

  let res_json =
    fist.handle(router, req("/json"), Nil, fn() {
      response.new(404) |> response.set_body("")
    })

  res_json.status |> should.equal(200)
  res_json.body |> should.equal("{\"a\":1}")
  response.get_header(res_json, "content-type")
  |> should.equal(Ok("application/json"))
}

/// Functor Map Value Transformation:
/// Pure string-to-string transformation across all registered handlers.
pub fn map_test() {
  let router =
    fist.new()
    |> fist.get("/hello", to: fn(_, _, _) { "hello" })
    |> fist.map(fn(s) { "mapped " <> s })

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/hello")
  let res = fist.handle(router, req, Nil, fn() { "not found" })

  res |> should.equal("mapped hello")
}

pub type MyAnswer {
  Success(String)
  Failure
}

/// ADT Routing Domain Types:
/// Fist operates over arbitrary return types, supporting custom application ADTs natively.
pub fn adt_return_test() {
  let router =
    fist.new()
    |> fist.get("/success", to: fn(_, _, _) { Success("yay") })
    |> fist.get("/fail", to: fn(_, _, _) { Failure })

  let req = fn(path) {
    request.new() |> request.set_method(Get) |> request.set_path(path)
  }

  fist.handle(router, req("/success"), Nil, fn() { Failure })
  |> should.equal(Success("yay"))
  fist.handle(router, req("/fail"), Nil, fn() { Failure })
  |> should.equal(Failure)
}

/// Multi-Stage Pipeline Composition:
/// Successive fist.map stages form an incremental pipeline transforming domain types to HTTP responses.
pub fn multi_layer_map_test() {
  let router =
    fist.new()
    |> fist.get("/double/:n", to: fn(_req, _ctx, params) {
      let n =
        dict.get(params, "n")
        |> result.unwrap("0")
        |> int.parse
        |> result.unwrap(0)
      n * 2
    })
    // Stage 1: Int -> String
    |> fist.map(fn(n) { "Result: " <> int.to_string(n) })
    // Stage 2: String -> Response(String)
    |> fist.map(fn(body) { response.new(200) |> response.set_body(body) })
    // Stage 3: Attach custom header
    |> fist.map(fn(res) { response.prepend_header(res, "x-fist", "power") })

  let req =
    request.new() |> request.set_path("/double/21") |> request.set_method(Get)
  let res =
    fist.handle(router, req, Nil, fn() {
      response.new(404) |> response.set_body("not found")
    })

  res.body |> should.equal("Result: 42")
  res.status |> should.equal(200)
  response.get_header(res, "x-fist") |> should.equal(Ok("power"))
}

/// Handler Decorator Pipeline:
/// Custom higher-order function wrappers compose smoothly with whole-router transformations.
pub fn functional_pipeline_test() {
  let with_auth = fn(
    handler: fn(request.Request(String), Nil, dict.Dict(String, String)) ->
      String,
  ) {
    fn(req, ctx, params) {
      case request.get_header(req, "authorization") {
        Ok("secret") -> handler(req, ctx, params)
        _ -> "Unauthorized"
      }
    }
  }

  let router =
    fist.new()
    |> fist.get("/secret", to: with_auth(fn(_, _, _) { "Top Secret Data" }))
    |> fist.map(string.uppercase)

  let req_no_auth =
    request.new() |> request.set_path("/secret") |> request.set_method(Get)
  fist.handle(router, req_no_auth, Nil, fn() { "" })
  |> should.equal("UNAUTHORIZED")

  let req_auth =
    request.new()
    |> request.set_path("/secret")
    |> request.set_method(Get)
    |> request.set_header("authorization", "secret")

  fist.handle(router, req_auth, Nil, fn() { "" })
  |> should.equal("TOP SECRET DATA")
}

/// Context Value Propagation:
/// Fist passes caller-provided context directly into route handlers.
pub fn context_test() {
  let router =
    fist.new()
    |> fist.get("/ctx", to: fn(_req, ctx, _params) { "Context: " <> ctx })

  let req = request.new() |> request.set_path("/ctx") |> request.set_method(Get)

  fist.handle(router, req, "Hello Context", fn() { "" })
  |> should.equal("Context: Hello Context")
}
