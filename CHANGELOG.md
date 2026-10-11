# Changelog

## [Unreleased]

### Added

- Clear search text directly in the script list, code search, text snippets and Knowledge Base.

- Browse documented functions, object methods, systems, structures, enums, events and callbacks in the Knowledge Base. Filter by alphabetically sorted categories, preview and follow type references, and return to previous entries.

- API help includes documented default values and restriction/secret metadata for functions, arguments and returns.

- Search documented Blizzard functions by name, description or parameter in the new Knowledge Base, with live results and a full detail view. F12 opens the matching API entry while local definitions retain priority. The movable window initially opens beside the editor when screen space permits. Colored signatures and types make entries easier to read, and a right-click action prepares function names for copying.

- Optional Blizzard API hover help with argument and return types, plus a configurable syntax color for documented global functions and namespace calls. Documentation loads when opening the editor outside combat.

### Changed

- Knowledge Base full-text indexing runs in small background steps with progress feedback; name search remains available while it builds.

- Knowledge Base windows can be resized and remember their size; API help omits the redundant metadata explanation.

- API help consistently displays boolean types and optional argument/default annotations, separately from nullable types.

- Knowledge Base search results no longer show redundant name tooltips.

### Fixed

- Debug variable tooltips use wider, text-sized previews without oversized empty margins.
- Large debug terminal dumps refresh the display once per dump instead of once per output line.

- An idle editor no longer repeatedly refreshes unchanged code, line numbers and the script list.

- Knowledge Base opening and live searches avoid unnecessary article formatting and repeated result sorting.

- Knowledge Base navigation buttons remain fully clickable, and opened entries start at the top of the detail view.

- Code hover targets stay aligned with text across long scripts, wrapping and scrolling.

- API arguments with default values are marked optional even when they do not accept nil.

- API hover help uses compact text-sized tooltips with colored signatures and wrapping for long type names.

## [1.0.0] - 2026-10-11

### Initial release

- Write and run Lua in WoW with syntax highlighting, code formatting, bracket completion, configurable indentation, customizable fonts and colors, and definition navigation.
- Organize saved scripts in folders, search your code, reuse text snippets, save all edited scripts, and recover unfinished drafts.
- Share functions and data through named helper modules with `requireHelper()`.
- Run saved scripts automatically at addon startup, login or selected WoW events. Automatic execution is off by default.
- Debug scripts, helpers and supported inline event handlers with persistent breakpoints, Step Over, Step Into, Continue and Stop. Supported events queue while execution is paused and WoW keeps running.
- Inspect variables and nested tables in hover tooltips and the variable panel. Evaluate expressions and change accessible variables in the debug terminal, with command history and autoscroll. Secret values follow WoW's display restrictions.
- Schedule debugging of saved code at addon startup or login, once or on every login/reload. Code is read-only during debugging by default, with an option to allow editing and a passive breakpoint notice while minimized.
- Inspect print, dump, return values and errors in a resizable output panel. Numbered dump arguments preserve nil positions; output can be embedded, detached or docked, with copy, clear, autoscroll and configurable history.
- Adjust the workspace with resizable windows, fullscreen, saved placement, optional screen clamping and multiline output previews while minimized.
- Access categorized help, keyboard shortcuts, session error history, Blizzard Frame Stack and Event Trace from the workspace.
- One shared download supports Retail, Forever and TBC, with a localized interface in all eleven WoW languages.
