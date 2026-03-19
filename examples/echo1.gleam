import fist
import gleam/dict
import gleam/int
import gleam/result
import gleam/string

pub fn main() {
  fist.new()
  |> fist.get("/shout/:msg", to: fn(_req, params) {
    let msg = dict.get(params, "msg") |> result.unwrap("")
    fist.ok(string.uppercase(msg))
  })
  |> fist.get("/repeat/:n/:msg", to: fn(_req, params) {
    let n = dict.get(params, "n") |> result.try(int.parse) |> result.unwrap(0)
    let msg = dict.get(params, "msg") |> result.unwrap("")
    fist.ok(string.repeat(msg <> " ", n))
  })
  |> fist.map(fist.render_mist)
  |> fist.start(8080)
}
