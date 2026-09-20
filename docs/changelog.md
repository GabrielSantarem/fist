# Changelog

## v1.7.0
- **Feat**: Added Wildcard Catch-All routes (`*param` / `/*`) for matching arbitrary multi-segment sub-paths.
- **Feat**: Implemented strict 3-tier specificity matching: `Static > Dynamic (:param) > Wildcard (*param)` with automatic deep backtracking to ancestor wildcards.
- **Feat**: Added `fist.merge` for monoidal router combination.
- **Feat**: Implemented Fail-Fast collision detection: immediate runtime panics for duplicate endpoints, conflicting dynamic parameter names, non-terminal wildcards, and sibling wildcard collisions.
- **Feat**: Added full cross-target compatibility for both BEAM (Erlang) and JavaScript runtimes.
- **Test**: Expanded test suite to 84 comprehensive specification tests with zero failures across Erlang and JavaScript targets.
- **Docs**: Standardized test documentation to specification style and updated core concept guides.

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
