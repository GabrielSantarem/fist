# Fist User Guide 👊

This guide provides practical examples for using the Fist router in your Gleam applications.

## Table of Contents
1. [Static Routes](#static-routes)
2. [Dynamic Routes & Parameters](#dynamic-routes--parameters)
3. [Using Context](#using-context)
4. [Customizing Not Found](#customizing-not-found)
5. [Route Metadata & Documentation](#route-metadata--documentation)
6. [Full Example](#full-example)

---

## Static Routes

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

---

## Dynamic Routes & Parameters

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
    |> fist.get("/users/:id/posts/:postId", to: post_handler)
}
```

### ⚠️ Important: Parameter Overriding

Fist uses a Trie structure. This means **you cannot have two different dynamic parameter names at the same tree level**.

**Incorrect:**
```gleam
fist.new()
|> fist.get("/api/:user_id", ...)
|> fist.get("/api/:client_id", ...) // ❌ This will OVERRIDE :user_id with :client_id
```

**Correct:**
Differentiate them by a static prefix or handle the logic inside one handler.
```gleam
fist.new()
|> fist.get("/users/:user_id", ...)
|> fist.get("/clients/:client_id", ...)
```

---

## Using Context

Fist is generic over a `context` type. This allows you to pass database connections, configuration, or any other state to your handlers without global variables.

1. **Define your Context type:**
```gleam
pub type AppContext {
  AppContext(db_name: String, secret_key: String)
}
```

2. **Use it in handlers:**
```gleam
fn dashboard_handler(_req, ctx: AppContext, _params) {
  // Access ctx.db_name here
  response.new(200) |> response.set_body("Connected to " <> ctx.db_name)
}
```

3. **Pass it when handling a request:**
```gleam
pub fn main() {
  let router = fist.new() |> fist.get("/dashboard", to: dashboard_handler)
  let ctx = AppContext(db_name: "prod_db", secret_key: "123")
  
  // Pass 'ctx' here
  fist.handle(router, request, ctx, not_found_handler)
}
```

---

## Customizing Not Found

The `fist.handle` function requires a fallback function that is called when no route matches. This is where you define your 404 behavior.

```gleam
import gleam/http/response

fn not_found() {
  response.new(404)
  |> response.set_header("content-type", "application/json")
  |> response.set_body("{\"error\": \"Route not found\"}")
}

// Usage
fist.handle(router, req, ctx, not_found)
```

---

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

## Full Example

Here is a complete example combining everything.

```gleam
import fist
import gleam/http.{Get, Post}
import gleam/http/request
import gleam/http/response
import gleam/dict
import gleam/result

// 1. Context
pub type Ctx { Ctx(db: String) }

// 2. Handlers
fn get_user(_req, ctx: Ctx, params) {
  let id = result.unwrap(dict.get(params, "id"), "")
  response.new(200) 
  |> response.set_body("User " <> id <> " from " <> ctx.db)
}

fn create_user(req, _ctx, _params) {
  response.new(201) |> response.set_body("Created!")
}

// 3. Main
pub fn main() {
  let router = 
    fist.new()
    |> fist.get("/users/:id", to: get_user)
    |> fist.describe("Get a user by ID")
    
    |> fist.post("/users", to: create_user)
    |> fist.describe("Create a new user")

  // Simulate a request
  let req = request.new() 
    |> request.set_path("/users/42")
    |> request.set_method(Get)
  
  let ctx = Ctx(db: "Postgres")

  let res = fist.handle(router, req, ctx, fn() {
    response.new(404) |> response.set_body("Not Found")
  })
}
```
