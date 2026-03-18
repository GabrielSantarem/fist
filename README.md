# Fist 👊
A declarative, type-safe router for the [Mist](https://github.com/rawhat/mist) web server in Gleam, inspired by Axum.

## Features
- **Declarative API**: Build your router with a clean, chainable syntax: `fist.get("/", to: handler)`.
- **Dynamic Routing**: Capture URL parameters with `:parameter_name`.
- **Generic Bodies**: Works with any request/response body type (`String`, `BitArray`, or `mist.Connection`).
- **Testable**: Test your routing logic with plain strings before connecting to a real server.
- **Type Safe**: Gleam's type system ensures your handlers always match your router's expectations.

## Installation
Add `fist` to your `gleam.toml`:
```toml
[dependencies]
fist = { path = "../fist" } # Or from Hex when available
```

## Quick Start

### 1. Define your handlers
A handler is a function that receives a `Request` and a `Dict(String, String)` with the captured URL parameters.

```gleam
import gleam/dict.{type Dict}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/result

fn hello_handler(_req: Request(body), params: Dict(String, String)) -> Response(String) {
  let name = dict.get(params, "name") |> result.unwrap("stranger")

  response.new(200)
  |> response.set_body("Hello, " <> name <> "!")
}
```

### 2. Create the router
Use the declarative API to map paths to handlers.

```gleam
import fist

pub fn make_router() {
  fist.new()
  |> fist.get("/hello/:name", to: hello_handler)
  |> fist.post("/users/:id/posts/:post_id", to: complex_handler)
}
```

### 3. Handle requests
Pass incoming requests to the `handle` function along with a fallback for unmatched routes.

```gleam
import gleam/http/response

pub fn handle_request(req) {
  let router = make_router()

  fist.handle(router, req, fn() {
    response.new(404)
    |> response.set_body("Page not found")
  })
}
```

## Working with URL parameters
URL parameters are always captured as `String`. Use conversion functions to parse them into other types:

```gleam
import gleam/int
import gleam/dict
import gleam/result

fn my_handler(_req, params) {
  let id =
    dict.get(params, "id")
    |> result.then(int.parse)
    |> result.unwrap(0) // fallback if the value is not a valid Int

  // ... use id as an Int
}
```

## Integration with Mist
Since `fist` is generic, it works directly with `mist.Connection`:

```gleam
import mist
import fist
import gleam/bytes_tree
import gleam/dict
import gleam/result

pub fn main() {
  fist.new()
  |> fist.get("/", to: fn(_req, _params) {
    response.new(200)
    |> response.set_body(mist.Bytes(bytes_tree.from_string("Hello, World!")))
  })
  |> fist.get("/hello/:name", to: fn(_req, params) {
    let name = dict.get(params, "name") |> result.unwrap("stranger")
    response.new(200)
    |> response.set_body(
      mist.Bytes(bytes_tree.from_string("Hello, " <> name <> "!")),
    )
  })
  |> fist.get("/echo/:message", to: fn(_req, params) {
    let msg = dict.get(params, "message") |> result.unwrap("")
    response.new(200)
    |> response.set_body(mist.Bytes(bytes_tree.from_string("Echo: " <> msg)))
  })
  |> fist.post("/submit", to: fn(_req, _params) {
    response.new(201)
    |> response.set_body(mist.Bytes(bytes_tree.from_string("Submitted!")))
  })
  |> fist.start(port: 8080)
}
```
