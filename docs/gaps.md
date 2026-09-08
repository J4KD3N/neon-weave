# Gaps & assumptions

Updated every session. Remove items when closed; note the closing commit.

## Open (as of 2026-09-08, session S0)

- **Not yet opened in the editor.** No Godot executable was found on the build machine during S0. CI (Godot 4.6.stable, Linux) imported the project and passed all 17 unit tests on the first push (run 34236943312), so scripts compile and the registry works headless. Still unproven: the boot scene rendering, and the `.uid` sidecar files the editor generates. First local action: open in Godot 4.6, press Play, commit the `.uid` files.
- **Release workflow unverified** until the first `v*` tag. macOS export from Linux uses ad-hoc signing and no notarization; a real Apple signing path is an M2/M4 task.
- **No per-kind content schemas yet.** The registry loads anything; validation (required fields, enum values, cross-references like `subclasses` ids) lands with each system. Track in `docs/content-schemas.md` when created.
- **No GodotSteam.** `Platform` has only the null backend (D-007).
- **Content is placeholder-thin**: 2 races and 2 classes carry only descriptive fields. Mechanical hooks (`hooks`, `resource`) are strings until the class/race systems define them.
- ~~Branch protection~~ closed 2026-09-08: `main` requires a PR with a green, up-to-date `ci` check, enforced for admins, no force-pushes or deletions.
- **No `.gdignore` for a `build/` dir**; exports write to `build/` which is git-ignored but the editor will still scan it if present locally. Add `build/.gdignore` when first exporting.
