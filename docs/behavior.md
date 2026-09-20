# Core Concepts & Behavior

Understanding how Fist processes requests will help you design predictable, secure, and high-performance APIs.

---

## 1. The Radix Trie Engine

At its core, Fist uses a **Radix Trie** (Prefix Tree) to store and match route patterns:

*   **Algorithmic Efficiency:** Routing lookup time is $O(k)$ relative to the number of segments $k$ in the request path, remaining constant regardless of whether your application registers 10 or 10,000 routes.
*   **Segment-Based Tree:** Each URL path is tokenized by forward slashes (`/`), where each segment represents a node in the tree.

---

## 2. Path Normalization & Defensive Security (RFC 3986)

Before traversing the Trie, Fist sanitizes and canonicalizes incoming paths according to **RFC 3986 Section 5.2.4**:

*   **Dot-Segment Resolution (`remove_dot_segments`):**
    *   Single dots (`.`) representing the current directory are stripped: `/api/./v1/users` $\to$ `/api/v1/users`.
    *   Double dots (`..`) representing parent directory traversal are resolved: `/static/css/../js/bundle.js` $\to$ `/static/js/bundle.js`.
    *   Traversals attempting to escape above root are clamped safely at root: `/../../secret` $\to$ `/secret`.
*   **Encoded Traversal Protection:** Percent-encoded dots (`%2e%2e` and `%2e`) are decoded before path canonicalization, neutralizing Web Application Firewall (WAF) evasion attacks.
*   **Backslash Canonicalization:** Windows-style backslashes (`\`) are normalized to standard forward slashes (`/`), preventing OS-dependent traversal bypasses.
*   **Null-Byte Stripping:** Injected null bytes (`\0` and `%00`) are removed to prevent string truncation vulnerabilities in downstream filesystem calls or native C drivers.
*   **Slashes & Case:**
    *   Trailing slashes are normalized: `/users` and `/users/` resolve to the same route.
    *   Duplicate slashes are collapsed: `//api///v1` becomes `/api/v1`.
    *   Routing is **case-sensitive**: `/Users` is distinct from `/users`.
*   **Automatic Decoding:** Dynamic parameter tokens and wildcard captures are percent-decoded (e.g., `/user/Jo%C3%A3o` extracts `"João"`, `/tags/c%2B%2B` extracts `"c++"`).
*   **Query String & Fragment Decoupling:** Query strings (`?query=1`) and fragment identifiers (`#hash`) are stripped before Trie matching and can be parsed independently via `fist/extract`.

---

## 3. Precedence & Priority

When an incoming URL could theoretically match multiple registered routes, Fist resolves conflicts using a deterministic 3-tier hierarchy:

$$\mathbf{Static} \;\;>\;\; \mathbf{Dynamic \; (:param)} \;\;>\;\; \mathbf{Wildcard \; (*param)}$$

### Step-by-Step Traversal Example

Consider a router configured with these three routes:
```gleam
fist.new()
|> fist.get("/posts/new", new_post_handler)       // Tier 1: Static
|> fist.get("/posts/:id", show_post_handler)      // Tier 2: Dynamic
|> fist.get("/posts/*rest", catch_all_handler)    // Tier 3: Wildcard
```

Fist resolves requests as follows:
1.  **Request `GET /posts/new`:**
    *   Matches the exact static segment `/new`. Handled by `new_post_handler`.
2.  **Request `GET /posts/42`:**
    *   `/42` does not match any static child under `/posts`.
    *   Matches the dynamic parameter `:id`. Handled by `show_post_handler` with `params = dict.from_list([#("id", "42")])`.
3.  **Request `GET /posts/2026/archive`:**
    *   Multi-segment path. Neither `/posts/new` nor `/posts/:id` can consume two segments.
    *   Matches the wildcard catch-all `*rest`. Handled by `catch_all_handler` with `params = dict.from_list([#("rest", "2026/archive")])`.
4.  **Automatic Backtracking:**
    *   Suppose a request arrives for `GET /posts/new/download`.
    *   The engine follows the static branch to `/posts/new`, but finds no child segment named `/download`.
    *   Instead of failing immediately with 404, Fist **backtracks** up the tree to the `/posts` node and checks for an ancestor wildcard catch-all.
    *   It successfully delegates the request to `*rest` with `rest = "new/download"`.

---

## 4. Middleware Execution & Static Wrapping

Middlewares in Fist use **Static Wrapping** rather than dynamic runtime dispatch:

*   **Compile-Time / Initialization-Time Wrapping:** When you call `fist.wrap` or `fist.group(..., with: [mw1, mw2])`, middleware closures wrap the handlers directly in the Trie at router definition time.
*   **Zero Lookup Overhead:** During request dispatch, Trie matching executes directly to the pre-wrapped handler with zero intermediate list traversal overhead.
*   **Execution Order (Outside-In):** Middlewares execute in natural declaration order:
    1.  `mw1` executes pre-processing (request phase).
    2.  `mw2` executes pre-processing.
    3.  The route handler executes business logic and returns a response.
    4.  `mw2` executes post-processing (response phase, headers, timing).
    5.  `mw1` executes post-processing.
*   **Early Termination (Short-Circuiting):** Any middleware can return a response directly without invoking `next(req, ctx, params)`. For example, an authentication middleware can return HTTP 401 immediately, safely bypassing inner middlewares and the handler.

---

## 5. Fail-Fast Safety & Collision Protection

Fist adheres to a strict **Fail-Fast** philosophy. Any routing ambiguity, duplicate registration, or conflicting parameter definition causes an **immediate panic at startup**, ensuring configuration errors are caught during test or boot rather than silently in production.

### Duplicate Route Protection
Registering the exact same HTTP method and path twice causes an immediate panic:
```gleam
// 💥 Panics: duplicate route already registered
fist.new()
|> fist.get("/endpoint", handler_v1)
|> fist.get("/endpoint", handler_v2)
```

### Dynamic Parameter Name Consistency
A single Trie node level can only bind one dynamic parameter name. Registering conflicting names at the same level panics:
```gleam
// 💥 Panics: cannot register ':user_id' because ':id' is already registered at this level
fist.new()
|> fist.get("/users/:id/profile", handler_a)
|> fist.get("/users/:user_id/settings", handler_b)
```
*Solution:* Use consistent parameter names across routes (e.g. `/users/:id/profile` and `/users/:id/settings`). When identical names are used, branches merge cleanly.

### Wildcard Invariants
*   **Terminal Only:** A wildcard must always be the final segment in a path. Registering `/files/*path/details` panics.
*   **Minimum Segment Requirement:** A wildcard requires at least one segment to match. A request to `/files` against `/files/*path` returns 404, allowing `/files` to serve a directory listing and `/files/*path` to serve file downloads.
*   **Relative Path Stripping:** Wildcard parameters are formatted without leading slashes (e.g. `"images/photo.png"` instead of `"/images/photo.png"`). Combined with RFC 3986 normalization, this prevents accidental root-escape directory traversal when serving static files.
*   **Mount Prefix Restriction:** Using a wildcard in a mount prefix (e.g. `fist.mount(parent, "/api/*rest", sub, ...)`) panics.
