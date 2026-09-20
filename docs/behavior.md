# Core Concepts & Behavior

Understanding how Fist processes requests will help you design clean APIs and understand its deterministic routing engine.

## The Trie Structure

Fist uses a **Radix Trie** (Prefix Tree) internally:
*   **Performance:** Routing is $O(n)$ relative to the path length, remaining constant regardless of having 10 or 10,000 routes.
*   **Structure:** Paths are split into segments. Each segment corresponds to a node in the tree.

## Path Normalization & Defensive Security (RFC 3986)

Fist automatically normalizes and sanitizes paths before matching:

*   **RFC 3986 Section 5.2.4 (`remove_dot_segments`):**
    *   Single dots (`.`) representing the current directory are removed (`/api/./v1/users` $\to$ `/api/v1/users`).
    *   Double dots (`..`) representing the parent directory are resolved safely (`/static/css/../js/bundle.js` $\to$ `/static/js/bundle.js`).
    *   Traversals attempting to escape above root (`/../../secret`) are clamped at root (`/secret`), preventing directory traversal exploits.
*   **Percent-Encoded Dot Traversals:** Encoded dots (`%2e%2e` and `%2e`) are decoded before dot-segment resolution, eliminating WAF evasion attacks.
*   **Windows Backslash Normalization:** Backslashes (`\`) are normalized to standard forward slashes (`/`), preventing OS-specific traversal bypasses.
*   **Null-Byte Sanitization:** Injected null bytes (`\0` / `%00`) are stripped to protect downstream filesystem and C-based drivers from string truncation exploits.
*   **Trailing Slashes:** `/users` and `/users/` are normalized to the **same route**.
*   **Double Slashes:** `//api///v1` is normalized to `/api/v1`.
*   **Case Sensitivity:** Fist is **Case Sensitive**. `/Users` is distinct from `/users`.
*   **Percent-Encoding:** Parameter values and segments are automatically decoded (e.g., `/user/Jo%C3%A3o` extracts `"João"`, `/search/c%2B%2B` extracts `"c++"`).
*   **Query Strings & Fragments:** Stripped cleanly from path matching (`/users?limit=10#top` matches `/users`).

## Precedence & Priority

When a request URL could potentially match multiple routes, Fist resolves conflicts using a strict 3-tier specificity hierarchy:

$$\mathbf{Static} \;\;>\;\; \mathbf{Dynamic \; (:param)} \;\;>\;\; \mathbf{Wildcard \; (*param)}$$

1.  **Exact Static Match:**
    *   `/posts/new` takes priority over `/posts/:id` and `/posts/*rest`.
2.  **Dynamic Match (`:param`):**
    *   `/users/:id` matches single segments if no static route matches.
3.  **Wildcard Catch-All (`*param`):**
    *   `/static/*filepath` matches all remaining segments if neither static nor dynamic branches match.
4.  **Deep Backtracking:**
    *   If traversal down a static or dynamic branch hits a dead-end without finding a handler, Fist automatically backtracks to ancestor wildcard catch-alls to check for a looser match.

## Fail-Fast Safety & Collision Protection

Fist embraces a strict **Fail-Fast** design philosophy. Ambiguous routes, duplicate endpoints, and conflicting segment names **panic immediately** at startup rather than silently overwriting each other.

### 1. Duplicate Routes Panic
Registering the exact same HTTP method and path twice on a router (or combining them via `fist.merge` or `fist.mount`) causes an immediate runtime panic:

```gleam
// 💥 Panics: duplicate route already registered
fist.new()
|> fist.get("/endpoint", handler_v1)
|> fist.get("/endpoint", handler_v2)
```

### 2. Conflicting Dynamic Parameter Names Panic
Because a Radix Trie node can only bind one dynamic parameter name per level, defining different names at the same level panics:

```gleam
// 💥 Panics: cannot register ':user_id' because ':id' is already registered at this level
fist.new()
|> fist.get("/users/:id/profile", handler_a)
|> fist.get("/users/:user_id/settings", handler_b)
```

**✅ Solution:** Use consistent parameter names (`/users/:id/profile` and `/users/:id/settings`). When identical names are used, branches merge cleanly.

### 3. Wildcard Rules & Invariants

*   **Terminal Position:** A wildcard must be the final segment in a path. Registering `/files/*path/details` panics.
*   **Minimum Segment Requirement:** A wildcard requires at least one segment to match. Requesting `/files` against `/files/*path` yields 404, allowing `/files` to serve a directory listing and `/files/*path` to serve file downloads.
*   **No Leading Slash:** The captured string is clean and relative (e.g. `"images/photo.png"` instead of `"/images/photo.png"`). Combined with RFC 3986 normalization, this completely eliminates path traversal risks when serving files.
*   **Prefix Mounting Restriction:** Using a wildcard inside a mount prefix (e.g. `fist.mount(parent, "/api/*rest", sub, ...)`) panics.
