# Releases

The repository starts private. Pushing a version tag publishes one shared package to CurseForge, Wago and WoWInterface and attaches it to a GitHub release. Do not push release tags until the code and metadata are ready for public distribution.

## Setup

Configure repository Actions secrets `CURSE_API_TOKEN`, `WAGO_API_TOKEN` and `WOWI_API_TOKEN` with access to CurseForge project `1736834` Wago project `EGPaBWN1` and WoWInterface project `27254`. GitHub provides `GITHUB_TOKEN` automatically. Never put token values in source files or local build scripts.

Original project code and artwork use MIT. Bundled libraries retain their own terms; see [THIRD_PARTY.md](../THIRD_PARTY.md). In particular, LibDataBroker provides explicit embedding guidance but no conventional open-source license; the MIT grant does not cover it.

## Preparing a tag

1. Maintain all changes under `[Unreleased]` in `CHANGELOG.md`.
2. Move the changes shipping into a nonempty `## [1.0.0] - YYYY-MM-DD` section. Use the exact tag, without a `v` prefix.
3. Run CI checks locally, commit, then tag and push the reviewed commit. Tags may also use `1.0.0-alpha1`, `1.0.0-beta1`, or `1.0.0-rc1`. Alpha tags produce alpha packages; beta and RC tags produce beta packages.
4. Check the release workflow and the resulting files on all three services. A green source check is not an in-game test.

The preparation script rejects missing, duplicate or empty tag sections and generates identical package and GitHub notes. One canonical `!!!LuaWorkbench.toc` lists all supported interface versions: Retail, Forever and TBC. The pinned packager runs once, detects all versions from that TOC, and uploads the same ZIP to CurseForge, Wago, WoWInterface and GitHub. WoWInterface compatibility labels are limited to the game versions supported by its API; the shared ZIP still includes support for all three clients. An archive check runs before uploads. The package includes runtime assets and license notices; developer files and local deployment scripts are excluded.

The local build copies the same TOC to every selected client and removes only the two obsolete LuaWorkbench flavor TOCs. Client selectors choose installation destinations, not different packages. Existing release tags and previously uploaded files stay unchanged.

Uploads to separate services are not transactional. On a failure, inspect which files were already published before retrying; do not move or reuse a published tag. The workflow has no manual upload trigger.

## Local deployment

`build.sh` is a local, ignored convenience script and is deliberately absent from GitHub and release archives. It can deploy Retail, Forever and TBC to existing local clients. The committed `scripts/deploy.py` is also usable directly as documented in the main README. Neither deployment method publishes a release or touches SavedVariables.
