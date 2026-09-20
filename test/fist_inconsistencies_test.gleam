import fist
import fist/extract
import gleam/dict
import gleam/http.{Get}
import gleam/http/request
import gleam/result
import gleam/string
import gleeunit
import gleeunit/should
import support

pub fn main() {
  gleeunit.main()
}

// =============================================================================
// CATEGORY 1: SECURITY VULNERABILITIES & WAF EVASION (RFC 3986)
// =============================================================================

/// Tests secure handling of percent-encoded slashes (%2F / %2f):
/// Ensures directory traversal attempts using percent-encoded slashes
/// (e.g. `/download/..%2fetc/passwd`) are canonicalized before segmenting,
/// safely resolving outside the wildcard mount and returning 404.
pub fn security_encoded_slash_traversal_bypass_test() {
  let router =
    fist.new()
    |> fist.get("/download/*filepath", fn(_, _, params) {
      let fp = dict.get(params, "filepath") |> result.unwrap("")
      "file:" <> fp
    })

  // Case A: Standard decoded slash traversal -> safely clamped/neutralized (404)
  let req_normal =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/download/../../etc/passwd")

  fist.handle(router, req_normal, Nil, fn() { "404" })
  |> should.equal("404")

  // Case B: Percent-encoded slash (%2f) traversal -> properly canonicalized and neutralized (404)
  let req_bypass =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/download/..%2fetc/passwd")

  let result = fist.handle(router, req_bypass, Nil, fn() { "404" })
  result |> should.equal("404")
}

/// Tests protection against encoded dots combined with encoded slashes (%2e%2e%2f):
/// Ensures evasion attempts combining %2e and %2f are normalized before routing,
/// returning 404 rather than escaping the route boundary.
pub fn security_encoded_dots_and_slash_bypass_test() {
  let router =
    fist.new()
    |> fist.get("/files/*filepath", fn(_, _, params) {
      let fp = dict.get(params, "filepath") |> result.unwrap("")
      "file:" <> fp
    })

  let req_double_encoded =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/files/%2e%2e%2f%2e%2e%2fetc/shadow")

  let result = fist.handle(router, req_double_encoded, Nil, fn() { "404" })
  result |> should.equal("404")
}

// =============================================================================
// CATEGORY 2: GUARD ISOLATION AND STATE POLLUTION PREVENTION
// =============================================================================

/// Tests guard isolation between sibling routes sharing a dynamic prefix:
/// Registering `/users/:id/posts` with an integer guard, followed by
/// `/users/:id/profile` without a guard, ensures `/users/alice/profile`
/// is reachable and not polluted by the previous route's guard.
pub fn guard_pollution_cross_route_leak_test() {
  let router =
    fist.new()
    // Route 1: with integer guard on :id
    |> fist.get("/users/:id/posts", fn(_, _, _) { "user posts" })
    |> fist.guard("id", when: extract.is_int)
    // Route 2: WITHOUT guard on :id (should accept any alphanumeric string)
    |> fist.get("/users/:id/profile", fn(_, _, _) { "user profile" })

  let req_numeric =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/123/profile")

  fist.handle(router, req_numeric, Nil, fn() { "404" })
  |> should.equal("user profile")

  let req_string =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/alice/profile")

  // Alice can access her profile without being rejected by the posts guard
  let res_string = fist.handle(router, req_string, Nil, fn() { "404" })
  res_string |> should.equal("user profile")
}

/// Tests that attaching a guard to a subsequent route does not retroactively mutate prior routes:
/// Registering `/users/:id/profile` first (unguarded), and then `/users/:id/posts` (guarded),
/// splits the dynamic branch so `/users/alice/profile` remains fully accessible.
pub fn retroactive_guard_leak_breaks_previous_route_test() {
  let router =
    fist.new()
    // Route 1 registered FIRST without guard
    |> fist.get("/users/:id/profile", fn(_, _, _) { "user profile" })
    // Route 2 registered AFTER with guard
    |> fist.get("/users/:id/posts", fn(_, _, _) { "user posts" })
    |> fist.guard("id", when: extract.is_int)

  let req_alice =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/alice/profile")

  // Profile route remains accessible for non-integers
  fist.handle(router, req_alice, Nil, fn() { "404" })
  |> should.equal("user profile")

  // Posts route is guarded against non-integers
  let req_posts_alice =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/alice/posts")

  fist.handle(router, req_posts_alice, Nil, fn() { "404" })
  |> should.equal("404")

  // Posts route accepts valid integers
  let req_posts_num =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/42/posts")

  fist.handle(router, req_posts_num, Nil, fn() { "404" })
  |> should.equal("user posts")
}

