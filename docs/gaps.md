# Gaps & assumptions

Updated every session. Remove items when closed; note the closing commit.

## Open (as of 2026-09-08, session S5 — M1 started, see docs/m1-plan.md)

- **M0 question still open**: the loop exists end to end (yard → Shard → fight/collect → extract or wipe → yard → Bastion) but nobody has played it. "Is the loop fun?" needs a person with the editor open. Balance numbers are all first guesses, including building costs.
- **XP and Ciphers have no sink**: Salvage and Aether buy building levels; XP (levels/talents) and Ciphers (rare keys/merchants) wait on later systems. No item loot, rarity or affixes.
- **Bastion is a text screen** over the yard; no building visuals, no dedicated map (M1 art/companion sessions decide).
- **Creator is a text screen too**: no appearance customisation beyond the race overlay, no portrait, no title screen (C at home is the entry point), origins gate nothing yet (`dialogue_tag` waits for S11's dialogue data), and only the five M2 races exist.
- **Depth only adds bodies**: enemy stats and pools do not scale with Beacon depth (D-038).
- **Shards are plain**: no secrets, vaults or merchants (GDD §11); one room style; corridors are 1 wide; enemy groups are random per room with no difficulty ramp by distance; pickups are two types.
- **Enemies on a previous map are forgotten** when you leave it; N (launch) and H (home) are still bare keys rather than a Beacon interaction on the map.
- **Saves have no UI**: three slots exist but only slot 1 is reachable (F5/F9) plus the autosave (F10); no slot picker, no confirmation on overwrite, no content-version check (a save from a different content set loads by index and may misplace deltas).
- **Map format is ASCII-only** stays true for handcrafted maps; generated ones go through the same rows format by design (D-028).

- **Combat texture is in but shallow**: cover, elevation, surfaces and Surge/Heat exist (S7) but the AI ignores all of them (it will stand in biogrowth and shoot into cover), elevation has no movement cost or stairs, there are no hackable turrets/doors, no stealth openers, no difficulty settings or Iron Weave; enemies never move in exploration; awareness is a radius, not a cone.
- **Death-stakes mode has no setup UI**: `rules/combat.json` `story_protected` is the only switch. Downed members revive at 1 HP after victory; there is no healing yet, so HP only goes down between fights.
- **Only two AI archetypes** (rusher, ranged). Summoner, stealther, controller wait on their mechanics.
- **Drone Shepherd has no drones**: no summons or turrets yet (Swarmlord/Artificer are subclasses, M2+); the class is a Scrap-spending gunner for now. Circuit-Witch has no Glitchbinder/Plaguecoder spread mechanics.
- **Subclasses, multiclassing, the Weave Tree and levels** (GDD §8) do not exist; classes are flat ability lists.
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
