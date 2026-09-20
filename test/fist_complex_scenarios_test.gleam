import fist
import gleam/dict
import gleam/http.{Delete, Get, Patch, Put}
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/result
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// =============================================================================
// SCENARIO 1: Enterprise Multi-Tier Context Polymorphism with Nested Mounts & Merge
// =============================================================================

pub type GlobalContext {
  GlobalContext(service_name: String, request_id: String, database_url: String)
}

pub type TenantContext {
  TenantContext(
    service_name: String,
    request_id: String,
    tenant_id: String,
    database_url: String,
  )
}

pub type AdminContext {
  AdminContext(
    service_name: String,
    request_id: String,
    tenant_id: String,
    operator: String,
  )
}

pub type ApiResponse {
  ApiResponse(status: Int, body: String, service: String)
}

/// Enterprise Hierarchical Context Polymorphism & Modular Merging:
/// Tests deep multi-level context elevation (Global -> Tenant -> Admin) combined with
/// router merging, dynamic path extraction, and output transformation into domain responses.
pub fn enterprise_context_polymorphism_and_merge_test() {
  // 1. Admin Sub-router (requires AdminContext)
  let admin_sub_router =
    fist.new()
    |> fist.get("/audit", fn(_req, ctx: AdminContext, _params) {
      ApiResponse(
        status: 200,
        body: "operator:" <> ctx.operator <> " tenant:" <> ctx.tenant_id,
        service: ctx.service_name,
      )
    })
    |> fist.delete("/purge", fn(_req, ctx: AdminContext, _params) {
      ApiResponse(
        status: 200,
        body: "purged by " <> ctx.operator,
        service: ctx.service_name,
      )
    })

  // 2. Tenant Sub-router (requires TenantContext)
  let tenant_sub_router =
    fist.new()
    |> fist.get("/dashboard", fn(_req, ctx: TenantContext, _params) {
      ApiResponse(
        status: 200,
        body: "dashboard for " <> ctx.tenant_id,
        service: ctx.service_name,
      )
    })
    // Mount Admin router inside Tenant router
    |> fist.mount(
      at: "/admin",
      sub: admin_sub_router,
      transform: fn(t_ctx: TenantContext) {
        AdminContext(
          service_name: t_ctx.service_name,
          request_id: t_ctx.request_id,
          tenant_id: t_ctx.tenant_id,
          operator: "superadmin",
        )
      },
    )

  // 3. Public router (requires GlobalContext)
  let public_router =
    fist.new()
    |> fist.get("/health", fn(_req, ctx: GlobalContext, _params) {
      ApiResponse(status: 200, body: "healthy", service: ctx.service_name)
    })
    |> fist.get(
      "/public/assets/*filepath",
      fn(_req, ctx: GlobalContext, params) {
        let fp = dict.get(params, "filepath") |> result.unwrap("")
        ApiResponse(
          status: 200,
          body: "asset:" <> fp,
          service: ctx.service_name,
        )
      },
    )

  // 4. Organization router mounted with dynamic parameter in prefix (:org_id)
  let org_router =
    fist.new()
    |> fist.mount(
      at: "/orgs/:org_id",
      sub: tenant_sub_router,
      transform: fn(g_ctx: GlobalContext) {
        TenantContext(
          service_name: g_ctx.service_name,
          request_id: g_ctx.request_id,
          tenant_id: "tenant-alpha",
          database_url: g_ctx.database_url,
        )
      },
    )

  // 5. Merge Public and Organization routers into unified application
  let app_router =
    fist.merge(public_router, org_router)
    // Wrap with metrics tracking header middleware
    |> fist.wrap(fn(next) {
      fn(req, ctx: GlobalContext, params) {
        let res: ApiResponse = next(req, ctx, params)
        ApiResponse(..res, body: res.body <> " [req:" <> ctx.request_id <> "]")
      }
    })
    // Map domain ApiResponse to gleam/http/response.Response
    |> fist.map(fn(res: ApiResponse) {
      response.new(res.status)
      |> response.set_header("x-service", res.service)
      |> response.set_body(res.body)
    })

  let global_ctx =
    GlobalContext(
      service_name: "acme-api",
      request_id: "trace-987",
      database_url: "postgres://localhost/db",
    )

  // Test A: Public endpoint
  let req_health =
    request.new() |> request.set_method(Get) |> request.set_path("/health")
  let res_health =
    fist.handle(app_router, req_health, global_ctx, fn() {
      response.new(404) |> response.set_body("Not Found")
    })
  res_health.status |> should.equal(200)
  res_health.body |> should.equal("healthy [req:trace-987]")

  // Test B: Public wildcard asset
  let req_asset =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/public/assets/branding/logo.svg")
  let res_asset =
    fist.handle(app_router, req_asset, global_ctx, fn() {
      response.new(404) |> response.set_body("Not Found")
    })
  res_asset.status |> should.equal(200)
  res_asset.body
  |> should.equal("asset:branding/logo.svg [req:trace-987]")

  // Test C: Tenant dashboard
  let req_tenant =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/orgs/org-123/dashboard")
  let res_tenant =
    fist.handle(app_router, req_tenant, global_ctx, fn() {
      response.new(404) |> response.set_body("Not Found")
    })
  res_tenant.status |> should.equal(200)
  res_tenant.body
  |> should.equal("dashboard for tenant-alpha [req:trace-987]")

  // Test D: Deeply nested admin audit endpoint
  let req_admin =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/orgs/org-123/admin/audit")
  let res_admin =
    fist.handle(app_router, req_admin, global_ctx, fn() {
      response.new(404) |> response.set_body("Not Found")
    })
  res_admin.status |> should.equal(200)
  res_admin.body
  |> should.equal("operator:superadmin tenant:tenant-alpha [req:trace-987]")

  // Test E: Allowed methods across merged tiers
  let allowed_admin_purge =
    fist.allowed_methods(app_router, "/orgs/org-123/admin/purge")
  allowed_admin_purge |> should.equal([Delete])
}

