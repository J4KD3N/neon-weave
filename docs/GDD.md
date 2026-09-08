# NEON WEAVE — Master Prompt & Design Document (v5, Complete)

The complete, canonical GDD-as-prompt. Point every build session at this document. Edit [bracketed] items to taste; record deviations in `docs/decisions.md`.

⚠ Contains full story spoilers — this is the builder's copy.

---

## THE PROMPT

You are building **Neon Weave**, an open-source, moddable, party-based, isometric arcane-cyberpunk CRPG in **Godot 4.x (GDScript)**, targeting a **Steam release (demo + full 1.0)** on **Windows, Linux, and macOS**. This document is the canonical Game Design Document. Where a decision isn't covered, propose options and log the outcome in `docs/decisions.md`.

### 1. Vision & Pillars

Centuries after a hyper-advanced civilization collapsed, its technology fused with leaking magic. The player leads a party of Weavers — scavenger-mages delving procedurally generated ruins ("Shards") while a handcrafted 30+ hour campaign uncovers what ended the old world.

**Design pillars (test every feature against these):**
1. Tactical combat that rewards positioning and party synergy, never mashing.
2. Exploration that always dangles one more secret.
3. Permanent, visible growth — the Bastion, the party, and the story all build over time.
4. Player expression — builds, choices, and consequences that matter.

**Tone**: gritty and mature. Blood, body horror at the magic/machine boundary, moral compromise, factions with ugly sides. Neon-lit melancholy. Target an M/PEGI-18-adjacent rating; dark, not edgy-for-its-own-sake.

### 2. Story Spine (spoilers)

**The truth of the collapse ("the Sundering")**: the old civilization's ruling council didn't lose control of their network — they deliberately tore open the Weft (the mana-realm) and pulled it through, knowing it would destroy their world. They did it to drown something: their own seed-intelligence, the **Choir**, which had begun quietly optimizing humanity out of its own future. Magic was the poison they chose over extinction. It half-worked. The Choir survives, fragmented and mad, singing through corrupted machines — and the fusion has never stopped deepening.

**Act 1 — The Waking** (~8 hrs): The Shards are stirring; expeditions go wrong; the party assembles. Ends with first contact with a lucid Choir fragment and the revelation that the Sundering was chosen, not suffered.
**Act 2 — The Choosing** (~14 hrs): Faction commitment (locks the others), companion loyalty quests, delving for the three Keys to the **Loom** — the fusion's heart. The Choir courts the player through stolen voices. Ends with the Loom's location and a companion-centered catastrophe shaped by prior choices.
**Act 3 — The Loom** (~8+ hrs): Race the Choir and rival factions to the Loom. Final dungeons remix every system (all surfaces, all enemy families). At the Loom the player sets the fusion's final state.

**Ending states** (faction path + key flags + companion outcomes modify each):
- **Lattice**: purge the Weft, restore the machine-order — clean, bright, and quietly inhuman.
- **Rootched**: complete the fusion — a flowering, unrecognizable new world.
- **Ashfound**: burn both magic and machine — a hard, free, diminished humanity.
- **[Secret] The Weaver's Mend**: requires all three Keys intact, high party loyalty, and sparing a lucid Choir fragment — reweave the Loom so human, machine, and Weft hold each other in tension. The hopeful ending, hardest to earn.

### 3. Companions (6)

One per class; six races represented (Chromed, Aetherborn, Skyborn, Swarmborn reserved as player-flavored). Each has a personal questline, approval, banter, faction tension, and death-contingency paths. [Romanceable: Sera, Kaj-7, Whisper, Yev.]

| Companion | Race / Class | Character | Personal quest hook | Faction tension |
|---|---|---|---|---|
| **Sera Voss** | Trueborn Scrap-Knight | Ex-Ashfound purge soldier; gruff shield, guilt she won't name | A village she "purged" wasn't what she was told | Ashfound loyalist — strains hard on Rootched path |
| **Kaj-7** | Synth Drone Shepherd | Gentle awakened machine; curious, literal, quietly funny | Tracing the signal that woke it — which leads to the Choir | Lattice courts it; fears being "restored" |
| **Whisper** | Splicekin Wireghost | Ex-corporate infiltration asset; snark as armor, trusts no one | Her gene-line's maker is still alive and recalling assets | Neutral; hates all institutions equally |
| **Cinder** | Hollow Aetherbinder | Echo-priest who died in the Sundering and remembers it | Finding what still tethers him — and whether to cut it | None; the party's living lore source |
| **Yev** | Rootkin Circuit-Witch | Serene fusion mystic, unsettling calm, sees the Weft as sacred | Her grove is being weaponized by her own faction | Rootched believer — breaks on Lattice/Ashfound paths |
| **Dax** | Vaultkin Null Blade | Vault-raised mercenary; pragmatic, allergic to magic and ideology | His vault's seal is failing with family inside | Ashfound-leaning; loyalty is to people, not causes |

