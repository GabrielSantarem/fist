import fist
import gleam/bytes_tree
import gleam/dict
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/option.{None}
import gleam/result
import gleam/string
import logging
import mist

// --- HANDLERS ---

fn hello(_req, _ctx, params) {
  let name = dict.get(params, "name") |> result.unwrap("stranger")
  response.new(200)
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string("Hello, " <> name <> " from Mist!")),
  )
}

fn api_json(_req, _ctx, _params) {
  response.new(200)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string(
      "{\"status\": \"ok\", \"server\": \"mist\"}",
    )),
  )
}

// --- HELPERS ---

fn empty_body() {
  mist.Bytes(bytes_tree.new())
}

fn serve_file(path: String) {
  case mist.send_file(path, offset: 0, limit: None) {
    Ok(file) -> response.new(200) |> response.set_body(file)
    Error(err) -> {
      let msg = case err {
        mist.NoAccess -> "No access to file: " <> path
        mist.NoEntry -> "File not found: " <> path
        mist.IsDir -> "Is a directory: " <> path
        mist.UnknownFileError -> "Unknown file error: " <> path
      }
      logging.log(logging.Debug, msg)
      response.new(404) |> response.set_body(empty_body())
    }
  }
}

fn serve_index() {
  serve_file("priv/static/index.html")
}

// --- ROUTER ---

fn make_router() {
  fist.new()
  |> fist.get("/hello/:name", to: hello)
  |> fist.get("/api/status", to: api_json)
}

// --- SERVICE ---

fn make_service(router) {
  fn(req: request.Request(mist.Connection)) {
    case string.starts_with(req.path, "/static/") {
      True -> {
        req.path
        |> string.replace("/static/", "priv/static/")
        |> serve_file
      }
      False -> fist.handle(router, req, Nil, serve_index)
    }
  }
}

// --- MAIN ---

pub fn main() {
  logging.configure()
  logging.set_level(logging.Debug)

  let assert Ok(_) =
    make_router()
    |> make_service
    |> mist.new
    |> mist.port(8080)
    |> mist.start

  process.sleep_forever()
}