// =============================================================================
// SCENARIO 2: Multi-Tier Nested Wildcards with Interleaved Dynamic & Static Sibling Backtracking
// =============================================================================

/// Complex Multi-Tier Backtracking Hierarchy:
/// Validates nested backtracking where requests can match deep leaves, fall back to
/// parent wildcards, or fall back all the way to a global catch-all.
pub fn multi_tier_wildcard_backtracking_hierarchy_test() {
  let router =
    fist.new()
    // Level 0: Global root catch-all
    |> fist.get("/*global_catchall", fn(_, _, params) {
      let rest = dict.get(params, "global_catchall") |> result.unwrap("")
      "global:" <> rest
    })
    // Level 1: Organizations catch-all
    |> fist.get("/orgs/*orgs_rest", fn(_, _, params) {
      let rest = dict.get(params, "orgs_rest") |> result.unwrap("")
      "orgs-catchall:" <> rest
    })
    // Level 2: Specific org repositories catch-all
    |> fist.get("/orgs/:org_id/repos/*repo_rest", fn(_, _, params) {
      let org = dict.get(params, "org_id") |> result.unwrap("")
      let rest = dict.get(params, "repo_rest") |> result.unwrap("")
      "repo-catchall:" <> org <> ":" <> rest
    })
    // Level 3: Specific repository commits catch-all
    |> fist.get("/orgs/:org_id/repos/:repo_id/commits/*path", fn(_, _, params) {
      let org = dict.get(params, "org_id") |> result.unwrap("")
      let repo = dict.get(params, "repo_id") |> result.unwrap("")
      let path = dict.get(params, "path") |> result.unwrap("")
      "commits:" <> org <> "/" <> repo <> ":" <> path
    })
    // Level 3: Exact static sibling under the same branch
    |> fist.get("/orgs/:org_id/repos/:repo_id/commits/HEAD", fn(_, _, params) {
      let org = dict.get(params, "org_id") |> result.unwrap("")
      let repo = dict.get(params, "repo_id") |> result.unwrap("")
      "head-commit:" <> org <> "/" <> repo
    })

  let dispatch = fn(path_str) {
    let req =
      request.new() |> request.set_method(Get) |> request.set_path(path_str)
    fist.handle(router, req, Nil, fn() { "404" })
  }

  // A. Exact match hits static HEAD route
  dispatch("/orgs/acme/repos/core/commits/HEAD")
  |> should.equal("head-commit:acme/core")

  // B. Specific commit path matches commits wildcard
  dispatch("/orgs/acme/repos/core/commits/branch/feat-123")
  |> should.equal("commits:acme/core:branch/feat-123")

  // C. Unmatched path under repo (e.g. issues) backtracks to Level 2 repo catch-all
  dispatch("/orgs/acme/repos/core/issues/42")
  |> should.equal("repo-catchall:acme:core/issues/42")

  // D. Unmatched path under orgs (e.g. members) backtracks to Level 1 orgs catch-all
  dispatch("/orgs/acme/members/teams/engineering")
  |> should.equal("orgs-catchall:acme/members/teams/engineering")

  // E. Completely unrelated path falls back to Level 0 global catch-all
  dispatch("/random/unknown/path")
  |> should.equal("global:random/unknown/path")
}

// =============================================================================
// SCENARIO 3: Exotic Unicode, Percent-Encoding, Emoji, and Dotfile Combinations
// =============================================================================

