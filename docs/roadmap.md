# Roadmap

Quick notes on the project's direction and upcoming features.

## Completed

### v1.4.0
- **Route Metadata**: Implemented `describe` and `inspect` for route documentation and introspection.

### v1.3.0
- **Pure Router Focus**: Removed internal helper functions to keep the core minimal.
- **Documentation**: Consolidated Roadmap and Todo.

### v1.1.0
- **Core Features**: Tree-based routing (Trie), Generic handler outputs, and Generic context.
- **Standalone**: Removed mandatory dependency on the Mist web server.

## Upcoming / Todo

- **Sub-routers / Mounting**: Support for mounting routers at specific paths (e.g. `/api/v1`).
- **Middleware**: Implement a simple middleware pattern.
- **OpenAPI/Swagger**: Research adding metadata generation for API documentation.

## Things to Think About / Research

- **Extractors / Typed Parameters**: Explore a way to inject extracted, typed parameters directly into handlers (e.g., receiving `id: Int` instead of parsing `params: Dict`), likely via adapter function or something else.
