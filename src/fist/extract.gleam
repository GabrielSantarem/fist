import gleam/dict.{type Dict}
import gleam/float
import gleam/http/request.{type Request}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri

/// Represents an error encountered while attempting to extract or parse a parameter.
pub type ExtractError {
  /// The specified key was not found in the parameters or query dictionary.
  NotFound(key: String)
  /// The parameter was found, but failed type conversion to the expected format.
  InvalidFormat(key: String, raw_value: String, expected: String)
}

/// Converts an `ExtractError` into a standardized, human-readable error description.
pub fn error_to_string(error: ExtractError) -> String {
  case error {
    NotFound(key) -> "Missing required parameter '" <> key <> "'"
    InvalidFormat(key, raw, expected) ->
      "Invalid parameter '"
      <> key
      <> "': expected "
      <> expected
      <> ", got '"
      <> raw
      <> "'"
  }
}

// --- CORE PATH PARAMETER EXTRACTORS ---

/// Extracts a string parameter from a dictionary.
/// Returns `Error(NotFound(key))` if the key is missing.
pub fn string(
  from params: Dict(String, String),
  key key: String,
) -> Result(String, ExtractError) {
  case dict.get(params, key) {
    Ok(val) -> Ok(val)
    Error(Nil) -> Error(NotFound(key))
  }
}

/// Extracts a non-empty string parameter from a dictionary.
/// Returns `Error(NotFound(key))` if the key is missing, or
/// `Error(InvalidFormat(key, val, "non-empty string"))` if the trimmed value is empty.
pub fn non_empty_string(
  from params: Dict(String, String),
  key key: String,
) -> Result(String, ExtractError) {
  case string(params, key) {
    Ok(val) -> {
      case string.trim(val) {
        "" -> Error(InvalidFormat(key, val, "non-empty string"))
        _ -> Ok(val)
      }
    }
    Error(err) -> Error(err)
  }
}

/// Extracts and parses an integer parameter from a dictionary.
/// Returns `Error(NotFound(key))` if missing, or `Error(InvalidFormat(key, val, "integer"))`
/// if parsing fails.
pub fn int(
  from params: Dict(String, String),
  key key: String,
) -> Result(Int, ExtractError) {
  case string(params, key) {
    Ok(val) -> {
      case int.parse(val) {
        Ok(parsed) -> Ok(parsed)
        Error(Nil) -> Error(InvalidFormat(key, val, "integer"))
      }
    }
    Error(err) -> Error(err)
  }
}

/// Extracts and parses a floating-point number from a dictionary.
/// Returns `Error(NotFound(key))` if missing, or `Error(InvalidFormat(key, val, "float"))`
/// if parsing fails.
pub fn float(
  from params: Dict(String, String),
  key key: String,
) -> Result(Float, ExtractError) {
  case string(params, key) {
    Ok(val) -> {
      case float.parse(val) {
        Ok(parsed) -> Ok(parsed)
        Error(Nil) -> Error(InvalidFormat(key, val, "float"))
      }
    }
    Error(err) -> Error(err)
  }
}

/// Extracts and parses a boolean parameter from a dictionary.
/// Recognizes "true", "1", "yes", "t" as `True` and "false", "0", "no", "f" as `False` (case-insensitive).
pub fn bool(
  from params: Dict(String, String),
  key key: String,
) -> Result(Bool, ExtractError) {
  case string(params, key) {
    Ok(val) -> {
      case string.lowercase(val) {
        "true" | "1" | "yes" | "t" -> Ok(True)
        "false" | "0" | "no" | "f" -> Ok(False)
        _ -> Error(InvalidFormat(key, val, "boolean"))
      }
    }
    Error(err) -> Error(err)
  }
}

/// Extracts and validates an RFC 4122 standard UUID (e.g. "123e4567-e89b-12d3-a456-426614174000").
/// Returns lowercase normalized UUID string on success, or `InvalidFormat` on failure.
pub fn uuid(
  from params: Dict(String, String),
  key key: String,
) -> Result(String, ExtractError) {
  case string(params, key) {
    Ok(val) -> {
      case is_valid_uuid(val) {
        True -> Ok(string.lowercase(val))
        False -> Error(InvalidFormat(key, val, "valid RFC 4122 UUID"))
      }
    }
    Error(err) -> Error(err)
  }
}

