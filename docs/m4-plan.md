# M4 plan — Polish and 1.0

Written at the close of M3 (S46, 2026-09-21). M3 made the game content complete: three acts wired end to end on every path, five endings, six companions, four romances, three factions, ten races, four biomes, seven buildings, modding docs and a validator, `v0.3.0` from one tag. M4 makes it good, and ships it. GDD §14: balance, Steam Deck performance, localization scaffolding, launch.

## What M4 is for

1. **Balance** over the whole game, with people. The harness (`test_balance.gd`) stands in for playtesters today; M4 starts with the first external playtest and reorders the rest by what it finds.
2. **The tracks that need people** land: art, audio, Steam, Apple. Each is a hand-off doc already (`docs/art-pipeline.md`, `docs/store-page.md`, `steam/`); M4 sessions integrate what comes back.
3. **Polish the surfaces**: the creator as a screen, dialogue with portraits, the pad as a first-class input, saves with slots and confirmations, accessibility.
4. **Ship**: notarized macOS, Steam depots, Workshop, `v1.0.0`.

## Sessions

| Session | Work | Done when |
|---|---|---|
| S47 | **First external playtest** and its triage: two people finish Act 1; findings ranked; `test_balance.gd` bands moved to what they found | A triage doc with owners; the harness bands match the playtest |
| S48 | **Balance pass 1, fights**: depth-3 extraction off the floor, the Key keepers and the Loom's Voice rowed and in band, the Cathedral survivable with retreat and heals, boss telegraphs | Every harness row in band; depth 3 extracts 40%+ naive |
| S49 | **Balance pass 2, economy and approval**: building costs, loot ranges, XP, approval per act so loyalty (4) and romance (5) are reachable where the story expects them | A walkthrough reaches approval 5 by the Keys without setting it |
| S50 | **Difficulty settings and Iron Weave**: three difficulties as rules overrides; Iron Weave (one save, Mortal, no reloads) as an account flag | Each difficulty is a rules entry; Iron Weave completes the campaign test |
| S51 | **Creator as a screen**: appearance overlays, portraits (placeholders), origins on New game, attribute preview of what a point buys | The creator is the first screen of a new game |
| S52 | **Dialogue and journal surfaces**: portraits in the panel, a log, quest tracking on the HUD, the Roster and Quarters as one screen | Every text panel has a face and a history |
| S53 | **Pad and Deck**: analog glide, rumble, the Deck's resolution and font sizes, a performance budget per map and Shard size | 60 fps on a Deck-class target in every biome at the largest Shard |
| S54 | **Saves and settings**: slots with names and thumbnails, overwrite confirmation, autosave rotation, music and SFX buses, accessibility (glyphs, text size, colour-blind palettes) | A settings screen a stranger can use |
| S55 | **Localization scaffolding**: every string through a table, a pseudo-locale test, the content kinds' text fields enumerated for translators | The game runs in pseudo-locale with no untranslated string |
| S56 | **Art integration**: the pipeline fed with real sheets as they arrive; palette and lighting pass; the CRT and glow polish; screenshots for the store | Every race and family has a sheet or a documented placeholder |
| S57 | **Audio integration**: recorded SFX and composed music behind the same events; buses; a music state machine per act | No synthesised placeholder remains on a shipping path |
| S58 | **Steam**: GodotSteam binaries, app id, achievements verified live, cloud saves, Steam Input, the demo depot with `--demo`, Workshop upload of a mod folder | The demo and the full game both on a Steam client |
| S59 | **Apple**: notarization, the universal binary, Gatekeeper clean | A macOS stranger opens the app without a warning |
| S60 | **1.0 close**: the campaign test green at every difficulty, gaps triage, `v1.0.0`, the store page live | Launch |

## Running assumptions

- **Playtesting first.** Nothing in S48–S50 is authored before S47's findings; the harness bands are hypotheses until then.
- **Content is complete; M4 does not add beats.** Writing lands as line replacements through the same data; the reactivity test and the validator keep the criteria met.
- **Placeholders ship until replaced**, with the title-screen note, as in every build since `v0.2.0-demo`.
- **The campaign test is the release gate**: no tag without it green on every path in both modes, at every difficulty once S50 lands.

## Progress
- S47 First external playtest — kit ready, playtest pending people: `-- --playtest` writes a log of what the harness measures (maps, fights, runs, choices, the ending); `tools/playtest_report.gd` turns a folder of logs into the triage table beside the harness bands; `docs/playtest.md` has the script, the questions and the triage template with owners. The harness bands move when two people have played. D-102.
- S48 Balance pass 1, fights — done without the playtest (the user's call): lab rounds as harness overrides, then landed: a lighter depth curve (0.10), a softer boss (2.5) with a wind-up round, a breather after a win (0.2), medkits in every Shard pool, depth adds at most one group, the Cathedral and the Approach lighter, the Choir acting second with a weaker bolt and one wisp. Harness: Undercity d3 45%, Cathedral d3 40%, Approach 30%, Markets 30% (under the 40% aim; the long cantor fights are hostile to naive play by design), the Voice 35%, every row in band. D-103.
