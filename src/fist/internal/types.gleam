import gleam/dict.{type Dict}
import gleam/http.{type Method}
import gleam/http/request.{type Request}
import gleam/option.{type Option, None}

/// A handler function that processes a request and produces an output.
pub type Handler(req_body, ctx, output) =
  fn(Request(req_body), ctx, Dict(String, String)) -> output

/// A route registered in the Trie, storing the handler and optional metadata description.
pub type Route(req_body, ctx, output) {
  Route(handler: Handler(req_body, ctx, output), description: Option(String))
}

/// A single dynamic branch in the Radix Trie.
/// Dynamic branches can optionally be guarded with a pure predicate function `guard`.
/// Guarded branches take precedence over unguarded dynamic branches during matching.
pub type DynamicBranch(req_body, ctx, output) {
  DynamicBranch(
    param_name: String,
    guard: Option(fn(String) -> Bool),
    child: Node(req_body, ctx, output),
  )
}

/// A node in the router's internal Trie structure.
pub type Node(req_body, ctx, output) {
  Node(
    /// If this node represents the end of a valid path, it will have a Route object.
    route: Option(Route(req_body, ctx, output)),
    /// Static children are exact string matches (e.g., "users", "settings").
    static_children: Dict(String, Node(req_body, ctx, output)),
    /// Dynamic children are single-segment wildcard branches, evaluated in priority order.
    dynamic_children: List(DynamicBranch(req_body, ctx, output)),
    /// A wildcard child is a multi-segment catch-all parameter (e.g., "*filepath", "*rest").
    wildcard_child: Option(#(String, Route(req_body, ctx, output))),
  )
}

/// A single segment in a reverse-routable route template.
pub type TemplateSegment {
  StaticSegment(value: String)
  DynamicSegment(name: String, guard: Option(fn(String) -> Bool))
  WildcardSegment(name: String)
}

/// A reverse-routable route template.
pub type RouteTemplate {
  RouteTemplate(name: String, method: Method, segments: List(TemplateSegment))
}

/// A lightweight, self-contained registry of named route templates.
/// Safe to store in application context without circular type dependencies.
pub opaque type PathRegistry {
  PathRegistry(routes: Dict(String, RouteTemplate))
}

/// Constructor to unwrap or create a PathRegistry.
pub fn new_path_registry(routes: Dict(String, RouteTemplate)) -> PathRegistry {
  PathRegistry(routes)
}

/// Accessor for the underlying templates dictionary.
pub fn path_registry_routes(
  registry: PathRegistry,
) -> Dict(String, RouteTemplate) {
  registry.routes
}

/// The internal representation of a Router.
pub type Router(req_body, ctx, output) {
  Router(
    routes: Dict(Method, Node(req_body, ctx, output)),
    last_added: Option(#(Method, List(String))),
    named_routes: Dict(String, RouteTemplate),
  )
}

/// Information about a registered route, used for introspection/documentation.
pub type RouteInfo {
  RouteInfo(
    method: Method,
    path: String,
    description: String,
    params: List(String),
  )
}

/// Helper to create an empty Trie node.
pub fn empty_node() -> Node(req_body, ctx, output) {
  Node(
    route: None,
    static_children: dict.new(),
    dynamic_children: [],
    wildcard_child: None,
  )
}

/// Helper to create a new, empty Router.
pub fn new_router() -> Router(req_body, ctx, output) {
  Router(routes: dict.new(), last_added: None, named_routes: dict.new())
}
