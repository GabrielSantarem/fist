# Changelog

## v1.8.0
- **Feat**: Added typed parameter extraction module `fist/extract` with ergonomic helpers (`extract.int`, `extract.float`, `extract.bool`, `extract.string`, `extract.non_empty_string`, `extract.uuid`, `extract.custom`).
- **Feat**: Added first-class `use` expression extractors (`extract.require_int`, `extract.require_bool`, `extract.require_string`, etc.) for idiomatic early-return error handling in handlers.
- **Feat**: Added request query string helpers (`extract.query_params`, `extract.query_string`, `extract.query_int`, `extract.query_bool`).
- **Feat**: Added auto-generated TypeScript declarations (`.d.mts`) with generic parameter typing for JavaScript/TypeScript projects.
- **Chore**: Aligned `gleam.toml` with official specification, added explicit Codeberg/Hex links, and isolated `internal_modules` to keep public HexDocs clean.
- **Docs**: Added Section 9 to User Guide detailing parameter extraction patterns and `use` syntax.
- **Test**: Expanded test suite to 122 automated tests passing with zero failures and zero warnings across Erlang and JavaScript runtimes.

## v1.7.0
- **Feat**: Added Wildcard Catch-All routes (`*param` / `/*`) for matching arbitrary multi-segment sub-paths with clean relative path extraction.
- **Feat**: Implemented strict 3-tier specificity matching: `Static > Dynamic (:param) > Wildcard (*param)` with automatic deep backtracking to ancestor wildcards.
- **Feat**: Added `fist.merge` for monoidal router combination.
- **Feat**: Implemented Fail-Fast collision detection: immediate runtime panics for duplicate endpoints, conflicting dynamic parameter names, empty dynamic parameter names (`/:`), non-terminal wildcards, and sibling wildcard collisions.
- **Feat**: Implemented RFC 3986 Section 5.2.4 Defensive Path Security (`remove_dot_segments`), resolving `.` and `..`, preventing directory traversal escapes above root, sanitizing null-bytes, and normalizing Windows backslashes.
- **Feat**: Added full cross-target compatibility with 100% build and runtime parity across both BEAM (Erlang) and JavaScript (Node.js/Bun/Deno/browser) targets.
- **Perf**: Added comprehensive scalability benchmarks verifying `O(k)` lookups on 2,000+ route Tries, 10,000-request burst dispatches, 50-level path nesting, and large-tree merges.
- **Test**: Expanded test suite to 111 comprehensive automated tests passing with zero failures and zero warnings across Erlang and JavaScript runtimes.
- **Docs**: Updated User Guide, Behavior Invariants, Advanced Patterns, and Roadmap for v1.7.0.

## v1.6.0
- **Fix**: Fixed dynamic segment handling in `mount` and `group` prefixes (e.g. `/orgs/:org_id`).
- **Fix**: Fixed middleware execution order in `fist.group` so middlewares execute in natural declaration order.
- **Feat**: Added automatic URL percent-decoding for path parameters and static segments (e.g. UTF-8, spaces, plus signs).
- **Feat**: Added defensive stripping of query parameters (`?`) and URL fragments (`#`) during path parsing.
- **Feat**: Added `fist.head` and `fist.options` HTTP method helper functions.
- **Feat**: Added `fist.allowed_methods` to inspect all registered HTTP methods for a given route (enabling CORS preflight and 405 Method Not Allowed).
- **Test**: Expanded test coverage to 51 tests, including deep Trie backtracking, precedence rules, and edge cases.
- **Docs**: Rewrote documentation and user guide for conciseness and clarity. Removed deprecated examples.

## v1.5.0
- **Feat**: Added `fist.wrap` for applying middlewares to all routes in a router.
- **Feat**: Added `fist.group` for scoping routes under a prefix and shared middlewares.
- **Feat**: Added `fist.mount` and `fist.map_context` for modular routing and context polymorphism.
- **Feat**: Implemented internal Trie merging for robust sub-router support.

## v1.4.0
- **Feat**: Added `fist.describe` and `fist.inspect` for route documentation and introspection.

## v1.3.0
- **Chore**: Pure Router focus. Removed internal helper functions to keep the core minimal.
- **Docs**: Consolidated Roadmap and Todo.

## v1.1.0
- **Feat**: Tree-based routing (Trie).
- **Feat**: Generic handler outputs and Generic context.
- **Chore**: Removed mandatory dependency on the Mist web server.
