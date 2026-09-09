# M3 — Content Complete plan

GDD §14: *M3 — Content Complete: full campaign + all endings, all companions/romances, factions, 10 races with reactivity, biomes, modding docs.*

M2 turned the systems into a demo a stranger can download. M3 has to turn the demo into the whole game: three acts (~30 hours per §2), four endings plus the secret one, six companions with four romances, three mutually exclusive factions that change vendors, areas and endings, ten playable races with reactivity, four biomes, the Loom, and modding docs good enough that other people build on the same registry.

That is more content than sessions. The M2 lesson (D-075, S22) is that a session can author a beat *thin* and *wired*: every map, trigger, quest stage, fight and branch exists in data, both death-stakes modes hold, and a test walks it end to end; prose density and length come from a writing pass that no session can do alone. M3 plans on that split explicitly:

1. **Systems the campaign needs** that do not exist yet: items and cyberware, the last five races and their hooks, progression to level 12 with multiclassing, faction joining with consequences, two more biomes, the Bastion's last three buildings, tooling for acts with branches and endings.
2. **Content**, authored thin and wired on those systems, in story order, each session ending in a playable, tested beat.
3. **Parallel tracks** that need people: writing, art, audio, playtesting, Steam, Apple.

One system per session (GDD §15). Every session ends with a PR, decisions, gaps, tests, and a harness row for every new fight (`test_balance.gd`, D-081).

## Sessions

### Phase A — systems (S28–S37)

