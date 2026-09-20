import fist
import gleam/dict
import gleam/http.{Get, Post}
import gleam/http/request
import gleam/int
import gleam/list
import gleeunit/should

pub type RootContext {
  RootContext(id: Int)
}

pub type SubContext {
  SubContext(name: String)
}

pub type DeepContext {
  DeepContext(depth: Int, name: String)
}

fn root_handler(_req, ctx: RootContext, _params) {
  "root-" <> int.to_string(ctx.id)
}

fn sub_handler(_req, ctx: SubContext, _params) {
  "sub-" <> ctx.name
}

/// Sub-Router Mounting & Context Transformation:
/// Mounted routers inherit path prefixes and adapt context requirements using a mapper function.
pub fn mount_test() {
  let sub_router =
    fist.new()
    |> fist.get("/hello", sub_handler)

  let root_router =
    fist.new()
    |> fist.get("/status", root_handler)
    |> fist.mount("/api", sub_router, fn(ctx: RootContext) {
      SubContext(name: "transformed-" <> int.to_string(ctx.id))
    })

  // 1. Root route dispatch
  let req1 =
    request.new() |> request.set_method(Get) |> request.set_path("/status")
  fist.handle(root_router, req1, RootContext(id: 1), fn() { "404" })
  |> should.equal("root-1")

  // 2. Mounted sub-route dispatch with adapted context
  let req2 =
    request.new() |> request.set_method(Get) |> request.set_path("/api/hello")
  fist.handle(root_router, req2, RootContext(id: 1), fn() { "404" })
  |> should.equal("sub-transformed-1")
}

/// Dynamic Prefix Mounting:
/// Wildcards embedded within mount prefixes (e.g., /orgs/:org_id) are extracted alongside sub-route params.
pub fn dynamic_prefix_mount_test() {
  let sub_router =
    fist.new()
    |> fist.get("/members/:member_id", fn(_req, _ctx, params) {
      let org = dict.get(params, "org_id") |> should.be_ok
      let member = dict.get(params, "member_id") |> should.be_ok
      org <> ":" <> member
    })

  let root_router =
    fist.new()
    |> fist.mount("/orgs/:org_id", sub_router, fn(c) { c })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/orgs/acme/members/alice")

  fist.handle(root_router, req, Nil, fn() { "404" })
  |> should.equal("acme:alice")

  // Route inspection reflects prefixed path and cumulative parameter names
  let routes = fist.inspect(root_router)
  let assert Ok(route_info) = list.first(routes)
  route_info.path |> should.equal("/orgs/:org_id/members/:member_id")
  route_info.params |> should.equal(["org_id", "member_id"])
}

/// Basic Route Grouping:
/// Groups bundle routes under a common path prefix without requiring intermediate context mappers.
pub fn group_basic_test() {
  let router =
    fist.new()
    |> fist.group(at: "/v1", with: [], defining: fn(r) {
      r
      |> fist.get("/users", fn(_, _, _) { "users_v1" })
      |> fist.post("/users", fn(_, _, _) { "created_v1" })
    })

  let req_get =
    request.new() |> request.set_method(Get) |> request.set_path("/v1/users")
  let req_post =
    request.new() |> request.set_method(Post) |> request.set_path("/v1/users")

  fist.handle(router, req_get, Nil, fn() { "404" })
  |> should.equal("users_v1")

  fist.handle(router, req_post, Nil, fn() { "404" })
  |> should.equal("created_v1")
}

/// Onion Middleware Execution Order:
/// Middlewares execute in declaration order: the first declared middleware wraps subsequent ones (outermost first).
pub fn group_middleware_execution_order_test() {
  let middleware_first = fn(next) {
    fn(req, ctx, params) {
      let res = next(req, ctx, params)
      "first(" <> res <> ")"
    }
  }

  let middleware_second = fn(next) {
    fn(req, ctx, params) {
      let res = next(req, ctx, params)
      "second(" <> res <> ")"
    }
  }

  let router =
    fist.new()
    |> fist.group(
      at: "/api",
      with: [middleware_first, middleware_second],
      defining: fn(r) { r |> fist.get("/data", fn(_, _, _) { "content" }) },
    )

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/api/data")

  // Evaluated: first(second(handler()))
  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("first(second(content))")
}

