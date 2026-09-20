import fist
import fist/extract.{InvalidFormat, NotFound}
import gleam/dict
import gleam/http.{Get}
import gleam/http/request
import gleam/http/response.{type Response}
import gleam/int
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub type UserRole {
  Admin
  Member
}

fn parse_role(val: String) -> Result(UserRole, Nil) {
  case val {
    "admin" -> Ok(Admin)
    "member" -> Ok(Member)
    _ -> Error(Nil)
  }
}

pub fn extract_string_test() {
  let params = dict.from_list([#("name", "Alice")])

  extract.string(params, "name") |> should.equal(Ok("Alice"))
  extract.string(params, "unknown") |> should.equal(Error(NotFound("unknown")))
}

pub fn extract_non_empty_string_test() {
  let params =
    dict.from_list([
      #("valid", "Alice"),
      #("empty", ""),
      #("spaces", "   "),
    ])

  extract.non_empty_string(params, "valid") |> should.equal(Ok("Alice"))
  extract.non_empty_string(params, "empty")
  |> should.equal(Error(InvalidFormat("empty", "", "non-empty string")))
  extract.non_empty_string(params, "spaces")
  |> should.equal(Error(InvalidFormat("spaces", "   ", "non-empty string")))
  extract.non_empty_string(params, "missing")
  |> should.equal(Error(NotFound("missing")))
}

pub fn extract_int_test() {
  let params =
    dict.from_list([
      #("pos", "42"),
      #("neg", "-10"),
      #("invalid", "42abc"),
    ])

  extract.int(params, "pos") |> should.equal(Ok(42))
  extract.int(params, "neg") |> should.equal(Ok(-10))
  extract.int(params, "invalid")
  |> should.equal(Error(InvalidFormat("invalid", "42abc", "integer")))
  extract.int(params, "missing")
  |> should.equal(Error(NotFound("missing")))
}

pub fn extract_float_test() {
  let params =
    dict.from_list([
      #("val", "3.14"),
      #("invalid", "abc"),
    ])

  extract.float(params, "val") |> should.equal(Ok(3.14))
  extract.float(params, "invalid")
  |> should.equal(Error(InvalidFormat("invalid", "abc", "float")))
  extract.float(params, "missing")
  |> should.equal(Error(NotFound("missing")))
}

pub fn extract_bool_test() {
  let truthy =
    dict.from_list([
      #("a", "true"),
      #("b", "TRUE"),
      #("c", "1"),
      #("d", "yes"),
      #("e", "t"),
    ])

  extract.bool(truthy, "a") |> should.equal(Ok(True))
  extract.bool(truthy, "b") |> should.equal(Ok(True))
  extract.bool(truthy, "c") |> should.equal(Ok(True))
  extract.bool(truthy, "d") |> should.equal(Ok(True))
  extract.bool(truthy, "e") |> should.equal(Ok(True))

  let falsy =
    dict.from_list([
      #("a", "false"),
      #("b", "0"),
      #("c", "no"),
      #("d", "f"),
    ])

  extract.bool(falsy, "a") |> should.equal(Ok(False))
  extract.bool(falsy, "b") |> should.equal(Ok(False))
  extract.bool(falsy, "c") |> should.equal(Ok(False))
  extract.bool(falsy, "d") |> should.equal(Ok(False))

  let invalid = dict.from_list([#("val", "maybe")])
  extract.bool(invalid, "val")
  |> should.equal(Error(InvalidFormat("val", "maybe", "boolean")))
}

pub fn extract_uuid_test() {
  let valid_uuid = "123e4567-e89b-12d3-a456-426614174000"
  let upper_uuid = "123E4567-E89B-12D3-A456-426614174000"
  let invalid_chars = "123g4567-e89b-12d3-a456-426614174000"
  let invalid_len = "123e4567-e89b-12d3-a456"

  let params =
    dict.from_list([
      #("valid", valid_uuid),
      #("upper", upper_uuid),
      #("bad_chars", invalid_chars),
      #("bad_len", invalid_len),
    ])

  extract.uuid(params, "valid") |> should.equal(Ok(valid_uuid))
  extract.uuid(params, "upper") |> should.equal(Ok(valid_uuid))
  extract.uuid(params, "bad_chars")
  |> should.equal(
    Error(InvalidFormat("bad_chars", invalid_chars, "valid RFC 4122 UUID")),
  )
  extract.uuid(params, "bad_len")
  |> should.equal(
    Error(InvalidFormat("bad_len", invalid_len, "valid RFC 4122 UUID")),
  )
}

pub fn extract_custom_test() {
  let params =
    dict.from_list([
      #("role", "admin"),
      #("invalid_role", "superuser"),
    ])

  extract.custom(params, "role", "UserRole", parse_role)
  |> should.equal(Ok(Admin))

  extract.custom(params, "invalid_role", "UserRole", parse_role)
  |> should.equal(Error(InvalidFormat("invalid_role", "superuser", "UserRole")))
}

pub fn extract_optional_test() {
  let params = dict.from_list([#("int_val", "123"), #("bad_int", "not_an_int")])

  extract.optional_string(params, "missing") |> should.equal(None)
  extract.optional_string(params, "int_val") |> should.equal(Some("123"))

  extract.optional_int(params, "missing") |> should.equal(Ok(None))
  extract.optional_int(params, "int_val") |> should.equal(Ok(Some(123)))
  extract.optional_int(params, "bad_int")
  |> should.equal(Error(InvalidFormat("bad_int", "not_an_int", "integer")))
}

pub fn extract_fallback_defaults_test() {
  let params = dict.from_list([#("name", "Bob"), #("age", "30")])

  extract.string_or(params, "name", "Anonymous") |> should.equal("Bob")
  extract.string_or(params, "country", "Brazil") |> should.equal("Brazil")

  extract.int_or(params, "age", 0) |> should.equal(30)
  extract.int_or(params, "missing_age", 18) |> should.equal(18)

  extract.bool_or(params, "missing_flag", True) |> should.equal(True)
}

pub fn require_syntax_with_use_test() {
  let handle_item = fn(_req: request.Request(String), _ctx: Nil, params) -> Response(
    String,
  ) {
    use id <- extract.require_int(params, "id", or: fn(err) {
      response.new(400) |> response.set_body(extract.error_to_string(err))
    })
    use active <- extract.require_bool(params, "active", or: fn(err) {
      response.new(400) |> response.set_body(extract.error_to_string(err))
    })

    response.new(200)
    |> response.set_body(case active {
      True -> "Active Item " <> int.to_string(id)
      False -> "Inactive Item " <> int.to_string(id)
    })
  }

  let router =
    fist.new()
    |> fist.get("/items/:id/:active", handle_item)

  // 1. Valid request
  let req_ok =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/items/100/true")

  let res_ok = fist.handle(router, req_ok, Nil, fn() { response.new(404) })
  res_ok.status |> should.equal(200)
  res_ok.body |> should.equal("Active Item 100")

  // 2. Malformed id (should short-circuit to 400 Bad Request)
  let req_bad_id =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/items/not_a_number/true")

  let res_bad_id =
    fist.handle(router, req_bad_id, Nil, fn() { response.new(404) })
  res_bad_id.status |> should.equal(400)
  res_bad_id.body
  |> should.equal(
    "Invalid parameter 'id': expected integer, got 'not_a_number'",
  )
}

pub fn query_parameters_extraction_test() {
  let req =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/search")
    |> request.set_query([
      #("q", "gleam"),
      #("page", "3"),
      #("sort", "asc"),
      #("verified", "true"),
    ])

  extract.query_string(req, "q") |> should.equal(Ok("gleam"))
  extract.query_int(req, "page") |> should.equal(Ok(3))
  extract.query_bool(req, "verified") |> should.equal(Ok(True))
  extract.query_string(req, "missing")
  |> should.equal(Error(NotFound("missing")))
}
