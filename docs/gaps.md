# Gaps & assumptions

Updated every session. Remove items when closed; note the closing commit.
Triaged at the end of M4 (S60, 2026-09-22, `v1.0.0`): closed items are gone
(see `docs/decisions.md` and git history); what is left is grouped by who
can close it and ordered by how much it hurts a player.
The full analysis with severities, owners, an order of attack and a risk
table is `docs/gap-analysis-v1.0.0.md` (2026-09-24).

**The 1.0 verdict.** The code and the content are complete and gated: the
campaign test plays every path on every difficulty in both modes and under
Iron Weave, every lever is data, and three status tools (`art_status`,
`audio_status`, `steam_check` with `apple_check`) say exactly what is still
generated or unverified. What 1.0 does not have is anything that needs a
person other than a session: a playtester, an artist, a composer, a
Steamworks account, an Apple membership. Each has a hand-off doc, a
checklist and a gate that stays red until it lands; the first section below
is that list. Nothing in the other sections blocks a player from finishing
the game.

## Needs a person (not a session)

- **Nobody outside the author has played it.** M2's exit criterion "two external playtesters finish the slice" is still unmet and M3 added two acts on top. The kit is ready (S47, D-102): `docs/playtest.md`, the `--playtest` log and `tools/playtest_report.gd`; the triage table is empty until two people have played, and the harness bands stay hypotheses until then.
- **Art is generated placeholders** (S56: every race and enemy says so in its entry, `docs/art-status.md` lists them, and the engine now lights the neon and glows the frame, but the sheets are still the generated rig): every build ships them with a title-screen note (D-079). The store page has no capsules, trailer or artist (`docs/store-page.md`). The pipeline is real (S10); the only sheets are tool-generated rigs for Trueborn and Scav; every other race, family and NPC uses the standard rig with an overlay. `docs/art-pipeline.md` is the hand-off.
- **Audio is synthesised placeholders** (S24; S57: every entry says so in `docs/audio-status.md`, a file beside the sidecar replaces it without a code change, and `tools/audio_status.gd --strict` is the gate that stays red until the last one lands): no recorded sound or composed music; the buses exist since S54.
- **Steam is wired but unverified** (S25, D-078; S58: `steam/READINESS.md` names the three blockers, GodotSteam, the app id and the depot ids, and `steam/CHECKLIST.md` is the ten live steps): no GodotSteam binaries, app id or Steamworks definitions here; achievements (twelve, five for the endings), cloud sync, the Steam Input template and the Workshop upload have never touched a live client; the demo depot must launch with `--demo`.
- **macOS is ad-hoc signed, not notarized** (D-079; S59: the release workflow notarizes with rcodesign the moment the five `APPLE_*` secrets exist, `apple/READINESS.md` says the checkout is ready, and `apple/CHECKLIST.md` is the nine live steps): Gatekeeper warns; no Apple account. Only the Linux binary is exercised by CI; the signed build has never been run on a Mac.
- **Modding is unproven by a stranger** (S45): nobody outside the repo has written a mod; the validator checks what the tests knew to check and nothing about balance, art sheets or audio files; Workshop upload is M4.

## Promised by the GDD, never started (found 2026-09-24)

- **A 30+ hour handcrafted campaign** (GDD §1, §11): the game plays four to six hours on a first run; Act 1 is two to three of them. The store pitch must say what exists, or the writing pass comes first. Owner: a writer, or sessions through the same data (`docs/content-schemas.md`).
- Closed 2026-09-24 (S61, D-117): a Gore setting (off / low / full), blood where a hit lands, a pool where someone goes down, a body where someone dies, kept with the save; machines leak oil; grime and failing lights dress the yard and every Shard. Left for art: real decal sprites and corpse poses in place of the placeholder shapes.
- **Account unlocks beyond origins** (§12: loadouts, cosmetics): the account and the creator take keys, but only origins are granted. One session.
- **Hackable turrets and doors** (§9): none. One session, gated by Tech.
- **Awareness as a cone and a detection roll** (§9, stealth openers): awareness is a radius and a hidden flag. One session.

## Engineering and process

- Closed 2026-09-24 (D-116): the Windows and macOS builds boot in CI before a release publishes; crash reports from the engine log; caps on mod media; the screenshot job is required and checks every frame; tests cannot touch the player's files; the engine version is held in one test. Left: the Windows and macOS smokes boot headless and quit, they do not play; a rendered Windows frame is best-effort; the crash report is a file the player must send by hand.

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
- **No language but English exists** (S55): the table, the template and the pseudo test are the scaffolding; nobody has filled a table, so plural rules, text expansion in fixed panels, right-to-left scripts and font coverage for non-Latin scripts are unmeasured; the dialogue history keeps lines in the language they were shown in; ids that reach the screen as words (a faction lean, a slot, a status) translate by id, not as content.
- **The colour-blind pass is untested by anyone who needs it** (S54): the Machado matrices and a standard daltonizing shift, on the whole frame; no per-element palette swap; nobody with protanopia, deuteranopia or tritanopia has said whether it helps.
- **Pad support is functional, not native** (S53): the stick walks and glides the combat cursor at its tilt and rumble marks hits, downs, wins, wipes and extractions, but the cursor is still cell-stepped, there is no gyro or trackpad path, and mouse is still the fastest way to target.
- **60 fps on a Deck is unmeasured** (S53): no Deck in the house; `rules/performance` and `tools/perf_budget.gd` hold the counts and the headless logic cost (~0.3 ms a frame in the largest Shard after the door cache), and `--perf` shows fps in a build, but rendering on the target has not been read. Text size and fullscreen default to the Deck on a 1280×800 Linux screen by heuristic, not by a Steam API.
- **Text panels have rig portraits, not drawn ones** (S52): every speaker with a body gets a face generated from the placeholder rig; the narrator and the Choir have none by design; the dialogue history is three lines in the panel and twelve in the journal, with no scrollback; quest tracking is one HUD line, not a map marker.
- **Creator is a text screen with a placeholder portrait** (S51): the first screen of a new game, with a tone and an accent as the only appearance choices (the placeholder rig can show no more; the placeholder sprite sheets have no `skin`/`accent` palette roles yet, so a Trueborn on the real sheet keeps the class tint), the portrait generated from the rig, no drawn portraits until the art track delivers; origins gate lines and unlocks but nothing mechanical; the Swarmborn disguise is an arcane check, not a roll; Synth still cannot repair with parts; Skyborn knowledge is a tag.
- **Saves** (S54): F5/F9 are the quick path to slot 1 and do not ask before overwriting (the saves screen does); titles are made, not typed; thumbnails need a rendered frame, so none exist from headless runs and CI has not looked at one; older autosaves are three deep by constant, not by setting; Iron Weave (S50) has no mid-combat save, so a fight walked out of restarts from its checkpoint rather than counting as a loss, and the finished run's autosave stays as a record; content mismatches are refused (D-080); a save inside a Shard is refused when `ShardGenerator.LAYOUT_VERSION` moves, which is by hand.
- **Movement is placeholder-simple**: followers pass through each other, no actor collision, WASD lets you stand visually behind a tall wall; party settling snaps with no animation.
- **Map format is ASCII-only** for handcrafted maps by design (D-028).
- **The campaign test wins its fights by fiat** and pins the global RNG; it proves wiring, not balance, and runs in its own CI job under a twenty-minute budget.
