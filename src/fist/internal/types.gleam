import gleam/dict.{type Dict}
import gleam/http.{type Method}
import gleam/http/request.{type Request}
import gleam/option.{type Option, None}

/// Encapsulates the handler logic and its metadata.
pub type Route(req_body, ctx, output) {
  Route(
    handler: fn(Request(req_body), ctx, Dict(String, String)) -> output,
    description: Option(String),
  )
}

/// A node in the router's internal Trie structure.
pub type Node(req_body, ctx, output) {
  Node(
    /// If this node represents the end of a valid path, it will have a Route object.
    route: Option(Route(req_body, ctx, output)),
    /// Static children are exact string matches (e.g., "users", "settings").
    static_children: Dict(String, Node(req_body, ctx, output)),
    /// A dynamic child is a wildcard parameter (e.g., ":id", ":slug").
    dynamic_child: Option(#(String, Node(req_body, ctx, output))),
  )
}

/// The internal representation of a Router.
pub type Router(req_body, ctx, output) {
  Router(
    routes: Dict(Method, Node(req_body, ctx, output)),
    last_added: Option(#(Method, List(String))),
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
  Node(route: None, static_children: dict.new(), dynamic_child: None)
}

/// Helper to create an empty Router.
pub fn new_router() -> Router(req_body, ctx, output) {
  Router(routes: dict.new(), last_added: None)
}
