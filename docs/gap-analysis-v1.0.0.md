# Neon Weave — gap analysis at v1.0.0

Date: 2026-09-24. Measured against the game's own design (`docs/GDD.md`: the four pillars, the system targets, the milestone roadmap), the working agreement, and what the repository can prove about itself (477 unit tests, the campaign test, four status tools, the CI jobs). Sources: `docs/gaps.md` as triaged at S60, `docs/decisions.md` (D-001 to D-115), the readiness and status reports, and the code.

## Where the project stands

| Measure | Value |
|---|---|
| Span | 2026-09-08 to 2026-09-22, 60 sessions, 77 commits, 115 logged decisions |
| Code | ~16,300 lines of GDScript; 67 test files, 477 tests, plus the campaign job |
| Content | 11 handcrafted maps, 5 Shard templates, 69 dialogues, 25 quests, 6 companions, 10 races, 6 classes, 5 endings, 3 factions, 7 buildings, 26 enemies |
| Release | `v1.0.0` on GitHub: Windows, Linux, universal macOS, from one tag; the Linux binary smoke-tested in CI |
| Gates | Campaign test: 25 endings (every path, every difficulty, both modes, Iron Weave) green in CI. Perf budget green. Art status: 2 sheets of 36 bodies. Audio status: 0 files of 38. Steam readiness: 3 blockers. Apple readiness: 0 blockers, 0 secrets. |

**Verdict in one sentence.** The software is complete, tested and shippable as an open-source game; the *product* the GDD describes (a 30-hour, art-and-music-bearing Steam title) is roughly one third of the way there, and every remaining third needs a person, money, or both rather than another engineering session.

## Severity scale

- **S1 Launch blocker.** Cannot ship on Steam as the GDD intends without it.
- **S2 Major.** A player finishing the game would notice and be hurt by it; or a design pillar is only half met.
- **S3 Minor.** Polish, or a promise the GDD made that nobody has asked for yet.

Owner is who can close it: **Person** (a role the project does not have), **Money** (an account or a commission), **Session** (an AI session can do it), or **Both**.

## 1. Promises the GDD made that have nothing behind them

Rows two to six closed on 2026-09-24 (S61 to S64, D-117 to D-120; `docs/m5-plan.md`); the table stands as the record of what was found. Row one, the 30-hour campaign, stays with a writer, and the store page now states the shipped length.

These are the gaps that `docs/gaps.md` does not list because they were never started, found by reading the GDD against the code.

| Gap | GDD source | Severity | Owner | Closing action |
|---|---|---|---|---|
| **A 30+ hour handcrafted campaign.** Act 1 is two to three hours; Acts 2 and 3 are wired, not dense. Total play is an estimated four to six hours on a first run. | §1, §11 | S1 for the store page (the promise is the pitch), S2 for the game | Person (a writer) + Session (the data format takes lines without code) | A writing pass per act: more beats per hub, companion lines at every site, per-faction consequences past the Key. Order of magnitude: 20 to 40 sessions of writing, or a writer with the schema doc. |
| **Gore slider.** Named in §9; no setting, no gore, no decals. | §9, §5 ("blood decals, corpse tiles") | S3 | Session | A `gore` setting (off/low/full), a decal layer on death in combat, corpse tiles left on the map; `blood` already exists in every palette. One session. |
| **Account unlocks beyond origins**: loadouts and cosmetics. | §12 | S3 | Session | Two more unlock kinds on the account; the account and the creator already take keys. One session. |
| **Hackable turrets and doors.** | §9 | S3 | Session | A `hack` interaction on `shepherd_turret` and locked doors, gated by Tech. One session. |
| **Mature tone in the environment layer**: blood decals, corpse tiles, grime, failing lights. | §5 | S2 (the pillar "gritty and mature" is carried by text alone today) | Session + Person (art) | The decal layer above; the rest is art. |
| **Awareness as a cone; a detection roll; true fog of war.** | §9 (stealth openers) | S3 | Session | Stealth works as a radius and a hidden flag today; a cone and a roll are one session. |

## 2. Verification gaps: things built but never touched by reality

The biggest category. Everything here is a claim the code makes about itself that no human, device or live service has checked.

