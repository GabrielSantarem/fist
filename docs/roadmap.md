# Roadmap

Project vision, milestone tracking, and architectural research for `fist`.

---

## Completed

### v1.7.0
- **Typed Parameter Extractors (`fist/extract`)**: Pure, ergonomic parameter extraction and validation helpers (`extract.int`, `extract.float`, `extract.bool`, `extract.string`, `extract.non_empty_string`, `extract.uuid`, `extract.custom`) with first-class `use` expression support (`require_*`) and query string helpers (`query_params`, `query_string`, `query_int`, `query_bool`).
- **Defensive Path Security (RFC 3986)**: Formal Section 5.2.4 `remove_dot_segments` implementation preventing path traversal attacks (`.` and `..`), null-byte sanitization (`\0`), and Windows backslash normalization.
- **Wildcard Catch-All (`*param` / `/*`)**: Multi-segment path matching capturing all trailing segments.
- **Strict 3-Tier Precedence**: `Static > Dynamic (:param) > Wildcard (*param)` with automatic deep backtracking to ancestor wildcards on dead-end static branches.
- **Monoidal Router Merging (`fist.merge`)**: Combining disjoint and compatible routers recursively.
- **Fail-Fast Collision Protection**: Immediate runtime panic on duplicate endpoints, conflicting dynamic parameter names, or conflicting wildcards.
- **TypeScript Declarations Generation**: Auto-generated `.d.mts` definitions with generic parameters for JavaScript and TypeScript users.
- **Full Cross-Target Compatibility**: 100% test coverage and build parity on both BEAM (Erlang) and JavaScript (Node.js/Bun/Deno/browser) runtimes.

### v1.6.0
- **Dynamic Mounting & Groups**: Full support for `:param` in `mount` and `group` prefixes (e.g. `/orgs/:org_id`).
- **Middleware Execution Order**: Declarative, outer-to-inner execution order in `fist.group`.
- **URL Percent-Decoding**: Automatic decoding of path parameters and UTF-8 characters (`João` -> `João`).
- **Defensive Path Parsing**: Automatic query string and fragment stripping.
- **HTTP Helpers**: Added `fist.head`, `fist.options`, and `fist.allowed_methods` for CORS preflight and 405 status codes.

### v1.5.0
- **Sub-routers & Mounting**: Modular routing via `fist.mount`.
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

### 1. v2.0 Route Documentation & Code Generation
Explore code generation, expanded schema metadata, and automated OpenAPI 3.1 / TypeScript client generation based on `fist.inspect`.

### 2. Multi-Tenant / Host-Based Routing
Explore virtual-host and subdomain multiplexing (`req.host`) for multi-tenant applications.
