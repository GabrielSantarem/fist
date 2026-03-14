# Fist 👊

A declarative, Axum-inspired router for the [Mist](https://github.com/rawhat/mist) web server in Gleam.

## Features

- **Declarative API**: Build your router using a clean, chainable syntax: `fist.get("/", to: handler)`.
- **Generic Bodies**: Works with any request/response body types (`String`, `BitArray`, or `mist.Connection`).
- **Testable**: Easily test your routing logic with simple strings before deploying to a real server.
- **Type Safe**: Leverages Gleam's type system to ensure your handlers match your router's expectations.

## Installation

Add `fist` to your `gleam.toml`:

```toml
[dependencies]
fist = { path = "../fist" } # Or from hex when available
```

## Quick Start

### 1. Define your Handlers

Handlers are just functions that take a `Request` and return a `Response`.

```gleam
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}

fn hello_handler(_req: Request(body)) -> Response(String) {
  response.new(200)
  |> response.set_body("Hello from Fist!")
}
```

### 2. Create the Router

Use the declarative API to map paths to handlers.

```gleam
import fist

pub fn make_router() {
  fist.new()
  |> fist.get("/", to: hello_handler)
  |> fist.post("/submit", to: submit_handler)
}
```

### 3. Handle Requests

Use the `handle` function to match incoming requests. This is where you define your "Not Found" behavior.

```gleam
import gleam/http/response

pub fn handle_request(req) {
  let router = make_router()
  
  fist.handle(router, req, fn() {
    response.new(404)
    |> response.set_body("Custom 404: Not Found")
  })
}
```

## Integration with Mist

Since `fist` is generic, you can use it directly with `mist.Connection` for high-performance streaming, or with `BitArray` for simpler logic.

```gleam
import mist
import fist

pub fn main() {
  let router = 
    fist.new()
    |> fist.get("/", to: fn(_req) {
      response.new(200)
      |> response.set_body(mist.Bytes(bit_array.from_string("Hi!")))
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

## How it works (The "Case" logic)

Under the hood, `fist` stores routes in a list and uses `list.find` to match the `method` and `path`. This allows you to avoid deep `case` nesting for simple routing, while still being able to use `case` inside your handlers for complex logic:

```gleam
fn complex_handler(req: Request(body)) {
  case request.path_segments(req) {
    ["user", id] -> handle_user(id)
    _ -> response.new(400)
  }
}
```
