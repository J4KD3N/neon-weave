# Gaps & assumptions

Updated every session. Remove items when closed; note the closing commit.

## Open (as of 2026-09-08, session S3)

- **Shards have no loop yet**: the extraction pad is placed and reachable but standing on it does nothing; no loot, XP, Salvage or "unbanked resources lost on wipe". Next session.
- **Shards are plain**: no secrets, vaults or merchants (GDD §11); one room style; corridors are 1 wide; enemy groups are random per room with no difficulty ramp by distance.
- **Entering a Shard resets the party** (respawned at full HP) and enemies on the previous map are forgotten; there is no Bastion/Beacon, so N/H are debug keys.
- **Map format is ASCII-only** stays true for handcrafted maps; generated ones go through the same rows format by design (D-028).

- **Combat is the M0 skeleton only**: no cover, elevation or surfaces (GDD §9); no class resources (Surge, Vent Heat); no XP, loot or extraction; no stealth openers; no difficulty settings; enemies never move in exploration; awareness is a radius, not a cone.
- **Death-stakes mode has no setup UI**: `rules/combat.json` `story_protected` is the only switch. Downed members revive at 1 HP after victory; there is no healing yet, so HP only goes down between fights.
- **Only two AI archetypes** (rusher, ranged). Summoner, stealther, controller wait on their mechanics.
- **Party settling can look odd**: members snap to the nearest free cells around their exploration positions with no animation.
- **Balance is unplaytested**: numbers in `content/rules/combat.json`, class stats and enemy stats are first guesses; the seeded scene test wins 4v3 but that is one seed.

- **Not yet opened in the editor.** No Godot executable on the build machine. CI runs the unit tests (including a headless instantiation of the exploration scene) and the `screenshot` job renders the scene under Xvfb; that PNG is the only visual check so far. Still unproven: real-time feel, input on a real window, `.uid` sidecars. First local action: open in Godot 4.6, press Play, commit the `.uid` files.
- **Movement is placeholder-simple**: no elevation, no facing sprites (8-direction mirroring waits on art), followers pass through each other, no actor-vs-actor collision, and WASD steering lets you stand visually "behind" a tall wall's top face.
- **Release workflow unverified** until the first `v*` tag. macOS export from Linux uses ad-hoc signing and no notarization; a real Apple signing path is an M2/M4 task.
- **No per-kind content schemas yet.** The registry loads anything; validation (required fields, enum values, cross-references like `subclasses` ids) lands with each system. Track in `docs/content-schemas.md` when created.
- **No GodotSteam.** `Platform` has only the null backend (D-007).
- **Content is placeholder-thin**: 2 races and 2 classes carry only descriptive fields. Mechanical hooks (`hooks`, `resource`) are strings until the class/race systems define them.
- ~~Branch protection~~ closed 2026-09-08: `main` requires a PR with a green, up-to-date `ci` check, enforced for admins, no force-pushes or deletions.
- **No `.gdignore` for a `build/` dir**; exports write to `build/` which is git-ignored but the editor will still scan it if present locally. Add `build/.gdignore` when first exporting.
