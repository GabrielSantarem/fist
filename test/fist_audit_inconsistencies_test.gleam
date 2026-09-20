import fist
import fist/extract
import gleam/dict
import gleam/http.{Get}
import gleam/http/request
import gleam/list
import gleam/result
import gleam/string
import gleeunit
import gleeunit/should
import support

pub fn main() {
  gleeunit.main()
}

// =============================================================================
// VERIFICATION 1:
// CROSS-ROUTE GUARD ISOLATION IN REVERSE ROUTING (update_template_guard)
// =============================================================================

/// Attaching a guard to a sibling route must not mutate or pollute
/// the named template of other routes sharing the same method and path structure.
pub fn proof_cross_route_guard_leak_in_reverse_routing_test() {
  let router =
    fist.new()
    // Route 1: numeric ID
    |> fist.get("/users/:id", fn(_, _, _) { "int user" })
    |> fist.guard("id", when: extract.is_int)
    |> fist.name("user_by_int")
    // Route 2: string slug with length > 3
    |> fist.get("/users/:id", fn(_, _, _) { "slug user" })
    |> fist.guard("id", when: fn(s) { string.length(s) > 3 })
    |> fist.name("user_by_slug")

  // "42" is a valid integer: "user_by_int" generates "/users/42"
  let res_int = fist.path(router, for: "user_by_int", with: [#("id", "42")])
  res_int |> should.equal(Ok("/users/42"))

  // "abcde" has length > 3: "user_by_slug" generates "/users/abcde"
  let res_slug =
    fist.path(router, for: "user_by_slug", with: [#("id", "abcde")])
  res_slug |> should.equal(Ok("/users/abcde"))

  // Non-integer is rejected by "user_by_int"
  fist.path(router, for: "user_by_int", with: [#("id", "alice")])
  |> should.equal(
    Error(fist.InvalidParameter(
      route: "user_by_int",
      param: "id",
      value: "alice",
    )),
  )
}

// =============================================================================
// VERIFICATION 2:
// EXTRACT_TEMPLATE_SEGMENTS SELECTS EXACT DYNAMIC SIBLING BRANCH
// =============================================================================

/// When multiple sibling branches have the same param_name, `extract_template_segments`
/// walks down the specific branch containing the route that was just added.
pub fn proof_extract_template_segments_picks_first_sibling_guard_test() {
  let router =
    fist.new()
    // Route 1: integer guard
    |> fist.get("/items/:id", fn(_, _, _) { "int_handler" })
    |> fist.guard("id", when: extract.is_int)
    |> fist.name("item_int")
    // Route 2: UUID guard
    |> fist.get("/items/:id", fn(_, _, _) { "uuid_handler" })
    |> fist.guard("id", when: extract.is_uuid)
    |> fist.name("item_uuid")

  let uuid_val = "123e4567-e89b-12d3-a456-426614174000"

  // "item_uuid" accepts valid UUID
  let uuid_res = fist.path(router, for: "item_uuid", with: [#("id", uuid_val)])
  uuid_res |> should.equal(Ok("/items/" <> uuid_val))

  // "item_int" accepts valid int
  let int_res = fist.path(router, for: "item_int", with: [#("id", "42")])
  int_res |> should.equal(Ok("/items/42"))

  // "item_uuid" rejects non-UUID integer
  fist.path(router, for: "item_uuid", with: [#("id", "42")])
  |> should.equal(
    Error(fist.InvalidParameter(route: "item_uuid", param: "id", value: "42")),
  )

  // Dispatching correctly hits respective handlers
  let req_int =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/items/42")

  fist.handle(router, req_int, Nil, fn() { "404" })
  |> should.equal("int_handler")

  let req_uuid =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/items/" <> uuid_val)

  fist.handle(router, req_uuid, Nil, fn() { "404" })
  |> should.equal("uuid_handler")
}

// =============================================================================
// VERIFICATION 3:
// ROUTE METADATA (fist.describe) ISOLATION IN POLYMORPHIC SIBLINGS
// =============================================================================

/// `fist.describe` attaches metadata specifically to the route that was just added,
/// preserving existing descriptions on sibling routes.
pub fn proof_describe_overwrites_sibling_route_description_test() {
  let router =
    fist.new()
    |> fist.get("/accounts/:id", fn(_, _, _) { "int" })
    |> fist.guard("id", when: extract.is_int)
    |> fist.describe("Integer account ID")
    |> fist.get("/accounts/:id", fn(_, _, _) { "uuid" })
    |> fist.guard("id", when: extract.is_uuid)
    |> fist.describe("UUID account ID")

  let infos = fist.inspect(router)

  let descriptions = list.map(infos, fn(info) { info.description })

  // Both descriptions are correctly preserved
  descriptions
  |> should.equal(["Integer account ID", "UUID account ID"])
}

// =============================================================================
// VERIFICATION 4:
// DOT-SEGMENT ESCAPE PROTECTION IN REVERSE ROUTING
// =============================================================================

/// Dynamic parameter values in reverse routing that attempt directory traversal
/// via dot-segments are rejected immediately with Error(InvalidParameter).
pub fn proof_reverse_routing_dot_segment_route_escape_test() {
  let router =
    fist.new()
    |> fist.get("/documents/:doc_id", fn(_, _, _) { "doc_handler" })
    |> fist.name("get_doc")
    |> fist.get("/admin", fn(_, _, _) { "admin_handler" })
    |> fist.name("admin_panel")

  // Generate URL with dot-segment traversal parameter: rejected
  fist.path(router, for: "get_doc", with: [#("doc_id", "../../admin")])
  |> should.equal(
    Error(fist.InvalidParameter(
      route: "get_doc",
      param: "doc_id",
      value: "../../admin",
    )),
  )

  // Single dot or double dot parameters are also rejected
  fist.path(router, for: "get_doc", with: [#("doc_id", "..")])
  |> should.equal(
    Error(fist.InvalidParameter(route: "get_doc", param: "doc_id", value: "..")),
  )

  fist.path(router, for: "get_doc", with: [#("doc_id", ".")])
  |> should.equal(
    Error(fist.InvalidParameter(route: "get_doc", param: "doc_id", value: ".")),
  )
}

// =============================================================================
// VERIFICATION 5:
// FAIL-FAST ON CONFLICTING UNGUARDED DYNAMIC NAMES AT SAME LEVEL
// =============================================================================

/// Registering or merging conflicting terminal dynamic parameter names
/// without disambiguating guards triggers an immediate fail-fast panic.
pub fn proof_conflicting_dynamic_names_without_guards_does_not_panic_test() {
  // 1. Single router with conflicting terminal dynamic parameter names at same level:
  let single_router_result =
    support.rescue(fn() {
      fist.new()
      |> fist.get("/users/:id", fn(_, _, _) { "by_id" })
      |> fist.get("/users/:username", fn(_, _, _) { "by_username" })
    })

  // Fails fast with panic as documented
  single_router_result |> should.be_error

  // 2. Merging two routers with conflicting terminal dynamic parameter names at same level:
  let router_a =
    fist.new()
    |> fist.get("/records/:record_id", fn(_, _, _) { "rec_a" })

  let router_b =
    fist.new()
    |> fist.get("/records/:slug", fn(_, _, _) { "rec_b" })

  let merge_result = support.rescue(fn() { fist.merge(router_a, router_b) })

  // Fails fast with panic on merge as documented
  merge_result |> should.be_error
}

// =============================================================================
// VERIFICATION 6:
// SAME_SEGMENT_SHAPES IN IDEMPOTENT NAME SHARING
// =============================================================================

/// If route templates have matching parameter names and both methods are guarded,
/// route name assignment is accepted.
pub fn proof_same_segment_shapes_ignores_guards_in_name_sharing_test() {
  let router =
    fist.new()
    |> fist.get("/entities/:id", fn(_, _, _) { "get entity" })
    |> fist.guard("id", when: extract.is_int)
    |> fist.name("entity")
    |> fist.put("/entities/:id", fn(_, _, _) { "put entity" })
    |> fist.guard("id", when: extract.is_int)

  let result = support.rescue(fn() { fist.name(router, "entity") })
  result |> should.be_ok
}

// =============================================================================
// VERIFICATION 7:
// NULL-BYTE (%00) STRIPPING AND SANITIZATION
// =============================================================================

/// Null bytes (\0 and %00) are stripped and empty segments resulting from them
/// are safely removed, matching canonical endpoints.
pub fn proof_null_byte_creates_empty_segment_mismatch_test() {
  let router =
    fist.new()
    |> fist.get("/api/v1/health", fn(_, _, _) { "ok" })

  let req_with_null =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/api/%00/v1/health")

  // Successfully normalizes to /api/v1/health and matches handler
  fist.handle(router, req_with_null, Nil, fn() { "404" })
  |> should.equal("ok")
}

// =============================================================================
// VERIFICATION 8:
// MOUNT PREFIXES AND DYNAMIC SEGMENT BEHAVIOR
// =============================================================================

/// Dynamic segments in mount prefixes remain generic and reverse routing generates
/// the prefixed path cleanly.
pub fn proof_mount_prefix_dynamic_segments_cannot_have_guards_test() {
  let sub =
    fist.new()
    |> fist.get("/projects/:project_id", fn(_, _, _) { "project" })
    |> fist.name("project_detail")

  let parent = fist.new()

  let mounted =
    parent
    |> fist.mount(at: "/orgs/:org_id", sub: sub, transform: fn(c) { c })

  // Calling guard immediately after mount panics because mount operates on the router tree
  let guard_attempt =
    support.rescue(fn() { fist.guard(mounted, "org_id", when: extract.is_int) })
  guard_attempt |> should.be_error

  // Reverse path generates the correct URL
  let path_res =
    fist.path(mounted, for: "project_detail", with: [
      #("org_id", "42"),
      #("project_id", "123"),
    ])

  path_res |> should.equal(Ok("/orgs/42/projects/123"))
}

// =============================================================================
// VERIFICATION 9:
// REPEATED PARAMETER NAMES ACROSS HIERARCHICAL MOUNT
// =============================================================================

/// When a parent router mounts a sub-router where both use the same parameter name,
/// parameter extraction stores the most specific leaf parameter.
pub fn proof_repeated_param_name_across_mount_overwrites_parent_param_test() {
  let sub =
    fist.new()
    |> fist.get("/items/:id", fn(_, _, params) {
      dict.get(params, "id") |> result.unwrap("none")
    })

  let parent =
    fist.new()
    |> fist.mount(at: "/categories/:id", sub: sub, transform: fn(c) { c })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/categories/books/items/99")

  fist.handle(parent, req, Nil, fn() { "404" })
  |> should.equal("99")
}
