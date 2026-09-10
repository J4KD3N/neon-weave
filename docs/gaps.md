# Gaps & assumptions

Updated every session. Remove items when closed; note the closing commit.
Triaged at the end of M2 (S27, 2026-09-09): closed items from M0–M2 are
gone (see `docs/decisions.md` and git history); what is left is grouped
by who can close it and roughly ordered by how much it hurts the demo.

## Needs a person (not a session)

M3 is planned in `docs/m3-plan.md` (D-082); the items below are its parallel tracks.

- **Nobody outside the author has played the demo.** M2's exit criterion "two external playtesters finish the slice" is unmet. `test_balance.gd` is the instrument a playtest will be measured against; the S13 triage row stays open for whatever they find.
- ~~The AP economy question~~ closed 2026-09-09 (S28, D-083): every damaging ability costs one more AP; fights are two actions a turn. The first external playtest is still owed and will re-open whatever it finds.
- **Art is generated placeholders**: `v0.2.0-demo` ships them with a title-screen note (D-079). The store page has no capsules, trailer or artist (`docs/store-page.md`). The pipeline is real (S10); the only sheets are tool-generated rigs for Trueborn and Scav, every other race and enemy uses the static capsule, overlays are stamped not composited, no per-biome palette, no CRT shader, no lighting or glow pass.
- **Audio is synthesised placeholders** (S24): no recorded sound or composed music; no separate music and SFX volume buses.
- **Steam is wired but unverified** (S25, D-078): no GodotSteam binaries, app id or Steamworks definitions here; achievements, cloud sync and the Steam Input template have never touched a live client; `steam/app_build.vdf` waits on depot ids.
- **macOS is ad-hoc signed, not notarized** (D-079): Gatekeeper warns; no Apple account. Only the Linux binary is exercised by CI; Windows was booted by hand for v0.2.0; macOS by nobody.

## Demo content (M2 leftovers, sessions can close)

- **Depth 3 is a wall for naive play** (S33 harness, geared level-6 party, no retreating or healing): Undercity and Ghost Markets both extract ~15% of depth-3 runs and the Datacore ~30% at depth 2, against 65–80% at depths 1–2. The boss posted at the pad after two extra groups with no healing between fights is the shape of it. Owned by the M4 balance pass; the harness rows hold low floors until then. The Null Cathedral and the Loom Approach are behind story flags no content sets yet (`null_cathedral_found`, `loom_located`: S41), so only tests and `--biome=` reach them. Under naive play the Cathedral extracts 0% at depth 3 and the Loom Approach 5% (silencing fonts, a room-wide hush, wardens three quarters off arcane); the harness prints the rows with no floor until the M4 pass sets one.
- **The demo slice is thin**: one map per story beat, no writing pass, well under the planned 2–3 hours; Pell has no follow-up and the relay station has one fight. The deeper→throat hand-off is in data since S27 (D-081).
- **Narrative depth**: three companions; the five endings exist as data but nothing in Act 1 sets the Keys, spares a fragment or fires `ending` (S41–S43); the Quarters have one scene per companion (S35) and no romance until S37; all three factions have envoys, offer quests, areas and vendors since S32, but joining has no consequences past the door and the shop yet (no faction quests, no areas changing, no ending hooks until S36/S40), and the Rootched have no leaning companion until Yev; no romance, portraits or companion reactions in combat; banter is a toast; dialogue is a text panel with number keys; NPCs never move.
- **Economy is first-guess**: the road nets roughly 10–18 salvage and 1–3 Aether against a 15/2 Beacon upgrade, so most players run one Shard before depth 2; building costs, loot ranges and XP values have been checked only by the harness.
- **Items are thin** (S29, D-084): twelve bases and eight affixes, one crate pickup type, no consumables or resource costs on gear, no item art beyond a colour, no family-specific drop tables yet (`families` exists on items but nothing uses it), no sell-back; secrets still hold one pickup.
- **Enemies on a previous map are forgotten** when you leave it (map-placed enemies respawn on re-entry); transitions fire on step-on with no confirmation.

## Systems (M3+)

- **Combat texture is shallow**: cover, elevation, surfaces and resources exist and the AI weighs them (D-067); no movement cost for elevation, no hackable turrets or doors, no difficulty settings or Iron Weave; enemies never move in exploration; awareness is a radius, not a cone; no attack of opportunity or reactions; previews skip conduit chains.
- **Five AI archetypes** share one texture score. Missing: retreat when losing, focus fire, target selection beyond nearest. Hidden combatants are drawn faint for both sides; no true fog or detection roll.
- **Progression v2 leftovers** (S31, D-086): the second class of a multiclass has no subclass and no resource loop of its own; the Weave is the only place levels move and there is no preview of what a level would give; talents are still flat stat bumps; capstones are one ability each with no story or visual moment; party summons use the enemy placeholder art.
- **Pad support is functional, not native**: the combat cursor steps one cell per press, no analog glide, no rumble; mouse is still the fastest way to target.
- **Creator is a text screen**: no appearance beyond the race overlay, no portrait, not part of New game (C at home), origins gate nothing yet. Ten races since S30; Hollow and Swarmborn have their tags but no NPC reactions yet (the S44 pass), Synth still cannot repair with parts, and Skyborn knowledge and Swarmborn disguise are only tags until lines use them.
- **Saves**: F5/F9 still mean slot 1; no confirmation on overwrite. Content mismatches are refused since S27 (D-080); a save inside a Shard is also refused when `ShardGenerator.LAYOUT_VERSION` moves, which is by hand.
- **Movement is placeholder-simple**: followers pass through each other, no actor collision, WASD lets you stand visually behind a tall wall; party settling snaps with no animation.
- **Map format is ASCII-only** for handcrafted maps by design (D-028).
