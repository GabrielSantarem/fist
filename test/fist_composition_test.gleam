import fist
import fist/extract
import gleam/dict
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/int
import gleam/result
import gleeunit/should

// --- TEST TYPES FOR CONTEXT POLYMORPHISM ---

pub type SysContext {
  SysContext(db: String, env: String)
}

pub type UserContext {
  UserContext(db: String)
}

pub type DbContext {
  DbContext(conn: String)
}

// --- TEST MIDDLEWARES ---

fn append_header_middleware(key: String, value: String) {
  fn(
    next: fn(request.Request(req), ctx, dict.Dict(String, String)) ->
      Response(String),
  ) {
    fn(req, ctx, params) {
      let resp = next(req, ctx, params)
      response.set_header(resp, key, value)
    }
  }
}

// --- TESTS ---

/// Multi-Tier Mount with Dynamic Prefixes and Guards:
/// Deeply nested mountings with dynamic parameters in prefixes and route leaves
/// properly accumulate path parameters and enforce segment guards.
pub fn multi_tier_mount_with_dynamic_prefixes_and_guards_test() {
  // 1. Comments sub-router: /comments/:cid (cid must be int)
  let comments_router =
    fist.new()
    |> fist.get("/comments/:cid", fn(_, _, params) {
      let team = dict.get(params, "team") |> result.unwrap("")
      let pid = dict.get(params, "pid") |> result.unwrap("")
      let cid = dict.get(params, "cid") |> result.unwrap("")
      team <> " : " <> pid <> " : " <> cid
    })
    |> fist.guard("cid", when: extract.is_int)

  // 2. Posts router: mounts comments at /posts/:pid
  let posts_router =
    fist.new()
    |> fist.mount("/posts/:pid", comments_router, fn(c) { c })

  // 3. Teams root router: mounts posts at /teams/:team
  let root_router =
    fist.new()
    |> fist.mount("/teams/:team", posts_router, fn(c) { c })

  // Valid request: all segments present and cid is int
  let req_valid =
    request.new()
    |> request.set_path(
      "/teams/devs/posts/123e4567-e89b-12d3-a456-426614174000/comments/99",
    )
  fist.handle(root_router, req_valid, Nil, fn() { "404" })
  |> should.equal("devs : 123e4567-e89b-12d3-a456-426614174000 : 99")

  // Invalid request: cid is not an integer
  let req_invalid_cid =
    request.new()
    |> request.set_path(
      "/teams/devs/posts/123e4567-e89b-12d3-a456-426614174000/comments/bad-id",
    )
  fist.handle(root_router, req_invalid_cid, Nil, fn() { "404" })
  |> should.equal("404")
}

/// Diamond Merge with Disjoint Middlewares:
/// When merging two mounted routers that have their own distinct middlewares,
/// each route branch only executes its own middleware chain, and 404s execute no middleware.
pub fn diamond_merge_with_disjoint_middlewares_test() {
  let v1 =
    fist.new()
    |> fist.get("/data", fn(_, _, _) {
      response.new(200) |> response.set_body("v1 data")
    })
    |> fist.wrap(append_header_middleware("X-Api-Version", "v1"))

  let v2 =
    fist.new()
    |> fist.get("/data", fn(_, _, _) {
      response.new(200) |> response.set_body("v2 data")
    })
    |> fist.wrap(append_header_middleware("X-Api-Version", "v2"))

  let root =
    fist.new()
    |> fist.mount("/api/v1", v1, fn(c) { c })
    |> fist.mount("/api/v2", v2, fn(c) { c })

  let req_v1 = request.new() |> request.set_path("/api/v1/data")
  let resp_v1 =
    fist.handle(root, req_v1, Nil, fn() {
      response.new(404) |> response.set_body("not found")
    })
  resp_v1.body |> should.equal("v1 data")
  response.get_header(resp_v1, "x-api-version") |> should.equal(Ok("v1"))

  let req_v2 = request.new() |> request.set_path("/api/v2/data")
  let resp_v2 =
    fist.handle(root, req_v2, Nil, fn() {
      response.new(404) |> response.set_body("not found")
    })
  resp_v2.body |> should.equal("v2 data")
  response.get_header(resp_v2, "x-api-version") |> should.equal(Ok("v2"))

  let req_missing = request.new() |> request.set_path("/api/v1/nonexistent")
  let resp_missing =
    fist.handle(root, req_missing, Nil, fn() {
      response.new(404) |> response.set_body("not found")
    })
  resp_missing.body |> should.equal("not found")
  response.get_header(resp_missing, "x-api-version") |> should.equal(Error(Nil))
}

