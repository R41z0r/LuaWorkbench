# Contributing

Bug reports, translations, documentation and pull requests are welcome. Keep each change focused and explain the observed behavior and expected result.

Use Lua 5.1-compatible syntax. Keep the addon standalone. User-facing strings belong in Localization.lua; update all eleven locales together and keep their keys sorted. Include a short note in the shared CHANGELOG.md under Unreleased.

Before submitting, run `luacheck --no-color -q .`, `python3 scripts/check_lua_upvalues.py .`, `python3 scripts/validate_project.py`. Report which game clients were actually tested; static checks do not replace in-game checks.

Do not include credentials, personal paths, SavedVariables, local build scripts or generated release output. Preserve bundled library notices. Contributions to original project code are accepted under the MIT license in LICENSE. Third-party libraries retain their respective terms.
