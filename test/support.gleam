import gleam/dynamic.{type Dynamic}

@external(erlang, "fist_test_ffi", "rescue")
pub fn rescue(fun: fn() -> a) -> Result(a, Dynamic)
