# Roadmap

Quick notes on the project's direction and upcoming features.

## Completed

### v1.3.0
- **Pure Router Focus**: Removed internal helper functions to keep the core minimal.
- **Documentation**: Consolidated Roadmap and Todo.

### v1.1.0
- **Core Features**: Tree-based routing (Trie), Generic handler outputs, and Generic context.
- **Standalone**: Removed mandatory dependency on the Mist web server.

## Upcoming / Todo

- **Sub-routers / Mounting**: Support for mounting routers at specific paths (e.g. `/api/v1`).
- **Middleware**: Implement a simple middleware pattern.
- **Route Metadata**: Implement a `describe` function to annotate routes with docstrings (e.g., `|> docs.new(desc: "User route")`).
- **Introspection**: Ability to traverse the node tree to reconstruct and inspect dynamic segments like `:id`.
- **OpenAPI/Swagger**: Research adding metadata generation for API documentation.
