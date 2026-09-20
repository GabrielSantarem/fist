import { Ok, Error } from "./gleam.mjs";

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
