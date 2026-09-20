import { Ok, Error } from "./gleam.mjs";
import { get } from "../gleam_stdlib/gleam/dict.mjs";

export function rescue(fun) {
  try {
    return new Ok(fun());
  } catch (err) {
    return new Error(err);
  }
}

export function time_ms(fun) {
  const t0 = Date.now();
  const res = fun();
  const t1 = Date.now();
  return [t1 - t0, res];
}

export function target_name() {
  return "javascript";
}

export function make_native_handler(prefix) {
  return (_req, _ctx, params) => {
    let nameResult = get(params, "name");
    let name = nameResult instanceof Ok ? nameResult[0] : "world";
    return `${prefix}:${name}`;
  };
}

export function make_native_middleware(tag) {
  return (next) => {
    return (req, ctx, params) => {
      const res = next(req, ctx, params);
      return `${tag}(${res})`;
    };
  };
}

export function measure_memory_bytes() {
  if (typeof process !== "undefined" && process.memoryUsage) {
    return process.memoryUsage().heapUsed;
  }
  return 0;
}
