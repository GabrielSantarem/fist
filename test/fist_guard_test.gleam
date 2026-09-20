import fist
import fist/extract
import gleam/dict
import gleam/http.{Get, Post}
import gleam/http/request
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleeunit/should
import support

/// Single Guard Acceptance & Rejection:
/// When a dynamic parameter has a guard, matching values execute the handler,
/// while non-matching values return the fallback (404).
pub fn single_guard_test() {
  let router =
    fist.new()
    |> fist.get("/users/:id", fn(_, _, params) {
      let id = dict.get(params, "id") |> result.unwrap("")
      "user " <> id
    })
    |> fist.guard("id", when: extract.is_int)

  let req_valid = request.new() |> request.set_path("/users/42")
  let req_invalid = request.new() |> request.set_path("/users/gabriel")

  fist.handle(router, req_valid, Nil, fn() { "404" })
  |> should.equal("user 42")

  fist.handle(router, req_invalid, Nil, fn() { "404" })
  |> should.equal("404")
}

/// Guard Fallthrough to Generic Dynamic Branch:
/// If a guarded branch rejects the segment, routing continues seamlessly to
/// an unguarded dynamic branch at the same level.
pub fn guard_fallthrough_to_generic_dynamic_test() {
  let router =
    fist.new()
    |> fist.get("/users/:id", fn(_, _, params) {
      let id = dict.get(params, "id") |> result.unwrap("")
      "numeric: " <> id
    })
    |> fist.guard("id", when: extract.is_int)
    |> fist.get("/users/:username", fn(_, _, params) {
      let username = dict.get(params, "username") |> result.unwrap("")
      "username: " <> username
    })

  let req_int = request.new() |> request.set_path("/users/123")
  let req_string = request.new() |> request.set_path("/users/alice")

  fist.handle(router, req_int, Nil, fn() { "404" })
  |> should.equal("numeric: 123")

  fist.handle(router, req_string, Nil, fn() { "404" })
  |> should.equal("username: alice")
}

/// Multiple Guarded Branches with Priority Order:
/// Multiple guarded dynamic branches at the same level are evaluated in priority order.
pub fn multiple_guarded_branches_priority_test() {
  let router =
    fist.new()
    |> fist.get("/resources/:id", fn(_, _, params) {
      let id = dict.get(params, "id") |> result.unwrap("")
      "id: " <> id
    })
    |> fist.guard("id", when: extract.is_int)
    |> fist.get("/resources/:uuid", fn(_, _, params) {
      let uuid = dict.get(params, "uuid") |> result.unwrap("")
      "uuid: " <> uuid
    })
    |> fist.guard("uuid", when: extract.is_uuid)
    |> fist.get("/resources/:slug", fn(_, _, params) {
      let slug = dict.get(params, "slug") |> result.unwrap("")
      "slug: " <> slug
    })

  let req_int = request.new() |> request.set_path("/resources/999")
  let req_uuid =
    request.new()
    |> request.set_path("/resources/123e4567-e89b-12d3-a456-426614174000")
  let req_slug = request.new() |> request.set_path("/resources/my-post-title")

  fist.handle(router, req_int, Nil, fn() { "404" })
  |> should.equal("id: 999")

  fist.handle(router, req_uuid, Nil, fn() { "404" })
  |> should.equal("uuid: 123e4567-e89b-12d3-a456-426614174000")

  fist.handle(router, req_slug, Nil, fn() { "404" })
  |> should.equal("slug: my-post-title")
}

