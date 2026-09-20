# Fist 👊

A declarative, type-safe, tree-based HTTP router for Gleam.

`fist` is a pure router library that operates directly on standard `gleam/http` types, completely decoupled from any specific web server (Mist, Wisp, Elli, etc.).

---

## Features

- **Declarative & Chainable API**: `fist.get("/", to: handler)`
- **Full HTTP Method Support**: `get`, `post`, `put`, `delete`, `patch`, `head`, `options`, and custom methods via `route`
- **Trie-Based Routing (Radix Tree)**: $O(n)$ path lookups with automatic backtracking from static to dynamic routes
- **Dynamic Parameters**: Extract URL variables (`:id`) with automatic percent-decoding (`/user/Jo%C3%A3o` -> `"João"`)
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
import fist
import gleam/dict
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/result

// 1. Define custom application context
pub type AppContext {
  AppContext(api_version: String)
}

// 2. Define your handlers: fn(Request, Context, Params) -> Response
fn get_user(_req: Request(String), ctx: AppContext, params: dict.Dict(String, String)) {
  let user_id = dict.get(params, "user_id") |> result.unwrap("anonymous")

  response.new(200)
  |> response.set_header("x-api-version", ctx.api_version)
  |> response.set_body("User profile: " <> user_id)
}

// 3. Build the router
pub fn router() {
  fist.new()
  |> fist.get("/", to: fn(_, _, _) {
    response.new(200) |> response.set_body("Welcome!")
  })
  |> fist.group(at: "/api/v1", with: [], defining: fn(v1) {
    v1
    |> fist.get("/users/:user_id", to: get_user)
    |> fist.describe("Get user by ID")
  })
}

// 4. Dispatch requests
pub fn handle_request(req: Request(String), ctx: AppContext) -> Response(String) {
  fist.handle(router(), req, ctx, not_found: fn() {
    response.new(404) |> response.set_body("Route Not Found")
  })
}
```

---

## Documentation

For full documentation and core architecture details:
- **[User Guide](docs/guide.md)**: Route definitions, groups, middlewares, and inspection.
- **[Core Concepts & Behavior](docs/behavior.md)**: Trie structure, normalization, backtracking, and constraints.
- **[Advanced Patterns](docs/advanced.md)**: Context polymorphism, ADT output mapping, and modular architecture.
