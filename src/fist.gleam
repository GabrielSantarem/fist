import fist/internal/inspect
import fist/internal/reverse
import fist/internal/trie
import fist/internal/types.{
  DynamicSegment, StaticSegment, WildcardSegment, path_registry_routes,
}
import gleam/dict.{type Dict}
import gleam/http.{type Method, Delete, Get, Head, Options, Patch, Post, Put}
import gleam/http/request.{type Request}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/uri

// --- TYPES ---\n
/// Represents the router instance.
/// Holds the Radix Trie structure for efficient route matching.
pub opaque type Router(req_body, ctx, output) {
  Router(inner: types.Router(req_body, ctx, output))
}

/// Metadata about a registered route, introspectable via `fist.inspect`.
pub type RouteInfo =
  types.RouteInfo

/// Errors encountered during reverse path generation via `fist.path` or `fist.path_from`.
pub type PathError {
  /// The route name is not registered in the router.
  RouteNotFound(name: String)
  /// A required dynamic or wildcard parameter was not provided in the parameters list.
  MissingParameter(route: String, missing: String)
  /// A parameter was provided, but its value failed the route guard predicate.
  InvalidParameter(route: String, param: String, value: String)
}

/// A lightweight, self-contained registry of named route templates.
/// Safe to store in application context without circular type dependencies.
pub type PathRegistry =
  types.PathRegistry

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

