import fist
import gleam/http.{Get, Post}
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

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

  // Verify route count
  list.length(routes) |> should.equal(3)

  // Verify specific routes
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

pub fn describe_without_route_test() {
  // describe called on empty router should do nothing safely
  let router =
    fist.new()
    |> fist.describe("Ghost description")

  fist.inspect(router) |> should.equal([])
}

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
