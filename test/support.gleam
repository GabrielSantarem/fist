import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/http/request.{type Request}

@external(erlang, "fist_test_ffi", "rescue")
@external(javascript, "./fist_test_ffi.mjs", "rescue")
pub fn rescue(fun: fn() -> a) -> Result(a, Dynamic)

@external(erlang, "fist_test_ffi", "time_ms")
@external(javascript, "./fist_test_ffi.mjs", "time_ms")
pub fn time_ms(fun: fn() -> a) -> #(Int, a)

@external(erlang, "fist_test_ffi", "target_name")
@external(javascript, "./fist_test_ffi.mjs", "target_name")
pub fn target_name() -> String

@external(erlang, "fist_test_ffi", "make_native_handler")
@external(javascript, "./fist_test_ffi.mjs", "make_native_handler")
pub fn make_native_handler(
  prefix: String,
) -> fn(Request(a), ctx, Dict(String, String)) -> String

@external(erlang, "fist_test_ffi", "make_native_middleware")
@external(javascript, "./fist_test_ffi.mjs", "make_native_middleware")
pub fn make_native_middleware(
  tag: String,
) -> fn(fn(Request(a), ctx, Dict(String, String)) -> String) ->
  fn(Request(a), ctx, Dict(String, String)) -> String

@external(erlang, "fist_test_ffi", "measure_memory_bytes")
@external(javascript, "./fist_test_ffi.mjs", "measure_memory_bytes")
pub fn measure_memory_bytes() -> Int
