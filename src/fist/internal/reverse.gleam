import fist/internal/types.{
  type Node, type RouteTemplate, type Router, type TemplateSegment,
  DynamicSegment, RouteTemplate, Router, StaticSegment, WildcardSegment,
  empty_node,
}
import gleam/dict.{type Dict}
import gleam/http.{type Method}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

/// Compares two lists of template segments to check if they have identical path structures.
pub fn same_segment_shapes(
  a: List(TemplateSegment),
  b: List(TemplateSegment),
) -> Bool {
  case a, b {
    [], [] -> True
    [StaticSegment(sa), ..rest_a], [StaticSegment(sb), ..rest_b] if sa == sb ->
      same_segment_shapes(rest_a, rest_b)
    [DynamicSegment(pa, _), ..rest_a], [DynamicSegment(pb, _), ..rest_b]
      if pa == pb
    -> same_segment_shapes(rest_a, rest_b)
    [WildcardSegment(wa), ..rest_a], [WildcardSegment(wb), ..rest_b]
      if wa == wb
    -> same_segment_shapes(rest_a, rest_b)
    _, _ -> False
  }
}

/// Converts a list of template segments into a human-readable path string (e.g. "/users/:id/profile").
pub fn segments_to_string(segments: List(TemplateSegment)) -> String {
  case segments {
    [] -> "/"
    _ -> {
      let parts =
        list.map(segments, fn(seg) {
          case seg {
            StaticSegment(s) -> s
            DynamicSegment(name, _) -> ":" <> name
            WildcardSegment(name) -> "*" <> name
          }
        })
      "/" <> string.join(parts, "/")
    }
  }
}

/// Extracts reverse-routable template segments by walking raw path segments alongside the Trie.
pub fn extract_template_segments(
  segments: List(String),
  current_node: Node(req, ctx, out),
) -> List(TemplateSegment) {
  case segments {
    [] -> []

    ["*" <> param_name, ..] -> {
      let name = case param_name {
        "" -> "wildcard"
        _ -> param_name
      }
      [WildcardSegment(name)]
    }

    [":" <> param_name, ..rest] -> {
      let matching_branch =
        list.find(current_node.dynamic_children, fn(branch) {
          branch.param_name == param_name
        })

      let #(guard, next_node) = case matching_branch {
        Ok(branch) -> #(branch.guard, branch.child)
        Error(Nil) -> #(None, empty_node())
      }

      [
        DynamicSegment(name: param_name, guard: guard),
        ..extract_template_segments(rest, next_node)
      ]
    }

    [segment, ..rest] -> {
      let next_node =
        dict.get(current_node.static_children, segment)
        |> result.unwrap(empty_node())

      [StaticSegment(segment), ..extract_template_segments(rest, next_node)]
    }
  }
}

/// Assigns a unique name to the last added route in the router.
///
/// If the same name is registered to the exact same path template (e.g. for multiple HTTP methods
/// sharing a canonical resource URL), the registration is accepted idempotently.
/// If the name is registered to a conflicting path template, it panics immediately.
pub fn name_route(
  router: Router(req, ctx, out),
  name: String,
) -> Router(req, ctx, out) {
  case string.trim(name) {
    "" -> panic as "Invalid route name: route name cannot be empty"
    _ -> Nil
  }

  case router.last_added {
    None ->
      panic as "Invalid route name: fist.name must be called immediately after registering a route"

    Some(#(method, segments)) -> {
      let root_node =
        dict.get(router.routes, method) |> result.unwrap(empty_node())
      let template_segments = extract_template_segments(segments, root_node)

      case dict.get(router.named_routes, name) {
        Ok(existing) -> {
          case same_segment_shapes(existing.segments, template_segments) {
            True -> router
            False ->
              panic as string.concat([
                  "Route name collision: route '",
                  name,
                  "' is already registered to a different path '",
                  segments_to_string(existing.segments),
                  "', cannot redefine as '",
                  segments_to_string(template_segments),
                  "'",
                ])
          }
        }
        Error(Nil) -> {
          let template =
            RouteTemplate(
              name: name,
              method: method,
              segments: template_segments,
            )
          let updated_named = dict.insert(router.named_routes, name, template)
          Router(..router, named_routes: updated_named)
        }
      }
    }
  }
}

