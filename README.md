# Fist 👊

A declarative, type-safe, tree-based HTTP router for Gleam.

`fist` is a pure router library that operates directly on standard `gleam/http` types, completely decoupled from any specific web server (Mist, Wisp, Elli, etc.). It compiles with 100% parity to both the **BEAM (Erlang)** and **JavaScript** (Node.js, Deno, Bun, browser) targets with zero native runtime dependencies.

---

## Features

- **Declarative & Chainable API**: `fist.get("/", to: handler)`
- **Full HTTP Method Support**: `get`, `post`, `put`, `delete`, `patch`, `head`, `options`, and custom methods via `route`
- **Trie-Based Routing (Radix Tree)**: $O(k)$ path lookups with strict 4-tier precedence (`Static > Guarded Dynamic > Unguarded Dynamic > Wildcard`) and deep automatic backtracking
- **Route Guards & Dynamic Fallthrough**: Validate path parameters at the Trie level with `fist.guard(when: ...)` and fall through seamlessly to sibling branches
- **Named Routes & Reverse Routing**: Attach identifiers with `fist.name` and generate canonical URLs with `fist.path` and `fist.path_from`
- **Bidirectional Soundness**: Reverse routing validates route guards during URL generation, preventing broken redirects and invalid links
- **Decoupled `PathRegistry`**: Store route templates in application context without circular type dependencies
- **Query Parameter Auto-Serialization**: Unconsumed parameters in `fist.path` are automatically encoded and appended as URL query strings
- **Wildcard Catch-Alls**: Capture arbitrary sub-paths (`*param` or `/*`) with relative path extraction
- **Monoidal Router Merging**: Recursively combine disjoint routers with `fist.merge`
- **Fail-Fast Collision Safety**: Immediate runtime panics on route duplications, conflicting dynamic parameter names, or conflicting wildcards
- **Defensive Path Security (RFC 3986)**: Standardized Section 5.2.4 `remove_dot_segments` canonicalization against directory traversal (`.` and `..`), null-byte stripping, and Windows backslash normalization
- **Dynamic Parameters**: Extract URL variables (`:id`) with automatic percent-decoding (`/user/João` -> `"João"`)
- **Route Groups & Prefixes**: Cleanly group endpoints with `fist.group`
- **Composable Middlewares**: Zero-overhead static wrapping via `fist.wrap` executed in natural declaration order
- **Context Polymorphism**: Combine modular sub-routers with different context types using `mount` and `map_context`
- **Output Transformation**: Return custom Algebraic Data Types (ADTs) and transform them globally with `fist.map`
- **Route Introspection & Metadata**: Attach descriptions with `describe` and inspect the route tree with `inspect`
- **HTTP 405 & CORS Preflight**: Inspect supported methods for any path using `fist.allowed_methods`

---

## Installation

```sh
gleam add fist
```

---

## Quick Example

```gleam
import fist.{type PathRegistry}
import fist/extract
import gleam/dict
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/result

// 1. Define application context containing the PathRegistry
pub type AppContext {
  AppContext(api_version: String, registry: PathRegistry)
}

// 2. Define route handlers
fn show_user_by_id(_req: Request(String), _ctx: AppContext, params: dict.Dict(String, String)) {
  let user_id = dict.get(params, "id") |> result.unwrap("")
  response.new(200) |> response.set_body("Numeric user ID: " <> user_id)
}

fn show_user_by_slug(_req: Request(String), _ctx: AppContext, params: dict.Dict(String, String)) {
  let slug = dict.get(params, "username") |> result.unwrap("")
  response.new(200) |> response.set_body("Username: " <> slug)
}

fn redirect_to_user(_req: Request(String), ctx: AppContext, _params) {
  let assert Ok(url) =
    fist.path_from(ctx.registry, for: "user_by_id", with: [#("id", "42")])

  response.new(302)
  |> response.set_header("location", url)
  |> response.set_body("")
}

// 3. Build the router with guards and named routes
pub fn build_app() {
  let router =
    fist.new()
    |> fist.get("/", to: fn(_, _, _) { response.new(200) |> response.set_body("Welcome!") })
    // Matches /users/42 (numeric ID)
    |> fist.get("/users/:id", to: show_user_by_id)
    |> fist.guard("id", when: extract.is_int)
    |> fist.name("user_by_id")
    // Falls through to match /users/alice (string username)
    |> fist.get("/users/:username", to: show_user_by_slug)
    |> fist.name("user_by_slug")
    |> fist.get("/jump", to: redirect_to_user)

  // Extract PathRegistry from completed root router
  let registry = fist.path_registry(router)
  let ctx = AppContext(api_version: "v1", registry: registry)

  #(router, ctx)
}

// 4. Dispatch requests
pub fn handle_request(req: Request(String)) -> Response(String) {
  let #(router, ctx) = build_app()
  fist.handle(router, req, ctx, not_found: fn() {
    response.new(404) |> response.set_body("Route Not Found")
  })
}
```

---

## Documentation

Full documentation and API reference are published on [HexDocs](https://hexdocs.pm/fist/):
- **[User Guide](https://hexdocs.pm/fist/guide.html)**: Route definitions, guards, named routes, reverse routing, groups, middlewares, and inspection.
- **[Core Concepts & Behavior](https://hexdocs.pm/fist/behavior.html)**: Radix Trie structure, 4-tier precedence, RFC 3986 normalization, bidirectional soundness, and fail-fast invariants.
- **[Advanced Patterns](https://hexdocs.pm/fist/advanced.html)**: Context polymorphism, avoiding circular types with `PathRegistry`, multi-tier mounts, and ADT mapping.
- **[Roadmap](https://hexdocs.pm/fist/roadmap.html)**: Upcoming features and architectural exploration.

*(Repository markdown sources are available in the [`docs/`](https://codeberg.org/MrTomate/fist/src/branch/master/docs) directory).*
