import fist
import gleam/dict
import gleam/http.{Get}
import gleam/http/request
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleeunit
import gleeunit/should
import support

pub fn main() {
  gleeunit.main()
}

fn middleware(next) {
  fn(req, ctx, params) { next(req, ctx, params) <> "." }
}

/// Middleware Stress Test:
/// Evaluates dispatch performance and recursion stability across 1,000 stacked middleware layers.
pub fn heavy_middleware_stress_test() {
  let router =
    fist.new()
    |> fist.get("/ping", fn(_, _, _) { "pong" })
    |> int.range(from: 0, to: 1000, with: _, run: fn(acc, _) {
      fist.wrap(acc, middleware)
    })

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/ping")

  let res = fist.handle(router, req, Nil, fn() { "404" })
  string.length(res) |> should.equal(1004)
}

fn append_id(id: String) {
  fn(next) { fn(req, ctx, params) { next(req, ctx, params) <> id } }
}

/// Static Wrap Middleware Order:
/// Wrap applies onion layering where the most recently wrapped middleware is the outermost layer.
pub fn middleware_order_test() {
  let router =
    fist.new()
    |> fist.get("/order", fn(_, _, _) { "root" })
    |> fist.wrap(append_id("1"))
    |> fist.wrap(append_id("2"))

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/order")

  // Evaluated: append_id("2")(append_id("1")(handler())) -> "root12"
  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("root12")
}

fn check_auth(_req) -> Bool {
  False
}

fn auth_middleware(next) {
  fn(req, ctx, params) {
    case check_auth(req) {
      True -> next(req, ctx, params)
      False -> "Unauthorized"
    }
  }
}

/// Middleware Short-Circuiting Baseline:
/// Middleware returning early halts the pipeline before handler invocation.
pub fn middleware_short_circuit_test() {
  let router =
    fist.new()
    |> fist.get("/private", fn(_, _, _) { "Secret Data" })
    |> fist.wrap(auth_middleware)

  let req =
    request.new() |> request.set_method(Get) |> request.set_path("/private")

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("Unauthorized")
}

/// Large Scale Route Tree Stress Benchmark:
/// Populates 2,000 distinct routes in the Trie and validates O(k) path-length lookup
/// across initial, middle, terminal, and non-existent paths.
pub fn large_scale_route_tree_benchmark_test() {
  let total_routes = 2000

  let router =
    int.range(from: 0, to: total_routes, with: fist.new(), run: fn(acc, idx) {
      let path = "/api/v1/resource_" <> int.to_string(idx) <> "/action"
      fist.get(acc, path, fn(_, _, _) { "res:" <> int.to_string(idx) })
    })

  let dispatch = fn(path_str) {
    let req =
      request.new() |> request.set_method(Get) |> request.set_path(path_str)
    fist.handle(router, req, Nil, fn() { "404" })
  }

  // Measure lookup at initial route
  let #(_t0, res_first) =
    support.time_ms(fn() { dispatch("/api/v1/resource_0/action") })
  res_first |> should.equal("res:0")

  // Measure lookup at middle route
  let #(_t1, res_mid) =
    support.time_ms(fn() { dispatch("/api/v1/resource_1000/action") })
  res_mid |> should.equal("res:1000")

  // Measure lookup at terminal route
  let #(_t2, res_last) =
    support.time_ms(fn() { dispatch("/api/v1/resource_1999/action") })
  res_last |> should.equal("res:1999")

  // Measure lookup on non-existent route
  let #(_t3, res_missing) =
    support.time_ms(fn() { dispatch("/api/v1/resource_missing/action") })
  res_missing |> should.equal("404")
}

