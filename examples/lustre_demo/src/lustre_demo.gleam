import fist
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import home
import lustre/element
import mist

// 1. Defina um handler que usa Lustre para gerar o HTML
fn home_handler(_req, _ctx, _params) {
  let html_str =
    home.view("Bem-vindo ao Fist!")
    |> element.to_document_string

  response.new(200)
  |> response.set_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(html_str)))
}

// 2. Crie o router fist e configure as rotas
fn make_router() {
  fist.new()
  |> fist.get("/", to: home_handler)
}

// 3. Rode o servidor mist passando o handler do fist
pub fn main() {
  let router = make_router()

  let assert Ok(_) =
    mist.new(fn(req) {
      fist.handle(router, req, Nil, fn() {
        response.new(404)
        |> response.set_header("content-type", "text/plain")
        |> response.set_body(
          mist.Bytes(bytes_tree.from_string("Não encontrado")),
        )
      })
    })
    |> mist.port(8080)
    |> mist.start

  process.sleep_forever()
}
