# Core Concepts & Behavior

Understanding how Fist processes requests, executes guards, and generates reverse paths will help you design predictable, secure, and high-performance APIs.

---

## 1. The Radix Trie Engine

At its core, Fist uses a **Radix Trie** (Prefix Tree) to store and match route patterns:

- **Algorithmic Efficiency:** Routing lookup time is `O(k)` relative to the number of segments `k` in the request path, remaining constant regardless of whether your application registers 10 or 10,000 routes.
- **Segment-Based Tree:** Each URL path is tokenized by forward slashes (`/`), where each segment represents a node in the tree.
- **Polymorphic Sibling Dynamic Children:** Unlike simplistic radix trees that restrict a node to at most one dynamic parameter child, Fist supports multiple dynamic branches per node, disambiguated by route guards and declared priority order.

---

## 2. Path Normalization & Defensive Security (RFC 3986)

Before traversing the Trie, Fist sanitizes and canonicalizes incoming paths according to **RFC 3986 Section 5.2.4**:

- **Dot-Segment Resolution (`remove_dot_segments`):**
  - Single dots (`.`) representing the current directory are stripped: `/api/./v1/users` → `/api/v1/users`.
  - Double dots (`..`) representing parent directory traversal are resolved: `/static/css/../js/bundle.js` → `/static/js/bundle.js`.
  - Traversals attempting to escape above root are clamped safely at root: `/../../secret` → `/secret`.
