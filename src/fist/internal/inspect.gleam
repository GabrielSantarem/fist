import fist/internal/types.{type Node, type RouteInfo, type Router, RouteInfo}
import gleam/dict
import gleam/http.{type Method}
import gleam/list
import gleam/option
import gleam/string

pub fn inspect_node(
  node: Node(req_body, ctx, output),
  method: Method,
  path_acc: List(String),
  params_acc: List(String),
) -> List(RouteInfo) {
  let current_info = case node.route {
    option.Some(r) -> [
      RouteInfo(
        method: method,
        path: "/" <> string.join(path_acc, "/"),
        description: option.unwrap(r.description, ""),
        params: params_acc,
      ),
    ]
    option.None -> []
  }

  let static_infos =
    dict.to_list(node.static_children)
    |> list.flat_map(fn(pair) {
      let #(segment, child) = pair
      inspect_node(child, method, list.append(path_acc, [segment]), params_acc)
    })

  let dynamic_infos =
    node.dynamic_children
    |> list.flat_map(fn(branch) {
      inspect_node(
        branch.child,
        method,
        list.append(path_acc, [":" <> branch.param_name]),
        list.append(params_acc, [branch.param_name]),
      )
    })

  let wildcard_infos = case node.wildcard_child {
    option.Some(#(param_name, r)) -> [
      RouteInfo(
        method: method,
        path: "/"
          <> string.join(list.append(path_acc, ["*" <> param_name]), "/"),
        description: option.unwrap(r.description, ""),
        params: list.append(params_acc, [param_name]),
      ),
    ]
    option.None -> []
  }

  list.flatten([current_info, static_infos, dynamic_infos, wildcard_infos])
}

pub fn inspect(router: Router(req_body, ctx, output)) -> List(RouteInfo) {
  dict.to_list(router.routes)
  |> list.flat_map(fn(pair) {
    let #(method, root_node) = pair
    inspect_node(root_node, method, [], [])
  })
}
