# Gaps & assumptions

Updated every session. Remove items when closed; note the closing commit.

## Open (as of 2026-09-08, session S0)

- **Not validated locally.** No Godot executable was found on the build machine during S0, so the project has not been opened in the editor or run headless yet. CI runs the tests on the first push. First local action: open in Godot 4.6, run `godot --headless --path . -s tests/test_runner.gd`, commit the generated `.uid` files.
- **Release workflow unverified** until the first `v*` tag. macOS export from Linux uses ad-hoc signing and no notarization; a real Apple signing path is an M2/M4 task.
- **No per-kind content schemas yet.** The registry loads anything; validation (required fields, enum values, cross-references like `subclasses` ids) lands with each system. Track in `docs/content-schemas.md` when created.
- **No GodotSteam.** `Platform` has only the null backend (D-007).
- **Content is placeholder-thin**: 2 races and 2 classes carry only descriptive fields. Mechanical hooks (`hooks`, `resource`) are strings until the class/race systems define them.
- **GitHub remote not created** in S0; the repo is local-only. Public repo from day one is a GDD requirement (§4) — create it and push.
- **Branch protection / required `ci` check** not applied (needs the remote first).
- **No `.gdignore` for a `build/` dir**; exports write to `build/` which is git-ignored but the editor will still scan it if present locally. Add `build/.gdignore` when first exporting.
