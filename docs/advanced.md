# Advanced Patterns

`fist` is generic over request bodies, application contexts, and handler outputs. This architecture enables powerful, decoupled design patterns.

---

## 1. Custom Return Types (ADTs)

Handlers are not forced to return a `gleam/http/response.Response`. They can return domain-specific Algebraic Data Types (ADTs). You then transform these domain values globally using `fist.map`.

```gleam
import fist
import gleam/http/response.{type Response}

pub type ApiResponse {
  Text(String)
  Json(String)
  Forbidden
}

fn user_handler(_req, _ctx, _params) {
  Json("{\"status\": \"active\"}")
}

pub fn create_router() -> fist.Router(body, ctx, Response(String)) {
  fist.new()
  |> fist.get("/api/user", to: user_handler)
  |> fist.map(fn(res) {
    case res {
      Text(msg) -> response.new(200) |> response.set_body(msg)
      Json(json) ->
        response.new(200)
        |> response.set_header("content-type", "application/json")
        |> response.set_body(json)
      Forbidden -> response.new(403) |> response.set_body("Forbidden")
    }
  })
}
```

---

## 2. Context Polymorphism (`mount`, `map_context`)

Applications often have sub-modules requiring different context dependencies (e.g. an Admin section needing an authenticated `AdminUser`, while public routes need `Nil`).

`mount` combines sub-routers while adapting their context requirements using a mapper function:

```gleam
pub type AppContext {
  AppContext(current_user: Option(User), db: Database)
}

pub type AdminContext {
  AdminContext(admin_user: User, db: Database)
}

// Sub-router expecting AdminContext
pub fn admin_router() -> fist.Router(req, AdminContext, resp) {
  fist.new()
  |> fist.get("/metrics", to: show_metrics)
}

// Parent router expecting AppContext
pub fn root_router() {
  fist.new()
  |> fist.mount(
    at: "/admin",
    sub: admin_router(),
    transform: fn(app_ctx: AppContext) {
      // Elevate or transform context
      case app_ctx.current_user {
        Some(user) -> AdminContext(admin_user: user, db: app_ctx.db)
        None -> panic as "Unauthorized access before route dispatch"
      }
    },
  )
}
```

---

## 3. Middleware Architecture (Static Wrapping)

`fist` uses **Static Wrapping**. When you call `fist.wrap` or `fist.group(..., with: [mw1, mw2])`, the middleware functions wrap the handlers in the Trie at definition time.

- **Zero Lookup Overhead**: Routing lookups remain $O(n)$ without inspecting middleware lists during tree traversal.
- **Execution Order**: In `group(at: "...", with: [mw1, mw2])`, `mw1` is the outermost wrapper and executes first, followed by `mw2`, and finally the handler.

---

## 4. Route Metadata (`describe`) Chaining

Because `describe` operates on the most recently added route, it must be called immediately after that route's definition:

```gleam
// ✅ Correct
router
|> fist.get("/users", to: list_users)
|> fist.describe("List all active users")
|> fist.post("/users", to: create_user)
|> fist.describe("Create a new user")

// ❌ Incorrect (Description will not attach to the route)
router
|> fist.get("/users", to: list_users)
|> fist.wrap(my_middleware)
|> fist.describe("List all active users")
```