| Session | System | Why here | Done when |
|---|---|---|---|
| **S28** | **Combat economy decision**: run the AP experiment from D-081 (basic attacks 2 AP, 1-AP utility) against the balance harness and a scripted comparison; fix whatever the first external playtest reports; retreat and focus-fire for the AI | The biggest open feel question (gaps, top item) shapes every fight authored after it; changing it later re-tunes three acts | A decision logged either way with the harness table before and after; the AI retreats when losing and focuses a downed-adjacent target; every M2 fight still in band |
| S29 | **Items, affixes, cyberware**: `items` kind with slots (weapon, armour, two trinkets, cyberware for Chromed), data-defined affixes on the S18 rarity roll, item drops from enemies, vaults and merchants, an inventory and equip screen, Workshop crafting from Salvage | Shards have rarity but nothing rare; Chromed's hook is "extra equipment slots" and there is no equipment | Loot drops with affixes in Shards; equip changes stats through `StatBlock`; a saved loadout reloads; merchants sell items |
| S30 | **Races 6–10**: Hollow, Splicekin, Vaultkin (playable now), Skyborn, Swarmborn as registry entries with rig overlays; the mechanical hooks the vocabulary lacks (dark sight, toxin resistance, salvage bonus, bestial senses, old-world knowledge checks, self-mend, disguise) added as generic rules, not race code | Ten races is an M3 exit criterion; Dax's race is already half here | All ten in the creator; every hook is a rule or effect any entry could use; `test_creator.gd` covers each |
| S31 | **Progression v2**: level cap 12, multiclassing from 5, capstones at 8, the Weave Tree as cross-class Tech/Arcane/Body talents, and the subclass identities that are still strings (chain lightning, taunts, drone swarms, turrets, DoT spread, parries and counters, silence zones) as ability mechanics | The demo capped at 6 with one talent tier; a 30-hour game needs the second half of the curve and the subclasses to be what the GDD says | A level-12 multiclass capstone build saves and loads; every subclass ability does its named thing in a test; the Arcanum respecs across classes |
| S32 | **Factions v2**: joining (mutually exclusive, locks the others), faction vendors and areas gated by membership and reputation, Rootched and Ashfound NPCs and envoys on the plaza, faction-coloured approval per the casting rule, the `act2` gate that S21 left | Act 2 is "The Choosing"; the choice needs somewhere to be made and something to change | Joining any faction closes the other two, opens its vendor and area, moves every companion's approval per D-074; `test_factions.gd` covers all three paths |
| S33 | **Biome 3, Ghost Markets**: palette, tiles (echo-static surface, market stalls as cover, failing lights), enemy family (echo-wraiths, failed Hollows, Choir cultists; elite and boss), Beacon depth/unlock, harness rows | Third biome; the Choir's first family with a voice | Renders in CI; validator passes 100 seeds; family mixes all five archetypes; extraction rate in band |
| S34 | **Biome 4, The Null Cathedral**: null-touched horrors, anti-magic constructs, the Choir's inner voices; a `null` surface that silences; Act 3's final-dungeon remix (every surface, every family) as a template option | Fourth biome and the Act 3 dungeon material in one, before Act 3 is authored | Same bar as S33, plus a remix template that mixes families and surfaces by rule |
| S35 | **Bastion v2**: the Archive (lore fragments as content, assembled into the Sundering's history with a reading UI), the Garden (Rootkin regen, ingredient economy), the Quarters (companion and romance scenes as dialogue with a place), account-level unlocks across playthroughs (`user://account.json`: origins, loadouts, cosmetics) | GDD §12 lists seven buildings; four exist. Romance needs a room, lore needs a shelf, replays need something to keep | Seven buildings on the plaza; a fragment found in a Shard reads in the Archive; a Quarters scene fires from approval; a second playthrough starts with an unlocked origin |
| S36 | **Campaign tooling v2**: quest branches (stages that fork on flags), faction-locked and act-locked transitions, scripted sequences (a trigger that runs a list of effects with pauses and camera moves), world-state edits (a map that changes after a beat), an ending state machine reading faction, keys and companion outcomes | Acts 2–3 branch on the faction and end four ways; the S19 format can express one road | A test authors a three-way branch and a scripted sequence in data; every ending state resolves from flags in `test_endings.gd` |
| S37 | **Romance and approval scenes**: romance flags and gates for Sera, Kaj-7, Whisper and Yev, approval thresholds that open Quarters scenes, jealousy-free exclusivity as data, both death-stakes paths (a dead romance option is a scene, not a crash) | Four romances are an exit criterion and they hang off S35 and the new companions | Each romance reaches its scene and its refusal in a test; Mortal-mode death mid-romance resolves |

### Phase B — content (S38–S46)

| Session | Content | Why here | Done when |
|---|---|---|---|
| S38 | **Companions 4–6**: Whisper (Splicekin Wireghost), Cinder (Hollow Aetherbinder), Yev (Rootkin Circuit-Witch) as registry entries: recruit, talk, banter, personal quests that intersect the plot (Whisper's maker recalling assets; Cinder's tether is a Loom Key; Yev's grove weaponised by the Rootched), three-way banter with the first three, both death-stakes paths | Six companions is the exit criterion; the party choice in Act 2 needs six to choose from | All six recruitable across Act 1–2; `test_content_narrative.gd` covers every graph; no engine change needed |
| S39 | **Act 1 complete**: the demo slice grown to the act (~8 hours in the GDD): the expeditions going wrong as a set of Shard-site quests, the relay station as a hub with Pell's follow-up, the Lattice and Rootched envoys, Whisper and Cinder recruited, the throat descent as three maps, the reveal that the Sundering was chosen; the demo boundary moves to `rules/demo` | The demo ends where the act should begin to open up; Act 2 needs a full Act 1 behind it | `test_act1.gd` walks every stage; both death-stakes modes; harness rows for every fight; length logged honestly |
| S40 | **Act 2, The Choosing, part 1**: faction commitment (three paths, each locking the others), companion loyalty quests (six, on S37/S38), the Choir courting through stolen voices (dialogue that borrows companion lines) | The faction choice is the game's hinge | Each path playable to the loyalty quests in a test; the casting rule holds on each |
| S41 | **Act 2, part 2**: the three Keys to the Loom as delves (one per biome, S33 and S17 and S34's cathedral fringe), the Loom's location, the companion-centred catastrophe shaped by prior choices (S36 scripted sequence) | Act 2's ending is the biggest branch in the game | All three Keys reachable on every faction path; the catastrophe resolves differently for at least three prior-choice states in a test |
| S42 | **Act 3, The Loom**: the race against the Choir and rival factions, final dungeons from the S34 remix template, the Loom itself as a map, the final confrontation as a fight and a choice | The end | Playable from the catastrophe to the Loom on every path in a test |
| S43 | **Endings**: Lattice, Rootched, Ashfound and the Weaver's Mend (three intact Keys, high loyalty, a spared lucid fragment), with companion and key modifiers, an epilogue screen from `S36`'s state machine, credits | All endings is an exit criterion | Every ending reachable by test; the secret one only on its conditions; the epilogue lists each companion's fate |
| S44 | **Race and origin reactivity pass**: race-, origin- and skill-gated lines across the campaign per the §6 reactivity budget (Hollow and Swarmborn last and most), NPCs who react to a Hollow in the party, a disguise check for Swarmborn | "10 races with reactivity" is the criterion, and reactivity is writing over data that exists after S30 | Every race has gated lines in every act; `test_content_narrative.gd` counts them per race |
| S45 | **Modding docs and tools**: `docs/modding.md` complete for every kind, an example mod per kind, content schemas for every kind (`docs/content-schemas.md`), a `--validate-mods` CLI that runs the schema and cross-reference checks on a mod folder and prints what is wrong, Steam Workshop layout noted for M4 | Modding docs are an exit criterion, and the schema test is the tool | A stranger's mod adding a race, a class, a companion and a map validates from the CLI and loads |
| S46 | **M3 close**: a scripted full-campaign test on every faction path in both death-stakes modes, final gaps triage, `v0.3.0` tagged through `release.yml`, plan for M4 | Content complete means provably complete | `test_campaign_full.gd` green in CI under the time budget; tag built on three platforms |

## Parallel tracks (not sessions)

- **Writing**: every content session authors thin and wired; prose density, length and voice are a pass by a writer over the dialogue files, which are data and need no session. Tracked per act in gaps as "thin" until the pass lands.
- **Art**: the same pipeline as M2 (S10); M3 adds five race overlays, two enemy families, two tilesets, portraits for six companions, ending illustrations. Still needs an artist; placeholders remain the default and never block a session.
- **Audio**: recorded sound and composed music replace the S24 synth placeholders file by file; separate music and SFX buses are an M4 item unless a session touches settings.
- **Playtesting**: after S28, S39, S41 and S43. None has happened; `test_balance.gd` stands in.
- **Steam and Apple**: a live Steam client to verify S25, a Steamworks app id for the depot script, an Apple developer account for notarization. All wait on the user.

## Out of M3 scope (M4)

Balance pass over the whole game, Steam Deck performance, localization scaffolding, Steam Workshop, real notarization, achievements beyond the demo set, accessibility settings beyond glyphs.

## Order and dependencies

S28 first because the AP economy shapes every fight authored afterwards and a first playtest may reorder everything. S29 before S30 because Chromed's hook is equipment. S30 before S31 because multiclassing and race hooks share the rules vocabulary. S32 before S36 because faction-locked transitions need factions to lock on. S33 and S34 before S41–S42 because the Keys and the final dungeons live in those biomes. S35 before S37 because romance needs the Quarters. S36 before any Phase B session. S38 before S39 because Act 1 complete recruits Whisper and Cinder. S39 → S40 → S41 → S42 → S43 in story order. S44 after S43 because reactivity is written over finished lines. S45 late because the schemas must cover every kind that exists. S46 last.

## Running assumptions

- **"Content complete" means wired, not dense.** Every beat exists in data, plays end to end in a test, and holds both death-stakes modes; hours and prose come from the writing track. Length per act is logged in gaps as measured, never as planned.
- **Level cap 12, multiclassing at 5, capstones at 8** per §8, all in `rules/progression` from S31. The demo's cap of 6 stays in `rules/demo` for the demo build.
- **Factions lock at commitment (S40), not at first contact**; Act 1 only warms or cools them (D-074 stands).
- **The Choir is content**: fragments, cultists and stolen voices are enemies, NPCs and dialogue entries; no Choir code.
- **The demo build keeps shipping** from the same repo: `rules/demo.end_flag` moves as Act 1 grows and the release workflow tags `v0.2.x-demo` between M3 tags.
- **Every new fight gets a harness row** with a band before its PR merges.
- **The AP economy is decided in S28** by the harness and a playtest, whichever way; Phase B does not start on an undecided economy.
- **Placeholder art and audio can ship in `v0.3.0`**; the store page still cannot.

## Exit criteria (GDD §14, made testable)

- Three acts playable start to finish on each of the three faction paths, in both death-stakes modes, by a scripted test in CI.
- Four endings plus the Weaver's Mend, each reached by test only on its conditions.
- Six companions recruitable, each with a personal quest and banter; four romances reaching scene and refusal.
- Three factions joinable and mutually exclusive, with vendors, areas and companion consequences.
- Ten playable races in the creator, each with a mechanical hook that is a rule and gated lines in every act.
- Four biomes rendering in CI, each with a family, an elite and a boss, and harness rows in band.
- Seven Bastion buildings.
- Modding docs and a validator that a stranger's mod passes.
- `v0.3.0` built on three platforms from one tag.

## Progress
- S28 Combat economy — done: the AP experiment ran as harness overrides first, then landed in content (every damaging ability +1 AP; two attacks or a heavy plus a self action per 4-AP turn); Warlord and Undercity gangs retuned on the new economy; AI focus fire (lowest-HP hostile in reach) and a once-per-fight rusher retreat behind `ai_retreat_hp_fraction`. No external playtest existed to triage. D-083.
- S29 Items, affixes, cyberware — done: `items` and `affixes` kinds, instances rolled by rarity (affix count from `rules/loot`), drops by enemy tier and from loot crates, the Fence sells gear, the Workshop crafts it, equipment in the ledger builds feeds `PartyBuilder` stats and damage, Chromed get two cyberware slots from race data, the pack screen on I. D-084.
- S30 Races 6–10 — done: Hollow, Splicekin, Skyborn, Swarmborn new and Vaultkin playable; every hook is a `traits` entry any race, origin or enemy can carry (resist, regen on a surface, detect hidden, per-ability damage, arcane-heal immunity, bonus abilities, salvage bonus, mend after a fight, talent cost, tags for conditions); the five M1/M2 races got theirs; four overlay kinds; `race_tag` conditions. D-085.
