import fist
import gleam/http.{Get}
import gleam/http/request
import gleam/list
import gleeunit
import gleeunit/should
import support

pub fn main() {
  gleeunit.main()
}

/// Target Runtime Name Identification:
/// Ensures the test runner correctly distinguishes between Erlang and JavaScript targets.
pub fn target_name_detection_test() {
  let name = support.target_name()
  list.contains(["erlang", "javascript"], name) |> should.be_true
}

/// Native FFI Handler Registration and Execution:
/// Demonstrates that raw Erlang funs and JavaScript arrow functions can be registered
/// directly as first-class fist route handlers.
pub fn native_ffi_handler_execution_test() {
  let native_handler = support.make_native_handler("native")

  let router =
    fist.new()
    |> fist.get("/greet/:name", native_handler)

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/greet/gleam")

  let res = fist.handle(router, req, Nil, fn() { "404" })
  res |> should.equal("native:gleam")
}

/// Native FFI Middleware Interoperability:
/// Confirms that native Erlang and JavaScript functions can wrap Gleam handlers as middlewares.
pub fn native_ffi_middleware_wrapping_test() {
  let native_mw = support.make_native_middleware("NATIVE")

  let router =
    fist.new()
    |> fist.get("/echo", fn(_, _, _) { "hello" })
    |> fist.wrap(native_mw)

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/echo")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("NATIVE(hello)")
}

/// Empty Dynamic Parameter Name Registration Panic:
/// Registering an empty dynamic segment (e.g. '/users/:') causes an immediate fail-fast panic.
pub fn empty_dynamic_parameter_name_panics_test() {
  support.rescue(fn() {
    fist.new()
    |> fist.get("/users/:", fn(_, _, _) { "invalid" })
  })
  |> should.be_error

  support.rescue(fn() {
    fist.new()
    |> fist.get("/users/:/posts", fn(_, _, _) { "invalid" })
  })
  |> should.be_error
}

/// Empty Dynamic Prefix Parameter Name Panic:
/// Mounting at a prefix with an empty dynamic segment (e.g. '/tenants/:') causes a fail-fast panic.
pub fn empty_dynamic_prefix_parameter_name_panics_test() {
  let child =
    fist.new()
    |> fist.get("/dashboard", fn(_, _, _) { "ok" })

  support.rescue(fn() {
    fist.new()
    |> fist.mount("/tenants/:", child, fn(c) { c })
  })
  |> should.be_error
}

/// Memory Consumption Tracking Helper:
/// Validates that target memory can be measured across Erlang processes and JavaScript runtimes.
pub fn memory_consumption_tracking_test() {
  let initial_mem = support.measure_memory_bytes()
  { initial_mem >= 0 } |> should.be_true
}