/// Exotic Internationalized URLs, Emojis, and Dotfiles:
/// Tests complex URLs combining UTF-8 emojis, multi-byte Cyrillic, Kanji,
/// hidden dotfiles, percent-encoding, and trailing wildcard captures.
pub fn exotic_unicode_and_emojis_routing_test() {
  let router =
    fist.new()
    |> fist.get("/loja/:categoria/*produto", fn(_, _, params) {
      let cat = dict.get(params, "categoria") |> result.unwrap("")
      let prod = dict.get(params, "produto") |> result.unwrap("")
      cat <> " -> " <> prod
    })
    |> fist.get("/repos/:user/.github/*workflow", fn(_, _, params) {
      let u = dict.get(params, "user") |> result.unwrap("")
      let wf = dict.get(params, "workflow") |> result.unwrap("")
      "workflow:" <> u <> ":" <> wf
    })

  let dispatch = fn(path_str) {
    let req =
      request.new() |> request.set_method(Get) |> request.set_path(path_str)
    fist.handle(router, req, Nil, fn() { "404" })
  }

  // 1. Emoji and accented Portuguese
  dispatch("/loja/café%20☕/doces/brigadeiro%20gourmet.json")
  |> should.equal("café ☕ -> doces/brigadeiro gourmet.json")

  // 2. Japanese Kanji with spaces and plus signs
  dispatch("/loja/%E6%97%A5%E6%9C%AC%E8%AA%9E/本/東京+2026.pdf")
  |> should.equal("日本語 -> 本/東京+2026.pdf")

  // 3. Hidden directory with dot (.github) and wildcard
  dispatch("/repos/gleam-lang/.github/workflows/ci.yml")
  |> should.equal("workflow:gleam-lang:workflows/ci.yml")
}

// =============================================================================
// SCENARIO 4: Middleware Isolation in Diamond Merges
// =============================================================================

/// Diamond Router Merge Middleware Isolation:
/// When router A (wrapped in mw_a) and router B (wrapped in mw_b) are merged into router C,
/// mw_a must only affect router A's routes, and mw_b must only affect router B's routes.
pub fn diamond_merge_middleware_isolation_test() {
  let router_a =
    fist.new()
    |> fist.get("/service-a", fn(_, _, _) { "A" })
    |> fist.wrap(fn(next) {
      fn(req, ctx, params) { "[" <> next(req, ctx, params) <> "-MW_A]" }
    })

  let router_b =
    fist.new()
    |> fist.get("/service-b", fn(_, _, _) { "B" })
    |> fist.wrap(fn(next) {
      fn(req, ctx, params) { "{" <> next(req, ctx, params) <> "-MW_B}" }
    })

  // Merge A and B
  let merged = fist.merge(router_a, router_b)

  // Wrap merged with a global outer middleware
  let app =
    merged
    |> fist.wrap(fn(next) {
      fn(req, ctx, params) { "<" <> next(req, ctx, params) <> "-GLOBAL>" }
    })

  let req_a =
    request.new() |> request.set_method(Get) |> request.set_path("/service-a")
  let req_b =
    request.new() |> request.set_method(Get) |> request.set_path("/service-b")

  // Route A must have MW_A and GLOBAL, but NOT MW_B
  fist.handle(app, req_a, Nil, fn() { "404" })
  |> should.equal("<[A-MW_A]-GLOBAL>")

  // Route B must have MW_B and GLOBAL, but NOT MW_A
  fist.handle(app, req_b, Nil, fn() { "404" })
  |> should.equal("<{B-MW_B}-GLOBAL>")
}

// =============================================================================
// SCENARIO 5: Full HTTP Method Spectrum & Preflight on Same Branch
// =============================================================================

/// Full CRUD Method Matrix with Dynamic Segments:
/// Tests handling of GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD, and Custom Verbs
/// on identical and sub-paths, asserting allowed_methods and exact dispatch.
pub fn full_crud_method_matrix_test() {
  let router =
    fist.new()
    |> fist.get("/items/:id", fn(_, _, params) {
      "get:" <> dict.get(params, "id") |> result.unwrap("")
    })
    |> fist.put("/items/:id", fn(_, _, params) {
      "put:" <> dict.get(params, "id") |> result.unwrap("")
    })
    |> fist.patch("/items/:id", fn(_, _, params) {
      "patch:" <> dict.get(params, "id") |> result.unwrap("")
    })
    |> fist.delete("/items/:id", fn(_, _, params) {
      "delete:" <> dict.get(params, "id") |> result.unwrap("")
    })
    |> fist.head("/items/:id", fn(_, _, _) { "head-ok" })
    |> fist.options("/items/:id", fn(_, _, _) { "options-ok" })
    |> fist.route(
      method: http.Other("PURGE"),
      path: "/items/:id",
      handler: fn(_, _, _) { "purged" },
    )

  let req = fn(method) {
    request.new() |> request.set_method(method) |> request.set_path("/items/99")
  }

  fist.handle(router, req(Get), Nil, fn() { "404" }) |> should.equal("get:99")
  fist.handle(router, req(Put), Nil, fn() { "404" }) |> should.equal("put:99")
  fist.handle(router, req(Patch), Nil, fn() { "404" })
  |> should.equal("patch:99")
  fist.handle(router, req(Delete), Nil, fn() { "404" })
  |> should.equal("delete:99")
  fist.handle(router, req(http.Head), Nil, fn() { "404" })
  |> should.equal("head-ok")
  fist.handle(router, req(http.Options), Nil, fn() { "404" })
  |> should.equal("options-ok")
  fist.handle(router, req(http.Other("PURGE")), Nil, fn() { "404" })
  |> should.equal("purged")

  // Check allowed methods includes all registered methods
  let methods = fist.allowed_methods(router, "/items/99")
  list.contains(methods, Get) |> should.be_true
  list.contains(methods, Put) |> should.be_true
  list.contains(methods, Patch) |> should.be_true
  list.contains(methods, Delete) |> should.be_true
  list.contains(methods, http.Head) |> should.be_true
  list.contains(methods, http.Options) |> should.be_true
  list.contains(methods, http.Other("PURGE")) |> should.be_true
}