/// Hierarchical Group Nesting:
/// Nested groups accumulate path prefixes and cascade middleware stacks from outside in.
pub fn nested_groups_test() {
  let mw_outer = fn(next) {
    fn(req, ctx, params) { next(req, ctx, params) <> "-outer" }
  }
  let mw_inner = fn(next) {
    fn(req, ctx, params) { next(req, ctx, params) <> "-inner" }
  }

  let router =
    fist.new()
    |> fist.group(at: "/api", with: [mw_outer], defining: fn(r1) {
      r1
      |> fist.group(at: "/v2", with: [mw_inner], defining: fn(r2) {
        r2 |> fist.get("/ping", fn(_, _, _) { "pong" })
      })
    })

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/api/v2/ping")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("pong-inner-outer")
}

/// Dynamic Segment in Group Prefix:
/// Groups support dynamic wildcards in their prefix definition.
pub fn group_with_dynamic_prefix_test() {
  let router =
    fist.new()
    |> fist.group(at: "/users/:user_id", with: [], defining: fn(r) {
      r
      |> fist.get("/profile", fn(_, _, params) {
        let uid = dict.get(params, "user_id") |> should.be_ok
        "profile of " <> uid
      })
      |> fist.get("/posts/:post_id", fn(_, _, params) {
        let uid = dict.get(params, "user_id") |> should.be_ok
        let pid = dict.get(params, "post_id") |> should.be_ok
        uid <> " post " <> pid
      })
    })

  let req1 =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/42/profile")
  fist.handle(router, req1, Nil, fn() { "404" })
  |> should.equal("profile of 42")

  let req2 =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/42/posts/99")
  fist.handle(router, req2, Nil, fn() { "404" })
  |> should.equal("42 post 99")
}

/// Sub-Router Root Route Propagation:
/// A sub-router's root route ("/") correctly maps to the mount point prefix (e.g., "/admin").
pub fn subrouter_with_root_route_mounted_test() {
  let sub =
    fist.new()
    |> fist.get("/", fn(_, _, _) { "sub root" })
    |> fist.get("/items", fn(_, _, _) { "sub items" })

  let router =
    fist.new()
    |> fist.get("/", fn(_, _, _) { "main root" })
    |> fist.mount("/admin", sub, fn(c) { c })

  // Mounted sub-router root route maps to "/admin"
  let req_admin =
    request.new() |> request.set_method(Get) |> request.set_path("/admin")
  fist.handle(router, req_admin, Nil, fn() { "404" })
  |> should.equal("sub root")

  // Trailing slash variant "/admin/"
  let req_admin_slash =
    request.new() |> request.set_method(Get) |> request.set_path("/admin/")
  fist.handle(router, req_admin_slash, Nil, fn() { "404" })
  |> should.equal("sub root")

  // Sub-router child route "/admin/items"
  let req_items =
    request.new() |> request.set_method(Get) |> request.set_path("/admin/items")
  fist.handle(router, req_items, Nil, fn() { "404" })
  |> should.equal("sub items")

  // Parent router's own root route remains intact
  let req_main =
    request.new() |> request.set_method(Get) |> request.set_path("/")
  fist.handle(router, req_main, Nil, fn() { "404" })
  |> should.equal("main root")
}

/// Root Prefix Mount Merging:
/// Mounting at "/" or "" merges the sub-tree directly into the parent's root without additional prefix segments.
pub fn mount_at_root_test() {
  let sub =
    fist.new()
    |> fist.get("/extra", fn(_, _, _) { "extra" })

  let router =
    fist.new()
    |> fist.get("/original", fn(_, _, _) { "original" })
    |> fist.mount("/", sub, fn(c) { c })

  let req1 =
    request.new() |> request.set_method(Get) |> request.set_path("/original")
  fist.handle(router, req1, Nil, fn() { "404" })
  |> should.equal("original")

  let req2 =
    request.new() |> request.set_method(Get) |> request.set_path("/extra")
  fist.handle(router, req2, Nil, fn() { "404" })
  |> should.equal("extra")
}

/// Multi-Level Context Transformation:
/// Context types can be successively transformed across arbitrary levels of nested mounts.
pub fn deeply_nested_mount_test() {
  let level3 =
    fist.new()
    |> fist.get("/leaf", fn(_req, ctx: DeepContext, _params) {
      "leaf:" <> ctx.name <> ":" <> int.to_string(ctx.depth)
    })

  let level2 =
    fist.new()
    |> fist.mount("/level3", level3, fn(ctx: SubContext) {
      DeepContext(depth: 3, name: ctx.name <> "-deep")
    })

  let root =
    fist.new()
    |> fist.mount("/level2", level2, fn(ctx: RootContext) {
      SubContext(name: "root-" <> int.to_string(ctx.id))
    })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/level2/level3/leaf")

  fist.handle(root, req, RootContext(id: 7), fn() { "404" })
  |> should.equal("leaf:root-7-deep:3")
}
