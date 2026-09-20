import gleam/list
import gleam/result
import gleam/string
import gleam/uri

/// Normalizes and splits a path string into canonical segments.
/// Implements RFC 3986 Section 5.2.4 (Remove Dot Segments) to eliminate
/// directory traversal attacks (`.` and `..`), normalizes backslashes,
/// decodes percent-encoded tokens, strips null bytes, and trims query/fragment strings.
pub fn parse_path(path: String) -> List(String) {
  let clean_path = case string.split_once(path, "?") {
    Ok(#(p, _)) -> p
    Error(Nil) -> path
  }
  let clean_path = case string.split_once(clean_path, "#") {
    Ok(#(p, _)) -> p
    Error(Nil) -> clean_path
  }

  // Canonicalize path separators and percent-encoded separators/dots to neutralize WAF evasion
  let clean_path =
    clean_path
    |> string.replace("\\", "/")
    |> string.replace("%5c", "/")
    |> string.replace("%5C", "/")
    |> string.replace("%2f", "/")
    |> string.replace("%2F", "/")
    |> string.replace("%2e", ".")
    |> string.replace("%2E", ".")

  clean_path
  |> string.split("/")
  |> list.filter(fn(s) { s != "" })
  |> list.map(fn(segment) {
    uri.percent_decode(segment)
    |> result.unwrap(segment)
    |> string.replace("\u{0000}", "")
  })
  |> remove_dot_segments
}

/// Recursively removes dot segments according to RFC 3986 Section 5.2.4.
/// - "." is ignored (current directory)
/// - ".." pops the preceding segment (parent directory)
/// - Traversals attempting to escape above root are capped at root
fn remove_dot_segments(segments: List(String)) -> List(String) {
  do_remove_dot_segments(segments, [])
}

fn do_remove_dot_segments(
  remaining: List(String),
  acc: List(String),
) -> List(String) {
  case remaining {
    [] -> list.reverse(acc)
    [".", ..rest] -> do_remove_dot_segments(rest, acc)
    ["..", ..rest] -> {
      case acc {
        [_, ..popped] -> do_remove_dot_segments(rest, popped)
        [] -> do_remove_dot_segments(rest, [])
      }
    }
    [segment, ..rest] -> do_remove_dot_segments(rest, [segment, ..acc])
  }
}