/// Extracts an ASCII alphanumeric string parameter from a dictionary.
/// Returns `Error(NotFound(key))` if missing, or `Error(InvalidFormat(key, val, "alphanumeric"))`
/// if it contains non-alphanumeric characters or is empty.
pub fn alphanumeric(
  from params: Dict(String, String),
  key key: String,
) -> Result(String, ExtractError) {
  case string(params, key) {
    Ok(val) -> {
      case is_alphanumeric(val) {
        True -> Ok(val)
        False -> Error(InvalidFormat(key, val, "alphanumeric"))
      }
    }
    Error(err) -> Error(err)
  }
}

/// Extracts a parameter and applies a custom parser function.
pub fn custom(
  from params: Dict(String, String),
  key key: String,
  expected expected_name: String,
  parser parse_fn: fn(String) -> Result(a, Nil),
) -> Result(a, ExtractError) {
  case string(params, key) {
    Ok(val) -> {
      case parse_fn(val) {
        Ok(parsed) -> Ok(parsed)
        Error(Nil) -> Error(InvalidFormat(key, val, expected_name))
      }
    }
    Error(err) -> Error(err)
  }
}

// --- OPTIONAL & FALLBACK EXTRACTORS ---

/// Extracts an optional string. Returns `None` if the key is missing.
pub fn optional_string(
  from params: Dict(String, String),
  key key: String,
) -> Option(String) {
  dict.get(params, key) |> option.from_result
}

/// Extracts an optional integer. Returns `Ok(None)` if missing, `Ok(Some(Int))` if valid,
/// or `Error(InvalidFormat)` if present but malformed.
pub fn optional_int(
  from params: Dict(String, String),
  key key: String,
) -> Result(Option(Int), ExtractError) {
  case dict.get(params, key) {
    Ok(val) -> {
      case int.parse(val) {
        Ok(i) -> Ok(Some(i))
        Error(Nil) -> Error(InvalidFormat(key, val, "integer"))
      }
    }
    Error(Nil) -> Ok(None)
  }
}

/// Extracts an optional float. Returns `Ok(None)` if missing, `Ok(Some(Float))` if valid,
/// or `Error(InvalidFormat)` if present but malformed.
pub fn optional_float(
  from params: Dict(String, String),
  key key: String,
) -> Result(Option(Float), ExtractError) {
  case dict.get(params, key) {
    Ok(val) -> {
      case float.parse(val) {
        Ok(f) -> Ok(Some(f))
        Error(Nil) -> Error(InvalidFormat(key, val, "float"))
      }
    }
    Error(Nil) -> Ok(None)
  }
}

/// Extracts an optional boolean. Returns `Ok(None)` if missing, `Ok(Some(Bool))` if valid,
/// or `Error(InvalidFormat)` if present but malformed.
pub fn optional_bool(
  from params: Dict(String, String),
  key key: String,
) -> Result(Option(Bool), ExtractError) {
  case dict.get(params, key) {
    Ok(val) -> {
      case string.lowercase(val) {
        "true" | "1" | "yes" | "t" -> Ok(Some(True))
        "false" | "0" | "no" | "f" -> Ok(Some(False))
        _ -> Error(InvalidFormat(key, val, "boolean"))
      }
    }
    Error(Nil) -> Ok(None)
  }
}

/// Extracts an optional UUID. Returns `Ok(None)` if missing, `Ok(Some(UUID))` if valid,
/// or `Error(InvalidFormat)` if present but malformed.
pub fn optional_uuid(
  from params: Dict(String, String),
  key key: String,
) -> Result(Option(String), ExtractError) {
  case dict.get(params, key) {
    Ok(val) -> {
      case is_valid_uuid(val) {
        True -> Ok(Some(string.lowercase(val)))
        False -> Error(InvalidFormat(key, val, "valid RFC 4122 UUID"))
      }
    }
    Error(Nil) -> Ok(None)
  }
}