| Gap | Evidence | Severity | Owner | Closing action |
|---|---|---|---|---|
| **Nobody outside the author has played it.** M2's exit criterion, still unmet at 1.0. Balance, pacing, clarity and fun are all unmeasured. | `docs/playtest.md`, S47 kit, empty triage table | **S1** (the single largest risk) | Person | Two players, one session each. `-- --playtest` writes the log; `tools/playtest_report.gd` turns logs into the harness's own tables. Cost to the project: nil beyond finding two people. |
| **Steam has never touched a live client.** Achievements, cloud, Steam Input, the demo depot, the Workshop upload: all coded against the API, none run. | `steam/READINESS.md`: three blockers (GodotSteam, app id, depot ids) | S1 | Money (Steamworks fee) + Person (ten checklist steps) | `steam/CHECKLIST.md`. Expect one or two rounds of fixes on first contact: the UGC signal shapes and the cloud file API are the likeliest to differ from the code's assumptions. |
| **The notarized macOS build has never been produced or run.** The workflow is proven only on its fallback path. | `apple/READINESS.md` ready; secrets absent | S1 for Mac players | Money (Apple membership) + Person (a Mac) | `apple/CHECKLIST.md`. The first tag with secrets is the real test of rcodesign against Godot's export; budget a fix round. |
| **60 fps on a Deck is unmeasured.** Logic is ~0.3 ms a frame headless; rendering on the target has never been read. | `rules/performance`, `--perf` | S2 | Person (a Deck) | Run `--perf` in every biome at the largest Shard; read the number. If it misses, the lighting budget (`max_lights`) and the screen-effects pass are the first levers. |
| **The Key keepers and the Loom Voice are unmeasured by the harness** (fights inside Shards) and won by fiat in the campaign test. | gaps "Balance" | S2 | Session + Person | The playtest logs cover them; or a harness row that stages the keeper fight directly. One session for the row. |
| **The colour-blind pass** has not been seen by anyone with protanopia, deuteranopia or tritanopia. | S54 | S3 | Person | One tester per type, one screen each. |
| **No language but English**; text expansion, plurals, RTL and non-Latin fonts are unmeasured. | S55 | S2 for any non-English market | Person (translator) | The template is generated by CI; one language filled would expose the panel-width and plural problems in an afternoon. |
| **Modding is unproven by a stranger.** | S45 | S3 | Person | One outside mod. The validator and the Workshop path exist. |
| **Save thumbnails** have never been captured from a rendered frame in CI. | S54 | S3 | Session | A screenshot-job step that saves a slot and reads the PNG back. Half a session. |

## 3. Placeholder gaps: what ships generated

| Gap | Evidence | Severity | Owner | Closing action |
|---|---|---|---|---|
| **Art.** Two generated rigs stand for 36 bodies; tiles, portraits, buildings and pickups are generated; no capsules, no trailer, no store art. | `docs/art-status.md`, `docs/store-page.md` | S1 for Steam (a store page cannot open without capsules; placeholder sprites will read as unfinished) | Money (an artist) | `docs/art-pipeline.md` is the hand-off: a sheet is a PNG beside a sidecar, race overlays composite, the lighting and the palette do the neon. Sprites: 10 races, 26 enemies, ~20 tiles, 7 buildings; portraits: 6 companions plus NPCs; store: 5 capsules and a trailer. |
| **Audio.** All 38 entries are synthesised. | `docs/audio-status.md`; `tools/audio_status.gd --strict` is red | S1 for Steam, S2 for the open-source game | Money (a composer and a sound designer) | `docs/audio-pipeline.md`. Ten tracks (title, Bastion ×2, combat ×2, five biomes) and 28 effects; a file beside each sidecar, no code. The gate turns green by itself. |
| **The credits** name an artist, a composer and a playtester who do not exist. | gaps "Content" | S3 | Session | Edit `rules/credits` when they exist. |

## 4. Balance gaps

All measured under the harness's naive policy; none met a person.

| Gap | Numbers | Severity | Owner |
|---|---|---|---|
| Depth-3 extraction: Undercity 45%, Cathedral 40%, Markets 30%, Loom Approach 30% naive. The Markets stay low because a naive party chases kiting cantors. | S48, D-103 | S2 | Person (playtest), then Session |
| The Loom's Voice: 35% at level 11 with a 20% floor, by design the hardest fight. | S42, S48 | S2 | Same |
| Economy and approval: the road pays the Beacon's first step exactly; loyalty (4) and romance (5) reachable by the Keys with the kinder choices; Dax and benched companions do not. | S49, D-104 | S3 | Same |
| Tactician has never been played by anyone; its numbers are the Balanced numbers scaled. | S50 | S3 | Person |

## 5. Content density gaps

| Gap | Severity | Owner | Closing action |
|---|---|---|---|
| Acts 2 and 3 are one site, one report and one hall per beat; the Loom has no companion lines of its own. | S2 | Session (writing) | The writing pass in §1. |
| Consequences past the door: faction areas never change; nothing past the Key is written per faction; a benched companion counts as recruited for scenes and endings; no ending line for a companion who resisted the catastrophe. | S2 | Session | Per-faction late-game lines and area states; a `benched` condition on scenes and epilogues. Two sessions. |
| Items are thin: twelve bases, eight affixes, one crate, no consumables, no sell-back, no family drop tables. | S2 for pillar 4 (expression) | Session | Consumables and family tables are data; sell-back is one merchant verb. Two sessions. |
| Enemies on a left map respawn; transitions fire on step-on. | S3 | Session | Persist map deltas in the narrative; a confirm on transitions. One session. |

