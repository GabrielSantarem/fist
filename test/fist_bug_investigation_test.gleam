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
// RFC 3986 & BIDIRECTIONAL SOUNDNESS WITH PERCENT-ENCODED SLASH (%2F)
// =============================================================================

/// Documentation claim (docs/behavior.md):
/// "Dynamic Segments (:param): Parameter values are percent-encoded using RFC 3986 rules.
///  Injected forward slashes (/) become %2F. This guarantees that user input cannot alter
///  the segment structure of the URL or escape to other routes."
/// "Bidirectional Soundness: A web router should never generate a URL that its own routing
///  engine would reject or misroute."
///
/// Verified: When `fist.path` encodes a slash to `%2F`, `fist.handle` treats it as a single
/// dynamic parameter value rather than splitting segments, maintaining bidirectional soundness.
pub fn proof_encoded_slash_breaks_bidirectional_soundness_test() {
  let router =
    fist.new()
    |> fist.get("/files/:filename", fn(_, _, params) {
      let f = dict.get(params, "filename") |> result.unwrap("")
      "file:" <> f
    })
    |> fist.name("get_file")

  // Generate URL for a filename that contains an encoded slash
  let assert Ok(generated_url) =
    fist.path(router, for: "get_file", with: [#("filename", "sub/report.pdf")])

  // Generated URL is "/files/sub%2Freport.pdf"
  generated_url |> should.equal("/files/sub%2Freport.pdf")

  // Dispatch the generated URL back to the router
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path(generated_url)

  let response = fist.handle(router, req, Nil, fn() { "404" })

  // Verified bidirectional soundness: returns the parameter value with slash
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

/// Documentation claim (docs/behavior.md):
/// "Polymorphic Sibling Dynamic Children: Unlike simplistic radix trees that restrict
///  a node to at most one dynamic parameter child, Fist supports multiple dynamic branches
///  per node, disambiguated by route guards and declared priority order."
///
/// Verified: Two routes with the same parameter name (:id) and different guards
/// coexist as polymorphic siblings. The earlier route is not corrupted by the latter.
pub fn proof_same_param_name_guards_corrupt_prior_route_test() {
  let router =
    fist.new()
    |> fist.get("/users/:id", fn(_, _, _) { "int_handler" })
    |> fist.guard("id", when: extract.is_int)
    |> fist.get("/users/:id", fn(_, _, _) { "uuid_handler" })
    |> fist.guard("id", when: extract.is_uuid)

  // Request with a valid integer "42" matches the integer route
  let req_int =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/42")

  fist.handle(router, req_int, Nil, fn() { "404" })
  |> should.equal("int_handler")

  // Request with a valid UUID matches the UUID route
  let req_uuid =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/123e4567-e89b-12d3-a456-426614174000")

  fist.handle(router, req_uuid, Nil, fn() { "404" })
  |> should.equal("uuid_handler")
}

// =============================================================================
// VERIFICATION 3:
// GUARD ISOLATION ACROSS ROUTERS DURING `fist.merge`
// =============================================================================

/// Documentation claim (docs/behavior.md):
/// "Monoidal Router Merging (fist.merge): Combining disjoint and compatible routers recursively."
///
/// Verified: Router B's unguarded route is not polluted by Router A's guard during merge.
pub fn proof_merge_pollutes_unguarded_route_test() {
  let router_a =
    fist.new()
    |> fist.get("/items/:id/details", fn(_, _, _) { "details" })
    |> fist.guard("id", when: extract.is_int)

  let router_b =
    fist.new()
    |> fist.get("/items/:id/summary", fn(_, _, _) { "summary" })

  let req_slug =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/items/wireless-mouse/summary")

  // Before merge, router_b accepts string slugs
  fist.handle(router_b, req_slug, Nil, fn() { "404" })
  |> should.equal("summary")

  // After merge: unguarded route remains accessible
  let merged = fist.merge(router_a, router_b)
  fist.handle(merged, req_slug, Nil, fn() { "404" })
  |> should.equal("summary")

  // Guarded route from router_a also works
  let req_int =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/items/42/details")

  fist.handle(merged, req_int, Nil, fn() { "404" })
  |> should.equal("details")
}

/// Verified: Merging two routers with different guards on the same parameter name
/// keeps distinct dynamic branches, allowing both routes to be matched.
pub fn proof_merge_conflicting_guards_kills_both_routes_test() {
  let router_a =
    fist.new()
    |> fist.get("/records/:key/edit", fn(_, _, _) { "edit" })
    |> fist.guard("key", when: fn(s) { s == "alpha" })

  let router_b =
    fist.new()
    |> fist.get("/records/:key/view", fn(_, _, _) { "view" })
    |> fist.guard("key", when: fn(s) { s == "beta" })

  let merged = fist.merge(router_a, router_b)

  let req_alpha =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/records/alpha/edit")

  let req_beta =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/records/beta/view")

  fist.handle(merged, req_alpha, Nil, fn() { "404" })
  |> should.equal("edit")
  fist.handle(merged, req_beta, Nil, fn() { "404" })
  |> should.equal("view")
}

// =============================================================================
// VERIFICATION 4:
// ORDERED DYNAMIC FALLTHROUGH ON DISTINCT PARAMETER NAMES IN MERGE
// =============================================================================

pub fn proof_merge_conflicting_dynamic_params_does_not_panic_test() {
  let router_a =
    fist.new()
    |> fist.get("/users/:id", fn(_, _, _) { "a" })

  let router_b =
    fist.new()
    |> fist.get("/users/:username", fn(_, _, _) { "b" })

  let result = support.rescue(fn() { fist.merge(router_a, router_b) })
  result |> should.be_ok
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

  // Reverse path for "get_user" with non-numeric id "alice" succeeds:
  let res = fist.path(router, for: "get_user", with: [#("id", "alice")])

  res |> should.equal(Ok("/users/alice"))
}

// =============================================================================
// VERIFICATION 6:
// REVERSE ROUTING TEMPLATE COMPATIBILITY
// =============================================================================

pub fn proof_idempotent_name_sharing_conflicting_guards_deadlocks_test() {
  let router =
    fist.new()
    |> fist.get("/users/:id", fn(_, _, _) { "get" })
    |> fist.guard("id", when: extract.is_int)
    |> fist.name("user")
    |> fist.post("/users/:id", fn(_, _, _) { "post" })
    |> fist.guard("id", when: extract.is_uuid)
    |> fist.name("user")

  // GET template generates integer paths successfully
  fist.path(router, for: "user", with: [#("id", "42")])
  |> should.equal(Ok("/users/42"))
}

// =============================================================================
// VERIFICATION 7:
// `extract.is_bool` AND `extract.bool`
// =============================================================================

pub fn proof_extract_is_bool_accepts_undocumented_values_test() {
  extract.is_bool("yes") |> should.be_true
  extract.is_bool("no") |> should.be_true
  extract.is_bool("t") |> should.be_true
  extract.is_bool("f") |> should.be_true
}

// =============================================================================
// VERIFICATION 8:
// `extract.float` AND `extract.is_float` REJECT INTEGER STRINGS
// =============================================================================

pub fn proof_extract_float_rejects_integer_strings_test() {
  extract.is_float("42") |> should.be_false
  extract.is_float("-10") |> should.be_false

  let params = dict.from_list([#("price", "42")])
  extract.float(params, "price") |> should.be_error
}

// =============================================================================
// VERIFICATION 9:
// DYNAMIC MOUNT / GROUP PREFIXES
// =============================================================================

pub fn proof_dynamic_mount_prefix_cannot_be_guarded_test() {
  let sub =
    fist.new()
    |> fist.get("/users", fn(_, _, _) { "sub users" })

  let parent = fist.new()

  let result =
    support.rescue(fn() {
      parent
      |> fist.mount(at: "/orgs/:org_id", sub: sub, transform: fn(c) { c })
      |> fist.guard("org_id", when: extract.is_int)
    })

  result |> should.be_error
}

// =============================================================================
// HISTORICAL ROUTER PATTERN:
// DEEP ANCESTOR WILDCARD BACKTRACKING WITH PARTIAL STATIC MISMATCHES
// =============================================================================

pub fn historical_deep_wildcard_backtracking_test() {
  let router =
    fist.new()
    |> fist.get("/api/v1/projects/:id/members/list", fn(_, _, _) {
      "deep static"
    })
    |> fist.get("/api/*catchall", fn(_, _, params) {
      let catchall = dict.get(params, "catchall") |> result.unwrap("")
      "catch:" <> catchall
    })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/api/v1/projects/10/members/audit")

  let response = fist.handle(router, req, Nil, fn() { "404" })

  response |> should.equal("catch:v1/projects/10/members/audit")
}

// =============================================================================
// REVERSE ROUTING:
// QUERY PARAMETER PRESERVATION WITH DUPLICATE KEYS
// =============================================================================

pub fn reverse_routing_duplicate_query_keys_preserved_test() {
  let router =
    fist.new()
    |> fist.get("/articles", fn(_, _, _) { "articles" })
    |> fist.name("articles_index")

  let assert Ok(url) =
    fist.path(router, for: "articles_index", with: [
      #("tag", "gleam"),
      #("tag", "beam"),
    ])

  url |> should.equal("/articles?tag=gleam&tag=beam")
}
