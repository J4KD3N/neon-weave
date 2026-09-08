# M2 — Steam Demo plan

GDD §14: *Act 1 (~2-3 hrs), 2 biomes, 3 companions (Sera, Kaj-7, Dax), Lattice introduced, 6 classes, 5 races, Steam integration, 3-platform exports, store page. Wishlists.*

M1 gave us one hour that runs end to end on keyboard and pad. M2 has to turn that into something a stranger downloads from Steam, plays for two or three hours, and wishlists. That is three different kinds of work, and the plan keeps them apart:

1. **Systems** the demo cannot ship without (progression, the last two classes, better AI, a second biome, campaign tooling, a front end, audio, Steam, release).
2. **Content** authored on top of those systems (Act 1 opening, two companions, the Lattice, the second biome's enemy family).
3. **Art and store assets**, which the repo cannot produce. They run in parallel with an artist and are a hard gate on "store page", not on any code session.

One system per session (GDD §15). Each session ends with a PR, decisions, gaps, tests, and a CI screenshot. Content sessions ship their content *and* the schema validation for their kind.

## Sessions

| Session | System | Why here | Done when |
|---|---|---|---|
| **S13** | **M1 playtest triage**: fix what the first full keyboard + pad playtests turn up; camera pan to the acting combatant; move undo; save-slot picker | The M0/M1 question ("is it fun?") finally has an answer and it will list bugs before features | Every playtest finding is a closed issue or a gaps entry with a session assigned |
| S14 | **Progression**: XP → levels 1–6 for the demo (cap in `rules/progression`), per-level stat growth and ability unlocks from class data, subclass choice at level 3 (two per class, as data), Aether talents as a minimal Weave Tree, Arcanum respec | XP and Aether have had no sink since M0; a 3-hour demo needs the character to change | Level-up, subclass and talent are registry data; a saved level-3 Stormcaller reloads as one; the Arcanum is a fourth Bastion building |
| S15 | **Classes 5–6**: Wireghost (Heat: stealth and hacks build it, overheating reveals; hidden state, ambush bonus) and Null Blade (Null: absorbs arcane damage as fuel; silence zone) | Completes the six-class roster and forces two generic mechanics, stealth and damage-type absorption, through the resource vocabulary | Both playable with subclasses; one enemy family member uses stealth; `test_classes_5_6.gd` |
| S16 | **Enemy AI v2**: summoner, controller and stealther archetypes; cover, elevation and surface awareness; elite and boss templates; depth scaling of stats and pools (closes D-038) | The AI ignores every S7 mechanic; fights are only tactical for one side | Each archetype has a scripted test fight it wins against a naive party; depth 3 is measurably harder than depth 1 |
| S17 | **Biome 2, Verdant Datacore**: palette, tiles (spore surface, canopy height, biogrowth variants), room styles, enemy family (4 types + elite + boss), Beacon unlocks biomes as well as depth | Second biome is an M2 exit criterion and the first test that biomes are data | `--shard` renders it in CI; validator passes 100 seeds; family AI mix uses S16 archetypes |
| S18 | **Shard features**: secrets, vaults opened with Ciphers, a merchant, extraction waypoints, difficulty ramp by distance from spawn, loot rarity + affixes | GDD §11 lists these as what makes Shards replayable; Ciphers get their sink | Generator emits all four features as data; every feature has a validator rule |
| S19 | **Campaign tooling**: map format v2 (triggers, doors, scripted events, transitions), quest system v2 (objectives, journal, main-quest stages), a dedicated Bastion map with visible building levels | Act 1 is handcrafted; nothing authored can exist until the map format can express it | The yard is replaced by a Bastion map; one authored story map with a door, a trigger and a transition plays end to end in a test |
| S20 | **Kaj-7 and Dax**: registry entries (Vaultkin race entry for Dax, companion-only for now), personal quests that intersect the main plot, three-way banter, approval scenes, both death-stakes paths | Three companions is the M2 exit criterion; two more prove the S11 data model scales without engine changes | Both recruitable in Act 1; `test_content_narrative.gd` covers their graphs; no engine change was needed (GDD §15) |
| S21 | **The Lattice**: faction data model (reputation, faction NPCs, faction-coloured dialogue and approval), the Lattice introduction quest, Kaj-7 tension hook; joining stays locked until Act 2 | "Lattice introduced" is an exit criterion; factions are the Act 2 engine and need their data shape settled now | Faction reputation in saves; Lattice reachable and refusable in Act 1; Sera and Kaj-7 react per the casting rule |
| S22 | **Act 1 demo slice**: the first 2–3 hours of Act 1 authored on S19 tooling: expeditions going wrong, the party assembling, ending at a cliffhanger before first contact; demo boundary and "thanks for playing" | This is the product | Playable start to demo end without the debug keys; every quest has both death-stakes paths; content schemas validate |
| S23 | **Front end**: title screen, new game with death-stakes choice, settings (video, audio, input remap to `user://input.json`), save-slot UI, pause menu, pad glyph swap | A demo starts at a title screen, not in a yard | Cold start to gameplay through the front end on pad alone; settings persist |
| S24 | **Audio pipeline**: data-defined sound events on abilities, surfaces, UI and footsteps; music per biome and state (explore, combat, Bastion); placeholder generated audio | There is no sound at all; a silent demo reads as broken | Every ability and surface has an event; music crossfades on state change; content kind `audio` with schema |
| S25 | **Steam**: GodotSteam backend behind `Platform` (achievements, cloud saves, demo depot id, Steam Input default template mirroring `docs/controller.md`); Steam-free build stays the default and what CI runs | Exit criterion; D-007 said M2 | Achievements and cloud sync work in a local Steam client; the null backend passes the same contract tests |
| S26 | **Release**: first tagged build (`v0.2.0-demo`) through `release.yml` on all three platforms, macOS signing decision, `build/.gdignore`, demo depot layout, store-page asset checklist fed by the CI screenshot job | "Never break the exports" has never been tested by a tag | Three downloadable builds from one tag; a fresh machine runs each to the demo end |
| S27 | **Demo tuning**: balance pass on the demo slice only (rules, class and enemy numbers), content-version check on saves, final gaps triage | The demo is judged on feel; M4 is the real balance pass but a wishlisting demo cannot wait | Two external playtesters finish the slice; save from a different content set is refused, not misloaded |

## Parallel tracks (not sessions)

- **Art**: the S10 pipeline takes real sheets as file-for-file replacements. The demo needs 5 race rigs with overlays, ~10 enemies across two families, two tilesets, portraits for three companions, and a capsule. This needs an artist; every session before S26 keeps the generated placeholders so nothing blocks on it. Decision point at S22: ship the demo with placeholders and a clear "art in progress" note, or hold for art.
- **Store page**: capsule, trailer, screenshots, description. The repo contributes `screenshot` job PNGs and the S26 builds. Needs a Steamworks account and the demo depot before S25 can be tested for real.
- **Playtesting**: after S13, S19, S22 and S27, a full playthrough by someone who is not the author.

## Out of M2 scope (M3+)

Romance, joinable factions and their vendors/areas, races 6–10, Act 2 and 3, the Loom, the Archive assembling lore, Garden and Quarters, multiclassing and capstones, localization, Steam Deck performance tuning, real Apple notarization.

## Order and dependencies

S13 first because playtest findings may reorder everything after it. S14 before S15 so the new classes ship with subclasses. S16 before S17 so the new family has behaviours to use. S19 before S20–S22 because companions and the act need authored maps. S23–S24 late because they are polish with few dependants, but before S25 because Steam achievements and cloud hooks hang off the front end. S25 before S26 because the release includes the Steam build. S27 last.

## Running assumptions

- **Demo length** is 2–3 hours of Act 1's ~8, ending before first contact with the lucid Choir fragment so the full game keeps its reveal. Revisit at S22.
- **Level cap 6 in the demo** (subclass at 3, one talent tier). The full game's cap is `[12]` per the GDD and lives in `rules/progression` from S14.
- **Dax is a Vaultkin**, a race outside the five playable M2 races. It ships as a companion-only race entry with a rig overlay; making it playable is M3 with races 6–10.
- **Placeholder art can ship in the demo** if no artist is attached by S22; the store page cannot.
- **Steam is never required**: CI, tests and the open repo run the null backend; GodotSteam is a GDExtension in `addons/` loaded only when present.
- **No balance pass before S27**; sessions may adjust `content/rules/` for their own feature.

## Progress
- S13 playtest triage — done (camera pan, move undo, three-slot save picker, soak test in `test_soak.gd`). Human playtest findings still land here as follow-ups.
- S14 Progression — done: party level from banked XP (cap 6), class growth/unlocks, eight subclasses with one ability each, six talents, the Arcanum, the Weave menu (T at home). D-064.