## 6. Systems gaps (pillar 1: tactical combat)

| Gap | Severity | Owner |
|---|---|---|
| No attack of opportunity, no movement cost for elevation, no cone awareness: positioning matters less than the pillar wants. | S2 | Session (one each) |
| Five archetypes share one texture score; hidden units drawn faint for both sides. | S3 | Session |
| Multiclass: no second subclass or resource loop; talents are flat stat bumps; capstones have no story. | S3 | Session |
| Pad: cell-stepped cursor, no gyro or trackpad path; mouse is fastest. | S3 | Session + Person (Deck) |
| Creator: appearance is a tone and an accent; origins gate lines only; Synth cannot repair with parts; Skyborn knowledge is a tag. | S3 | Session, some blocked on art |
| Saves: F5/F9 overwrite without asking; three autosaves by constant; no mid-combat save (Iron Weave restarts a fight it left). | S3 | Session |
| Movement: no actor collision, no settling animation. | S3 | Session |

## 7. Engineering and process gaps

Closed on 2026-09-24 (D-116); the table stands as the record of what was found.

| Gap | Severity | Owner | Closing action |
|---|---|---|---|
| **The campaign test wins fights by fiat** and pins the RNG: it proves wiring, not play. | S2 | Session | Keep it; add a second job that plays a subset with the naive policy and a wide tolerance, so a balance regression trips something. One session. |
| **No editor-side testing.** Every test is headless; nothing checks what a menu looks like beyond the screenshot job, which is best-effort. | S3 | Session | Make the screenshot job required and diff a few frames against golden images with a tolerance. One session. |
| **No crash reporting or telemetry** beyond the opt-in playtest log. | S2 for launch | Session | A crash handler that writes `user://crash_<stamp>.txt` and a title-screen prompt to send it. One session. |
| **Godot version drift.** The project targets 4.7.2; `project.godot` said 4.6 until S59 fixed the version line, and the editor settings the notarize step writes are pinned to 4.7. | S3 | Session | Pin the engine version in one place and a CI check that the workflow, the presets and `project.godot` agree. Half a session. |
| **Tests wrote the player's real files** until S55 (settings, bindings); the account file is still the real one in a few older tests. | S3 | Session | Point the remaining tests at their own account path. Half a session. |
| **The CI matrix** runs Linux only for the game; Windows and macOS binaries are exported but never executed. | S2 for those platforms | Session + Person | A Windows runner smoke step is one session; macOS needs the notarized build and a Mac. |
| **Security scanning** covers the repo (Trivy, SBOM) but nothing covers mods at load: a mod is JSON, but a sprite PNG or an audio file from the Workshop is read from disk unvalidated. | S3 | Session | Size and format caps on mod media in the validator and the loader. Half a session. |

## What to do next, in order

1. **Two playtesters this week.** Free, and it decides everything in §4 and half of §5. Hand them `docs/playtest.md`; send back `session_*.jsonl`; one session turns the logs into the next balance and writing plan.
2. **The Steamworks account.** One fee unblocks the demo page, the achievements, the cloud and the Workshop, and turns three of the four S1 rows into checklist ticks. Budget a fix round for first contact with the live API.
3. **Commission art before audio.** Art blocks the store page and the Steam review; audio blocks nothing but feel. The pipeline docs are the briefs; the status tools show the artist and the composer what remains as they deliver.
4. **The writing pass**, act by act, with the playtest findings in hand. This is the only S1 row that is mostly session work, and it is the biggest.
5. **The Apple membership** last: it matters only once there are Mac players, and the workflow is already waiting.
6. **Systems polish from §6 and §7** as filler between the above: attacks of opportunity, the naive-policy job, crash reports, the gore slider.

## Top risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The store page promises 30 hours and ships four to six. | High, if the pitch is not rewritten | Refund rate, reviews | Rewrite the pitch to the game that exists, or do the writing pass first. |
| Balance is wrong in a way the harness cannot see. | High until someone plays | Frustration in the Markets and at the Voice; the Cathedral keeper | Step 1 above. |
| First contact with the live Steam API needs code changes. | Medium | A week of fixes | The checklist expects it; the null backend keeps CI green meanwhile. |
| Notarization fails on the first real tag. | Medium | Mac build stays ad-hoc | The verify step and the notary log; the checklist names the usual causes. |
| Placeholder art reads as unfinished on Steam's review. | High without art | The page is rejected or ignored | Step 3. |

`docs/gaps.md` is the living version of this document: §2 to §7 were already there, and §1 and §7 were folded in on 2026-09-24.
