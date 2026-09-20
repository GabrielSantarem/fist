import fist
import gleam/dict
import gleam/http.{Get}
import gleam/http/request
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

/// RFC 3986 Current Directory Dot Removal:
/// Single dot segments ('.') are pruned during path canonicalization.
pub fn dot_segment_removal_test() {
  let router =
    fist.new()
    |> fist.get("/api/v1/status", fn(_, _, _) { "ok" })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/api/./v1/./status")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("ok")
}

/// RFC 3986 Parent Directory Resolution:
/// Double dot segments ('..') unwind the preceding segment in the path.
pub fn parent_directory_resolution_test() {
  let router =
    fist.new()
    |> fist.get("/static/js/bundle.js", fn(_, _, _) { "bundle" })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/static/css/../js/bundle.js")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("bundle")
}

/// Upward Traversal Capped at Root:
/// Traversals attempting to climb above root (/..) are clamped at the root level per RFC 3986.
pub fn upward_traversal_above_root_test() {
  let router =
    fist.new()
    |> fist.get("/dashboard", fn(_, _, _) { "dashboard" })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/../../../../dashboard")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("dashboard")
}

/// Percent-Encoded Dot Traversal Defense:
/// Encoded dots (%2e / %2E) are decoded and resolved before route matching.
pub fn percent_encoded_traversal_test() {
  let router =
    fist.new()
    |> fist.get("/api/v1/status", fn(_, _, _) { "ok" })

  let req1 =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/api/%2e/v1/status")

  let req2 =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/api/v2/%2e%2e/v1/status")

  fist.handle(router, req1, Nil, fn() { "404" })
  |> should.equal("ok")
  fist.handle(router, req2, Nil, fn() { "404" })
  |> should.equal("ok")
}

/// Windows Backslash Normalization:
/// Backslashes are normalized to forward slashes to prevent OS-specific path bypasses.
pub fn windows_backslash_traversal_test() {
  let router =
    fist.new()
    |> fist.get("/assets/images/logo.png", fn(_, _, _) { "logo" })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/assets\\css\\..\\images\\logo.png")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("logo")
}

/// Wildcard Path Traversal Neutralization:
/// Internal dot traversals within wildcard requests resolve before parameter capture.
pub fn wildcard_path_traversal_neutralization_test() {
  let router =
    fist.new()
    |> fist.get("/download/*filepath", fn(_, _, params) {
      let fp = dict.get(params, "filepath") |> should.be_ok
      "file:" <> fp
    })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/download/docs/old/../../media/sample.mp4")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("file:media/sample.mp4")
}

/// Wildcard Root Escape Prevention:
/// Traversal payloads escaping the router base namespace fail to match the wildcard handler (404).
pub fn wildcard_root_escape_prevention_test() {
  let router =
    fist.new()
    |> fist.get("/download/*filepath", fn(_, _, params) {
      let fp = dict.get(params, "filepath") |> should.be_ok
      "file:" <> fp
    })

  // /download/../../etc/passwd collapses to /etc/passwd and does not match /download/*filepath
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/download/../../etc/passwd")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("404")
}

/// Hidden Dotfiles Preservation:
/// Filenames with leading dots (e.g. .env, .gitignore) are treated as literal tokens, not dot segments.
pub fn hidden_dotfiles_preservation_test() {
  let router =
    fist.new()
    |> fist.get("/config/:filename", fn(_, _, params) {
      let f = dict.get(params, "filename") |> should.be_ok
      "config:" <> f
    })

  let req_env =
    request.new() |> request.set_method(Get) |> request.set_path("/config/.env")
  let req_git =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/config/.gitignore")

  fist.handle(router, req_env, Nil, fn() { "404" })
  |> should.equal("config:.env")
  fist.handle(router, req_git, Nil, fn() { "404" })
  |> should.equal("config:.gitignore")
}

/// Null Byte Sanitization:
/// Injected null bytes (%00) are stripped to prevent string termination exploits in backend systems.
pub fn null_byte_injection_sanitization_test() {
  let router =
    fist.new()
    |> fist.get("/user/:username", fn(_, _, params) {
      let name = dict.get(params, "username") |> should.be_ok
      "user:" <> name
    })

  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/user/admin%00bypass")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("user:adminbypass")
}
