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

## 4. Route Guards & Dynamic Fallthrough (`fist.guard`)

Route guards attach functional validation predicates (`fn(String) -> Bool`) directly to dynamic path parameters in the Radix Trie.

### Guarding Parameters
When an incoming request matches a dynamic segment, the guard predicate evaluates. If it returns `True`, routing continues down that branch. If `False`, the router seamlessly falls through to subsequent candidate branches.

```gleam
import fist
import fist/extract

let router =
  fist.new()
  // Matches numeric IDs only (e.g. /users/42)
  |> fist.get("/users/:id", to: show_user_by_id)
  |> fist.guard("id", when: extract.is_int)
  // Matches all other string usernames (e.g. /users/john_doe)
  |> fist.get("/users/:username", to: show_user_by_username)
```

### Precedence & Fallthrough
In the example above:
1. A request to `/users/42` evaluates `extract.is_int("42")` → `True`. Dispatched to `show_user_by_id`.
2. A request to `/users/john_doe` evaluates `extract.is_int("john_doe")` → `False`. Fist automatically falls through to the sibling `:username` branch and dispatches to `show_user_by_username`.

### Combining Multiple Guards
Multiple `fist.guard` calls on the same parameter chain with short-circuiting logical `AND`:

```gleam
router
|> fist.get("/tokens/:token", to: handle_token)
|> fist.guard("token", when: extract.is_alphanumeric)
|> fist.guard("token", when: fn(s) { string.length(s) == 32 })
```

---

## 5. Wildcard Catch-All (`*param`)

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

## 6. Router Merging (`fist.merge`)

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

## 7. Route Groups & Middlewares

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

## 8. Named Routes & Reverse Routing (`fist.name`, `fist.path`)

Assign semantic names to your routes to generate canonical URLs throughout your application:

```gleam
let router =
  fist.new()
  |> fist.get("/users/:id/profile", to: show_profile)
  |> fist.guard("id", when: extract.is_int)
  |> fist.name("user_profile")
```

### Generating URLs with `fist.path`
```gleam
// 1. Valid parameter generates URL
fist.path(router, for: "user_profile", with: [#("id", "42")])
// -> Ok("/users/42/profile")

// 2. Extra parameters are automatically appended as query string
fist.path(router, for: "user_profile", with: [
  #("id", "42"),
  #("tab", "activity"),
  #("sort", "desc"),
])
// -> Ok("/users/42/profile?tab=activity&sort=desc")
```

### Bidirectional Guard Enforcement
If a parameter fails the route's guard predicate, `fist.path` refuses to generate an invalid URL:

```gleam
fist.path(router, for: "user_profile", with: [#("id", "not-a-number")])
// -> Error(fist.InvalidParameter(route: "user_profile", param: "id", value: "not-a-number"))
```

### Error Handling
`fist.path` returns a `Result(String, fist.PathError)`:
*   `Error(RouteNotFound(name))`: Route name is not registered.
*   `Error(MissingParameter(route, missing))`: A required path parameter was omitted.
*   `Error(InvalidParameter(route, param, value))`: The value is empty or failed its guard predicate.

---

## 9. Decoupled Context Pattern (`PathRegistry`)

To allow route handlers to generate paths without introducing circular type dependencies (e.g. `Router` stored inside `AppContext` which is required by `Router`), Fist provides the opaque type **`PathRegistry`**.

### Full Application Example

```gleam
import fist.{type PathRegistry}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}

// 1. Context stores only the lightweight PathRegistry
pub type AppContext {
  AppContext(registry: PathRegistry)
}

// 2. Handlers generate URLs via fist.path_from
fn handle_redirect(_req: Request(String), ctx: AppContext, _params) -> Response(String) {
  case fist.path_from(ctx.registry, for: "user_profile", with: [#("id", "99")]) {
    Ok(url) ->
      response.new(302)
      |> response.set_header("location", url)
      |> response.set_body("")
    Error(_) ->
      response.new(500) |> response.set_body("Routing error")
  }
}

// 3. Build router and extract registry from the completed root router
pub fn app() {
  let router =
    fist.new()
    |> fist.get("/users/:id", to: fn(_, _, _) { response.new(200) |> response.set_body("Profile") })
    |> fist.name("user_profile")
    |> fist.get("/jump", to: handle_redirect)

  let registry = fist.path_registry(router)
  let ctx = AppContext(registry: registry)

  #(router, ctx)
}
```

> [!IMPORTANT]
> Always extract `fist.path_registry` from your **final root router** after all `mount`, `merge`, and `group` operations are complete to ensure all mount prefixes are captured.

---

## 10. Inspecting Named Routes

You can inspect registered route templates for debugging, sitemaps, or admin dashboards:

```gleam
let registry = fist.path_registry(router)

// Check if a route name exists
fist.has_path(registry, "user_profile") // -> True

// List all registered route names
fist.path_names(registry) // -> ["user_profile", "jump"]

// Inspect canonical template pattern
fist.path_template(registry, "user_profile") // -> Ok("/users/:id")
```

---

## 11. Metadata & Documentation (`describe`, `inspect`)

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

## 12. Execution & HTTP Status Handling

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

---

## 13. Typed Parameter Extractors (`fist/extract`)

The `fist/extract` module provides pure, ergonomic helpers to extract and parse path and query parameters into concrete Gleam types, avoiding boilerplate string parsing inside your route handlers.

### Built-in Parsers
- `extract.int(params, "id")`: Parses integer (`Int`).
- `extract.float(params, "price")`: Parses floating-point number (`Float`).
- `extract.bool(params, "active")`: Parses boolean (`"true"`, `"1"`, `"yes"` vs `"false"`, `"0"`, `"no"`).
- `extract.string(params, "slug")`: Validates key presence.
- `extract.non_empty_string(params, "name")`: Rejects empty strings and whitespace.
- `extract.uuid(params, "id")`: Validates and normalizes RFC 4122 UUIDs (`8-4-4-4-12` hex).
- `extract.custom(params, "role", "UserRole", parse_fn)`: Custom domain parsers.

### Ergonomic `use` Syntax

Use the `require_*` family of functions with Gleam's `use` expression to easily validate parameters and short-circuit on error:

```gleam
import fist
import fist/extract
import gleam/http/response.{type Response}
import gleam/int

fn get_product(_req, _ctx, params) -> Response(String) {
  use product_id <- extract.require_int(params, "id", or: fn(err) {
    response.new(400) |> response.set_body(extract.error_to_string(err))
  })
  use is_active <- extract.require_bool(params, "active", or: fn(err) {
    response.new(400) |> response.set_body(extract.error_to_string(err))
  })

  // product_id is an Int, is_active is a Bool
  response.new(200)
  |> response.set_body("Product " <> int.to_string(product_id))
}
```

### Query String Parameters

You can also extract query parameters directly from any `Request`:

```gleam
let query = extract.query_params(req)
let page = extract.int_or(query, "page", default: 1)
let search = extract.string_or(query, "q", default: "")
```
