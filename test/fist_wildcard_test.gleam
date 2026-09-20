import fist
import gleam/dict
import gleam/http.{Get}
import gleam/http/request
import gleam/list
import gleeunit
import gleeunit/should
import support

pub fn main() {
  gleeunit.main()
}

/// Basic Multi-Segment Wildcard Capture:
/// Wildcard captures all trailing segments separated by slashes without leading slash.
pub fn basic_wildcard_test() {
  let router =
    fist.new()
    |> fist.get("/static/*filepath", fn(_, _, params) {
      let path = dict.get(params, "filepath") |> should.be_ok
      "file:" <> path
    })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/static/css/theme/dark.css")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("file:css/theme/dark.css")
}

/// Single-Segment Wildcard Capture:
/// Wildcard captures a single trailing segment cleanly.
pub fn single_segment_wildcard_test() {
  let router =
    fist.new()
    |> fist.get("/files/*path", fn(_, _, params) {
      let path = dict.get(params, "path") |> should.be_ok
      "file:" <> path
    })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/files/document.pdf")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("file:document.pdf")
}

/// Wildcard Minimum Segment Invariant:
/// A wildcard requires at least one segment; requesting the parent prefix without segments returns 404.
pub fn wildcard_requires_at_least_one_segment_test() {
  let router =
    fist.new()
    |> fist.get("/files/*path", fn(_, _, _) { "matched" })

  let req_base =
    request.new() |> request.set_method(Get) |> request.set_path("/files")
  let req_trailing_slash =
    request.new() |> request.set_method(Get) |> request.set_path("/files/")

  fist.handle(router, req_base, Nil, fn() { "404" })
  |> should.equal("404")
  fist.handle(router, req_trailing_slash, Nil, fn() { "404" })
  |> should.equal("404")
}

/// Static Node and Wildcard Coexistence:
/// A base path can serve a static route while its wildcard child serves sub-paths.
pub fn static_and_wildcard_coexistence_test() {
  let router =
    fist.new()
    |> fist.get("/files", fn(_, _, _) { "index listing" })
    |> fist.get("/files/*path", fn(_, _, params) {
      let path = dict.get(params, "path") |> should.be_ok
      "file:" <> path
    })

  let req_index =
    request.new() |> request.set_method(Get) |> request.set_path("/files")
  let req_file =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/files/images/logo.png")

  fist.handle(router, req_index, Nil, fn() { "404" })
  |> should.equal("index listing")
  fist.handle(router, req_file, Nil, fn() { "404" })
  |> should.equal("file:images/logo.png")
}

/// Static Precedence Over Wildcard:
/// Exact static routes take priority over overlapping wildcard catch-alls.
pub fn static_precedence_over_wildcard_test() {
  let router =
    fist.new()
    |> fist.get("/api/v1/*rest", fn(_, _, _) { "wildcard" })
    |> fist.get("/api/v1/health", fn(_, _, _) { "health" })

  let req_static =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/api/v1/health")
  let req_wildcard =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/api/v1/other/path")

  fist.handle(router, req_static, Nil, fn() { "404" })
  |> should.equal("health")
  fist.handle(router, req_wildcard, Nil, fn() { "404" })
  |> should.equal("wildcard")
}

/// Dynamic Parameter Precedence Over Wildcard:
/// Single-segment dynamic routes take priority over multi-segment wildcards.
pub fn dynamic_precedence_over_wildcard_test() {
  let router =
    fist.new()
    |> fist.get("/users/:id", fn(_, _, params) {
      let id = dict.get(params, "id") |> should.be_ok
      "user:" <> id
    })
    |> fist.get("/users/*rest", fn(_, _, params) {
      let rest = dict.get(params, "rest") |> should.be_ok
      "rest:" <> rest
    })

  let req_single =
    request.new() |> request.set_method(Get) |> request.set_path("/users/42")
  let req_multi =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/42/posts/featured")

  fist.handle(router, req_single, Nil, fn() { "404" })
  |> should.equal("user:42")
  fist.handle(router, req_multi, Nil, fn() { "404" })
  |> should.equal("rest:42/posts/featured")
}

