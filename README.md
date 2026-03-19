# Fist 👊
A declarative, type-safe router for the [Mist](https://github.com/rawhat/mist) web server in Gleam, inspired by Axum.

## Features
- **Declarative API**: Build your router with a clean, chainable syntax: `fist.get("/", to: handler)`.
- **Dynamic Routing**: Capture URL parameters with `:parameter_name`.
- **Generic Output**: Handlers can return anything (`Response`, `String`, or your own custom types).
- **Transformation Pipeline**: Use `fist.map` to transform your router's output (e.g., from `String` to `mist.ResponseData`).
- **Response Helpers**: Built-in functions like `fist.ok`, `fist.json`, and `fist.text` for faster development.
- **Type Safe**: Gleam's type system ensures your handlers always match your router's expectations.

## Installation
Add `fist` to your `gleam.toml`:
```toml
[dependencies]
fist = { path = "../fist" } # Or from Hex when available
```

## Quick Start

### 1. Define your handlers
With `fist`, you can return standard `Response` types using built-in helpers.

```gleam
import gleam/dict.{type Dict}
import gleam/http/request.{type Request}
import gleam/result
import fist

fn hello_handler(_req: Request(body), params: Dict(String, String)) {
  let name = dict.get(params, "name") |> result.unwrap("stranger")
  fist.ok("Hello, " <> name <> "!")
}
```

### 2. Create and transform the router
You can write your business logic using simple `Response(String)` and then transform it for your web server (like Mist) at the end.

```gleam
import fist

pub fn main() {
  fist.new()
  |> fist.get("/hello/:name", to: hello_handler)
  |> fist.get("/json", to: fn(_, _) { fist.json("{\"status\": \"ok\"}") })
  // Transform all Response(String) to Response(mist.ResponseData)
  |> fist.map(fist.render_mist)
  |> fist.start(port: 8080)
}
```


## Advanced: Custom Return Types (ADTs)
Because `fist` is generic over the handler's output, you can use your own Algebraic Data Types and map them.

```gleam
pub type MyAnswer {
  Success(String)
  UserFound(User)
  Error(String)
}

fn my_handler(_, _) {
  Success("Operation completed")
}

pub fn start() {
  fist.new()
  |> fist.get("/", to: my_handler)
  |> fist.map(fn(answer) {
    case answer {
      Success(msg) -> fist.ok(msg)
      UserFound(user) -> fist.json(user_to_json(user))
      Error(err) -> fist.text("Error: " <> err) // Adicione .set_status(400) se necessário
    }
  })
  |> fist.map(fist.render_mist)
  |> fist.start(8080)
}
```

## Integration with Mist
The `fist.start` function provides a convenient way to run your router with Mist. It expects a router where handlers return `Response(mist.ResponseData)`.

```gleam
import mist
import fist

pub fn main() {
  fist.new()
  |> fist.get("/", to: fn(_req, _params) {
    fist.ok("Hello from Mist!")
  })
  |> fist.map(fist.render_mist)
  |> fist.start(port: 8080)
}
```
