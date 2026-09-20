import { Ok, Error } from "./gleam.mjs";

export function rescue(fun) {
  try {
    return new Ok(fun());
  } catch (err) {
    return new Error(err);
  }
}
