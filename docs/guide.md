# Fist User Guide 👊

This guide provides practical examples for using the Fist router in your Gleam applications.

## Table of Contents

1.  **[Core Concepts & Behavior](behavior.html)** - How the router works, path normalization, and precedence.
2.  **[Basic Routing](#basic-routing)** - Defining simple static and dynamic routes.
3.  **[Advanced Patterns](advanced.html)** - Middleware, Context, and Custom Return Types.
4.  **[Integration & Deployment](integration.html)** - Using with Mist and Serving Static Files.

---

## Basic Routing

Static routes are exact string matches. They always take priority over dynamic routes.

```gleam
import fist
import gleam/http/response

fn home_handler(_, _, _) {
  response.new(200) |> response.set_body("Welcome Home!")
}

pub fn main() {
  let router =
    fist.new()
    |> fist.get("/", to: home_handler)
    |> fist.get("/about", to: fn(_, _, _) {
      response.new(200) |> response.set_body("About Us")
    })
}
```

## Dynamic Parameters

Dynamic routes use segments starting with `:` to capture values. These values are passed to your handler in the `params` dictionary.

```gleam
import fist
import gleam/dict
import gleam/result
import gleam/http/response

fn user_handler(_req, _ctx, params) {
  // Extract the "id" parameter
  let id = dict.get(params, "id") |> result.unwrap("unknown")

  response.new(200)
  |> response.set_body("Viewing user: " <> id)
}

pub fn main() {
  let router =
    fist.new()
    |> fist.get("/users/:id", to: user_handler)
}
```

## Route Groups and Middlewares

Fist allows you to group routes under a common prefix and apply middlewares to them. A middleware is a function that wraps a handler:

```gleam
fn auth_middleware(next) {
  fn(req, ctx, params) {
    case is_authenticated(req) {
      True -> next(req, ctx, params)
      False -> response.new(401)
    }
  }
}

pub fn main() {
  fist.new()
  |> fist.group(at: "/api/v1", with: [auth_middleware], defining: fn(v1) {
    v1
    |> fist.get("/users", list_users)
    |> fist.post("/users", create_user)
  })
}
```

Middlewares are applied at definition time (Static Wrapping), ensuring zero performance overhead during route lookup.

## Route Metadata & Documentation

Fist allows you to attach descriptions to routes. This is useful for generating documentation automatically.

```gleam
import fist

let router =
  fist.new()
  |> fist.get("/users", to: list_users)
  |> fist.describe("Returns a list of all users")

  |> fist.post("/users", to: create_user)
  |> fist.describe("Creates a new user")
```

### Introspection
You can inspect the registered routes programmatically:

```gleam
import gleam/io

pub fn print_routes(router) {
  fist.inspect(router)
  |> list.each(fn(route) {
    io.println(route.method <> " " <> route.path <> " - " <> route.description)
  })
}
// Output:
// GET /users - Returns a list of all users
// POST /users - Creates a new user
```

---

*Continue reading:*
*   [Core Concepts & Behavior →](behavior.html)
*   [Advanced Patterns →](advanced.html)
*   [Integration & Static Files →](integration.html)
