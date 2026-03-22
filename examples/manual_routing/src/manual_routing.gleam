import fist
import gleam/dict
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/int
import gleam/io
import gleam/list
import gleam/result

// GET / -> 200 Home
// GET /hello/tomate -> 200 Hello, tomate!
// GET /hello/gleam -> 200 Hello, gleam!
// POST /echo -> 200 Echo:
// GET /nao/existe -> 404 Not Found

fn make_request(method: http.Method, path: String) {
  request.new()
  |> request.set_method(method)
  |> request.set_path(path)
  |> request.set_body("")
}

fn not_found() {
  response.new(404)
  |> response.set_body("Not Found")
}

pub fn main() {
  let router =
    fist.new()
    |> fist.get("/", to: fn(_, _, _) {
      response.new(200) |> response.set_body("Home")
    })
    |> fist.get("/hello/:name", to: fn(_, _, params) {
      let name = dict.get(params, "name") |> result.unwrap("stranger")
      response.new(200) |> response.set_body("Hello, " <> name <> "!")
    })
    |> fist.post("/echo", to: fn(req, _, _) {
      response.new(200) |> response.set_body("Echo: " <> req.body)
    })

  let requests = [
    make_request(http.Get, "/"),
    make_request(http.Get, "/hello/tomate"),
    make_request(http.Get, "/hello/gleam"),
    make_request(http.Post, "/echo"),
    make_request(http.Get, "/nao/existe"),
  ]

  requests
  |> list.each(fn(req) {
    let res = fist.handle(router, req, Nil, not_found)
    io.println(
      req.method |> http.method_to_string
      <> " "
      <> req.path
      <> " -> "
      <> res.status |> int.to_string
      <> " "
      <> res.body,
    )
  })
}