/// Deep Backtracking From Dead-End Static Branch to Wildcard:
/// Traversal that partially matches static segments but terminates without match backtracks to wildcard.
pub fn deep_backtracking_to_wildcard_test() {
  let router =
    fist.new()
    |> fist.get("/static/*filepath", fn(_, _, params) {
      let fp = dict.get(params, "filepath") |> should.be_ok
      "wildcard:" <> fp
    })
    |> fist.get("/static/css/theme.css", fn(_, _, _) { "static:theme" })

  // 1. Exact match hits static route
  let req_theme =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/static/css/theme.css")
  fist.handle(router, req_theme, Nil, fn() { "404" })
  |> should.equal("static:theme")

  // 2. Dead-end in static "css" branch backtracks to ancestor wildcard /static/*filepath
  let req_other =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/static/css/custom.css")
  fist.handle(router, req_other, Nil, fn() { "404" })
  |> should.equal("wildcard:css/custom.css")
}

/// Root Level Wildcard Catch-All:
/// Root-level wildcard (/*rest) safely cohabits alongside root route (/).
pub fn root_level_wildcard_test() {
  let router =
    fist.new()
    |> fist.get("/", fn(_, _, _) { "home" })
    |> fist.get("/*rest", fn(_, _, params) {
      let rest = dict.get(params, "rest") |> should.be_ok
      "catchall:" <> rest
    })

  let req_root =
    request.new() |> request.set_method(Get) |> request.set_path("/")
  let req_catchall =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/anything/goes/here")

  fist.handle(router, req_root, Nil, fn() { "404" })
  |> should.equal("home")
  fist.handle(router, req_catchall, Nil, fn() { "404" })
  |> should.equal("catchall:anything/goes/here")
}

/// Non-Terminal Wildcard Registration Panic:
/// Placing path segments after a wildcard causes a fail-fast panic.
pub fn non_terminal_wildcard_panics_test() {
  support.rescue(fn() {
    fist.new()
    |> fist.get("/files/*rest/download", fn(_, _, _) { "invalid" })
  })
  |> should.be_error
}

/// Conflicting Wildcards Registration Panic:
/// Registering two wildcards at the same tree level causes a fail-fast panic.
pub fn conflicting_wildcards_panics_test() {
  support.rescue(fn() {
    fist.new()
    |> fist.get("/files/*a", fn(_, _, _) { "a" })
    |> fist.get("/files/*b", fn(_, _, _) { "b" })
  })
  |> should.be_error
}

/// Wildcard Merge Collision Panic:
/// Merging two routers with wildcards at the same level causes a fail-fast panic.
pub fn wildcard_merge_collision_panics_test() {
  let router_a =
    fist.new()
    |> fist.get("/static/*filepath", fn(_, _, _) { "a" })

  let router_b =
    fist.new()
    |> fist.get("/static/*filepath", fn(_, _, _) { "b" })

  support.rescue(fn() { fist.merge(router_a, router_b) })
  |> should.be_error
}

/// Wildcard Prefix Mounting Panic:
/// Using a wildcard in a mount prefix causes a fail-fast panic.
pub fn wildcard_prefix_mount_panics_test() {
  let child =
    fist.new()
    |> fist.get("/endpoint", fn(_, _, _) { "child" })

  support.rescue(fn() {
    fist.new()
    |> fist.mount("/api/*rest", child, fn(c) { c })
  })
  |> should.be_error
}

/// Percent-Encoded Characters in Wildcard:
/// Segment tokens within wildcard captures are percent-decoded preserving path delimiters.
pub fn wildcard_url_percent_decoding_test() {
  let router =
    fist.new()
    |> fist.get("/download/*path", fn(_, _, params) {
      let p = dict.get(params, "path") |> should.be_ok
      "path:" <> p
    })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/download/pasta%20de%20fotos/f%C3%A9rias%2B2026.jpg")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("path:pasta de fotos/férias+2026.jpg")
}

/// Wildcard Middleware and Introspection:
/// Middleware envelopes wildcard handlers and fist.inspect reports wildcard routes with parameters.
pub fn wildcard_middleware_and_inspect_test() {
  let router =
    fist.new()
    |> fist.get("/assets/*asset", fn(_, _, params) {
      let a = dict.get(params, "asset") |> should.be_ok
      a
    })
    |> fist.describe("Static asset handler")
    |> fist.wrap(fn(next) {
      fn(req, ctx, params) { "[" <> next(req, ctx, params) <> "]" }
    })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/assets/fonts/inter.woff2")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("[fonts/inter.woff2]")

  let routes = fist.inspect(router)
  let assert Ok(info) = list.first(routes)
  info.path |> should.equal("/assets/*asset")
  info.description |> should.equal("Static asset handler")
  info.params |> should.equal(["asset"])
}
