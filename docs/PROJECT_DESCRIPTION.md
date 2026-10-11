LuaWorkbench is a Lua editor for World of Warcraft. Write and run code in-game, save snippets for later, and keep them organized in folders. It works on its own and does not require another addon.

The editor includes syntax highlighting, code search, and a separate output panel for printed messages, return values and errors. You can also search through all your saved snippets, including their code.

- Run code with the Play button, **Ctrl+Enter**, or **F5**.
- Save with **Ctrl+S**, recover drafts after a reload, or return to the last saved version.
- Run saved scripts at startup, login or on a WoW event you choose.
- Adjust fonts, indentation, bracket completion and the output limit in Options.
- Resize the window, give the code editor more space, or minimize it while you play.

Open it with `/lua`, `/le`, `/luaeditor` or `/luaworkbench`. The **?** button lists the shortcuts and explains the available options.

Supports Retail, Forever and TBC, with translations for all 11 WoW languages.

**Please keep in mind:** This runs real Lua code in your game. Only run scripts you trust. A running script cannot be interrupted; an infinite loop can freeze the game. Automatic runs are off by default. Enable startup, login or a custom WoW event for each script; only its saved code will run.

LuaWorkbench's own code is MIT-licensed. Bundled libraries keep their original licenses and notices. The repository is private during initial development; contributions and translations will be welcome when it opens.
