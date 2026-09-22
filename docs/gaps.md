# Gaps & assumptions

Updated every session. Remove items when closed; note the closing commit.
Triaged at the end of M3 (S46, 2026-09-21): closed items from M0–M3 are
gone (see `docs/decisions.md` and git history); what is left is grouped
by who can close it and ordered by how much it hurts a player. M4 is
planned in `docs/m4-plan.md`.

## Needs a person (not a session)

- **Nobody outside the author has played it.** M2's exit criterion "two external playtesters finish the slice" is still unmet and M3 added two acts on top. The kit is ready (S47, D-102): `docs/playtest.md`, the `--playtest` log and `tools/playtest_report.gd`; the triage table is empty until two people have played, and the harness bands stay hypotheses until then.
- **Art is generated placeholders**: every build ships them with a title-screen note (D-079). The store page has no capsules, trailer or artist (`docs/store-page.md`). The pipeline is real (S10); the only sheets are tool-generated rigs for Trueborn and Scav; every other race, family and NPC uses the standard rig with an overlay. `docs/art-pipeline.md` is the hand-off.
- **Audio is synthesised placeholders** (S24): no recorded sound or composed music; no separate music and SFX volume buses.
- **Steam is wired but unverified** (S25, D-078): no GodotSteam binaries, app id or Steamworks definitions here; achievements (twelve, five for the endings), cloud sync and the Steam Input template have never touched a live client; `steam/app_build.vdf` waits on depot ids; the demo depot must launch with `--demo`.
- **macOS is ad-hoc signed, not notarized** (D-079): Gatekeeper warns; no Apple account. Only the Linux binary is exercised by CI.
- **Modding is unproven by a stranger** (S45): nobody outside the repo has written a mod; the validator checks what the tests knew to check and nothing about balance, art sheets or audio files; Workshop upload is M4.

## Balance (M4 sessions, after the playtest)

- **Depth 3 after balance pass 1** (S48, D-103): the Undercity extracts 45% of depth-3 runs naive, the Cathedral 40%, the Loom Approach 30%, the Ghost Markets 30% (their long cantor fights kite a naive party; a person focuses the cultists), the Datacore 40% at depth 2; floors sit just under those. The medkit, the breather and the wind-up were chosen on the naive policy and have not met a person.
- **The Key keepers are unmeasured** (S41): they fight inside Shards, so the harness cannot row them, and the Quiet Key's keeper under the Cathedral wipes naive play at level 9; the campaign test lets every fight fall by fiat for that reason.
- **The Loom** (S42, S48): the Voice sits at 35% naive wins at level 11 with a 20% floor, the hardest fight by design; the Ashfound strike team is a walkover.
- **Economy and approval are measured, not played** (S49, D-104): the road banks 14 salvage and 3 Aether against a 12/2 Beacon step; a depth-1 extraction ~20 salvage, 4 Aether, 52 XP, a depth-3 one ~41/10/97; Sera and Kaj-7 clear loyalty (4) and romance (5) by the Keys on every path with the kinder choices, and the campaign test asserts it; Dax on the two paths that wound him and any companion left at the Bastion do not, by design. All of it under the naive policy; a person may spend and choose differently.

## Content (wired, not dense)

- **Length**: Act 1 is nine beats, four handcrafted fights and four Shard runs, two to three hours against the GDD's eight; Act 2 is the oath, one site and one report per path, one site per loyalty, three voices, three delves and the catastrophe; Act 3 is one Shard and one hall. No writing pass has happened; the relay hub has one fight, the loyalty and Key sites are one dialogue each, and the Loom's hall has one lore fragment and no companion lines of its own.
- **Consequences past the door**: joining opens a path quest, an area and a vendor, but the areas never change and nothing past the Key is written per faction; a benched companion still counts as recruited for scenes, loyalty and endings; no ending has a line for a companion who resisted the catastrophe beyond the alive one.
- **Items are thin** (S29, D-084): twelve bases and eight affixes plus the example mod's lamp, one crate pickup type, no consumables or resource costs on gear, no item art beyond a colour, no family-specific drop tables, no sell-back.
- **Enemies on a previous map are forgotten** when you leave it (map-placed enemies respawn on re-entry); transitions fire on step-on with no confirmation.
- **The credits** name an artist, a composer and a first playtester who do not exist yet.

## Systems (M4)

- **Combat texture is shallow**: cover, elevation, surfaces and resources exist and the AI weighs them (D-067); no movement cost for elevation, no hackable turrets or doors; difficulties overlay the rules (S50) but nobody has played Tactician; enemies never move in exploration; awareness is a radius, not a cone; no attack of opportunity.
- **Five AI archetypes** share one texture score with focus fire and a once-per-fight retreat (S28); hidden combatants are drawn faint for both sides; no true fog or detection roll.
- **Progression v2 leftovers** (S31, D-086): the second class of a multiclass has no subclass and no resource loop of its own; the Weave is the only place levels move and there is no preview of what a level would give; talents are still flat stat bumps; capstones are one ability each with no story of their own.
- **Pad support is functional, not native**: the combat cursor steps one cell per press, no analog glide, no rumble; mouse is still the fastest way to target.
- **Creator is a text screen**: no appearance beyond the race overlay, no portrait, not part of New game (C at home); origins gate lines and unlocks but nothing mechanical; the Swarmborn disguise is an arcane check, not a roll; Synth still cannot repair with parts; Skyborn knowledge is a tag.
- **Saves**: F5/F9 still mean slot 1; Iron Weave (S50) has no mid-combat save, so a fight walked out of restarts from its checkpoint rather than counting as a loss, and the finished run's autosave stays as a record; no confirmation on overwrite; content mismatches are refused (D-080); a save inside a Shard is refused when `ShardGenerator.LAYOUT_VERSION` moves, which is by hand.
- **Movement is placeholder-simple**: followers pass through each other, no actor collision, WASD lets you stand visually behind a tall wall; party settling snaps with no animation.
- **Map format is ASCII-only** for handcrafted maps by design (D-028).
- **The campaign test wins its fights by fiat** and pins the global RNG; it proves wiring, not balance, and runs in its own CI job under a twenty-minute budget.
