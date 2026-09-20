import fist.{
  type PathRegistry, InvalidParameter, MissingParameter, RouteNotFound,
}
import fist/extract
import gleam/http/request
import gleeunit/should
import support

pub type AppContext {
  AppContext(registry: PathRegistry)
}

/// Static Route Reverse Path:
/// Generates canonical URL for static endpoints without parameters.
pub fn static_named_route_test() {
  let router =
    fist.new()
    |> fist.get("/about", fn(_, _, _) { "about" })
    |> fist.name("about_page")

  fist.path(router, for: "about_page", with: [])
  |> should.equal(Ok("/about"))
}

/// Root Route Reverse Path:
/// Correctly formats root path `/` with and without extra query parameters.
pub fn root_named_route_test() {
  let router =
    fist.new()
    |> fist.get("/", fn(_, _, _) { "home" })
    |> fist.name("home")

  fist.path(router, for: "home", with: [])
  |> should.equal(Ok("/"))

  fist.path(router, for: "home", with: [#("ref", "twitter")])
  |> should.equal(Ok("/?ref=twitter"))
}

/// Dynamic Parameter Interpolation:
/// Dynamic path segments `:id` are substituted with provided arguments.
pub fn dynamic_parameter_interpolation_test() {
  let router =
    fist.new()
    |> fist.get("/users/:id/profile", fn(_, _, _) { "profile" })
    |> fist.name("user_profile")

  fist.path(router, for: "user_profile", with: [#("id", "42")])
  |> should.equal(Ok("/users/42/profile"))
}

/// Multiple Dynamic Parameters Interpolation:
/// Multi-segment dynamic routes substitute all parameters in path order.
pub fn multiple_dynamic_parameters_test() {
  let router =
    fist.new()
    |> fist.get("/orgs/:org/projects/:project/issues/:issue_id", fn(_, _, _) {
      "issue"
    })
    |> fist.name("project_issue")

  fist.path(router, for: "project_issue", with: [
    #("org", "gleam-lang"),
    #("project", "fist"),
    #("issue_id", "128"),
  ])
  |> should.equal(Ok("/orgs/gleam-lang/projects/fist/issues/128"))
}

/// Wildcard Parameter Interpolation:
/// Catch-all wildcards `*filepath` substitute multi-segment paths preserving slashes.
pub fn wildcard_interpolation_test() {
  let router =
    fist.new()
    |> fist.get("/static/*filepath", fn(_, _, _) { "asset" })
    |> fist.name("static_asset")

  fist.path(router, for: "static_asset", with: [
    #("filepath", "css/themes/dark.css"),
  ])
  |> should.equal(Ok("/static/css/themes/dark.css"))
}

/// Percent-Encoding in Dynamic and Wildcard Parameters:
/// Special characters in dynamic parameters are percent-encoded according to RFC 3986.
pub fn percent_encoding_in_parameters_test() {
  let router =
    fist.new()
    |> fist.get("/search/:category/:query", fn(_, _, _) { "search" })
    |> fist.name("search")
    |> fist.get("/downloads/*path", fn(_, _, _) { "download" })
    |> fist.name("download")

  fist.path(router, for: "search", with: [
    #("category", "books & magazines"),
    #("query", "c++ guide"),
  ])
  |> should.equal(Ok("/search/books%20%26%20magazines/c++%20guide"))

  // Wildcard encodes filename special characters while preserving '/' separators
  fist.path(router, for: "download", with: [
    #("path", "my docs/report 2026.pdf"),
  ])
  |> should.equal(Ok("/downloads/my%20docs/report%202026.pdf"))
}

/// Extra Unused Parameters Appended as Query String:
/// Any parameters not consumed by dynamic or wildcard path segments are formatted
/// as standard URL query parameters.
pub fn extra_parameters_as_query_string_test() {
  let router =
    fist.new()
    |> fist.get("/users/:id", fn(_, _, _) { "user" })
    |> fist.name("user_detail")

  fist.path(router, for: "user_detail", with: [
    #("id", "100"),
    #("tab", "activity"),
    #("sort", "desc"),
  ])
  |> should.equal(Ok("/users/100?tab=activity&sort=desc"))
}

/// Route Guard Validation:
/// `fist.path` enforces route guard predicates, rejecting invalid values with `InvalidParameter`.
pub fn guard_validation_in_path_generation_test() {
  let router =
    fist.new()
    |> fist.get("/users/:id", fn(_, _, _) { "user" })
    |> fist.guard("id", when: extract.is_int)
    |> fist.name("user_show")

  // Valid integer passes guard
  fist.path(router, for: "user_show", with: [#("id", "42")])
  |> should.equal(Ok("/users/42"))

  // String fails integer guard
  fist.path(router, for: "user_show", with: [#("id", "not-a-number")])
  |> should.equal(
    Error(InvalidParameter(
      route: "user_show",
      param: "id",
      value: "not-a-number",
    )),
  )
}

/// Guard Attached After `fist.name`:
/// Calling `fist.guard` after `fist.name` updates the template's guard condition.
pub fn guard_attached_after_fist_name_test() {
  let router =
    fist.new()
    |> fist.get("/items/:code", fn(_, _, _) { "item" })
    |> fist.name("item_code")
    |> fist.guard("code", when: extract.is_int)

  fist.path(router, for: "item_code", with: [#("code", "999")])
  |> should.equal(Ok("/items/999"))

  fist.path(router, for: "item_code", with: [#("code", "abc")])
  |> should.equal(
    Error(InvalidParameter(route: "item_code", param: "code", value: "abc")),
  )
}

/// Missing Parameter Error:
/// Omitting a required path segment parameter returns `MissingParameter`.
pub fn missing_parameter_error_test() {
  let router =
    fist.new()
    |> fist.get("/posts/:id/comments/:cid", fn(_, _, _) { "comment" })
    |> fist.name("comment_view")

  fist.path(router, for: "comment_view", with: [#("id", "10")])
  |> should.equal(
    Error(MissingParameter(route: "comment_view", missing: "cid")),
  )
}

/// Route Not Found Error:
/// Requesting a path for an unregistered name returns `RouteNotFound`.
pub fn route_not_found_error_test() {
  let router = fist.new()

  fist.path(router, for: "non_existent", with: [])
  |> should.equal(Error(RouteNotFound("non_existent")))
}

/// Mounted Sub-Router Prefixes Named Routes:
/// When a router is mounted under a prefix, all its named routes inherit the mount prefix.
pub fn mounted_sub_router_prefixes_named_routes_test() {
  let sub =
    fist.new()
    |> fist.get("/users/:id", fn(_, _, _) { "sub user" })
    |> fist.name("sub_user")

  let parent =
    fist.new()
    |> fist.mount("/api/v1", sub, fn(c) { c })

  fist.path(parent, for: "sub_user", with: [#("id", "7")])
  |> should.equal(Ok("/api/v1/users/7"))
}

/// Mounted Sub-Router with Dynamic Prefix:
/// Dynamic parameters in mount prefixes are recognized and required by `fist.path`.
pub fn mounted_sub_router_with_dynamic_prefix_test() {
  let sub =
    fist.new()
    |> fist.get("/repos/:repo", fn(_, _, _) { "repo" })
    |> fist.name("repo_view")

  let parent =
    fist.new()
    |> fist.mount("/orgs/:org", sub, fn(c) { c })

  fist.path(parent, for: "repo_view", with: [
    #("org", "gleam-lang"),
    #("repo", "fist"),
  ])
  |> should.equal(Ok("/orgs/gleam-lang/repos/fist"))

  // Missing the prefix parameter returns MissingParameter
  fist.path(parent, for: "repo_view", with: [#("repo", "fist")])
  |> should.equal(Error(MissingParameter(route: "repo_view", missing: "org")))
}

/// Route Groups Inherit Group Prefix:
/// Routes named inside `fist.group` automatically inherit the group's prefix.
pub fn group_prefixes_named_routes_test() {
  let router =
    fist.new()
    |> fist.group(at: "/admin", with: [], defining: fn(r) {
      r
      |> fist.get("/metrics", fn(_, _, _) { "metrics" })
      |> fist.name("admin_metrics")
    })

  fist.path(router, for: "admin_metrics", with: [])
  |> should.equal(Ok("/admin/metrics"))
}

/// Router Merge Preserves Named Routes from Both Routers:
/// Merging two disjoint routers preserves all named routes in the resulting router.
pub fn merge_preserves_named_routes_test() {
  let router_a =
    fist.new()
    |> fist.get("/auth/login", fn(_, _, _) { "login" })
    |> fist.name("login")

  let router_b =
    fist.new()
    |> fist.get("/auth/register", fn(_, _, _) { "register" })
    |> fist.name("register")

  let merged = fist.merge(router_a, router_b)

  fist.path(merged, for: "login", with: []) |> should.equal(Ok("/auth/login"))
  fist.path(merged, for: "register", with: [])
  |> should.equal(Ok("/auth/register"))
}

/// Fail-Fast: Empty Route Name:
/// Calling `fist.name` with an empty or whitespace-only name panics immediately.
pub fn empty_name_panics_test() {
  support.rescue(fn() {
    fist.new()
    |> fist.get("/users", fn(_, _, _) { "users" })
    |> fist.name("   ")
  })
  |> should.be_error
}

/// Fail-Fast: Name Without Route:
/// Calling `fist.name` without a preceding route definition panics immediately.
pub fn name_without_route_panics_test() {
  support.rescue(fn() {
    fist.new()
    |> fist.name("orphan")
  })
  |> should.be_error
}

/// Fail-Fast: Route Name Collision in Same Router:
/// Registering two routes with the same name panics immediately.
pub fn duplicate_name_panics_test() {
  support.rescue(fn() {
    fist.new()
    |> fist.get("/path1", fn(_, _, _) { "1" })
    |> fist.name("duplicate")
    |> fist.get("/path2", fn(_, _, _) { "2" })
    |> fist.name("duplicate")
  })
  |> should.be_error
}

/// Fail-Fast: Name Collision on Mount:
/// Mounting a sub-router that shares a route name with the parent panics immediately.
pub fn name_collision_on_mount_panics_test() {
  let sub =
    fist.new()
    |> fist.get("/sub", fn(_, _, _) { "sub" })
    |> fist.name("shared_name")

  let parent =
    fist.new()
    |> fist.get("/parent", fn(_, _, _) { "parent" })
    |> fist.name("shared_name")

  support.rescue(fn() { fist.mount(parent, "/api", sub, fn(c) { c }) })
  |> should.be_error
}

/// Fail-Fast: Name Collision on Merge:
/// Merging two routers with colliding route names panics immediately.
pub fn name_collision_on_merge_panics_test() {
  let router_a =
    fist.new()
    |> fist.get("/a", fn(_, _, _) { "a" })
    |> fist.name("conflict")

  let router_b =
    fist.new()
    |> fist.get("/b", fn(_, _, _) { "b" })
    |> fist.name("conflict")

  support.rescue(fn() { fist.merge(router_a, router_b) })
  |> should.be_error
}

/// Decoupled Handler Usage via `PathRegistry`:
/// Extracting a `PathRegistry` and storing it inside application context allows
/// request handlers to generate paths without circular router type dependencies.
pub fn decoupled_handler_usage_test() {
  let router =
    fist.new()
    |> fist.get("/users/:id", fn(_, _, _) { "profile" })
    |> fist.name("user_profile")
    |> fist.get("/redirect-me", fn(_, ctx: AppContext, _) {
      case
        fist.path_from(ctx.registry, for: "user_profile", with: [#("id", "99")])
      {
        Ok(url) -> "redirect to " <> url
        Error(_) -> "error"
      }
    })

  let registry = fist.path_registry(router)
  let app_ctx = AppContext(registry: registry)

  let req = request.new() |> request.set_path("/redirect-me")
  fist.handle(router, req, app_ctx, fn() { "404" })
  |> should.equal("redirect to /users/99")
}

/// Idempotent Route Name Sharing Across Methods:
/// If GET and POST register the exact same canonical path template under the same name,
/// it is accepted idempotently without collision.
pub fn same_path_different_methods_idempotent_name_test() {
  let router =
    fist.new()
    |> fist.get("/users/:id", fn(_, _, _) { "get" })
    |> fist.name("user")
    |> fist.post("/users/:id", fn(_, _, _) { "post" })
    |> fist.name("user")

  fist.path(router, for: "user", with: [#("id", "50")])
  |> should.equal(Ok("/users/50"))
}

/// Fail-Fast: Conflicting Path with Same Route Name:
/// If two completely different route paths attempt to register under the same name,
/// it panics immediately.
pub fn conflicting_path_same_name_panics_test() {
  support.rescue(fn() {
    fist.new()
    |> fist.get("/users/:id", fn(_, _, _) { "users" })
    |> fist.name("item")
    |> fist.get("/products/:id", fn(_, _, _) { "products" })
    |> fist.name("item")
  })
  |> should.be_error
}

/// Multiple Names on Same Route Act as Aliases:
/// Calling `fist.name` multiple times on the same route registers aliases.
pub fn multiple_names_on_same_route_alias_test() {
  let router =
    fist.new()
    |> fist.get("/members/:id", fn(_, _, _) { "member" })
    |> fist.name("member_show")
    |> fist.name("user_show")

  fist.path(router, for: "member_show", with: [#("id", "12")])
  |> should.equal(Ok("/members/12"))

  fist.path(router, for: "user_show", with: [#("id", "12")])
  |> should.equal(Ok("/members/12"))
}

/// Dynamic Parameter Cannot Be Empty:
/// Supplying an empty string `""` for a dynamic parameter returns `InvalidParameter`.
pub fn empty_dynamic_parameter_value_rejected_test() {
  let router =
    fist.new()
    |> fist.get("/posts/:id", fn(_, _, _) { "post" })
    |> fist.name("post")

  fist.path(router, for: "post", with: [#("id", "")])
  |> should.equal(
    Error(InvalidParameter(route: "post", param: "id", value: "")),
  )
}

/// Wildcard Parameter Cannot Be Empty:
/// Supplying an empty string `""` for a wildcard parameter returns `InvalidParameter`.
pub fn empty_wildcard_parameter_value_rejected_test() {
  let router =
    fist.new()
    |> fist.get("/assets/*path", fn(_, _, _) { "asset" })
    |> fist.name("asset")

  fist.path(router, for: "asset", with: [#("path", "")])
  |> should.equal(
    Error(InvalidParameter(route: "asset", param: "path", value: "")),
  )
}

/// Wildcard Parameter Traversal Rejected:
/// Supplying dot segments (".." or ".") in wildcard parameter values returns InvalidParameter
/// preventing reverse path traversal attacks.
pub fn wildcard_parameter_traversal_rejected_test() {
  let router =
    fist.new()
    |> fist.get("/assets/*path", fn(_, _, _) { "asset" })
    |> fist.name("asset")

  fist.path(router, for: "asset", with: [#("path", "../../secret.pem")])
  |> should.equal(
    Error(InvalidParameter(
      route: "asset",
      param: "path",
      value: "../../secret.pem",
    )),
  )

  fist.path(router, for: "asset", with: [#("path", "images/../secrets/key")])
  |> should.equal(
    Error(InvalidParameter(
      route: "asset",
      param: "path",
      value: "images/../secrets/key",
    )),
  )
}

/// Path Injection Defense:
/// Slashes inside dynamic parameters are percent-encoded to prevent path structure corruption.
pub fn path_injection_attempt_encoded_safely_test() {
  let router =
    fist.new()
    |> fist.get("/users/:id/edit", fn(_, _, _) { "edit" })
    |> fist.name("user_edit")

  fist.path(router, for: "user_edit", with: [#("id", "42/delete/all")])
  |> should.equal(Ok("/users/42%2Fdelete%2Fall/edit"))
}

/// PathRegistry Inspection Helpers:
/// `has_path`, `path_names`, and `path_template` allow introspecting registered names.
pub fn registry_inspection_helpers_test() {
  let router =
    fist.new()
    |> fist.get("/users/:id/profile", fn(_, _, _) { "profile" })
    |> fist.name("profile")
    |> fist.get("/health", fn(_, _, _) { "ok" })
    |> fist.name("health")

  let registry = fist.path_registry(router)

  fist.has_path(registry, "profile") |> should.equal(True)
  fist.has_path(registry, "health") |> should.equal(True)
  fist.has_path(registry, "unknown") |> should.equal(False)

  fist.path_template(registry, "profile")
  |> should.equal(Ok("/users/:id/profile"))

  fist.path_template(registry, "health")
  |> should.equal(Ok("/health"))

  fist.path_template(registry, "unknown")
  |> should.equal(Error(Nil))
}

/// Router Merge with Compatible Same-Name Routes Succeeds:
/// If two merged routers happen to register the same route name for identical paths,
/// merge succeeds idempotently.
pub fn compatible_path_name_on_merge_test() {
  let a =
    fist.new()
    |> fist.get("/home", fn(_, _, _) { "a" })
    |> fist.name("home")

  let b =
    fist.new()
    |> fist.post("/home", fn(_, _, _) { "b" })
    |> fist.name("home")

  let merged = fist.merge(a, b)
  fist.path(merged, for: "home", with: []) |> should.equal(Ok("/home"))
}
