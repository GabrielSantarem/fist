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

- **Middleware Architectures**:
  - **Static Wrapping (Chosen)**:
    - *Definition*: Middlewares are applied at definition time by recursively wrapping handlers in the Trie.
    - *Pros*: 
        - **Maximum Performance**: Zero overhead during route lookup (Trie traversal). The only cost is nested function calls at execution time.
        - **Type Safety**: Leveraging simple function composition, making it easy to maintain Gleam's strict type system.
        - **Simplicity**: Requires no changes to the core `Node` data structure.
    - *Cons*: 
        - **Definition-time only**: Middleware is applied to the current state of the router.
        - **Opaque**: Once wrapped, you cannot easily inspect the middleware stack for a specific route.
    - *Syntax*:
      ```gleam
      router |> fist.wrap(middleware)
      // or via groups
      router |> fist.group(at: "/api", with: [auth_mw], defining: fn(r) { ... })
      ```

  - **On-Traversal (Discarded)**:
    - *Definition*: Middlewares are stored as a list in each Trie Node and executed sequentially as the router traverses the path segments.
    - *Pros*:
        - **Short-circuiting**: Middlewares can stop the traversal early (e.g., before even looking at child nodes).
        - **Dynamic Pipeline**: Easier to reason about "cascading" logic during the search process.
    - *Cons*:
        - **Performance Hit**: Every segment in the URL adds overhead for list operations and function applications during the search.
        - **Architectural Complexity**: Requires significant changes to `Node`, `find_route`, and `handle`.
        - **Type Hurdles**: Managing context polymorphism across a dynamic, recursive pipeline is significantly harder in Gleam.
    - *Syntax*:
      ```gleam
      router |> fist.use(middleware) // Adds middleware to the current node
      ```

- **Extractors / Typed Parameters**: Explore a way to inject extracted, typed parameters directly into handlers (e.g., receiving `id: Int` instead of parsing `params: Dict`), likely via adapter function or something else.
