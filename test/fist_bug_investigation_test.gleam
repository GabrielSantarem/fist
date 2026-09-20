import fist
import fist/extract
import gleam/dict
import gleam/http.{Get}
import gleam/http/request
import gleam/result
import gleeunit
import gleeunit/should
import support

pub fn main() {
  gleeunit.main()
}

// =============================================================================
// VERIFICATION 1:
// PERCENT-ENCODED SLASH (%2F) IN ROUTE PARAMETERS PRESERVES BIDIRECTIONAL SOUNDNESS
// =============================================================================

/// Verified: A route with a dynamic parameter `:filename` correctly generates
/// and handles filenames with percent-encoded slashes (`%2F`), preserving
/// bidirectional soundness without route hijacking.
pub fn proof_encoded_slash_breaks_bidirectional_soundness_test() {
  let router =
    fist.new()
    |> fist.get("/files/:filename", fn(_, _, params) {
      let f = dict.get(params, "filename") |> result.unwrap("")
      "file:" <> f
    })
    |> fist.name("get_file")

  // Generate URL for a filename that contains a slash
  let assert Ok(generated_url) =
    fist.path(router, for: "get_file", with: [#("filename", "sub/report.pdf")])

  // Generated URL has percent-encoded slash
  generated_url |> should.equal("/files/sub%2Freport.pdf")

  // Dispatch the generated URL back to the router
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path(generated_url)

  let response = fist.handle(router, req, Nil, fn() { "404" })

  // Verified: returns the parameter value with decoded slash
  response |> should.equal("file:sub/report.pdf")
}

/// Verified: Encoded slash does not alter URL segment structure, preventing route hijacking.
/// A request intended for a 1-param route is handled by the 1-param route.
pub fn proof_encoded_slash_route_hijacking_test() {
  let router =
    fist.new()
    |> fist.get("/docs/:filename", fn(_, _, _) { "single_param_route" })
    |> fist.get("/docs/:dir/:filename", fn(_, _, _) { "hijacked_multi_route" })

  // Client requests /docs/folder%2Fdoc.pdf (single parameter filename="folder/doc.pdf")
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/docs/folder%2Fdoc.pdf")

  let response = fist.handle(router, req, Nil, fn() { "404" })

  // Matches the single-param route as expected
  response |> should.equal("single_param_route")
}

// =============================================================================
// VERIFICATION 2:
// POLYMORPHIC SIBLING DYNAMIC CHILDREN WITH IDENTICAL PARAMETER NAMES
// =============================================================================

/// Verified: Fist supports multiple dynamic branches per node with the same
/// parameter name (e.g. `:id`), disambiguated by guards.
pub fn proof_polymorphic_sibling_dynamic_children_with_same_param_name_test() {
  let router =
    fist.new()
    // Branch 1: integer ID
    |> fist.get("/users/:id", fn(_, _, _) { "int_handler" })
    |> fist.guard("id", when: extract.is_int)
    // Branch 2: UUID ID
    |> fist.get("/users/:id", fn(_, _, _) { "uuid_handler" })
    |> fist.guard("id", when: extract.is_uuid)
    // Branch 3: Generic fallback slug
    |> fist.get("/users/:id", fn(_, _, _) { "slug_handler" })

  let req_int =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/123")

  let req_uuid =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/123e4567-e89b-12d3-a456-426614174000")

  let req_slug =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/alice-smith")

  fist.handle(router, req_int, Nil, fn() { "404" })
  |> should.equal("int_handler")

  fist.handle(router, req_uuid, Nil, fn() { "404" })
  |> should.equal("uuid_handler")

  fist.handle(router, req_slug, Nil, fn() { "404" })
  |> should.equal("slug_handler")
}

// =============================================================================
// VERIFICATION 3:
// MERGING ROUTERS PRESERVES POLYMORPHIC SIBLING BRANCHES WITH GUARDS
// =============================================================================

pub fn proof_merge_routers_with_guarded_sibling_branches_test() {
  let router_a =
    fist.new()
    |> fist.get("/items/:id", fn(_, _, _) { "int_item" })
    |> fist.guard("id", when: extract.is_int)

  let router_b =
    fist.new()
    |> fist.get("/items/:id", fn(_, _, _) { "uuid_item" })
    |> fist.guard("id", when: extract.is_uuid)

  let merged = fist.merge(router_a, router_b)

  let req_int =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/items/99")

  let req_uuid =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/items/550e8400-e29b-41d4-a716-446655440000")

  fist.handle(merged, req_int, Nil, fn() { "404" })
  |> should.equal("int_item")

  fist.handle(merged, req_uuid, Nil, fn() { "404" })
  |> should.equal("uuid_item")
}

// =============================================================================
// VERIFICATION 4:
// FAIL-FAST PANIC ON CONFLICTING UNGUARDED PARAMETER NAMES IN MERGE
// =============================================================================

pub fn proof_merge_conflicting_dynamic_params_panics_test() {
  let router_a =
    fist.new()
    |> fist.get("/users/:id", fn(_, _, _) { "a" })

  let router_b =
    fist.new()
    |> fist.get("/users/:username", fn(_, _, _) { "b" })

  let result = support.rescue(fn() { fist.merge(router_a, router_b) })
  // Now panics fail-fast as documented
  result |> should.be_error
}

// =============================================================================
// VERIFICATION 5:
// REVERSE ROUTING TEMPLATE GUARD ISOLATION ACROSS HTTP METHODS
// =============================================================================

/// Verified: Attaching a guard to a POST route does not pollute a named GET route
/// on the same path.
pub fn proof_update_template_guard_pollutes_other_methods_test() {
  let router =
    fist.new()
    |> fist.get("/users/:id", fn(_, _, _) { "get user" })
    |> fist.name("get_user")
    // Register a POST route on the same path with an integer guard:
    |> fist.post("/users/:id", fn(_, _, _) { "post user" })
    |> fist.guard("id", when: extract.is_int)
    |> fist.name("post_user")

  // The named GET route ("get_user") does NOT inherit the POST route's integer guard:
  let get_result =
    fist.path(router, for: "get_user", with: [#("id", "alice-string")])

  get_result |> should.equal(Ok("/users/alice-string"))

  // The named POST route enforces its integer guard:
  let post_int_result =
    fist.path(router, for: "post_user", with: [#("id", "42")])
  post_int_result |> should.equal(Ok("/users/42"))

  let post_str_result =
    fist.path(router, for: "post_user", with: [#("id", "alice-string")])
  post_str_result
  |> should.equal(
    Error(fist.InvalidParameter(
      route: "post_user",
      param: "id",
      value: "alice-string",
    )),
  )
}
