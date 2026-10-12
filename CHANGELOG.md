# Changelog

## [Unreleased]

## [1.2.0] - 2026-10-12

### Added

- Optional IntelliSense with keyboard navigation, Enter/Tab acceptance and parameter hints that remain visible while entering arguments. Request suggestions with Ctrl+Space without interrupting normal cursor navigation.
- Complete documented Blizzard APIs and enums, local variables, table members and functions, namespace aliases, and members and parameters from saved `requireHelper` modules.
- Move lines or selected blocks with Alt+Up/Down and duplicate them with Alt+Shift+Up/Down.
- Copy or cut the current line with native clipboard shortcuts when nothing is selected, and paste copied lines above the current line.
- Native macOS shortcuts: Command for editor actions and line/document navigation, Option for word navigation and line actions, and Shift to extend selections. Modified Backspace supports character, word and line deletion.

### Changed

- Typing an automatically inserted closing quote or bracket advances past it instead of inserting a duplicate.
- Use Shift+F12 to return from a definition jump, keeping Option+Arrow available for text navigation.

### Fixed

- Large scripts remain fully visible with consistent syntax colors and smoother typing and scrolling.
- Greatly reduce freezes when pasting large scripts into the editor.
- Keep the code editor focused when running a script with F5.
- Keep breakpoints aligned when inserting or joining lines, including blank lines and automatic indentation.
- Limit very large debug terminal outputs to prevent excessive processing and memory use.

## [1.1.0] - 2026-10-11

### Added

- Explore Blizzard API documentation in a searchable Knowledge Base, including functions, methods, objects, structures, enums, events and callbacks. Filter by category, follow type references and return with Back.
- View API signatures, arguments, returns, default values and documented restrictions in code hover tooltips. Use F12 to open API documentation and customize API syntax colors.
- Inspect UI elements with LuaWorkbench’s frame picker and Object Inspector. Browse colored fields and values, search expanded branches, navigate to parents and back, copy access paths or insert references into code. Supported secret values use native hover tooltips.
- Open debugger variables in the Object Inspector and access Blizzard’s Table Inspector from the toolbar.
- Clear search fields with one click in the script list, code search, text snippets and Knowledge Base.

### Changed

- Reduce editor activity while idle and refresh large debug terminal dumps more efficiently.
- Debug variable tooltips use wider previews sized to their contents.

### Fixed

- Code hover targets stay aligned with text across long scripts, wrapping and scrolling.

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