- **Encoded Traversal Protection:** Percent-encoded dots (`%2e%2e` and `%2e`) are decoded before path canonicalization, neutralizing Web Application Firewall (WAF) evasion attacks.
- **Backslash Canonicalization:** Windows-style backslashes (`\`) are normalized to standard forward slashes (`/`), preventing OS-dependent traversal bypasses.
- **Null-Byte Stripping:** Injected null bytes (`\0` and `%00`) are removed to prevent string truncation vulnerabilities in downstream filesystem calls or native C drivers.
- **Slashes & Case:**
  - Trailing slashes are normalized: `/users` and `/users/` resolve to the same route.
  - Duplicate slashes are collapsed: `//api///v1` becomes `/api/v1` (preventing open-redirect and SSRF parsing confusion).
  - Routing is **case-sensitive**: `/Users` is distinct from `/users`.
- **Automatic Decoding:** Dynamic parameter tokens and wildcard captures are percent-decoded on ingress (e.g., `/user/João` extracts `"João"`, `/tags/c%2B%2B` extracts `"c++"`).
- **Query String & Fragment Decoupling:** Query strings (`?query=1`) and fragment identifiers (`#hash`) are stripped before Trie matching and can be parsed independently via `fist/extract`.

---

## 3. Precedence & Priority

When an incoming URL could theoretically match multiple registered routes, Fist resolves conflicts using a deterministic 4-tier hierarchy:

> **Precedence Hierarchy:**
>
> **`Static`** &nbsp;>&nbsp; **`Guarded Dynamic`** &nbsp;>&nbsp; **`Unguarded Dynamic`** &nbsp;>&nbsp; **`Wildcard (*param)`**

### Deterministic Sibling Resolution

When a node contains multiple dynamic children (e.g. `:id` with an integer guard alongside generic `:username`):

1. **Guards First:** Children equipped with guard predicates (`fist.guard`) take precedence over unguarded children.
2. **Order of Declaration:** Among children with equal guard status, evaluation proceeds in the order they were registered.
3. **Dynamic Fallthrough (Backtracking):** If an incoming request matches a dynamic segment token, but that token fails the branch's guard predicate, Fist does **not** fail with 404 immediately. It seamlessly falls through to the next candidate sibling branch.

### Step-by-Step Traversal Example

Consider a router configured with these routes:

```gleam
fist.new()
|> fist.get("/posts/new", new_post_handler)                  // Tier 1: Static
|> fist.get("/posts/:id", show_post_by_id)                   // Tier 2: Guarded Dynamic
|> fist.guard("id", when: extract.is_int)
|> fist.get("/posts/:slug", show_post_by_slug)               // Tier 3: Unguarded Dynamic
|> fist.get("/posts/*rest", catch_all_handler)               // Tier 4: Wildcard
```

Fist resolves requests as follows:

1. **Request `GET /posts/new`:**
   - Matches the exact static segment `/new`. Handled by `new_post_handler`.

2. **Request `GET /posts/42`:**
   - `/42` does not match static `/new`.
   - Evaluates guarded branch `:id`. `extract.is_int("42")` returns `True`. Handled by `show_post_by_id` with `params = [#("id", "42")]`.

3. **Request `GET /posts/announcements`:**
   - `/announcements` does not match static `/new`.
   - Evaluates guarded branch `:id`. `extract.is_int("announcements")` returns `False`.
   - **Fallthrough:** Fist falls through to the unguarded `:slug` branch. Handled by `show_post_by_slug` with `params = [#("slug", "announcements")]`.

4. **Request `GET /posts/2026/archive`:**
   - Multi-segment path. Neither `/posts/new`, `/posts/:id`, nor `/posts/:slug` can consume two segments.
   - Matches the wildcard catch-all `*rest`. Handled by `catch_all_handler` with `params = [#("rest", "2026/archive")]`.

5. **Ancestor Wildcard Backtracking:**
   - Suppose a request arrives for `GET /posts/new/download`.
   - The engine follows the static branch to `/posts/new`, but finds no child segment named `/download`.
   - Instead of failing with 404, Fist **backtracks** up the tree to the `/posts` node and checks for an ancestor wildcard catch-all.
   - It successfully delegates the request to `*rest` with `rest = "new/download"`.

---

## 4. Route Guards & Fallthrough Engine

Route guards are pure Gleam predicate functions `fn(String) -> Bool` evaluated against raw parameter tokens during path matching.

- **Logical Conjunction Chaining:** Attaching multiple guards to the same parameter combines them with short-circuiting logical `AND` (`prev(s) && next(s)`):

  ```gleam
  router
  |> fist.get("/accounts/:id", handler)
  |> fist.guard("id", when: extract.is_int)
  |> fist.guard("id", when: fn(s) { string.length(s) >= 4 })
  ```

- **Fail-Fast Route Attachment:**
  - Calling `fist.guard` without an immediately preceding route definition panics immediately at startup.
  - Calling `fist.guard` with a parameter name that does not exist in the preceding route path (e.g. guarding `"uuid"` on path `/users/:id`) panics immediately with a descriptive error.

- **Built-in Predicates (`fist/extract`):**
  Fist provides zero-allocation validation helpers:
  - `extract.is_int`: Validates string parses to signed integer.
  - `extract.is_float`: Validates string parses to valid floating-point number.
  - `extract.is_bool`: Matches `"true"`, `"false"`, `"1"`, `"0"`.
  - `extract.is_uuid`: Validates 36-char canonical RFC 4122 UUID formatting (`8-4-4-4-12`).
  - `extract.is_alphanumeric`: Validates ASCII alphanumeric chars (`a-z`, `A-Z`, `0-9`).
  - `extract.is_non_empty`: Validates non-empty, non-whitespace strings.
  - `extract.is_regex`: Evaluates against compiled regular expressions.

---

## 5. Reverse Routing & Bidirectional Soundness

Reverse routing translates semantic route identifiers and parameters back into canonical URL paths via `fist.path` or `fist.path_from`.

### Bidirectional Soundness Invariant

A web router should never generate a URL that its own routing engine would reject or misroute. Fist enforces **Bidirectional Soundness**:

- When generating a URL with `fist.path`, all guard predicates associated with the route template are evaluated against the supplied parameter values.
- If a parameter violates its guard (e.g. passing `"admin"` to an `:id` parameter guarded by `is_int`), URL generation aborts immediately, returning `Error(InvalidParameter(route, param, value))`.
- This prevents bugs where redirects or template links lead to 404 or misrouted responses.

### Parameter Encoding & Path Injection Defense

- **Dynamic Segments (`:param`):** Parameter values are percent-encoded using RFC 3986 rules (`uri.percent_encode`). Injected forward slashes (`/`) become `%2F`. This guarantees that user input cannot alter the segment structure of the URL or escape to other routes.
- **Wildcard Segments (`*param`):** Wildcard values split on `/`, encode each component independently, and rejoin with `/`. Valid multi-level paths (e.g. `docs/guide 2026.pdf`) become `docs/guide%202026.pdf`, preserving path separators without allowing unencoded dangerous characters.
- **Empty Parameter Rejection:** Dynamic parameter segments and wildcard values cannot be empty strings (`""`). Passing `with: [#("id", "")]` returns `Error(InvalidParameter(route: "...", param: "id", value: ""))`, preventing the generation of broken double-slash URLs (e.g. `/users//settings`).

### Query Parameter Auto-Serialization

Any parameters passed in the `with` argument that are **not** consumed by path segments (`:param` or `*param`) are automatically formatted as standard URL query parameters (RFC 3986):

```gleam
fist.path(router, for: "search", with: [
  #("category", "books"),
  #("q", "gleam"),
  #("page", "2"),
])
// Yields: Ok("/search/books?q=gleam&page=2")
```

---

## 6. Route Names, Collisions & Idempotency Rules

Fist enforces strict rules around route naming to eliminate ambiguity:

### 1. Route Name Collisions on Conflicting Paths

If two different path patterns are assigned the same name, Fist panics immediately at startup:

```gleam
// 💥 Panics: Route name collision: route 'profile' is already registered to '/users/:id', cannot redefine as '/orgs/:id'
router
|> fist.get("/users/:id", get_user)
|> fist.name("profile")
|> fist.get("/orgs/:id", get_org)
|> fist.name("profile")
```

### 2. Idempotent Name Sharing Across HTTP Methods

In RESTful architectures, multiple HTTP methods often share the exact same resource path (e.g. `GET /users/:id` and `PUT /users/:id`).

- If the path template segments and guards are structurally identical, assigning the same route name to both methods is accepted **idempotently** without panic.
- `fist.path(router, for: "user", with: [#("id", "10")])` resolves to `/users/10`.

### 3. Route Aliases

Assigning multiple names to the same route is fully supported:

```gleam
router
|> fist.get("/members/:id", show_member)
|> fist.name("member_show")
|> fist.name("user_show")
```

Both `member_show` and `user_show` resolve to `/members/:id`.

### 4. Mount and Merge Collision Detection

- **Mount Collisions:** When mounting a sub-router with `fist.mount(parent, "/prefix", sub, ...)`, Fist prefixes all child route names and checks for collisions with the parent. If a child name already exists in the parent under a different path, Fist panics immediately.
- **Merge Collisions:** When combining routers with `fist.merge(a, b)`, if a route name exists in both routers:
  - If they point to identical paths, the merge is accepted idempotently.
  - If they point to conflicting paths, Fist panics immediately.

---

## 7. Middleware Execution & Static Wrapping

Middlewares in Fist use **Static Wrapping** rather than dynamic runtime dispatch:

- **Compile-Time / Initialization-Time Wrapping:** When you call `fist.wrap` or `fist.group(..., with: [mw1, mw2])`, middleware closures wrap the handlers directly in the Trie at router definition time.
- **Zero Lookup Overhead:** During request dispatch, Trie matching executes directly to the pre-wrapped handler with zero intermediate list traversal overhead.
- **Execution Order (Outside-In):** Middlewares execute in natural declaration order:
  1. `mw1` executes pre-processing (request phase).
  2. `mw2` executes pre-processing.
  3. The route handler executes business logic and returns a response.
  4. `mw2` executes post-processing (response phase, headers, timing).
  5. `mw1` executes post-processing.
- **Early Termination (Short-Circuiting):** Any middleware can return a response directly without invoking `next(req, ctx, params)`. For example, an authentication middleware can return HTTP 401 immediately, safely bypassing inner middlewares and the handler.

---

## 8. Common Pitfalls & How Fist Reacts

Here is how Fist defends against common mistakes and edge-case errors:

| Mistake / Edge Case | Fist Behavior | How to Resolve |
| :--- | :--- | :--- |
| **Orphan `fist.guard` call** (calling `guard` without preceding route) | 💥 Immediate panic at startup: `Invalid guard: fist.guard must be called immediately after registering a route` | Place `fist.guard` immediately after the route definition. |
| **Unknown parameter in guard** (guarding a param name that isn't in the path) | 💥 Immediate panic: `Invalid guard: parameter ':uuid' not found in the last added route path` | Ensure the parameter name in `fist.guard` matches the `:param` token. |
| **Empty route name** (`fist.name("")` or `fist.name("  ")`) | 💥 Immediate panic: `Invalid route name: route name cannot be empty` | Provide a meaningful non-empty string identifier. |
| **Orphan `fist.name` call** (calling `name` without preceding route) | 💥 Immediate panic: `Invalid route name: fist.name must be called immediately after registering a route` | Place `fist.name` immediately after the route definition. |
| **Incomplete Registry Extraction** (calling `fist.path_registry(sub)` *before* `fist.mount`) | Generates paths without the mount prefix (e.g. `/items/42` instead of `/api/v1/items/42`). | **Golden Rule:** Always extract `fist.path_registry(root_router)` from your final root router after all `mount` and `merge` operations are complete. |
| **Empty dynamic parameter value** (`with: [#("id", "")]`) | Returns `Error(InvalidParameter("route", "id", ""))`. Prevents generating broken URLs. | Ensure IDs and tokens are non-empty before calling `fist.path`. |
| **Attempted Path Injection** (`with: [#("id", "1/delete")]`) | Encodes `/` to `%2F` (`/users/1%2Fdelete`). Does not alter route structure. | Handled automatically. The URL remains safe and predictable. |
| **Wildcard in mount prefix** (`fist.mount(r, "/api/*rest", ...)`) | 💥 Immediate panic: Wildcards cannot appear in mount prefixes. | Mount prefixes must only contain static or dynamic segments. |
| **Conflicting dynamic names at same level without guards** | 💥 Immediate panic at startup: Prevents registering ambiguous dynamic branches without disambiguating guards. | Add route guards (e.g. `is_int`) or use consistent parameter names. |
