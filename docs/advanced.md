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

## Route Wrapping (Middlewares)

Fist provides the `fist.wrap` function to apply a middleware to all existing routes in a router. A middleware is a function that takes a handler and returns a new handler.

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
  // Wrap all routes defined ABOVE this line with the middleware
  |> fist.wrap(require_auth)
  // Routes defined BELOW this line will NOT have the middleware
  |> fist.get("/login", to: login_handler)
}
```

## Route Metadata (`describe`)

Fist allows you to attach descriptions to routes. However, note that the `describe` function relies on the **previously added route**. 

**⚠️ Chaining Break:**
Functions that transform the entire router (like `map` or `map_context`) clear the "last added route" state. **You must call `describe` immediately after the route definition.**

```gleam
// ✅ Correct
router
|> fist.get("/users", list_users)
|> fist.describe("List users")
|> fist.map(my_mapper)

// ❌ Incorrect (Description will be ignored)
router
|> fist.get("/users", list_users)
|> fist.map(my_mapper)
|> fist.describe("List users")
```

## Context Polymorphism with `mount`

One of Fist's most powerful features is the ability to combine routers with different context requirements. This is achieved through `mount` and `map_context`.

Imagine you have an admin router that requires an `AdminUser` context, but your main router has a `Nil` context:

```gleam
// admin.gleam
pub type AdminContext { AdminContext(user: User) }

pub fn admin_router() {
  fist.new()
  |> fist.get("/dashboard", show_dashboard) // Expects AdminContext
}

// main.gleam
pub fn main_router() {
  fist.new()
  |> fist.mount(
    at: "/admin",
    sub: admin.admin_router(),
    transform: fn(_nil_ctx) {
      // Logic to transform Root Context to AdminContext
      AdminContext(user: get_current_user())
    }
  )
}
```

This allows for true modularity and isolation of concerns across your application.

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
