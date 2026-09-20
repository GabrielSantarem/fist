# Roadmap

Project vision, milestone tracking, and architectural research for `fist`.

---

## Completed

### v1.7.0
- **Wildcard Catch-All (`*param` / `/*`)**: Multi-segment path matching capturing all trailing segments.
- **Strict 3-Tier Precedence**: `Static > Dynamic (:param) > Wildcard (*param)` with automatic deep backtracking to ancestor wildcards on dead-end static branches.
- **Monoidal Router Merging (`fist.merge`)**: Combining disjoint and compatible routers recursively.
- **Fail-Fast Collision Protection**: Immediate runtime panic on duplicate endpoints, conflicting dynamic parameter names, or conflicting wildcards.
- **Full Cross-Target Compatibility**: 100% test coverage and build parity on both BEAM (Erlang) and JavaScript (Node.js/Bun/Deno/browser) runtimes.

### v1.6.0
- **Dynamic Mounting & Groups**: Full support for `:param` in `mount` and `group` prefixes (e.g. `/orgs/:org_id`).
- **Middleware Execution Order**: Declarative, outer-to-inner execution order in `fist.group`.
- **URL Percent-Decoding**: Automatic decoding of path parameters and UTF-8 characters (`João` -> `João`).
- **Defensive Path Parsing**: Automatic query string and fragment stripping.
- **HTTP Helpers**: Added `fist.head`, `fist.options`, and `fist.allowed_methods` for CORS preflight and 405 status codes.

### v1.5.0
- **Sub-routers & Mounting**: Modular routing via `fist.mount``.
- **Context Polymorphism**: Mapping sub-router contexts via `fist.map_context`.
- **Route Groups**: Grouping endpoints under prefixes with `fist.group`.
- **Static Middlewares**: Functional route wrapping via `fist.wrap`.

### v1.4.0
- **Route Metadata**: Implemented `describe` and `inspect` for route documentation and introspection.

### v1.3.0
- **Pure Router Focus**: Removed internal helper functions to keep the core minimal.

### v1.1.0
- **Core Features**: Tree-based routing (Radix Trie), generic handler outputs, and generic context.
- **Decoupling**: Removed mandatory dependency on the Mist web server.

---

## Future Explorations

### 1. Typed Route Extractors
Investigate safe parameter extraction directly into handlers (e.g., extracting integer IDs or UUIDs without manual string parsing in handlers).

### 2. OpenAPI / Swagger Generation
Leverage `fist.inspect` to build automated OpenAPI 3.0 specification generators from router metadata and registered descriptions.
