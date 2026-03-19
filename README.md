# Fist 👊
A declarative, functional router for Gleam.

## Features
- **Declarative API**: Build your router with a clean, chainable syntax: `fist.get("/", to: handler)`.
- **Dynamic Routing**: Capture URL parameters with `:parameter_name`.
- **Generic Context**: Pass any context (database connections, config, etc.) to your handlers without rebuilding the router.
- **Generic Output**: Handlers can return anything (`Response`, `String`, or your own custom types).
- **Transformation Pipeline**: Use `fist.map` to transform your router's output globally.
- **Response Helpers**: Built-in functions like `fist.ok`, `fist.json`, and `fist.text` for faster development.
- **Pure Gleam**: No mandatory dependencies on specific web servers. Works with anything that uses the standard `gleam/http` types.

## Installation
Add `fist` to your `gleam.toml`:
```toml
[dependencies]
fist = { path = "../fist" } # Or from Hex when available
```

## Quick Start

### 1. Define your handlers
Handlers receive the request, a custom context, and the captured parameters.

```gleam
import gleam/dict.{type Dict}
import gleam/http/request.{type Request}
import gleam/result
import fist

fn hello_handler(_req: Request(body), _ctx: MyContext, params: Dict(String, String)) {
  let name = dict.get(params, "name") |> result.unwrap("stranger")
  fist.ok("Hello, " <> name <> "!")
}
```

### 2. Create and transform the router
You can write your business logic using simple types and then transform them at the end.

```gleam
import fist
import gleam/http/response

pub fn main() {
  let router = 
    fist.new()
    |> fist.get("/hello/:name", to: hello_handler)
    |> fist.get("/json", to: fn(_, _, _) { fist.json("{\"status\": \"ok\"}") })

  // Example of using the router with a context
  let req = ...
  let ctx = MyContext(...)
  
  fist.handle(router, req, ctx, fn() {
    fist.text("Not Found") |> response.set_status(404)
  })
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

fn my_handler(_, _, _) {
  Success("Operation completed")
}

pub fn create_router() {
  fist.new()
  |> fist.get("/", to: my_handler)
  |> fist.map(fn(answer) {
    case answer {
      Success(msg) -> fist.ok(msg)
      UserFound(user) -> fist.json(user_to_json(user))
      Error(err) -> fist.text("Error: " <> err)
    }
  })
}
```

## Integration with Web Servers
`fist` is a pure router. To use it with a server like **Mist** or **Wisp**, simply call `fist.handle` inside your server's request handler.

### Example with Mist
```gleam
import mist
import fist
import gleam/bytes_tree
import gleam/http/response

pub fn main() {
  let router = 
    fist.new()
    |> fist.get("/", to: fn(_, _, _) { fist.ok("Hello!") })

  let service = fn(req) {
    let res = fist.handle(router, req, Nil, fn() { 
      fist.ok("Not Found") |> response.set_status(404) 
    })
    
    // Convert your Response(String) to Mist's expected format
    response.set_body(res, mist.Bytes(bytes_tree.from_string(res.body)))
  }

  mist.new(service)
  |> mist.port(8080)
  |> mist.start()
}
```