// =============================================================================
// SCENARIO 6: Deeply Nested Groups with Multiple Dynamic Parameters and Scoped Middleware
// =============================================================================

/// Deeply Nested Groups with Dynamic Parameters and Layered Middlewares:
/// Validates nesting of groups with dynamic parameter prefixes and verifies that
/// each nested layer executes middlewares in exact hierarchical sequence.
pub fn deeply_nested_dynamic_groups_with_layered_middlewares_test() {
  let mw1 = fn(next) {
    fn(req, ctx, params) { "1[" <> next(req, ctx, params) <> "]1" }
  }
  let mw2 = fn(next) {
    fn(req, ctx, params) { "2[" <> next(req, ctx, params) <> "]2" }
  }
  let mw3 = fn(next) {
    fn(req, ctx, params) { "3[" <> next(req, ctx, params) <> "]3" }
  }

  let router =
    fist.new()
    |> fist.group(at: "/tenants/:tenant_id", with: [mw1], defining: fn(g1) {
      g1
      |> fist.group(at: "/projects/:proj_id", with: [mw2], defining: fn(g2) {
        g2
        |> fist.group(at: "/environments/:env", with: [mw3], defining: fn(g3) {
          g3
          |> fist.get("/config", fn(_, _, params) {
            let t = dict.get(params, "tenant_id") |> result.unwrap("")
            let p = dict.get(params, "proj_id") |> result.unwrap("")
            let e = dict.get(params, "env") |> result.unwrap("")
            t <> ":" <> p <> ":" <> e
          })
        })
      })
    })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/tenants/t-99/projects/p-42/environments/prod/config")

  // Execution order: mw1 outermost -> mw2 -> mw3 innermost -> handler
  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("1[2[3[t-99:p-42:prod]3]2]1")
}

// =============================================================================
// SCENARIO 7: Functor Mapping Over Asymmetrically Merged Subtrees
// =============================================================================

/// Global Functor Mapping Over Asymmetric Subtrees:
/// Confirms that fist.map visits all leaves across static, dynamic, and wildcard nodes
/// even after multiple mount, group, and merge operations.
pub fn functor_mapping_across_composite_asymmetric_trie_test() {
  let branch_static =
    fist.new()
    |> fist.get("/static/target", fn(_, _, _) { 10 })

  let branch_dynamic =
    fist.new()
    |> fist.get("/dynamic/:num", fn(_, _, params) {
      dict.get(params, "num")
      |> result.try(fn(s) {
        case s {
          "20" -> Ok(20)
          _ -> Error(Nil)
        }
      })
      |> result.unwrap(0)
    })

  let branch_wildcard =
    fist.new()
    |> fist.get("/wildcard/*rest", fn(_, _, _) { 30 })

  let merged =
    fist.merge(branch_static, branch_dynamic)
    |> fist.merge(branch_wildcard)
    // Map integer output to formatted String globally
    |> fist.map(fn(int_val) { "RESULT:" <> string_inspect(int_val) })

  let req1 =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/static/target")
  let req2 =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/dynamic/20")
  let req3 =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/wildcard/arbitrary/tail")

  fist.handle(merged, req1, Nil, fn() { "404" })
  |> should.equal("RESULT:10")
  fist.handle(merged, req2, Nil, fn() { "404" })
  |> should.equal("RESULT:20")
  fist.handle(merged, req3, Nil, fn() { "404" })
  |> should.equal("RESULT:30")
}

fn string_inspect(val: Int) -> String {
  case val {
    10 -> "10"
    20 -> "20"
    30 -> "30"
    _ -> "0"
  }
}
