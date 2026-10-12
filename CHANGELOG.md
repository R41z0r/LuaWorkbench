# Changelog

## [Unreleased]

### Added

- Complete documented enumeration names and their values through `Enum.`.

- Complete members of local tables and show parameter names for locally defined functions and methods.

- Complete documented API members and show parameter hints through local namespace aliases such as `local CA = C_AddOns`.

- Optional code completion for documented Blizzard APIs, local variables, parameters and script functions, with keyboard selection, Enter/Tab acceptance and API parameter hints. Suggestions respect local namespace shadowing and implicit method parameters.

- Copy or cut the current line with native clipboard shortcuts when no text is selected, including repeated cuts and empty final lines. Paste copied lines above the current line; returning from another copy field restores ordinary paste behavior.

- Platform-aware editor shortcuts and help: Command on macOS for saving, searching and running scripts; Option for line actions and formatting.

- Move the current line or selected line blocks with Alt+Up/Down and duplicate them with Alt+Shift+Up/Down, including blocks selected with the mouse and trailing empty lines at the end of the document.

### Changed

- Dismissed parameter help stays closed during cursor navigation; Ctrl+Space opens it again for the current call.

- Show parameter help above the cursor and completion suggestions below it in separate windows.

- Open automatic completion while editing, without interrupting cursor navigation through existing code; Ctrl+Space still requests suggestions explicitly.

- Keep parameter hints visible while typing arguments, including quoted strings.

- Typing an automatically inserted closing quote or bracket advances over it instead of inserting a duplicate.

- On macOS, Option+Left/Right navigates by word and Command+Left/Right moves to line boundaries and Command+Up/Down to code boundaries; Shift extends the selection.

- On macOS, Ctrl+Backspace deletes one character, Option+Backspace deletes the previous word, and Command+Backspace deletes to the start of the current line.

### Fixed

- Keep the code editor focused when running a script with F5.

- Keep breakpoints aligned when inserting newlines or joining lines with Backspace/Delete, including blank lines and automatic indentation.

- Bound debug terminal output for very large strings and tables.

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
