import fist
import gleam/dict
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/json
import gleam/list
import gleam/otp/actor
import gleam/result

pub type Todo {
  Todo(id: Int, title: String, completed: Bool)
}

pub type Message {
  GetAll(reply: process.Subject(List(Todo)))
  Add(title: String)
  Remove(id: Int)
}

fn start_db() {
  let assert Ok(actor) =
    actor.new([])
    |> actor.on_message(todo_handle)
    |> actor.start
  actor.data
}

fn todo_handle(todos: List(Todo), msg: Message) {
  case msg {
    GetAll(client) -> {
      process.send(client, todos)
      actor.continue(todos)
    }
    Add(title) -> {
      let new_id = list.length(todos)
      let new_todo = Todo(new_id, title, False)
      actor.continue([new_todo, ..todos])
    }
    Remove(id) -> {
      let filtered = list.filter(todos, fn(t) { t.id != id })
      actor.continue(filtered)
    }
  }
}

pub fn main() {
  let db = start_db()
  fist.new()
  |> fist.get("/todos", fn(_req, _params) {
    let todos = process.call(db, 100, sending: GetAll)

    let json_body =
      json.array(todos, fn(t: Todo) {
        json.object([
          #("id", json.int(t.id)),
          #("title", json.string(t.title)),
          #("completed", json.bool(t.completed)),
        ])
      })
      |> json.to_string

    fist.json(json_body)
  })
  |> fist.route(http.Post, path: "/todos", handler: fn(req, _params) {
    // take query params from requisition
    let title =
      fist.get_query(req)
      |> dict.get("title")
      |> result.unwrap("New Task")
      |> Add
    process.send(db, title)
    fist.ok("Task add")
  })
  |> fist.route(method: http.Delete, path: "/todos", handler: fn(req, _params) {
    let id =
      fist.get_query(req)
      |> dict.get("id")
      |> result.unwrap("No id provided")
      |> int.parse
      |> result.unwrap(0)
    process.send(db, Remove(id))
    fist.ok("Task removed")
  })
  |> fist.map(fist.render_mist)
  |> fist.start(8080)
}
