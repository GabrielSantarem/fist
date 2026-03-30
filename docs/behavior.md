# Core Concepts & Behavior

Understanding how Fist processes requests will help you design better APIs and avoid common pitfalls.

## The Trie Structure

Fist uses a **Radix Trie** (Prefix Tree) internally.
*   **Performance:** Routing is $O(n)$ relative to the path length, meaning it stays fast regardless of having 10 or 10,000 routes.
*   **Structure:** Paths are split into segments. Each segment is a node in the tree.

## Path Normalization

Fist automatically handles common URL inconsistencies so you don't have to write logic for them:

*   **Trailing Slashes:** `/users` and `/users/` are treated as the **same route**.
*   **Double Slashes:** `//api///v1` is normalized to `/api/v1`.
*   **Case Sensitivity:** Fist is **Case Sensitive**. `/Users` is distinct from `/users`.

## Precedence & Priority

When a request matches multiple possibilities (e.g., a static route and a wildcard), Fist follows this strict priority order:

1.  **Exact Static Match**
    *   Example: `/posts/new` takes priority over `/posts/:id`.
2.  **Dynamic Match**
    *   Example: `/posts/:id` matches if no static route matches.

## Constraints

### The "Same Level" Constraint

Because of the Trie structure, **you cannot register two different dynamic parameter names at the exact same position in the tree**. 

If you do, the last one defined will **overwrite** the parameter name for all handlers at that position.

**❌ Conflicting (Last one wins):**
```gleam
fist.new()
|> fist.get("/api/:user_id/posts", handler_a)
|> fist.get("/api/:id/settings", handler_b)
// Result: Both handlers will receive "id" as the parameter key.
// In handler_a, dict.get(params, "user_id") will return Error(Nil).
```

**✅ Recommended (Unique names or prefixes):**
```gleam
fist.new()
|> fist.get("/users/:user_id/posts", handler_a)
|> fist.get("/products/:product_id/settings", handler_b)
```