/// Multiple Guards on Different Path Segments:
/// Distinct dynamic parameters across segments can each be guarded independently.
pub fn multiple_guards_across_segments_test() {
  let router =
    fist.new()
    |> fist.get("/orgs/:org_id/projects/:project_id", fn(_, _, params) {
      let org = dict.get(params, "org_id") |> result.unwrap("")
      let project = dict.get(params, "project_id") |> result.unwrap("")
      org <> " -> " <> project
    })
    |> fist.guard("org_id", when: extract.is_int)
    |> fist.guard("project_id", when: extract.is_uuid)

  let req_both_valid =
    request.new()
    |> request.set_path(
      "/orgs/42/projects/123e4567-e89b-12d3-a456-426614174000",
    )
  let req_bad_org =
    request.new()
    |> request.set_path(
      "/orgs/acme/projects/123e4567-e89b-12d3-a456-426614174000",
    )
  let req_bad_project =
    request.new()
    |> request.set_path("/orgs/42/projects/not-a-uuid")

  fist.handle(router, req_both_valid, Nil, fn() { "404" })
  |> should.equal("42 -> 123e4567-e89b-12d3-a456-426614174000")

  fist.handle(router, req_bad_org, Nil, fn() { "404" })
  |> should.equal("404")

  fist.handle(router, req_bad_project, Nil, fn() { "404" })
  |> should.equal("404")
}

/// Guarded Branch Dead-End Fallthrough:
/// When a segment passes a guard, but downstream segments lead to a dead-end,
/// the router falls through to sibling branches that match the root segment.
pub fn guarded_branch_dead_end_fallthrough_test() {
  let router =
    fist.new()
    |> fist.get("/items/:id/edit", fn(_, _, params) {
      let id = dict.get(params, "id") |> result.unwrap("")
      "edit item " <> id
    })
    |> fist.guard("id", when: extract.is_int)
    |> fist.get("/items/:slug", fn(_, _, params) {
      let slug = dict.get(params, "slug") |> result.unwrap("")
      "view slug " <> slug
    })

  // "100" is an int, but Route A has no terminal route at "/items/:id"
  let req_single = request.new() |> request.set_path("/items/100")
  // Should fall through to Route B
  fist.handle(router, req_single, Nil, fn() { "404" })
  |> should.equal("view slug 100")

  // Downstream "/edit" matches Route A
  let req_edit = request.new() |> request.set_path("/items/100/edit")
  fist.handle(router, req_edit, Nil, fn() { "404" })
  |> should.equal("edit item 100")
}

/// Precedence: Static > Guarded Dynamic > Wildcard
pub fn precedence_with_guards_test() {
  let router =
    fist.new()
    |> fist.get("/posts/latest", fn(_, _, _) { "static latest" })
    |> fist.get("/posts/:id", fn(_, _, params) {
      let id = dict.get(params, "id") |> result.unwrap("")
      "guarded: " <> id
    })
    |> fist.guard("id", when: fn(_) { True })
    |> fist.get("/posts/*rest", fn(_, _, params) {
      let rest = dict.get(params, "rest") |> result.unwrap("")
      "wildcard: " <> rest
    })

  let req_static = request.new() |> request.set_path("/posts/latest")
  let req_dyn = request.new() |> request.set_path("/posts/popular")
  let req_multi = request.new() |> request.set_path("/posts/archive/2026/09")

  fist.handle(router, req_static, Nil, fn() { "404" })
  |> should.equal("static latest")

  fist.handle(router, req_dyn, Nil, fn() { "404" })
  |> should.equal("guarded: popular")

  fist.handle(router, req_multi, Nil, fn() { "404" })
  |> should.equal("wildcard: archive/2026/09")
}

/// Backtracking from Guarded Dynamic to Wildcard:
/// If a segment fails a guard, it backtracks to an ancestor wildcard.
pub fn backtracking_from_guard_to_wildcard_test() {
  let router =
    fist.new()
    |> fist.get("/files/:id/view", fn(_, _, params) {
      let id = dict.get(params, "id") |> result.unwrap("")
      "file id: " <> id
    })
    |> fist.guard("id", when: extract.is_int)
    |> fist.get("/files/*rest", fn(_, _, params) {
      let rest = dict.get(params, "rest") |> result.unwrap("")
      "catchall: " <> rest
    })

  let req_valid_id = request.new() |> request.set_path("/files/42/view")
  let req_invalid_id = request.new() |> request.set_path("/files/docs/view")
  let req_dead_end = request.new() |> request.set_path("/files/42/download")

  fist.handle(router, req_valid_id, Nil, fn() { "404" })
  |> should.equal("file id: 42")

  fist.handle(router, req_invalid_id, Nil, fn() { "404" })
  |> should.equal("catchall: docs/view")

  fist.handle(router, req_dead_end, Nil, fn() { "404" })
  |> should.equal("catchall: 42/download")
}