/// Merge Reordering with Polymorphic Dynamic Guards:
/// When merging two routers where Router A has a guarded branch and an unguarded fallback,
/// and Router B has a different guarded branch, the merged router prioritizes all guarded
/// branches before the unguarded fallback branch.
pub fn merge_reordering_with_polymorphic_guards_test() {
  let router_a =
    fist.new()
    |> fist.get("/search/:id", fn(_, _, params) {
      let id = dict.get(params, "id") |> result.unwrap("")
      "int search: " <> id
    })
    |> fist.guard("id", when: extract.is_int)
    |> fist.get("/search/:query", fn(_, _, params) {
      let q = dict.get(params, "query") |> result.unwrap("")
      "generic search: " <> q
    })

  let router_b =
    fist.new()
    |> fist.get("/search/:uuid", fn(_, _, params) {
      let u = dict.get(params, "uuid") |> result.unwrap("")
      "uuid search: " <> u
    })
    |> fist.guard("uuid", when: extract.is_uuid)

  let merged = fist.merge(router_a, router_b)

  // 1. Integer matches A's :id
  let req_int = request.new() |> request.set_path("/search/12345")
  fist.handle(merged, req_int, Nil, fn() { "404" })
  |> should.equal("int search: 12345")

  // 2. UUID matches B's :uuid
  let req_uuid =
    request.new()
    |> request.set_path("/search/123e4567-e89b-12d3-a456-426614174000")
  fist.handle(merged, req_uuid, Nil, fn() { "404" })
  |> should.equal("uuid search: 123e4567-e89b-12d3-a456-426614174000")

  // 3. Non-numeric, non-UUID string falls through to A's generic :query
  let req_generic = request.new() |> request.set_path("/search/gleam-lang")
  fist.handle(merged, req_generic, Nil, fn() { "404" })
  |> should.equal("generic search: gleam-lang")
}

/// Merge Shared Parameter Composed Guards:
/// When merging two routers that register endpoints under the exact same dynamic parameter
/// name with different guard conditions, both guard conditions are composed.
pub fn merge_shared_parameter_composed_guards_test() {
  let router_a =
    fist.new()
    |> fist.get("/reports/:year/summary", fn(_, _, params) {
      let y = dict.get(params, "year") |> result.unwrap("")
      "summary " <> y
    })
    |> fist.guard("year", when: extract.is_int)

  let router_b =
    fist.new()
    |> fist.get("/reports/:year/audit", fn(_, _, params) {
      let y = dict.get(params, "year") |> result.unwrap("")
      "audit " <> y
    })
    |> fist.guard("year", when: fn(y) {
      case int.parse(y) {
        Ok(n) -> n >= 2000
        Error(_) -> False
      }
    })

  let merged = fist.merge(router_a, router_b)

  let req_valid_sum = request.new() |> request.set_path("/reports/2025/summary")
  let req_valid_aud = request.new() |> request.set_path("/reports/2025/audit")
  let req_old_aud = request.new() |> request.set_path("/reports/1990/audit")
  let req_bad_year =
    request.new() |> request.set_path("/reports/notayear/summary")

  fist.handle(merged, req_valid_sum, Nil, fn() { "404" })
  |> should.equal("summary 2025")

  fist.handle(merged, req_valid_aud, Nil, fn() { "404" })
  |> should.equal("audit 2025")

  // 1990 fails the year >= 2000 guard
  fist.handle(merged, req_old_aud, Nil, fn() { "404" })
  |> should.equal("404")

  // "notayear" fails the is_int guard
  fist.handle(merged, req_bad_year, Nil, fn() { "404" })
  |> should.equal("404")
}

/// Context Polymorphism Chain:
/// Granular sub-routers with specialized context requirements can be composed
/// across multiple levels of hierarchy using `fist.map_context` and `fist.mount`.
pub fn context_polymorphism_chain_test() {
  // Sub-router requires DbContext
  let db_sub =
    fist.new()
    |> fist.get("/query", fn(_, ctx: DbContext, _) {
      "connected to " <> ctx.conn
    })

  // Intermediate router requires UserContext, mounts db_sub
  let user_router =
    fist.new()
    |> fist.mount("/db", db_sub, fn(uc: UserContext) { DbContext(conn: uc.db) })

  // Grandparent router has SysContext, mounts user_router
  let sys_router =
    fist.new()
    |> fist.mount("/admin", user_router, fn(sys: SysContext) {
      UserContext(db: sys.db)
    })

  let req = request.new() |> request.set_path("/admin/db/query")
  let initial_ctx = SysContext(db: "postgres://prod:5432", env: "production")

  fist.handle(sys_router, req, initial_ctx, fn() { "404" })
  |> should.equal("connected to postgres://prod:5432")
}

