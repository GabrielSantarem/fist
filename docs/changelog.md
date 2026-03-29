# Changelog

## v1.5.0 (Upcoming)
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
