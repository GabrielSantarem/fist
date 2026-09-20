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

---

## 5. Multi-Tier Mounts & Hierarchical Reverse Routing

When modular routers are mounted under multi-level dynamic prefixes, all prefix parameters are automatically prepended into the reverse routing templates:

```gleam
// 1. Issue sub-router
let issue_sub =
  fist.new()
  |> fist.get("/issues/:issue_id", to: show_issue)
  |> fist.name("project_issue")

// 2. Project sub-router mounts issue sub-router
let project_sub =
  fist.new()
  |> fist.mount(at: "/projects/:project_slug", sub: issue_sub, transform: fn(c) { c })

// 3. Organization root router mounts project sub-router
let app_router =
  fist.new()
  |> fist.mount(at: "/orgs/:org_name", sub: project_sub, transform: fn(c) { c })
```

### Path Generation with Cumulative Prefixes
When generating the reverse path for `project_issue`, `fist.path` requires all parameters across every tier:

```gleam
fist.path(app_router, for: "project_issue", with: [
  #("org_name", "beam-gleam"),
  #("project_slug", "fist-router"),
  #("issue_id", "42"),
])
// -> Ok("/orgs/beam-gleam/projects/fist-router/issues/42")
```

If any tier's parameter is missing, Fist reports the exact missing parameter:
```gleam
fist.path(app_router, for: "project_issue", with: [
  #("project_slug", "fist-router"),
  #("issue_id", "42"),
])
// -> Error(MissingParameter(route: "project_issue", missing: "org_name"))
```

---

## 6. Resolving Circular Type Recursion with `PathRegistry`

A frequent architectural dilemma in web frameworks is how route handlers can generate reverse URLs when they require access to the router:
1. `AppContext` needs `Router` to call `fist.path(router, ...)`.
2. But `Router` is generic over `AppContext` (`Router(req, AppContext, out)`).
3. This creates an impossible circular type recursion in statically typed languages!

### The Solution: Type Erasure via `PathRegistry`
Fist resolves this elegantly with the opaque type `PathRegistry`:
*   `PathRegistry` has **zero generic type arguments**. It only holds route templates, guard predicates, and segment names.
*   Your application context stores only `PathRegistry`.
*   Handlers generate paths by calling `fist.path_from(ctx.registry, for: name, with: params)`.

```gleam
// Handler is completely decoupled from Router
pub fn handle_create_user(_req, ctx: AppContext, _params) {
  let assert Ok(profile_url) =
    fist.path_from(ctx.registry, for: "user_profile", with: [#("id", "10")])

  response.new(201)
  |> response.set_header("location", profile_url)
  |> response.set_body("User created")
}
```

---

## 7. Route Aliasing & Seamless URL Migrations

When redesigning API endpoints or migrating URL names, you can assign multiple names to a single route by chaining `fist.name`:

```gleam
router
|> fist.get("/accounts/:id", to: show_account)
|> fist.name("user_account")       // New canonical name
|> fist.name("legacy_user_profile") // Deprecated alias
```

Both names resolve to `/accounts/:id`:
*   Existing code calling `legacy_user_profile` continues to work without disruption.
*   New modules can use `user_account`.
*   Both templates share the exact same guard validation and URL serialization.
