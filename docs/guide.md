# User Guide

`fist` is a declarative, type-safe, tree-based HTTP router for Gleam. It is independent of any specific web server and operates directly on standard `gleam/http` types.

---

## 1. Creating a Router

```gleam
import fist
import gleam/http/response

pub fn create_router() {
  fist.new()
  |> fist.get("/", to: fn(_req, _ctx, _params) {
    response.new(200) |> response.set_body("Hello, World!")
  })
}
```

---

## 2. Route Handlers & Methods

Every handler receives three arguments:
1. `req`: The HTTP `Request(req_body)`.
2. `ctx`: A custom application context (e.g. database, config, state).
3. `params`: A `Dict(String, String)` containing extracted URL parameters.

### Supported Methods
`fist` provides first-class helpers for standard HTTP methods:
- `fist.get(router, path, to: handler)`
- `fist.post(router, path, to: handler)`
- `fist.put(router, path, to: handler)`
- `fist.delete(router, path, to: handler)`
- `fist.patch(router, path, to: handler)`
- `fist.head(router, path, to: handler)`
- `fist.options(router, path, to: handler)`
- `fist.route(router, method: http.Other("..."), path, handler)` (Custom methods)

---

## 3. Dynamic Parameters

Prefix a segment with `:` to capture its value. Percent-encoded values are automatically decoded (e.g., `João` from `Jo%C3%A3o`).

```gleam
import fist
import gleam/dict
import gleam/http/response
import gleam/result

fn show_user(_req, _ctx, params) {
  let id = dict.get(params, "id") |> result.unwrap("unknown")
  response.new(200) |> response.set_body("User: " <> id)
}

let router =
  fist.new()
  |> fist.get("/users/:id", to: show_user)
  |> fist.get("/users/:id/posts/:post_id", to: show_post)
```

---

## 4. Route Groups & Middlewares

### Groups
Organize related routes under a common path prefix and apply shared middlewares:

```gleam
let router =
  fist.new()
  |> fist.group(at: "/api/v1", with: [auth_middleware], defining: fn(v1) {
    v1
    |> fist.get("/users", to: list_users)
    |> fist.post("/users", to: create_user)
  })
```

### Middlewares (`wrap`)
Middlewares are wrapper functions `(Handler) -> Handler`. They are applied at definition time (*Static Wrapping*), introducing zero Trie lookup overhead at runtime.

Middlewares execute in the exact order declared in the list (outer to inner):

```gleam
fn log_middleware(next) {
  fn(req, ctx, params) {
    // Before handler logic
    let res = next(req, ctx, params)
    // After handler logic
    res
  }
}

let router =
  fist.new()
  |> fist.get("/public", to: public_handler)
  |> fist.wrap(log_middleware)
```

---

## 5. Metadata & Documentation (`describe`, `inspect`)

You can document endpoints immediately after registering them:

```gleam
let router =
  fist.new()
  |> fist.get("/users", to: list_users)
  |> fist.describe("List all active users")
  |> fist.post("/users", to: create_user)
  |> fist.describe("Create a new user")

// Extract all routes and metadata programmatically:
let routes = fist.inspect(router)
```

---

## 6. Execution (`handle`, `allowed_methods`)

Dispatch requests using `fist.handle`:

```gleam
let response =
  fist.handle(
    router,
    request: req,
    context: ctx,
    not_found: fn() {
      response.new(404) |> response.set_body("Not Found")
    },
  )
```

To support CORS preflight (`OPTIONS`) or **405 Method Not Allowed**:

```gleam
case fist.allowed_methods(router, req.path) {
  [] -> not_found_handler()
  methods -> method_not_allowed_handler(methods)
}
```
