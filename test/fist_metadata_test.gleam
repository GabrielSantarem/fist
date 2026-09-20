import fist
import gleam/http.{Get, Post}
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

/// Metadata Attachment & Introspection:
/// fist.describe associates human-readable documentation with routes, introspectable via fist.inspect.
pub fn describe_and_inspect_test() {
  let handler = fn(_, _, _) { "ok" }

  let router =
    fist.new()
    |> fist.get("/users", to: handler)
    |> fist.describe("List users")
    |> fist.post("/users", to: handler)
    |> fist.describe("Create user")
    |> fist.get("/users/:id", to: handler)
    |> fist.describe("Get user by ID")

  let routes = fist.inspect(router)

  // Verify total route count
  list.length(routes) |> should.equal(3)

  // Verify specific route metadata
  let assert Ok(list_users) =
    list.find(routes, fn(r) { r.path == "/users" && r.method == Get })
  list_users.description |> should.equal("List users")
  list_users.params |> should.equal([])

  let assert Ok(create_user) =
    list.find(routes, fn(r) { r.path == "/users" && r.method == Post })
  create_user.description |> should.equal("Create user")

  let assert Ok(get_user) =
    list.find(routes, fn(r) { r.path == "/users/:id" && r.method == Get })
  get_user.description |> should.equal("Get user by ID")
  get_user.params |> should.equal(["id"])
}

/// No-op Describe Safety:
/// Calling describe on an empty router is a safe no-op that produces no phantom routes.
pub fn describe_without_route_test() {
  let router =
    fist.new()
    |> fist.describe("Ghost description")

  fist.inspect(router) |> should.equal([])
}

/// Metadata Preservation across Output Mapping:
/// fist.map transforms handler return types while maintaining route descriptions unchanged.
pub fn map_preserves_metadata_test() {
  let handler = fn(_, _, _) { "original" }

  let router =
    fist.new()
    |> fist.get("/data", to: handler)
    |> fist.describe("Important Data")
    |> fist.map(fn(s) { s <> " mapped" })

  let routes = fist.inspect(router)

  let assert Ok(route) = list.first(routes)
  route.description |> should.equal("Important Data")
  route.path |> should.equal("/data")
}

/// Complex Tree Introspection:
/// Full path segments and parameter identifiers are accurately reconstructed in deep hierarchies.
pub fn complex_tree_inspection_test() {
  let h = fn(_, _, _) { "" }

  let router =
    fist.new()
    |> fist.get("/api/v1/users", to: h)
    |> fist.describe("V1 Users")
    |> fist.get("/api/v1/posts/:postId/comments", to: h)
    |> fist.describe("Comments")

  let routes = fist.inspect(router)

  let assert Ok(comments_route) =
    list.find(routes, fn(r) { r.path == "/api/v1/posts/:postId/comments" })

  comments_route.description |> should.equal("Comments")
  comments_route.params |> should.equal(["postId"])
}

/// Mounted Sub-Router Introspection:
/// Introspecting a parent router surfaces mounted sub-router routes with combined prefixes and descriptions.
pub fn inspect_mounted_router_metadata_test() {
  let sub =
    fist.new()
    |> fist.get("/items", to: fn(_, _, _) { "items" })
    |> fist.describe("List sub items")
    |> fist.get("/items/:item_id", to: fn(_, _, _) { "item" })
    |> fist.describe("Get sub item")

  let parent =
    fist.new()
    |> fist.mount("/api/v1", sub, fn(c) { c })

  let routes = fist.inspect(parent)
  list.length(routes) |> should.equal(2)

  let assert Ok(items_route) =
    list.find(routes, fn(r) { r.path == "/api/v1/items" })
  items_route.description |> should.equal("List sub items")
  items_route.params |> should.equal([])

  let assert Ok(item_route) =
    list.find(routes, fn(r) { r.path == "/api/v1/items/:item_id" })
  item_route.description |> should.equal("Get sub item")
  item_route.params |> should.equal(["item_id"])
}

/// Root Route Introspection:
/// The root route ("/") is correctly reported with its description and an empty parameter list.
pub fn inspect_root_route_metadata_test() {
  let router =
    fist.new()
    |> fist.get("/", to: fn(_, _, _) { "root" })
    |> fist.describe("Root endpoint")

  let routes = fist.inspect(router)
  let assert Ok(root_route) = list.first(routes)
  root_route.path |> should.equal("/")
  root_route.description |> should.equal("Root endpoint")
  root_route.params |> should.equal([])
}

/// Sibling Dynamic Route Descriptions:
/// Distinct routes sharing the same dynamic parent segment preserve their respective descriptions.
pub fn describe_multiple_dynamic_routes_test() {
  let h = fn(_, _, _) { "" }
  let router =
    fist.new()
    |> fist.get("/users/:id/profile", to: h)
    |> fist.describe("User Profile")
    |> fist.get("/users/:id/settings", to: h)
    |> fist.describe("User Settings")

  let routes = fist.inspect(router)
  list.length(routes) |> should.equal(2)

  let assert Ok(profile) =
    list.find(routes, fn(r) { r.path == "/users/:id/profile" })
  profile.description |> should.equal("User Profile")

  let assert Ok(settings) =
    list.find(routes, fn(r) { r.path == "/users/:id/settings" })
  settings.description |> should.equal("User Settings")
}
