# Gaps & assumptions

Updated every session. Remove items when closed; note the closing commit.

## Open (as of 2026-09-08, session S1)

- **Not yet opened in the editor.** No Godot executable on the build machine. CI runs the unit tests (including a headless instantiation of the exploration scene) and the `screenshot` job renders the scene under Xvfb; that PNG is the only visual check so far. Still unproven: real-time feel, input on a real window, `.uid` sidecars. First local action: open in Godot 4.6, press Play, commit the `.uid` files.
- **Movement is placeholder-simple**: no elevation, no facing sprites (8-direction mirroring waits on art), followers pass through each other, no actor-vs-actor collision, and WASD steering lets you stand visually "behind" a tall wall's top face.
- **Map format is ASCII-only**: fine for M0; procgen Shards (a later M0 session) will build `MapData` directly instead of via rows.
- **Release workflow unverified** until the first `v*` tag. macOS export from Linux uses ad-hoc signing and no notarization; a real Apple signing path is an M2/M4 task.
- **No per-kind content schemas yet.** The registry loads anything; validation (required fields, enum values, cross-references like `subclasses` ids) lands with each system. Track in `docs/content-schemas.md` when created.
- **No GodotSteam.** `Platform` has only the null backend (D-007).
- **Content is placeholder-thin**: 2 races and 2 classes carry only descriptive fields. Mechanical hooks (`hooks`, `resource`) are strings until the class/race systems define them.
- ~~Branch protection~~ closed 2026-09-08: `main` requires a PR with a green, up-to-date `ci` check, enforced for admins, no force-pushes or deletions.
- **No `.gdignore` for a `build/` dir**; exports write to `build/` which is git-ignored but the editor will still scan it if present locally. Add `build/.gdignore` when first exporting.
