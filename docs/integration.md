# Integration & Static Files

Fist is a pure router library. It focuses exclusively on matching paths to handlers. It does not include a web server or file system capabilities out of the box.

However, it integrates seamlessly with any Gleam web server stack.

## Serving Static Files (Frontend)

To serve frontend assets (CSS, JS, Images, or a Single Page App) alongside your API, you should handle static files **before** calling `fist.handle` in your web server loop.

Here is an example using the popular **Mist** web server.

### Mist Example

This pattern checks for files in a `static/` folder first. If the file exists, it's served. If not, the request is passed to the Fist router.

```gleam
import mist
import fist
import gleam/http/request
import gleam/http/response
import gleam/bytes_tree
import gleam/string
import gleam/option.{None}

// ... your handlers ...

pub fn main() {
  // Define your dynamic API routes here
  let router =
    fist.new()
    |> fist.get("/api/users", to: users_handler)

  let service = fn(req: request.Request(mist.Connection)) {
    // 1. Check if the request is for a static asset
    //    (Assumes assets are requested like /static/style.css)
    let is_static = string.starts_with(req.path, "/static/")

    case is_static {
      True -> {
        // Rewrite URL to file path: /static/style.css -> priv/static/style.css
        let path = string.replace(req.path, "/static/", "priv/static/")

        // Use Mist's efficient file sender
        mist.send_file(path, offset: 0, limit: None)
        // If file not found, return 404 response
        |> result.map(fn(res) { res })
        |> result.lazy_unwrap(fn() {
          response.new(404) |> response.set_body(mist.Bytes(bytes_tree.new()))
        })
      }

      False -> {
        // 2. If not a static file, let Fist handle the routing logic
        fist.handle(router, req, Nil, fn() {
          // Fallback if no route matches
          response.new(404)
          |> response.set_body(mist.Bytes(bytes_tree.new()))
        })
      }
    }
  }

  // Start the server
  mist.new(service)
  |> mist.port(8080)
  |> mist.start_http()
}
```

## Single Page Applications (SPA)

If you are serving a React, Vue, or Lustre SPA, you often want to serve `index.html` for any unknown route (client-side routing).

You can achieve this in the "Not Found" handler of Fist:

```gleam
fist.handle(router, req, ctx, fn() {
  // Instead of 404, serve the main HTML file
  mist.send_file("priv/static/index.html", offset: 0, limit: None)
  |> result.unwrap(response.new(404))
})
```
