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

## 3. Dynamic Parameters (`:param`)

Prefix a segment with `:` to capture a single segment. Percent-encoded values are automatically decoded (e.g., `João` from `Jo%C3%A3o`).

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

## 4. Wildcard Catch-All (`*param`)

Prefix the terminal segment with `*` to capture all remaining path segments.
The captured value is formatted without a leading slash, preserving internal slashes and percent-decoding individual tokens.

```gleam
let router =
  fist.new()
  |> fist.get("/static/*filepath", to: fn(_req, _ctx, params) {
    let filepath = dict.get(params, "filepath") |> result.unwrap("")
    // Request to /static/css/theme/dark.css yields "css/theme/dark.css"
    response.new(200) |> response.set_body("Serving: " <> filepath)
  })
```

- **Minimum Segment Rule**: A wildcard requires at least one segment to match. For `/static/*filepath`, a request to `/static` returns 404 unless an explicit `/static` route is registered.
- **Terminal Position**: Wildcards must be the final segment of a path. Registering `/files/*path/download` causes an immediate fail-fast `panic`.
- **Catch-All Default Name**: Using `/*` defaults the parameter name to `"wildcard"`.

---

## 5. Router Merging (`fist.merge`)

You can combine two independent routers with identical context and output types using `fist.merge`:

```gleam
let user_router =
  fist.new()
  |> fist.get("/users", to: list_users)
  |> fist.post("/users", to: create_user)

let product_router =
  fist.new()
  |> fist.get("/products", to: list_products)

let app_router = fist.merge(user_router, product_router)
```

If two merged routers contain conflicting endpoints or conflicting dynamic parameter names at the same level, `fist.merge` panics immediately (fail-fast).

---

## 6. Route Groups & Middlewares

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

Middlewares execute in declaration order (the first in the list executes outermost):

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

## 7. Metadata & Documentation (`describe`, `inspect`)

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

## 8. Execution & HTTP Status Handling

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

### Handling 405 Method Not Allowed & CORS Preflight

Use `fist.allowed_methods(router, path)` to inspect registered methods for a given route:

```gleam
import fist
import gleam/http.{Get, Options, Post}
import gleam/http/response
import gleam/list
import gleam/string

pub fn dispatch(router, req, ctx) {
  case req.method {
    // 1. Automatic CORS Preflight
    Options -> {
      case fist.allowed_methods(router, req.path) {
        [] -> response.new(404) |> response.set_body("Not Found")
        methods -> {
          let allow =
            list.map(methods, string.inspect)
            |> string.join(", ")

          response.new(204)
          |> response.set_header("access-control-allow-methods", allow)
          |> response.set_header("access-control-allow-origin", "*")
          |> response.set_body("")
        }
      }
    }

    // 2. Standard Request Routing
    _ -> {
      fist.handle(router, req, ctx, not_found: fn() {
        case fist.allowed_methods(router, req.path) {
          [_, ..] as methods -> {
            let allow =
              list.map(methods, string.inspect)
              |> string.join(", ")

            response.new(405)
            |> response.set_header("allow", allow)
            |> response.set_body("Method Not Allowed")
          }
          [] -> response.new(404) |> response.set_body("Not Found")
        }
      })
    }
  }
}
```