/// Allowed Methods with Guard Sensitivity:
/// `allowed_methods` should only report methods whose dynamic parameter guards match.
pub fn allowed_methods_with_guard_test() {
  let router =
    fist.new()
    |> fist.get("/api/:id", fn(_, _, _) { "get id" })
    |> fist.guard("id", when: extract.is_int)
    |> fist.post("/api/:slug", fn(_, _, _) { "post slug" })
    |> fist.guard("slug", when: fn(s) { !extract.is_int(s) })

  // For "/api/123", only GET's guard passes
  let methods_numeric = fist.allowed_methods(router, "/api/123")
  methods_numeric |> should.equal([Get])

  // For "/api/hello", only POST's guard passes
  let methods_alpha = fist.allowed_methods(router, "/api/hello")
  methods_alpha |> should.equal([Post])
}

/// Guard In Mounted Sub-Router:
/// Mounted sub-routers maintain their guards cleanly after context and prefix mapping.
pub fn guard_in_mounted_router_test() {
  let sub =
    fist.new()
    |> fist.get("/users/:id", fn(_, _, params) {
      let id = dict.get(params, "id") |> result.unwrap("")
      "sub: " <> id
    })
    |> fist.guard("id", when: extract.is_int)

  let parent =
    fist.new()
    |> fist.mount("/api/v1", sub, fn(c) { c })

  let req_valid = request.new() |> request.set_path("/api/v1/users/77")
  let req_invalid = request.new() |> request.set_path("/api/v1/users/admin")

  fist.handle(parent, req_valid, Nil, fn() { "404" })
  |> should.equal("sub: 77")

  fist.handle(parent, req_invalid, Nil, fn() { "404" })
  |> should.equal("404")
}

/// Custom Predicate Guards:
/// Arbitrary user-defined pure functions can be used as guards.
pub fn custom_predicate_guard_test() {
  let is_prefixed = fn(s: String) { string.starts_with(s, "usr_") }
  let is_three_chars = fn(s: String) { string.length(s) == 3 }

  let router =
    fist.new()
    |> fist.get("/accounts/:account_id", fn(_, _, params) {
      let acc = dict.get(params, "account_id") |> result.unwrap("")
      "account: " <> acc
    })
    |> fist.guard("account_id", when: is_prefixed)
    |> fist.get("/codes/:code", fn(_, _, params) {
      let c = dict.get(params, "code") |> result.unwrap("")
      "code: " <> c
    })
    |> fist.guard("code", when: is_three_chars)

  let req_acc = request.new() |> request.set_path("/accounts/usr_12345")
  let req_acc_bad = request.new() |> request.set_path("/accounts/org_12345")
  let req_code = request.new() |> request.set_path("/codes/ABC")
  let req_code_bad = request.new() |> request.set_path("/codes/TOOLONG")

  fist.handle(router, req_acc, Nil, fn() { "404" })
  |> should.equal("account: usr_12345")

  fist.handle(router, req_acc_bad, Nil, fn() { "404" })
  |> should.equal("404")

  fist.handle(router, req_code, Nil, fn() { "404" })
  |> should.equal("code: ABC")

  fist.handle(router, req_code_bad, Nil, fn() { "404" })
  |> should.equal("404")
}

/// Fail-Fast: Guard on Non-Existent Parameter:
/// Attaching a guard to a parameter name not present in the route panics immediately.
pub fn guard_non_existent_param_panics_test() {
  support.rescue(fn() {
    fist.new()
    |> fist.get("/users/:id", fn(_, _, _) { "ok" })
    |> fist.guard("wrong_name", when: extract.is_int)
  })
  |> should.be_error
}