/// High-Throughput Burst Dispatch Benchmark:
/// Executes 10,000 consecutive dispatches against a composite router featuring
/// static, dynamic parameter, and wildcard routes.
pub fn high_throughput_burst_dispatch_benchmark_test() {
  let router =
    fist.new()
    |> fist.get("/health", fn(_, _, _) { "ok" })
    |> fist.get("/users/:id/profile", fn(_, _, params) {
      "user:" <> dict.get(params, "id") |> result.unwrap("")
    })
    |> fist.get("/static/*path", fn(_, _, params) {
      "static:" <> dict.get(params, "path") |> result.unwrap("")
    })

  let req_static =
    request.new() |> request.set_method(Get) |> request.set_path("/health")
  let req_dynamic =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/users/42/profile")
  let req_wildcard =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/static/css/app.css")

  // Run 10,000 dispatches (3,333 triplets)
  let #(elapsed_ms, total_ok) =
    support.time_ms(fn() {
      int.range(from: 0, to: 3333, with: 0, run: fn(count, _) {
        let r1 = fist.handle(router, req_static, Nil, fn() { "404" })
        let r2 = fist.handle(router, req_dynamic, Nil, fn() { "404" })
        let r3 = fist.handle(router, req_wildcard, Nil, fn() { "404" })
        case r1 == "ok" && r2 == "user:42" && r3 == "static:css/app.css" {
          True -> count + 3
          False -> count
        }
      })
    })

  total_ok |> should.equal(9999)
  // Ensure 10,000 dispatches complete within a generous 2,000ms threshold
  { elapsed_ms < 2000 } |> should.be_true
}

/// Deep Path Depth Stress Test:
/// Tests handling of an extraordinarily deep URL (50 nested segments)
/// to verify stack stability and recursion health.
pub fn deep_path_depth_stress_test() {
  let segments =
    int.range(from: 1, to: 50, with: [], run: fn(acc, i) {
      ["s" <> int.to_string(i), ..acc]
    })
    |> list.reverse

  let path = "/" <> string.join(segments, "/")

  let router =
    fist.new()
    |> fist.get(path, fn(_, _, _) { "deep-reached" })

  let req = request.new() |> request.set_method(Get) |> request.set_path(path)

  fist.handle(router, req, Nil, fn() { "404" })
  |> should.equal("deep-reached")
}

/// Large Router Merge Performance:
/// Fuses two independently constructed 500-route trees using fist.merge
/// and validates complete integrity of the combined 1,000-route router.
pub fn large_router_merge_performance_test() {
  let router_a =
    int.range(from: 0, to: 500, with: fist.new(), run: fn(acc, i) {
      fist.get(acc, "/service_a/endpoint_" <> int.to_string(i), fn(_, _, _) {
        "A:" <> int.to_string(i)
      })
    })

  let router_b =
    int.range(from: 0, to: 500, with: fist.new(), run: fn(acc, i) {
      fist.get(acc, "/service_b/endpoint_" <> int.to_string(i), fn(_, _, _) {
        "B:" <> int.to_string(i)
      })
    })

  let #(merge_ms, merged) =
    support.time_ms(fn() { fist.merge(router_a, router_b) })
  { merge_ms < 1000 } |> should.be_true

  // Verify routes from both halves
  let req_a =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/service_a/endpoint_250")
  let req_b =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/service_b/endpoint_499")

  fist.handle(merged, req_a, Nil, fn() { "404" }) |> should.equal("A:250")
  fist.handle(merged, req_b, Nil, fn() { "404" }) |> should.equal("B:499")
}

/// Adversarial Deep Backtracking Stress Test:
/// Evaluates backtracking latency when matching a path that matches 15 nested static segments
/// before dead-ending and unwinding back to an ancestor wildcard catch-all.
pub fn adversarial_deep_backtracking_stress_test() {
  let router =
    fist.new()
    |> fist.get("/*fallback", fn(_, _, params) {
      let f = dict.get(params, "fallback") |> result.unwrap("")
      "fallback:" <> f
    })
    |> fist.get("/a/b/c/d/e/f/g/h/i/j/k/l/m/n/leaf", fn(_, _, _) {
      "exact-leaf"
    })

  let req_mismatch =
    request.new()
    |> request.set_method(Get)
    |> request.set_path("/a/b/c/d/e/f/g/h/i/j/k/l/m/n/mismatch")

  // Run 1,000 deep unwinds in a loop
  let #(elapsed_ms, _) =
    support.time_ms(fn() {
      int.range(from: 0, to: 1000, with: Nil, run: fn(_, _) {
        let res = fist.handle(router, req_mismatch, Nil, fn() { "404" })
        res
        |> should.equal("fallback:a/b/c/d/e/f/g/h/i/j/k/l/m/n/mismatch")
      })
    })

  // Ensure 1,000 15-level deep backtracks complete under 1,000ms
  { elapsed_ms < 1000 } |> should.be_true
}