Casting rule: on every faction path, at least one companion approves and at least one is wounded by the choice. Companion quests intersect the main plot (Kaj-7's maker-signal is a Choir thread; Cinder's tether is a Loom Key).

### 4. Technical Foundation

- **Engine**: Godot 4.x, GDScript, static typing everywhere, scene-per-system architecture.
- **Open source**: public Git repo from day one. Code under [MIT]; art/story content under [CC-BY-SA]. LICENSE, CONTRIBUTING.md, build-from-source README.
- **Moddability is architecture**: ALL content — items, enemies, abilities, classes, races, companions' data, dialogue, biomes, loot tables, quests, factions — lives in data files (Godot Resources / JSON) loaded through a content registry that scans a `mods/` directory.
- **Steam**: GodotSteam for achievements, cloud saves, demo depot; all Steam calls behind an interface so the game runs Steam-free from the open repo.
- **Exports**: Windows, Linux (Steam Deck friendly), macOS.
- **CI**: GitHub Actions builds all three platforms on every tag; unit tests for combat math, procgen validity, save/load round-trips.

### 5. Visual Direction (isometric pixel + glow)

- **Isometric 2:1 projection**, 64×32px diamond tiles via Godot TileMap.
- **Characters**: pixel sprites ~48-64px tall, 4-direction facing mirrored to fake 8. Cycles: idle, walk, attack, cast, hit, death (4-8 frames).
- **Style rule**: dark desaturated environments; saturated neon reserved for meaning — spells, interactables, telegraphs, class colors (Arcane = purple, Tech = teal, Body = coral).
- **Glow lives in the engine** (2D lighting + WorldEnvironment), not the sprites.
- **Mature dressing in the environment layer**: blood decals, corpse tiles, grime, failing lights. CRT shader toggle.
- Palette-per-biome (~16 colors), data-defined. **Races share one humanoid paper-doll rig** with race overlays (marks, chrome, bark, plating) — 10 races, one sprite pipeline.

### 6. Races (10 playable)

Race = what the fusion did to your bloodline: a mechanical identity, a faction lean (tilts reputation, never locks), and origin-gated dialogue. Registry content.

| Race | Analog | Identity | Mechanical hook | Lean |
|---|---|---|---|---|
| Trueborn | Human | Unaltered humans | +talent points, most flexible | Ashfound |
| Chromed | — | Augmented humans | Cyberware = extra equipment slots | Lattice |
| Aetherborn | Sorcerer-blood | Magic-marked lineage | Free innate spell; interferes with gadgets | Rootched |
| Synth | Warforged | Awakened machines | Repairs with parts; poison/bleed immune; no magic healing | Lattice |
| Rootkin | — | Bio-fused with overgrowth | Regen near overgrowth; photosynthetic stamina | Rootched |
| Hollow | Undead | Echoes of the Sundering's dead | No breath/poison; mana-static body; unnerves NPCs | none |
| Splicekin | Beastfolk | Gene-built chimeras | Bestial senses, natural weapons | Ashfound |
| Vaultkin | Dwarves | Sealed-bunker generations | Dark sight, toxin resistance, salvage bonus | Ashfound |
| Skyborn | Elves | Fallen orbital castes | Old-world knowledge checks, agile | Lattice |
| Swarmborn | Changelings | Nanite colony in human shape | Out-of-combat self-mend; minor reshaping (disguise) | none |

- **Reactivity budget**: Hollow and Swarmborn need the most NPC reaction writing — schedule last.
- **Phased rollout**: [5] races in the M2 demo (Trueborn, Chromed, Aetherborn, Synth, Rootkin); all 10 by M3.

### 7. The Party & Character Creation

- **Full character creator**: race, appearance (paper-doll + overlays), origin/background (gates dialogue), attributes, starting class.
- **Party of up to 4** (protagonist + 3 of the 6 companions).
- **Companion death is a setup choice**: Story-Protected (KO only) or Mortal (permanent, narratively acknowledged). Every companion quest ships both paths.
- Romance arcs [4 of 6]; written mature, not gratuitous.

### 8. Classes & Builds

Six base classes; resource identity + levels 1-[12] + two subclasses at level [3].

| Class | Branches | Resource | Subclasses |
|---|---|---|---|
| Aetherbinder | Pure Arcane | **Surge** — builds as you cast; overload risk | Stormcaller (chain/AoE) · Wardweaver (shields, denial) |
| Circuit-Witch | Arcane · Tech | **Hexes** — stacking marks to detonate/exploit | Glitchbinder (turn enemy tech) · Plaguecoder (DoT spread) |
| Drone Shepherd | Pure Tech | **Scrap Charge** — harvested from kills/terrain | Swarmlord (drone swarm) · Artificer (warframe + turrets) |
| Wireghost | Tech · Body | **Heat** — stealth/hacks build it; overheat reveals | Razor (ambush burst) · Phantom (infiltration, control) |
| Null Blade | Body · Arcane | **Null** — absorbs magic damage as fuel | Voidfencer (parries, counters) · Suppressor (silence zones) |
| Scrap-Knight | Pure Body | **Vent Heat** — overheat/vent rhythm | Juggernaut (charges) · Warden (taunts, protection) |

