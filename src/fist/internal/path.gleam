import gleam/list
import gleam/result
import gleam/string
import gleam/uri

/// Splits a path string into segments, ignoring empty strings and decoding percent-encoded characters.
/// Also strips query parameters and URL fragments if present in the path.
pub fn parse_path(path: String) -> List(String) {
  let clean_path = case string.split_once(path, "?") {
    Ok(#(p, _)) -> p
    Error(Nil) -> path
  }
  let clean_path = case string.split_once(clean_path, "#") {
    Ok(#(p, _)) -> p
    Error(Nil) -> clean_path
  }
  clean_path
  |> string.split("/")
  |> list.filter(fn(s) { s != "" })
  |> list.map(fn(segment) {
    uri.percent_decode(segment) |> result.unwrap(segment)
  })
}
