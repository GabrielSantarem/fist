# Fist 👊

A declarative and type-safe router, inspired by Axum, for the [Mist](https://github.com/rawhat/mist) web server in Gleam.

## Features

- **Declarative API**: Build your router using a clean, chainable syntax: `fist.get("/", to: handler)`.
- **Dynamic Routing**: Easily capture URL parameters with `:parameter_name`.
- **Generic Bodies**: Works with any request/response body types (`String`, `BitArray`, or `mist.Connection`).
- **Testable**: Test your routing logic easily with simple strings before deploying to a real server.
- **Type Safe**: Leverages Gleam's type system to ensure your handlers match your router's expectations.

## Installation

Add `fist` to your `gleam.toml`:

```toml
[dependencies]
fist = { path = "../fist" } # Or from hex when available
```

## Quick Start

### 1. Define your Handlers

Handlers are functions that take a `Request` and a `Dict(String, String)` containing the captured URL parameters.

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

### 2. Create the Router

Use the declarative API to map paths to handlers.

```gleam
import fist

pub fn make_router() {
  fist.new()
  |> fist.get("/hello/:name", to: hello_handler)
  |> fist.post("/users/:id/posts/:post_id", to: complex_handler)
}
```

### 3. Handle Requests

Use the `handle` function to process incoming requests.

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

## Typing and Parameter Conversion

Since Gleam does not have metaprogramming, parameters are delivered as `String`. You can use conversion functions to get specific types:

```gleam
import gleam/int
import gleam/dict
import gleam/result

fn my_handler(_req, params) {
  let id = 
    dict.get(params, "id")
    |> result.then(int.parse)
    |> result.unwrap(0) // Default value if not a valid Int

  // ... logic with id (Int)
}
```

## Integration with Mist

Since `fist` is generic, you can use it directly with `mist.Connection`.

```gleam
import mist
import fist
import gleam/bit_array
import gleam/dict
import gleam/result

pub fn main() {
  let router = 
    fist.new()
    |> fist.get("/user/:id", fn(_req, params) {
      let id = dict.get(params, "id") |> result.unwrap("0")
      response.new(200)
      |> response.set_body(mist.Bytes(bit_array.from_string("User ID: " <> id)))
    })

  let server = fn(req) {
    fist.handle(router, req, fn() {
      response.new(404)
      |> response.set_body(mist.Bytes(bit_array.from_string("Not Found")))
    })
  }

  mist.new(server)
  |> mist.port(3000)
  |> mist.start_http
}
```