/// Output Transformation (fist.map) Across All Route Kinds:
/// `fist.map` transforms handlers across static, guarded dynamic, generic dynamic,
/// and wildcard routes uniformly.
pub fn output_transformation_all_route_kinds_test() {
  let router =
    fist.new()
    |> fist.get("/static", fn(_, _, _) { 200 })
    |> fist.get("/users/:id", fn(_, _, _) { 201 })
    |> fist.guard("id", when: extract.is_int)
    |> fist.get("/users/:name", fn(_, _, _) { 202 })
    |> fist.get("/files/*path", fn(_, _, _) { 204 })
    |> fist.map(fn(code) { response.new(code) })

  let req_static = request.new() |> request.set_path("/static")
  let req_guarded = request.new() |> request.set_path("/users/42")
  let req_fallback = request.new() |> request.set_path("/users/bob")
  let req_wildcard = request.new() |> request.set_path("/files/docs/readme.txt")

  let not_found_resp = fn() { response.new(404) }

  fist.handle(router, req_static, Nil, not_found_resp).status
  |> should.equal(200)

  fist.handle(router, req_guarded, Nil, not_found_resp).status
  |> should.equal(201)

  fist.handle(router, req_fallback, Nil, not_found_resp).status
  |> should.equal(202)

  fist.handle(router, req_wildcard, Nil, not_found_resp).status
  |> should.equal(204)
}

/// Group with Multiple Middlewares and Guards:
/// Demonstrates that in `fist.group`, middlewares wrap only handlers, execute outer-in,
/// and allow guarded routes to fall through to generic routes inside the group.
pub fn group_with_multiple_middlewares_and_guards_test() {
  let trace_mw = fn(tag: String) {
    fn(
      next: fn(request.Request(req), ctx, dict.Dict(String, String)) ->
        List(String),
    ) {
      fn(req, ctx, params) { [tag, ..next(req, ctx, params)] }
    }
  }

  let router =
    fist.new()
    |> fist.group(
      at: "/v1",
      with: [trace_mw("MW1"), trace_mw("MW2")],
      defining: fn(r) {
        r
        |> fist.get("/items/:id", fn(_, _, _) { ["int_item"] })
        |> fist.guard("id", when: extract.is_int)
        |> fist.get("/items/:slug", fn(_, _, _) { ["slug_item"] })
      },
    )

  // /v1/items/99 matches :id, middleware chain MW1 -> MW2 -> ["int_item"]
  let req_int = request.new() |> request.set_path("/v1/items/99")
  fist.handle(router, req_int, Nil, fn() { [] })
  |> should.equal(["MW1", "MW2", "int_item"])

  // /v1/items/keyboard falls through to :slug, MW1 -> MW2 -> ["slug_item"]
  let req_slug = request.new() |> request.set_path("/v1/items/keyboard")
  fist.handle(router, req_slug, Nil, fn() { [] })
  |> should.equal(["MW1", "MW2", "slug_item"])

  // 404 does not invoke middlewares
  let req_404 = request.new() |> request.set_path("/v1/notfound")
  fist.handle(router, req_404, Nil, fn() { ["fallback"] })
  |> should.equal(["fallback"])
}

/// Deep Static and Dynamic Cross-Branch Backtracking:
/// Verifies that when a static sub-path fails deep down, the engine backtracks
/// to dynamic sibling branches.
pub fn deep_static_and_dynamic_cross_branch_backtracking_test() {
  let router =
    fist.new()
    |> fist.get("/services/billing/invoices", fn(_, _, _) { "billing invoices" })
    |> fist.get("/services/:service_name/status", fn(_, _, params) {
      let svc = dict.get(params, "service_name") |> result.unwrap("")
      "status of " <> svc
    })
    |> fist.get("/services/*rest", fn(_, _, params) {
      let rest = dict.get(params, "rest") |> result.unwrap("")
      "services catchall: " <> rest
    })

  // 1. Static match
  let req1 = request.new() |> request.set_path("/services/billing/invoices")
  fist.handle(router, req1, Nil, fn() { "404" })
  |> should.equal("billing invoices")

  // 2. "billing" matches static, but "status" fails static and backtracks to :service_name/status
  let req2 = request.new() |> request.set_path("/services/billing/status")
  fist.handle(router, req2, Nil, fn() { "404" })
  |> should.equal("status of billing")

  // 3. Dynamic match
  let req3 = request.new() |> request.set_path("/services/auth/status")
  fist.handle(router, req3, Nil, fn() { "404" })
  |> should.equal("status of auth")

  // 4. Backtracking all the way to wildcard
  let req4 = request.new() |> request.set_path("/services/billing/export/csv")
  fist.handle(router, req4, Nil, fn() { "404" })
  |> should.equal("services catchall: billing/export/csv")
}

/// Empty Router Monoidal Operations:
/// Merging with or mounting an empty router acts as an identity operation.
pub fn empty_router_monoidal_composition_test() {
  let populated =
    fist.new()
    |> fist.get("/home", fn(_, _, _) { "home" })
  let empty = fist.new()

  let merged_left = fist.merge(empty, populated)
  let merged_right = fist.merge(populated, empty)

  let req = request.new() |> request.set_path("/home")

  fist.handle(merged_left, req, Nil, fn() { "404" }) |> should.equal("home")
  fist.handle(merged_right, req, Nil, fn() { "404" }) |> should.equal("home")

  // Mounting an empty router into populated router preserves existing routes
  let mounted_empty = fist.mount(populated, "/sub", empty, fn(c) { c })
  fist.handle(mounted_empty, req, Nil, fn() { "404" }) |> should.equal("home")
}
