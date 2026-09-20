# Roadmap

Project vision, milestone tracking, and architectural research for `fist`.

---

## Planned Milestones

### v1.9.0 — Developer Ergonomics & Type Safety

- **Named Routes & Reverse Routing (`fist.name`, `fist.path`)**:
  - Assign unique, type-friendly identifiers to registered endpoints.
  - Generate canonical URLs programmatically with safe parameter interpolation (`fist.path(router, "user_profile", [#("id", "42")])`), eliminating broken, hardcoded URL strings across applications.
- **Constrained Dynamic Routing & Route Guards (`fist.guard(param, when: predicate)`)**:
  - Add functional predicates to dynamic route segments (e.g. matching numeric `:id` vs alphabetic `:slug` at the same tree depth).
  - If a guard evaluates to `False`, the router seamlessly continues traversal to subsequent matching dynamic branches or wildcards before returning 404.

### v1.10.0 — Robustness, Observability & Standards Compliance

- **Advanced Routing Diagnostics & Debugging Tooling (`fist.explain`, `fist.trace`, `fist.visualize`)**:
  - Provide extensive, high-level debugging and diagnostic tools to inspect and trace routing decisions in complex trees.
  - **Route Execution Tracing (`fist.trace`)**: Step-by-step trace of how a request traverses the Radix Trie, detailing static matches, guard evaluations (`True`/`False`), dynamic branch fallthroughs, and wildcard backtracking decisions.
  - **Tree Diagnostics & Visualization (`fist.visualize`)**: Output the internal Radix Trie structure (ASCII tree, structured JSON, or diagnostic summary) to audit route hierarchy, parameter precedence, and guarded branch ordering.
  - **Conflict & Dead Route Detection (`fist.audit`)**: Proactively diagnose unreachable branches, shadowed dynamic segments, or redundant guards at compile/build time.
- **Automatic `HEAD` Method Derivation (RFC 9110)**:
  - Automatically fulfill HTTP `HEAD` requests using registered `GET` handlers with identical status codes and headers, stripping the response body as mandated by RFC 9110.
- **Panic Recovery Middleware (`fist.recover`)**:
  - Provide a zero-overhead error boundary middleware to catch unexpected runtime crashes and uncaught panics within handlers.
  - Return standardized HTTP 500 error responses and structured error logs without terminating the host BEAM process or JavaScript runtime.

---

## Completed

### v1.8.0

- **Typed Parameter Extractors (`fist/extract`)**: Pure, ergonomic parameter extraction and validation helpers (`extract.int`, `extract.float`, `extract.bool`, `extract.string`, `extract.non_empty_string`, `extract.uuid`, `extract.custom`) with first-class `use` expression support (`require_*`) and query string helpers (`query_params`, `query_string`, `query_int`, `query_bool`).
- **TypeScript Declarations Generation**: Auto-generated `.d.mts` definitions with full generic parameter typing for JavaScript and TypeScript consumers.
- **Packaging & Documentation Isolation**: Aligned `gleam.toml` with the official specification, added explicit Codeberg/Hex links, and marked `internal_modules` to keep public HexDocs clean.

### v1.7.0

- **Defensive Path Security (RFC 3986)**: Formal Section 5.2.4 `remove_dot_segments` implementation preventing path traversal attacks (`.` and `..`), null-byte sanitization (`\0`), and Windows backslash normalization.
- **Wildcard Catch-All (`*param` / `/*`)**: Multi-segment path matching capturing all trailing segments.
- **Strict 3-Tier Precedence**: `Static > Dynamic (:param) > Wildcard (*param)` with automatic deep backtracking to ancestor wildcards on dead-end static branches.
- **Monoidal Router Merging (`fist.merge`)**: Combining disjoint and compatible routers recursively.
- **Fail-Fast Collision Protection**: Immediate runtime panic on duplicate endpoints, conflicting dynamic parameter names, or conflicting wildcards.
- **Full Cross-Target Compatibility**: 100% test coverage and build parity on both BEAM (Erlang) and JavaScript (Node.js/Bun/Deno/browser) runtimes.
- **Scalability & Stress Benchmarks**: Validated `O(k)` lookups on 2,000+ route trees, 10,000-burst dispatches, and 50-level path nesting.

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

## Future Explorations (Backlog)

### 1. Structured Route Metadata, Tags & Scopes

- Allow attaching domain tags, authorization scopes, and rate limits to routes (`fist.tag(["admin", "internal"])`, `fist.require_scope(["metrics:read"])`).
- Enable middlewares to introspect the route definition and enforce access control policies declaratively.

### 2. Multi-Tenant & Host-Based Routing (`fist.host`)

- Virtual-host and subdomain multiplexing (`api.example.com`, `admin.example.com`, `*.tenant.com`) based on the request `Host` header.

### 3. Content Negotiation & Format Routing

- Route matching based on request `Accept` headers or URL extensions (`/reports.json` vs `/reports.csv`).

### 4. Configurable Trailing Slash Policy

- Configurable redirect actions (`RedirectSlash` 308 permanent redirect vs current silent `Normalize`).

### 5. v2.0 Route Documentation & Code Generation

- Automated OpenAPI 3.1 specification extraction and TypeScript client SDK generation based on structured route metadata and `fist.inspect`.
