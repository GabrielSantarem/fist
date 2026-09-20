import fist
import gleam/dict
import gleam/http.{Delete, Get, Post, Put}
import gleam/http/request
import gleam/list
import gleeunit
import gleeunit/should
import support

pub fn main() {
  gleeunit.main()
}

/// Merge Disjoint Routers:
/// Merging two independent routers combines their route tables cleanly.
pub fn merge_disjoint_routes_test() {
  let router_a =
    fist.new()
    |> fist.get("/users", fn(_, _, _) { "users list" })

  let router_b =
    fist.new()
    |> fist.post("/users", fn(_, _, _) { "user created" })
    |> fist.get("/products", fn(_, _, _) { "products list" })

  let merged = fist.merge(router_a, router_b)

  let req_users_get =
    request.new() |> request.set_method(Get) |> request.set_path("/users")
  let req_users_post =
    request.new() |> request.set_method(Post) |> request.set_path("/users")
  let req_products_get =
    request.new() |> request.set_method(Get) |> request.set_path("/products")

  fist.handle(merged, req_users_get, Nil, fn() { "404" })
  |> should.equal("users list")
  fist.handle(merged, req_users_post, Nil, fn() { "404" })
  |> should.equal("user created")
  fist.handle(merged, req_products_get, Nil, fn() { "404" })
  |> should.equal("products list")
}

/// Merge Shared Static Prefixes:
/// Sub-trees with identical static path prefixes are fused recursively.
pub fn merge_shared_static_prefix_test() {
  let router_a =
    fist.new()
    |> fist.get("/api/v1/auth/login", fn(_, _, _) { "login" })

  let router_b =
    fist.new()
    |> fist.get("/api/v1/auth/logout", fn(_, _, _) { "logout" })

  let merged = fist.merge(router_a, router_b)

  let req_login =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/api/v1/auth/login")
  let req_logout =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/api/v1/auth/logout")

  fist.handle(merged, req_login, Nil, fn() { "404" })
  |> should.equal("login")
  fist.handle(merged, req_logout, Nil, fn() { "404" })
  |> should.equal("logout")
}

/// Merge Compatible Dynamic Segments:
/// Routers sharing a dynamic segment with identical parameter names fuse harmoniously.
pub fn merge_shared_dynamic_parameter_names_test() {
  let router_a =
    fist.new()
    |> fist.get("/users/:id/profile", fn(_, _, params) {
      let id = dict.get(params, "id") |> should.be_ok
      "profile " <> id
    })

  let router_b =
    fist.new()
    |> fist.get("/users/:id/settings", fn(_, _, params) {
      let id = dict.get(params, "id") |> should.be_ok
      "settings " <> id
    })

  let merged = fist.merge(router_a, router_b)

  let req_profile =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/42/profile")
  let req_settings =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/42/settings")

  fist.handle(merged, req_profile, Nil, fn() { "404" })
  |> should.equal("profile 42")
  fist.handle(merged, req_settings, Nil, fn() { "404" })
  |> should.equal("settings 42")
}

/// Duplicate Endpoint Merge Collision Panic:
/// Merging two routers with identical HTTP method and path causes a fail-fast panic.
pub fn merge_duplicate_endpoint_collision_panics_test() {
  let router_a =
    fist.new()
    |> fist.get("/dashboard", fn(_, _, _) { "a" })

  let router_b =
    fist.new()
    |> fist.get("/dashboard", fn(_, _, _) { "b" })

  support.rescue(fn() { fist.merge(router_a, router_b) })
  |> should.be_error
}

/// Merging Distinct Dynamic Parameter Branches:
/// Merging routers with differing dynamic parameter names at the same level merges cleanly
/// as ordered dynamic branches, resolving through fallthrough.
pub fn merge_conflicting_dynamic_parameters_panics_test() {
  let router_a =
    fist.new()
    |> fist.get("/users/:id/profile", fn(_, _, _) { "a" })

  let router_b =
    fist.new()
    |> fist.get("/users/:user_id/settings", fn(_, _, _) { "b" })

  let merged = fist.merge(router_a, router_b)

  let req_a = request.new() |> request.set_path("/users/42/profile")
  let req_b = request.new() |> request.set_path("/users/42/settings")

  fist.handle(merged, req_a, Nil, fn() { "404" }) |> should.equal("a")
  fist.handle(merged, req_b, Nil, fn() { "404" }) |> should.equal("b")
}

/// Monoidal Empty Router Identity:
/// Merging any router with an empty router leaves the original routes unmodified.
pub fn merge_empty_router_identity_test() {
  let router =
    fist.new()
    |> fist.get("/hello", fn(_, _, _) { "world" })

  let merged_left = fist.merge(fist.new(), router)
  let merged_right = fist.merge(router, fist.new())

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/hello")

  fist.handle(merged_left, req, Nil, fn() { "404" })
  |> should.equal("world")
  fist.handle(merged_right, req, Nil, fn() { "404" })
  |> should.equal("world")
}

/// Allowed Methods Preservation:
/// Merging preserves and combines allowed HTTP methods across routers.
pub fn merge_preserves_allowed_methods_test() {
  let router_a =
    fist.new()
    |> fist.get("/items", fn(_, _, _) { "list" })
    |> fist.put("/items", fn(_, _, _) { "replace" })

  let router_b =
    fist.new()
    |> fist.post("/items", fn(_, _, _) { "create" })
    |> fist.delete("/items", fn(_, _, _) { "delete" })

  let merged = fist.merge(router_a, router_b)
  let methods = fist.allowed_methods(merged, "/items")

  list.contains(methods, Get) |> should.be_true
  list.contains(methods, Put) |> should.be_true
  list.contains(methods, Post) |> should.be_true
  list.contains(methods, Delete) |> should.be_true
}

/// Mount Collision Panic:
/// Mounting a sub-router that collides with existing parent routes causes a fail-fast panic.
pub fn mount_collision_panics_test() {
  let parent =
    fist.new()
    |> fist.get("/admin/panel", fn(_, _, _) { "parent panel" })

  let child =
    fist.new()
    |> fist.get("/panel", fn(_, _, _) { "child panel" })

  // Mounting child at /admin creates duplicate /admin/panel
  support.rescue(fn() { fist.mount(parent, "/admin", child, fn(c) { c }) })
  |> should.be_error
}
