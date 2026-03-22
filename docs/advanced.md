# Advanced Patterns

Fist is more than just a router; its generic nature allows for powerful architectural patterns.

## Custom Return Types

Handlers are not restricted to returning a `gleam/http/response.Response`. They can return **Algebraic Data Types (ADTs)**, which you can transform globally later. This keeps your business logic pure and testable.

### Example: Domain-Specific Return Type

```gleam
pub type AppResult {
  Html(String)
  Json(String)
  NotFound
}

// Handler returns pure data, not HTTP concepts
fn my_handler(_, _, _) {
  Json("{\"status\": \"ok\"}")
}

pub fn main() {
  let router =
    fist.new()
    |> fist.get("/api", to: my_handler)
    |> fist.map(fn(res) {
      // Global transformation layer: Convert AppResult -> Response
      case res {
        Html(body) -> response.new(200) |> response.set_body(body)
        Json(json) -> {
          response.new(200)
          |> response.set_header("content-type", "application/json")
          |> response.set_body(json)
        }
        NotFound -> response.new(404) |> response.set_body("Not Found")
      }
    })
}
```

## Functional Middleware

Fist does not yet have a dedicated API for middleware composition. However, you can achieve similar results by composing functions.

A middleware can be thought of as a function that takes a handler and returns a new handler.

### Authentication Example

```gleam
// 1. Define a middleware wrapper
fn require_auth(
  next: fn(Request, Ctx, Dict) -> Response
) {
  fn(req, ctx, params) {
    case request.get_header(req, "authorization") {
      Ok("secret-token") -> next(req, ctx, params) // Continue
      _ -> response.new(401) |> response.set_body("Unauthorized")
    }
  }
}

// 2. Use it in your router
pub fn main() {
  fist.new()
  |> fist.get("/public", to: public_handler)
  // Wrap the handler with the middleware function
  |> fist.get("/admin", to: require_auth(admin_handler))
}
```

## Context & State Management

Fist passes a generic `Context` to every handler, avoiding global state.

```gleam
pub type AppContext {
  AppContext(db_conn: Connection, api_key: String)
}

fn dashboard(req, ctx: AppContext, params) {
  // Use ctx.db_conn safely here
}

pub fn main() {
  let ctx = AppContext(db_conn: db.connect(), api_key: "secret")

  // The context is injected at runtime
  fist.handle(router, req, ctx, not_found_handler)
}
```