/// Returns the string value for `key`, or `default` if the key does not exist.
pub fn string_or(
  from params: Dict(String, String),
  key key: String,
  default default_val: String,
) -> String {
  dict.get(params, key) |> result.unwrap(default_val)
}

/// Returns the parsed integer value for `key`, or `default` if missing or malformed.
pub fn int_or(
  from params: Dict(String, String),
  key key: String,
  default default_val: Int,
) -> Int {
  case int(params, key) {
    Ok(val) -> val
    Error(_) -> default_val
  }
}

/// Returns the parsed boolean value for `key`, or `default` if missing or malformed.
pub fn bool_or(
  from params: Dict(String, String),
  key key: String,
  default default_val: Bool,
) -> Bool {
  case bool(params, key) {
    Ok(val) -> val
    Error(_) -> default_val
  }
}

// --- ERGONOMIC "USE" SYNTAX HELPERS ---

/// Ergonomic extractor for `use` syntax requiring a string parameter.
pub fn require_string(
  from params: Dict(String, String),
  key key: String,
  or on_error: fn(ExtractError) -> output,
  apply next: fn(String) -> output,
) -> output {
  case string(params, key) {
    Ok(val) -> next(val)
    Error(err) -> on_error(err)
  }
}

/// Ergonomic extractor for `use` syntax requiring a non-empty string parameter.
pub fn require_non_empty_string(
  from params: Dict(String, String),
  key key: String,
  or on_error: fn(ExtractError) -> output,
  apply next: fn(String) -> output,
) -> output {
  case non_empty_string(params, key) {
    Ok(val) -> next(val)
    Error(err) -> on_error(err)
  }
}

/// Ergonomic extractor for `use` syntax requiring an integer parameter.
pub fn require_int(
  from params: Dict(String, String),
  key key: String,
  or on_error: fn(ExtractError) -> output,
  apply next: fn(Int) -> output,
) -> output {
  case int(params, key) {
    Ok(val) -> next(val)
    Error(err) -> on_error(err)
  }
}

/// Ergonomic extractor for `use` syntax requiring a float parameter.
pub fn require_float(
  from params: Dict(String, String),
  key key: String,
  or on_error: fn(ExtractError) -> output,
  apply next: fn(Float) -> output,
) -> output {
  case float(params, key) {
    Ok(val) -> next(val)
    Error(err) -> on_error(err)
  }
}

/// Ergonomic extractor for `use` syntax requiring a boolean parameter.
pub fn require_bool(
  from params: Dict(String, String),
  key key: String,
  or on_error: fn(ExtractError) -> output,
  apply next: fn(Bool) -> output,
) -> output {
  case bool(params, key) {
    Ok(val) -> next(val)
    Error(err) -> on_error(err)
  }
}

/// Ergonomic extractor for `use` syntax requiring a valid RFC 4122 UUID.
pub fn require_uuid(
  from params: Dict(String, String),
  key key: String,
  or on_error: fn(ExtractError) -> output,
  apply next: fn(String) -> output,
) -> output {
  case uuid(params, key) {
    Ok(val) -> next(val)
    Error(err) -> on_error(err)
  }
}

/// Ergonomic extractor for `use` syntax requiring a custom parsed type.
pub fn require_custom(
  from params: Dict(String, String),
  key key: String,
  expected expected_name: String,
  parser parse_fn: fn(String) -> Result(a, Nil),
  or on_error: fn(ExtractError) -> output,
  apply next: fn(a) -> output,
) -> output {
  case custom(params, key, expected_name, parse_fn) {
    Ok(val) -> next(val)
    Error(err) -> on_error(err)
  }
}

// --- QUERY STRING EXTRACTORS ---

/// Parses query parameters from a `Request` into a dictionary.
/// Returns an empty dictionary if the request has no query string.
pub fn query_params(request: Request(a)) -> Dict(String, String) {
  case request.query {
    Some(q) -> {
      uri.parse_query(q)
      |> result.unwrap([])
      |> dict.from_list
    }
    None -> dict.new()
  }
}

