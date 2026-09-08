# Gaps & assumptions

Updated every session. Remove items when closed; note the closing commit.

## Open (as of 2026-09-08, M1 complete; M2 sessions in docs/m2-plan.md)

- **M0 question still open**: the loop exists end to end (yard → Shard → fight/collect → extract or wipe → yard → Bastion) but nobody has played it. "Is the loop fun?" needs a person with the editor open. Balance numbers are all first guesses, including building costs.
- **XP and Ciphers have no sink**: Salvage and Aether buy building levels; XP (levels/talents) and Ciphers (rare keys/merchants) wait on later systems. No item loot, rarity or affixes.
- **Bastion is a text screen** over the yard; no building visuals, no dedicated map (M1 art/companion sessions decide).
- **Narrative is one companion deep**: Sera only; no romance, portraits, journal UI, or companion reactions in combat; banter is a toast; dialogue is a text panel with number keys; NPCs never move; the death-stakes mode is still a rule flag with no setup UI (Mortal mode works but you cannot choose it in game).
- **Pad support is functional, not native**: the combat cursor steps one cell per press with key-repeat pacing (no analog glide), there is no on-screen button glyph swap when a pad is detected, no rumble, no Steam Input template yet (M2 with GodotSteam), and the system menu is the only way to save/load on a pad. Mouse remains the fastest way to target in combat.
- **Creator is a text screen too**: no appearance customisation beyond the race overlay, no portrait, no title screen (C at home is the entry point), origins gate nothing yet (`dialogue_tag` waits for S11's dialogue data), and only the five M2 races exist.
- ~~Depth only adds bodies~~ closed 2026-09-08 (S16, D-068): HP and damage scale with depth, elites roll in, the Warlord guards the pad from depth 3. Pools do not change by depth yet.
- **Shards are plain**: no secrets, vaults or merchants (GDD §11); one room style; corridors are 1 wide; enemy groups are random per room with no difficulty ramp by distance; pickups are two types.
- **Enemies on a previous map are forgotten** when you leave it; N (launch) and H (home) are still bare keys rather than a Beacon interaction on the map.
- **Saves have a list, not a UI**: the system menu reaches all three slots and the autosave with summaries (S13); F5/F9 still mean slot 1; no confirmation on overwrite, no content-version check (a save from a different content set loads by index and may misplace deltas).
- **Map format is ASCII-only** stays true for handcrafted maps; generated ones go through the same rows format by design (D-028).

- **Combat texture is in but shallow**: cover, elevation, surfaces and Surge/Heat exist (S7) and the AI now weighs them (D-067); elevation has no movement cost or stairs, there are no hackable turrets/doors, no stealth openers, no difficulty settings or Iron Weave; enemies never move in exploration; awareness is a radius, not a cone. Turn groups (D-057), hover previews (D-058), camera pan and move undo (S13) exist, but there is no attack-of-opportunity or reaction system, and previews do not cover conduit chains.
- **Death-stakes mode has no setup UI**: `rules/combat.json` `story_protected` is the only switch. Downed members revive at 1 HP after victory; there is no healing yet, so HP only goes down between fights.
- **Five AI archetypes** (rusher, ranged, stealther, summoner, controller) share one texture score (D-067). Still missing: retreat when losing, focus fire, target selection beyond nearest, and difficulty settings. Hidden combatants are drawn faint for both sides; no true fog or detection roll yet.
- **Drone Shepherd has no drones**: no summons or turrets yet (Swarmlord/Artificer are subclasses, M2+); the class is a Scrap-spending gunner for now. Circuit-Witch has no Glitchbinder/Plaguecoder spread mechanics.
- **Progression is shallow** (S14): one party-wide level, subclasses are one ability plus stat mods, talents are six flat stat buffs in two tiers, no multiclassing or capstones; subclass identities (chain lightning, taunts, drone swarms, turrets) need mechanics the ability vocabulary does not have yet; stealth, ambush, absorption and silence exist since S15. XP now has a sink; Ciphers still do not.
- **Party settling can look odd**: members snap to the nearest free cells around their exploration positions with no animation.
- **Balance is unplaytested**: numbers in `content/rules/combat.json`, class stats and enemy stats are first guesses; the seeded scene test wins 4v3 but that is one seed.

- ~~Not yet opened in the editor~~ closed 2026-09-08: the project runs locally on Godot 4.7.2 (PR #19 committed the `.uid` sidecars, PR #22 pinned CI to the same version); the first playtest drove S11b. Real-time feel on a real window is now the M1 playtest question for S13.
- **Art is generated placeholders**: the pipeline is real (S10) but the only sheets are tool-generated rigs for Trueborn and Scav; every other race/enemy uses the static capsule. Race overlays are not composited onto sheets yet (the placeholder rig still stamps them); tiles have no per-biome palette swap beyond the placeholder atlas; no CRT shader; no lighting/glow pass.
- **Movement is placeholder-simple**: followers pass through each other, no actor-vs-actor collision, and WASD steering lets you stand visually "behind" a tall wall's top face.
- **Release workflow unverified** until the first `v*` tag. macOS export from Linux uses ad-hoc signing and no notarization; a real Apple signing path is an M2/M4 task.
- **No per-kind content schemas yet.** The registry loads anything; validation (required fields, enum values, cross-references like `subclasses` ids) lands with each system. Track in `docs/content-schemas.md` when created.
- **No GodotSteam.** `Platform` has only the null backend (D-007).
- **Content is placeholder-thin**: 2 races and 2 classes carry only descriptive fields. Mechanical hooks (`hooks`, `resource`) are strings until the class/race systems define them.
- ~~Branch protection~~ closed 2026-09-08: `main` requires a PR with a green, up-to-date `ci` check, enforced for admins, no force-pushes or deletions.
- ~~No `.gdignore` for a `build/` dir~~ closed 2026-09-08: `build/.gdignore` is committed (git-ignore exception) so local exports and screenshots never enter the editor scan.
