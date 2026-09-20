import fist/internal/inspect
import fist/internal/trie
import fist/internal/types
import gleam/dict.{type Dict}
import gleam/http.{type Method, Delete, Get, Head, Options, Patch, Post, Put}
import gleam/http/request.{type Request}

// --- TYPES ---

/// Represents the router instance.
/// Holds the Radix Trie structure for efficient route matching.
pub opaque type Router(req_body, ctx, output) {
  Router(inner: types.Router(req_body, ctx, output))
}

/// Metadata about a registered route, introspectable via `fist.inspect`.
pub type RouteInfo =
  types.RouteInfo

// --- CONSTRUCTORS ---

/// Creates a new, empty router.
pub fn new() -> Router(req_body, ctx, output) {
  Router(types.new_router())
}

// --- ROUTING ---

/// Adds a route for an arbitrary HTTP method and path to the router.
pub fn route(
  router: Router(req_body, ctx, output),
  method method: Method,
  path path: String,
  handler handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  Router(trie.route(router.inner, method, path, handler))
}

/// Attaches a human-readable description to the last added route.
pub fn describe(
  router: Router(req_body, ctx, output),
  description: String,
) -> Router(req_body, ctx, output) {
  Router(trie.describe(router.inner, description))
}

/// Attaches a functional predicate (guard) to a dynamic parameter in the last added route.
///
/// When an incoming request matches this path segment, `predicate` is evaluated.
/// If `predicate` returns `True`, routing continues down this branch.
/// If `predicate` returns `False`, the router seamlessly falls through to subsequent
/// sibling branches (e.g. matching numeric `:id` before generic `:username`) before returning 404.
///
/// Panics if called without an immediately preceding route or if `param` is not in the route.
pub fn guard(
  router: Router(req_body, ctx, output),
  param param: String,
  when predicate: fn(String) -> Bool,
) -> Router(req_body, ctx, output) {
  Router(trie.guard(router.inner, param, predicate))
}

/// Adds a GET route to the router.
pub fn get(
  router: Router(req_body, ctx, output),
  path path: String,
  to handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  route(router, method: Get, path: path, handler: handler)
}

/// Adds a POST route to the router.
pub fn post(
  router: Router(req_body, ctx, output),
  path path: String,
  to handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  route(router, method: Post, path: path, handler: handler)
}

/// Adds a PUT route to the router.
pub fn put(
  router: Router(req_body, ctx, output),
  path path: String,
  to handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  route(router, method: Put, path: path, handler: handler)
}

/// Adds a DELETE route to the router.
pub fn delete(
  router: Router(req_body, ctx, output),
  path path: String,
  to handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  route(router, method: Delete, path: path, handler: handler)
}

/// Adds a PATCH route to the router.
pub fn patch(
  router: Router(req_body, ctx, output),
  path path: String,
  to handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  route(router, method: Patch, path: path, handler: handler)
}

/// Adds a HEAD route to the router.
pub fn head(
  router: Router(req_body, ctx, output),
  path path: String,
  to handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  route(router, method: Head, path: path, handler: handler)
}

/// Adds an OPTIONS route to the router.
pub fn options(
  router: Router(req_body, ctx, output),
  path path: String,
  to handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
) -> Router(req_body, ctx, output) {
  route(router, method: Options, path: path, handler: handler)
}

// --- TRANSFORMATION ---

/// Transforms the context of the router using a mapping function.
/// This is the foundation for context polymorphism, allowing a sub-router
/// that expects a specific context to be used within a parent router with a different context.
pub fn map_context(
  router: Router(req_body, ctx_b, output),
  with mapper: fn(ctx_a) -> ctx_b,
) -> Router(req_body, ctx_a, output) {
  Router(trie.map_context(router.inner, mapper))
}

/// Transforms the output of the router using a mapping function.
pub fn map(
  router: Router(req_body, ctx, a),
  with fun: fn(a) -> b,
) -> Router(req_body, ctx, b) {
  Router(trie.map(router.inner, fun))
}

// --- COMPOSITION ---

/// Mounts a sub-router at a specific prefix, transforming its context to match the parent.
/// This enables modular routing and context polymorphism.
pub fn mount(
  parent: Router(req, ctx_a, out),
  at prefix: String,
  sub sub_router: Router(req, ctx_b, out),
  transform mapper: fn(ctx_a) -> ctx_b,
) -> Router(req, ctx_a, out) {
  Router(trie.mount(parent.inner, prefix, sub_router.inner, mapper))
}

/// Merges two routers with identical context and output types into a single combined router.
/// Route trees are merged recursively. Collisions in routes or dynamic parameter names
/// cause an immediate fail-fast panic.
pub fn merge(
  a: Router(req, ctx, out),
  b: Router(req, ctx, out),
) -> Router(req, ctx, out) {
  Router(trie.merge(a.inner, b.inner))
}

/// Wraps all handlers in the router with the given middleware.
/// A middleware is a function that takes a handler and returns a new, wrapped handler.
pub fn wrap(
  router: Router(req, ctx, out),
  with middleware: fn(fn(Request(req), ctx, Dict(String, String)) -> out) ->
    fn(Request(req), ctx, Dict(String, String)) -> out,
) -> Router(req, ctx, out) {
  Router(trie.wrap(router.inner, middleware))
}

/// Groups a set of routes under a common prefix and applies middlewares.
/// Middlewares are applied in declaration order: the first middleware in the list
/// executes first, wrapping subsequent middlewares and handlers.
pub fn group(
  router: Router(req, ctx, out),
  at prefix: String,
  with middlewares: List(
    fn(fn(Request(req), ctx, Dict(String, String)) -> out) ->
      fn(Request(req), ctx, Dict(String, String)) -> out,
  ),
  defining build_sub_router: fn(Router(req, ctx, out)) -> Router(req, ctx, out),
) -> Router(req, ctx, out) {
  let sub_builder = fn(inner_sub) {
    let Router(built) = build_sub_router(Router(inner_sub))
    built
  }
  Router(trie.group(router.inner, prefix, middlewares, sub_builder))
}

// --- EXECUTION ---

/// Dispatches an incoming request through the router.
/// If no route matches, the `not_found` fallback function is invoked.
pub fn handle(
  router: Router(req_body, ctx, output),
  request: Request(req_body),
  context: ctx,
  not_found: fn() -> output,
) -> output {
  trie.handle(router.inner, request, context, not_found)
}

/// Returns a list of all HTTP methods supported for the given path.
/// Useful for handling CORS preflight OPTIONS requests and 405 Method Not Allowed responses.
pub fn allowed_methods(
  router: Router(req_body, ctx, output),
  path: String,
) -> List(Method) {
  trie.allowed_methods(router.inner, path)
}

/// Returns a list of all registered routes and their metadata.
pub fn inspect(router: Router(req_body, ctx, output)) -> List(RouteInfo) {
  inspect.inspect(router.inner)
}
