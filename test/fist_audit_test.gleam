import fist
import gleam/dict
import gleam/http/request
import gleam/list
import gleeunit/should

pub fn path_normalization_test() {
  let router =
    fist.new()
    |> fist.get("/api/v1/status", fn(_, _, _) { "ok" })

  let req1 = request.new() |> request.set_path("/api/v1/status/")
  let req2 = request.new() |> request.set_path("//api///v1/status")

  fist.handle(router, req1, Nil, fn() { "404" }) |> should.equal("ok")
  fist.handle(router, req2, Nil, fn() { "404" }) |> should.equal("ok")
}

pub fn case_sensitivity_test() {
  let router =
    fist.new()
    |> fist.get("/Users", fn(_, _, _) { "upper" })
    |> fist.get("/users", fn(_, _, _) { "lower" })

  let req_upper = request.new() |> request.set_path("/Users")
  let req_lower = request.new() |> request.set_path("/users")

  fist.handle(router, req_upper, Nil, fn() { "404" }) |> should.equal("upper")
  fist.handle(router, req_lower, Nil, fn() { "404" }) |> should.equal("lower")
}

pub fn parameter_name_conflict_test() {
  // O último nome definido em um mesmo nível sobrescreve o anterior
  let router =
    fist.new()
    |> fist.get("/users/:id/profile", fn(_, _, params) {
      dict.get(params, "id") |> should.be_error
      dict.get(params, "user_id") |> should.be_ok
      "profile"
    })
    |> fist.get("/users/:user_id/settings", fn(_, _, params) {
      dict.get(params, "user_id") |> should.be_ok
      "settings"
    })

  let req = request.new() |> request.set_path("/users/123/profile")
  fist.handle(router, req, Nil, fn() { "404" }) |> should.equal("profile")
}

pub fn describe_after_map_failure_test() {
  // Testando a fragilidade do describe após transformações
  let router =
    fist.new()
    |> fist.get("/data", fn(_, _, _) { "ok" })
    |> fist.map(fn(s) { s })
    // Limpa o last_added
    |> fist.describe("This description will be ignored")

  let routes = fist.inspect(router)
  let assert Ok(route) = list.first(routes)
  route.description |> should.equal("")
  // Falhou em adicionar a descrição
}

pub fn empty_path_root_test() {
  let router =
    fist.new()
    |> fist.get("", fn(_, _, _) { "empty" })
    |> fist.get("/", fn(_, _, _) { "slash" })

  // Ambos devem apontar para o mesmo nó (rota raiz)
  // O segundo sobrescreve o primeiro
  let req = request.new() |> request.set_path("/")
  fist.handle(router, req, Nil, fn() { "404" }) |> should.equal("slash")
}