/// Extracts a string query parameter from a request.
pub fn query_string(
  from request: Request(a),
  key key: String,
) -> Result(String, ExtractError) {
  string(query_params(request), key)
}

/// Extracts and parses an integer query parameter from a request.
pub fn query_int(
  from request: Request(a),
  key key: String,
) -> Result(Int, ExtractError) {
  int(query_params(request), key)
}

/// Extracts and parses a boolean query parameter from a request.
pub fn query_bool(
  from request: Request(a),
  key key: String,
) -> Result(Bool, ExtractError) {
  bool(query_params(request), key)
}

// --- INTERNAL HELPERS ---

fn is_valid_uuid(val: String) -> Bool {
  case string.length(val) == 36 {
    False -> False
    True -> {
      case string.split(val, "-") {
        [p1, p2, p3, p4, p5] -> {
          string.length(p1) == 8
          && string.length(p2) == 4
          && string.length(p3) == 4
          && string.length(p4) == 4
          && string.length(p5) == 12
          && is_hex_string(p1)
          && is_hex_string(p2)
          && is_hex_string(p3)
          && is_hex_string(p4)
          && is_hex_string(p5)
        }
        _ -> False
      }
    }
  }
}

fn is_hex_string(str: String) -> Bool {
  string.to_graphemes(str)
  |> list.all(is_hex_char)
}

fn is_hex_char(g: String) -> Bool {
  case g {
    "0"
    | "1"
    | "2"
    | "3"
    | "4"
    | "5"
    | "6"
    | "7"
    | "8"
    | "9"
    | "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F" -> True
    _ -> False
  }
}

// --- ROUTE GUARD PREDICATES ---

/// Pure guard predicate: returns `True` if the string segment parses as an integer.
pub fn is_int(val: String) -> Bool {
  case int.parse(val) {
    Ok(_) -> True
    Error(Nil) -> False
  }
}

/// Pure guard predicate: returns `True` if the string segment parses as a float.
pub fn is_float(val: String) -> Bool {
  case float.parse(val) {
    Ok(_) -> True
    Error(Nil) -> False
  }
}

/// Pure guard predicate: returns `True` if the string segment is a valid RFC 4122 UUID.
pub fn is_uuid(val: String) -> Bool {
  is_valid_uuid(val)
}

/// Pure guard predicate: returns `True` if the trimmed string segment is non-empty.
pub fn is_non_empty(val: String) -> Bool {
  case string.trim(val) {
    "" -> False
    _ -> True
  }
}

/// Pure guard predicate: returns `True` if the string segment is a boolean literal ("true", "false", "1", "0").
pub fn is_bool(val: String) -> Bool {
  case string.lowercase(val) {
    "true" | "false" | "1" | "0" | "yes" | "no" | "t" | "f" -> True
    _ -> False
  }
}

/// Pure guard predicate: returns `True` if the string segment contains only ASCII alphanumeric characters (`a-z`, `A-Z`, `0-9`).
pub fn is_alphanumeric(val: String) -> Bool {
  case val {
    "" -> False
    _ -> {
      string.to_graphemes(val)
      |> list.all(is_alphanumeric_char)
    }
  }
}

fn is_alphanumeric_char(char: String) -> Bool {
  case char {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "a"
    | "b"
    | "c"
    | "d"
    | "e"
    | "f"
    | "g"
    | "h"
    | "i"
    | "j"
    | "k"
    | "l"
    | "m"
    | "n"
    | "o"
    | "p"
    | "q"
    | "r"
    | "s"
    | "t"
    | "u"
    | "v"
    | "w"
    | "x"
    | "y"
    | "z" -> True
    "A"
    | "B"
    | "C"
    | "D"
    | "E"
    | "F"
    | "G"
    | "H"
    | "I"
    | "J"
    | "K"
    | "L"
    | "M"
    | "N"
    | "O"
    | "P"
    | "Q"
    | "R"
    | "S"
    | "T"
    | "U"
    | "V"
    | "W"
    | "X"
    | "Y"
    | "Z" -> True
    _ -> False
  }
}
