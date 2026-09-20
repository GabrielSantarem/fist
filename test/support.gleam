import gleam/dynamic.{type Dynamic}

@external(erlang, "fist_test_ffi", "rescue")
@external(javascript, "./fist_test_ffi.mjs", "rescue")
pub fn rescue(fun: fn() -> a) -> Result(a, Dynamic)