/// Updates guards in named route templates if `fist.guard` is called after `fist.name`.
pub fn update_template_guard(
  named_routes: Dict(String, RouteTemplate),
  target_method: Method,
  last_added_segments: List(String),
  target_param: String,
  predicate: fn(String) -> Bool,
) -> Dict(String, RouteTemplate) {
  dict.map_values(named_routes, fn(_, template) {
    case
      template.method == target_method
      && matches_segments(template.segments, last_added_segments)
    {
      True -> {
        let updated_segments =
          list.map(template.segments, fn(seg) {
            case seg {
              DynamicSegment(name, prev_guard) if name == target_param -> {
                let new_guard = case prev_guard {
                  Some(prev) -> fn(s) { prev(s) && predicate(s) }
                  None -> predicate
                }
                DynamicSegment(name, Some(new_guard))
              }
              other -> other
            }
          })
        RouteTemplate(..template, segments: updated_segments)
      }
      False -> template
    }
  })
}

fn matches_segments(
  template_segments: List(TemplateSegment),
  raw_segments: List(String),
) -> Bool {
  case template_segments, raw_segments {
    [], [] -> True
    [StaticSegment(a), ..rest_t], [b, ..rest_r] if a == b ->
      matches_segments(rest_t, rest_r)
    [DynamicSegment(a, _), ..rest_t], [":" <> b, ..rest_r] if a == b ->
      matches_segments(rest_t, rest_r)
    [WildcardSegment(a), ..], ["*" <> b, ..] if a == b -> True
    _, _ -> False
  }
}

/// Prefixes a route template with prefix segments.
pub fn prefix_template(
  prefix_segments: List(String),
  template: RouteTemplate,
) -> RouteTemplate {
  let prefix_template_segs =
    list.map(prefix_segments, fn(seg) {
      case seg {
        ":" <> p -> DynamicSegment(name: p, guard: None)
        s -> StaticSegment(s)
      }
    })

  RouteTemplate(
    ..template,
    segments: list.append(prefix_template_segs, template.segments),
  )
}

/// Merges named routes on `fist.mount`, prefixing each template and detecting collisions.
pub fn mount_named_routes(
  parent_named: Dict(String, RouteTemplate),
  sub_named: Dict(String, RouteTemplate),
  prefix_segments: List(String),
) -> Dict(String, RouteTemplate) {
  dict.to_list(sub_named)
  |> list.fold(parent_named, fn(acc, pair) {
    let #(name, template) = pair
    let prefixed = prefix_template(prefix_segments, template)
    case dict.get(acc, name) {
      Ok(existing) -> {
        case same_segment_shapes(existing.segments, prefixed.segments) {
          True -> acc
          False ->
            panic as string.concat([
                "Route name collision on mount: route '",
                name,
                "' is already registered to '",
                segments_to_string(existing.segments),
                "' in parent, cannot mount as '",
                segments_to_string(prefixed.segments),
                "'",
              ])
        }
      }
      Error(Nil) -> dict.insert(acc, name, prefixed)
    }
  })
}

/// Combines named routes on `fist.merge`, detecting collisions.
pub fn merge_named_routes(
  a_named: Dict(String, RouteTemplate),
  b_named: Dict(String, RouteTemplate),
) -> Dict(String, RouteTemplate) {
  dict.to_list(b_named)
  |> list.fold(a_named, fn(acc, pair) {
    let #(name, template) = pair
    case dict.get(acc, name) {
      Ok(existing) -> {
        case same_segment_shapes(existing.segments, template.segments) {
          True -> acc
          False ->
            panic as string.concat([
                "Route name collision on merge: route '",
                name,
                "' is registered to conflicting paths ('",
                segments_to_string(existing.segments),
                "' vs '",
                segments_to_string(template.segments),
                "')",
              ])
        }
      }
      Error(Nil) -> dict.insert(acc, name, template)
    }
  })
}