/// Fail-Fast: Guard Without Preceding Route:
/// Calling `fist.guard` immediately after `fist.new()` panics immediately.
pub fn guard_without_route_panics_test() {
  support.rescue(fn() {
    fist.new()
    |> fist.guard("id", when: extract.is_int)
  })
  |> should.be_error
}

/// Chained Multiple Guards on the Same Parameter:
/// Successive calls to `fist.guard` on the same parameter compose with logical AND (&&).
pub fn chained_multiple_guards_on_same_param_test() {
  let is_even = fn(s: String) {
    case int.parse(s) {
      Ok(n) -> n % 2 == 0
      Error(_) -> False
    }
  }

  let router =
    fist.new()
    |> fist.get("/even-numbers/:num", fn(_, _, params) {
      let n = dict.get(params, "num") |> result.unwrap("")
      "even: " <> n
    })
    |> fist.guard("num", when: extract.is_int)
    |> fist.guard("num", when: is_even)

  // 42 is an int AND even -> passes
  let req_even = request.new() |> request.set_path("/even-numbers/42")
  fist.handle(router, req_even, Nil, fn() { "404" })
  |> should.equal("even: 42")

  // 41 is an int but NOT even -> rejected
  let req_odd = request.new() |> request.set_path("/even-numbers/41")
  fist.handle(router, req_odd, Nil, fn() { "404" })
  |> should.equal("404")

  // "hello" is not an int -> rejected
  let req_str = request.new() |> request.set_path("/even-numbers/hello")
  fist.handle(router, req_str, Nil, fn() { "404" })
  |> should.equal("404")
}

/// Percent-Encoded Decoded Tokens with Guard:
/// URL percent-encoded tokens are decoded prior to guard predicate evaluation.
pub fn percent_encoded_guard_test() {
  let router =
    fist.new()
    |> fist.get("/tags/:tag", fn(_, _, params) {
      let t = dict.get(params, "tag") |> result.unwrap("")
      "tag: " <> t
    })
    |> fist.guard("tag", when: fn(t) { string.contains(t, " ") })

  // "%20" decodes to space " " -> guard passes
  let req_space = request.new() |> request.set_path("/tags/gleam%20beam")
  fist.handle(router, req_space, Nil, fn() { "404" })
  |> should.equal("tag: gleam beam")

  // No space -> guard fails
  let req_nospace = request.new() |> request.set_path("/tags/gleam")
  fist.handle(router, req_nospace, Nil, fn() { "404" })
  |> should.equal("404")
}

/// Merge Routers with Distinct Guarded Branches:
/// Merging two routers with different dynamic parameter names and guards
/// preserves all guards and orders them properly.
pub fn merge_with_distinct_guards_test() {
  let router_a =
    fist.new()
    |> fist.get("/items/:id", fn(_, _, params) {
      let id = dict.get(params, "id") |> result.unwrap("")
      "int item " <> id
    })
    |> fist.guard("id", when: extract.is_int)

  let router_b =
    fist.new()
    |> fist.get("/items/:slug", fn(_, _, params) {
      let slug = dict.get(params, "slug") |> result.unwrap("")
      "slug item " <> slug
    })

  let merged = fist.merge(router_a, router_b)

  let req_int = request.new() |> request.set_path("/items/500")
  let req_slug = request.new() |> request.set_path("/items/wireless-mouse")

  fist.handle(merged, req_int, Nil, fn() { "404" })
  |> should.equal("int item 500")

  fist.handle(merged, req_slug, Nil, fn() { "404" })
  |> should.equal("slug item wireless-mouse")
}

/// Inspect Routes on Guarded and Polymorphic Dynamic Paths:
/// `fist.inspect` correctly surfaces all registered dynamic branches.
pub fn inspect_with_guards_test() {
  let router =
    fist.new()
    |> fist.get("/users/:id", fn(_, _, _) { "id" })
    |> fist.guard("id", when: extract.is_int)
    |> fist.describe("Numeric user")
    |> fist.get("/users/:username", fn(_, _, _) { "username" })
    |> fist.describe("Generic username")

  let routes = fist.inspect(router)
  list.length(routes) |> should.equal(2)
}