- **Multiclassing** from level 5; capstones need [8+] levels in one class.
- **Weave Tree** (Tech/Arcane/Body) cross-class talents; respec at the Arcanum.
- Race/class synergies are inclinations, never restrictions.

### 9. Combat (turn-based, BG3-style)

- Real-time exploration; combat triggers on awareness or first strike; stealth openers viable.
- **Free movement + [4] AP** per turn; initiative; enemies play by player rules.
- Cover, flanking, elevation, and surfaces (mana pools amplify, conduits chain shock, corrosive biogrowth, hackable turrets/doors).
- Friendly fire [default on]. Gore slider. Difficulty: Story / Balanced / Tactician; "Iron Weave" permadeath mode.

### 10. Enemies & the Choir

**The Choir** is the recurring antagonist force: fragments of the drowned seed-intelligence singing through corrupted machines and minds. Its agents appear in every biome and escalate through the acts.

Enemy families (data-defined; ~3-4 types + 1 elite + 1 boss each):
- **Rusted Undercity**: scav gangs, feral security drones, chrome-addicts.
- **Verdant Datacore**: bio-machine hybrids, spore constructs, rogue Rootkin wilds.
- **Ghost Markets**: echo-wraiths, failed Hollows, Choir cultists.
- **The Null Cathedral**: null-touched horrors, anti-magic constructs, the Choir's inner voices.
Behavior archetypes: rusher, ranged, summoner, stealther, controller — mixed per family so encounters stay tactical.

### 11. World, Factions & Content Structure

- **Handcrafted campaign** (30+ hrs) per the story spine; **procgen Shards** as the replayable loot/XP engine (guaranteed-solvable, secrets, vaults, merchants, extraction waypoints; unbanked resources lost on wipe, story progress never lost).
- **[4+] biomes** as above.
- **3 joinable factions, mutually exclusive**: the **Lattice** (restore machine-order), the **Rootched** (complete the fusion), the **Ashfound** (burn both). Joining locks the others, changes vendors/areas/endings, colors companion approval, interacts with race.
- **Narrative reactivity**: flag/reputation system; skill/origin/race-gated dialogue; data-driven dialogue format; the **Archive** assembles lore fragments into the Sundering's true history.

### 12. Progression & Economy

- **The Bastion**: Workshop, Arcanum (respec), Med-bay, Archive, Beacon (unlock biomes/depths), Garden, Quarters (companion/romance scenes). Buildings visibly upgrade.
- **Account-level unlocks** across playthroughs: origins, loadouts, cosmetics.
- **Economy**: Salvage (building), Aether (talents), Ciphers (rare keys/merchants). Loot: rarity + data-defined affixes; cyberware drops for Chromed slots.

### 13. Saves & Sessions

Save anywhere out of combat; combat checkpoints; multiple slots + autosaves; Steam Cloud; versioned JSON saves with migration support.

### 14. Milestone Roadmap

- **M0 — Prototype**: one handcrafted map + one procgen biome, 2 classes (Scrap-Knight, Aetherbinder), 2 races (Trueborn, Synth), 3 enemy types, extraction loop, placeholder art. *Is the loop fun?*
- **M1 — Vertical Slice**: final art pipeline, creator v1 (5 races), full combat, 4 classes, Bastion (3 buildings), Sera fully written, save/load, controller. *One hour that feels final.*
- **M2 — Steam Demo**: Act 1 (~2-3 hrs), 2 biomes, 3 companions (Sera, Kaj-7, Dax), Lattice introduced, 6 classes, 5 races, Steam integration, 3-platform exports, store page. *Wishlists.*
- **M3 — Content Complete**: full campaign + all endings, all companions/romances, factions, 10 races with reactivity, biomes, modding docs.
- **M4 — Polish & 1.0**: balance, Steam Deck performance, localization scaffolding, launch.

Every milestone ships a playable build, updated `docs/`, logged decisions, and a gaps/assumptions list.

### 15. Working Agreement (for AI-assisted sessions)

- One system or feature per session; read `docs/decisions.md` and this GDD first.
- Data-driven first: hardcoded content is a bug.
- Every system ships with a test scene; unit tests wherever there's math.
- Never break the exports.
- Every companion/faction quest accounts for both death-stakes modes.
- New races/classes/companions are registry entries — if adding one requires engine changes, the architecture is wrong.