/// Tests that distinct guards on different endpoints with identical parameter names stay isolated:
/// Endpoints with distinct predicates do not collapse into an unintended conjunction (AND).
pub fn distinct_guards_conjunction_collision_test() {
  let router =
    fist.new()
    // Endpoint 1: requires integer
    |> fist.get("/users/:id/posts", fn(_, _, _) { "posts" })
    |> fist.guard("id", when: extract.is_int)
    // Endpoint 2: requires length > 5
    |> fist.get("/users/:id/tags", fn(_, _, _) { "tags" })
    |> fist.guard("id", when: fn(s) { string.length(s) > 5 })

  // "42" is a valid integer (length 2): /users/42/posts matches
  let req_posts =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/42/posts")

  fist.handle(router, req_posts, Nil, fn() { "404" })
  |> should.equal("posts")

  // /users/42/tags fails because length("42") <= 5
  let req_tags_short =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/42/tags")

  fist.handle(router, req_tags_short, Nil, fn() { "404" })
  |> should.equal("404")

  // /users/longstring/tags matches because length > 5
  let req_tags_long =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/longstring/tags")

  fist.handle(router, req_tags_long, Nil, fn() { "404" })
  |> should.equal("tags")
}

// =============================================================================
// CATEGORY 3: FAIL-FAST ON MOUNT WITH WILDCARD
// =============================================================================

/// Tests that mounting a subrouter with a wildcard prefix panics immediately,
/// even if the subrouter is empty.
pub fn mount_wildcard_prefix_empty_subrouter_misses_panic_test() {
  let parent = fist.new()
  let empty_sub = fist.new()

  let mount_result =
    support.rescue(fn() {
      fist.mount(parent, at: "/api/*rest", sub: empty_sub, transform: fn(c) {
        c
      })
    })

  mount_result |> should.be_error
}

// =============================================================================
// CATEGORY 4: REVERSE ROUTING AND BIDIRECTIONAL SOUNDNESS
// =============================================================================

/// Tests clean path generation in Wildcard Reverse Routing without duplicate slashes (//):
/// Prevents paths like `/files//docs/guide.pdf` and rejects parameters consisting only of slashes.
pub fn reverse_routing_wildcard_double_slash_generation_test() {
  let router =
    fist.new()
    |> fist.get("/files/*path", fn(_, _, _) { "files" })
    |> fist.name("download_file")

  // Leading slash normalized to avoid double slash
  let rendered =
    fist.path(router, for: "download_file", with: [#("path", "/docs/guide.pdf")])

  rendered |> should.equal(Ok("/files/docs/guide.pdf"))

  // Parameter with only slashes is rejected with InvalidParameter
  let root_slash =
    fist.path(router, for: "download_file", with: [#("path", "/")])
  root_slash
  |> should.equal(
    Error(fist.InvalidParameter(
      route: "download_file",
      param: "path",
      value: "/",
    )),
  )

  // Submitting the rendered URL back to the router matches successfully (bidirectional soundness)
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/files/docs/guide.pdf")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("files")
}

// =============================================================================
// CATEGORY 5: EXTRACT PREDICATES AND EXTRACTORS
// =============================================================================

pub fn extract_is_bool_test() {
  extract.is_bool("true") |> should.be_true
  extract.is_bool("false") |> should.be_true
  extract.is_bool("1") |> should.be_true
  extract.is_bool("0") |> should.be_true
  extract.is_bool("yes") |> should.be_true
  extract.is_bool("no") |> should.be_true
  extract.is_bool("TRUE") |> should.be_true
  extract.is_bool("abc") |> should.be_false
  extract.is_bool("") |> should.be_false
}

pub fn extract_is_alphanumeric_test() {
  extract.is_alphanumeric("token123") |> should.be_true
  extract.is_alphanumeric("ABC") |> should.be_true
  extract.is_alphanumeric("42") |> should.be_true
  extract.is_alphanumeric("hello_world") |> should.be_false
  extract.is_alphanumeric("hello-world") |> should.be_false
  extract.is_alphanumeric("hello world") |> should.be_false
  extract.is_alphanumeric("") |> should.be_false
}

pub fn extract_alphanumeric_extractor_test() {
  let params = dict.from_list([#("slug", "post123"), #("bad", "post-123")])

  extract.alphanumeric(params, "slug")
  |> should.equal(Ok("post123"))

  extract.alphanumeric(params, "bad")
  |> should.be_error

  extract.alphanumeric(params, "missing")
  |> should.be_error
}
