# Changelog

## [Unreleased]

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