/// Assigns a unique identifier name to the last added route for reverse routing.
///
/// Panics if called without an immediately preceding route definition, if `name` is empty,
/// or if `name` collides with an existing registered route name.
pub fn name(
  router: Router(req_body, ctx, output),
  name name: String,
) -> Router(req_body, ctx, output) {
  Router(trie.name(router.inner, name))
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

// --- COMPOSITION ---

/// Transforms the context required by the router handlers from `ctx_b` to `ctx_a`.
pub fn map_context(
  router: Router(req_body, ctx_b, output),
  mapper: fn(ctx_a) -> ctx_b,
) -> Router(req_body, ctx_a, output) {
  Router(trie.map_context(router.inner, mapper))
}

/// Transforms the output value of all route handlers using a mapping function.
pub fn map(
  router: Router(req_body, ctx, a),
  fun: fn(a) -> b,
) -> Router(req_body, ctx, b) {
  Router(trie.map(router.inner, fun))
}

/// Mounts a sub-router under a specified URL prefix, mapping parent context to child context.
pub fn mount(
  parent: Router(req, ctx_a, out),
  at prefix: String,
  sub sub_router: Router(req, ctx_b, out),
  transform mapper: fn(ctx_a) -> ctx_b,
) -> Router(req, ctx_a, out) {
  Router(trie.mount(parent.inner, prefix, sub_router.inner, mapper))
}

/// Combines two routers into a single unified router.
pub fn merge(
  a: Router(req, ctx, out),
  b: Router(req, ctx, out),
) -> Router(req, ctx, out) {
  Router(trie.merge(a.inner, b.inner))
}

/// Wraps all route handlers in the router with a middleware function.
pub fn wrap(
  router: Router(req, ctx, out),
  middleware: fn(fn(Request(req), ctx, Dict(String, String)) -> out) ->
    fn(Request(req), ctx, Dict(String, String)) -> out,
) -> Router(req, ctx, out) {
  Router(trie.wrap(router.inner, middleware))
}

/// Creates an isolated route group with a prefix and group-specific middlewares.
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

// --- REVERSE ROUTING ---

/// Generates a canonical URL path from a `Router` given a route name and parameter list.
///
/// Returns `Error(RouteNotFound(name))` if the route was not registered with `fist.name`.
/// Returns `Error(MissingParameter(route, missing))` if a required path segment parameter is omitted.
/// Returns `Error(InvalidParameter(route, param, value))` if a parameter fails its route guard predicate.
/// Unused parameters in `with` are automatically formatted and appended as URL query parameters.
pub fn path(
  router: Router(req_body, ctx, output),
  for name: String,
  with params: List(#(String, String)),
) -> Result(String, PathError) {
  path_from(path_registry(router), for: name, with: params)
}

/// Extracts a lightweight, self-contained `PathRegistry` from a `Router`.
///
/// The registry contains all named route templates and their guards, but has no generic
/// dependencies on request body, context, or output types. It can be safely stored in the
/// application context (e.g. `AppContext`) to allow handlers to generate reverse paths.
pub fn path_registry(router: Router(req_body, ctx, output)) -> PathRegistry {
  types.new_path_registry(router.inner.named_routes)
}

/// Generates a canonical URL path from a `PathRegistry` given a route name and parameter list.
pub fn path_from(
  registry: PathRegistry,
  for name: String,
  with params: List(#(String, String)),
) -> Result(String, PathError) {
  case dict.get(path_registry_routes(registry), name) {
    Error(Nil) -> Error(RouteNotFound(name))
    Ok(template) -> {
      do_render_path(template.segments, params, name, [], [])
    }
  }
}

/// Checks if a route name is registered in the PathRegistry.
pub fn has_path(registry: PathRegistry, name: String) -> Bool {
  dict.has_key(path_registry_routes(registry), name)
}

/// Returns a list of all registered route names in the PathRegistry.
pub fn path_names(registry: PathRegistry) -> List(String) {
  dict.keys(path_registry_routes(registry))
}

/// Returns the canonical path template string for a registered route name (e.g. "/users/:id").
pub fn path_template(
  registry: PathRegistry,
  name: String,
) -> Result(String, Nil) {
  case dict.get(path_registry_routes(registry), name) {
    Ok(template) -> Ok(reverse.segments_to_string(template.segments))
    Error(Nil) -> Error(Nil)
  }
}

fn do_render_path(
  remaining_segments: List(types.TemplateSegment),
  all_params: List(#(String, String)),
  route_name: String,
  path_acc: List(String),
  used_param_names: List(String),
) -> Result(String, PathError) {
  case remaining_segments {
    [] -> {
      let base_path = case path_acc {
        [] -> "/"
        _ -> "/" <> string.join(list.reverse(path_acc), "/")
      }

      let unused_params =
        list.filter(all_params, fn(pair) {
          let #(key, _) = pair
          !list.contains(used_param_names, key)
        })

      case unused_params {
        [] -> Ok(base_path)
        _ -> {
          let query_string = uri.query_to_string(unused_params)
          case base_path == "/" {
            True -> Ok("/?" <> query_string)
            False -> Ok(base_path <> "?" <> query_string)
          }
        }
      }
    }

    [StaticSegment(seg), ..rest] -> {
      do_render_path(
        rest,
        all_params,
        route_name,
        [seg, ..path_acc],
        used_param_names,
      )
    }

    [DynamicSegment(param_name, guard_opt), ..rest] -> {
      case list.key_find(all_params, param_name) {
        Error(Nil) ->
          Error(MissingParameter(route: route_name, missing: param_name))
        Ok(val) -> {
          case val == "" {
            True ->
              Error(InvalidParameter(
                route: route_name,
                param: param_name,
                value: "",
              ))
            False -> {
              case guard_opt {
                Some(predicate) -> {
                  case predicate(val) {
                    True -> {
                      let encoded = uri.percent_encode(val)
                      do_render_path(
                        rest,
                        all_params,
                        route_name,
                        [encoded, ..path_acc],
                        [param_name, ..used_param_names],
                      )
                    }
                    False ->
                      Error(InvalidParameter(
                        route: route_name,
                        param: param_name,
                        value: val,
                      ))
                  }
                }
                None -> {
                  let encoded = uri.percent_encode(val)
                  do_render_path(
                    rest,
                    all_params,
                    route_name,
                    [encoded, ..path_acc],
                    [param_name, ..used_param_names],
                  )
                }
              }
            }
          }
        }
      }
    }

    [WildcardSegment(param_name), ..rest] -> {
      case list.key_find(all_params, param_name) {
        Error(Nil) ->
          Error(MissingParameter(route: route_name, missing: param_name))
        Ok(val) -> {
          case val == "" {
            True ->
              Error(InvalidParameter(
                route: route_name,
                param: param_name,
                value: "",
              ))
            False -> {
              let encoded = encode_wildcard_path(val)
              do_render_path(
                rest,
                all_params,
                route_name,
                [encoded, ..path_acc],
                [param_name, ..used_param_names],
              )
            }
          }
        }
      }
    }
  }
}

fn encode_wildcard_path(val: String) -> String {
  string.split(val, "/")
  |> list.map(uri.percent_encode)
  |> string.join("/")
}
