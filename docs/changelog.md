# Changelog

All notable changes to the Fist router.

## v1.3.0
- **Breaking Change**: Removed response helpers (`fist.ok`, `fist.text`, `fist.json`, `fist.redirect`). Users should now construct their own responses or use `gleam_http` directly, keeping the router focused on routing logic.
- **Documentation**: Added comprehensive Roadmap and Todo documentation.
- **Documentation**: Updated documentation theme and internal generation tools.

## v1.2.0
- Added initial `Roadmap` and `Todo` documentation.
- Improved CI/CD for GitHub Pages deployment.
- Internal documentation improvements.

## v1.1.0
- **Pure Router Refactor**: Removed mandatory dependency on the Mist web server. Fist is now a standalone routing library.
- **Generic Context (`ctx`)**: Handlers now receive a generic context parameter (e.g., for DB connections), avoiding the need for closures.
- **Generic Handler Output**: Handlers can now return any type (Strings, custom ADTs, etc.).
- **Response Pipeline**: Introduced `fist.map` to transform all router outputs in a single step.
- **Response Helpers**: Added `fist.ok`, `fist.json`, `fist.text`, and `fist.redirect` to reduce boilerplate.

## v1.0.2
- **Trie-based Routing**: Method-based dictionary of trees for O(n) lookups.
- **Static Route Priority**: Static routes now correctly take priority over dynamic segments (`:param`).

## v1.0.1
- Improved path segmentation logic.

## v1.0.0
- Initial release.
