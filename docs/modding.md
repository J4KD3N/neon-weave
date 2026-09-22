# Modding Neon Weave

All game content is data. A mod is a folder that adds or overrides entries, and a validator tells you what is wrong before you load it.

## Where mods go

| Root | When it is scanned |
|---|---|
| `mods/` inside the project | Editor / development builds |
| `user://mods/` (Godot user data dir, e.g. `%APPDATA%\Godot\app_userdata\Neon Weave\mods`) | Always |
| `mods/` next to the game executable | Exported builds |

## Layout

```
my_mod/
  mod.json
  content/
    races/
      my_race.json
    items/
      rusty_blade.json      <- same kind + id as a base entry: overrides it
```

### `mod.json`

```json
{
  "id": "my_mod",
  "name": "My Mod",
  "version": "1.0.0",
  "priority": 0,
  "description": "Optional."
}
```

- `id` must be unique across installed mods. Defaults to the folder name.
- `priority`: mods load in ascending order; the highest priority wins when two mods set the same (kind, id). Base game is always lowest. Default `0`.

### Content entries

`content/<kind>/<id>.json`, exactly like the base game (`content/` in the repo). One JSON object per file. `id` defaults to the filename stem and must be lowercase snake_case. An override replaces the whole entry; there is no field-level merge, so copy the base entry and change what you need.

## Validating a mod

```
godot --headless --path . -s tools/validate_mods.gd -- --mods=path/to/mods
```

`--mods` takes a folder of mod folders, or one mod folder (the one with `mod.json`). The validator loads the base game plus your mod and prints every problem with the kind, id and mod it belongs to:

```
loaded mod stranger 1.0.0 (priority 0) from res://examples/mods/stranger
companions/ghost (broken): race points at races 'nope', which does not exist
dialogue/bad_talk (broken): node greet -> 'missing' does not exist
2 mod entries checked, 2 problems
```

It exits `0` when clean, `1` with problems, `2` on bad usage, so it runs in CI. `--all` reports base-game problems as well (the base is kept clean by the test suite). The same checks run in `tests/unit/test_content_validator.gd` over `examples/mods/stranger`, so the example is always a valid mod.

What it checks: every kind's required keys ([content schemas](content-schemas.md)), ids, every id a file points at (races, classes, abilities, dialogue, quests, companions, maps, tiles, enemies, pickups, factions, merchants, npcs, lore, audio), the condition and effect vocabularies wherever they appear (`requires`, `when`, `done_when`, `start_when`, `effects`, sequence steps), dialogue graphs (start nodes, next targets, dead ends, borrowed voices), quest stages, map placements (walkable cells, spawn cells, overlaps), Shard template pools, building levels and endings' epilogues.

## The example mod

`examples/mods/stranger/` is the smallest complete mod: a race, a class with a subclass and a resource, an ability, an item, a companion with a recruit graph, banter and a quest, and a map. Copy it. It is not loaded by default (only `mods/`, `user://mods/` and the exported `mods/` are), so it never changes the base game; the test suite loads it on purpose.

## Adding each kind

Every kind's required and optional keys are in [content schemas](content-schemas.md). The short version, with the base entry to copy:

| To add | Kind(s) | Copy | Notes |
|---|---|---|---|
| A race | `races` | `content/races/vaultkin.json` | `overlay` picks the rig overlay; `traits` are the S30 hooks (resist, regen_on_surface, detect_hidden, salvage_bonus, mend_after_combat, bonus_abilities, tags); `playable: false` keeps it off the creator |
| A class | `classes`, `subclasses`, `resources`, `abilities` | `content/classes/scrap_knight.json` | A class needs branches that exist, a resource entry, `stats` with every StatBlock key, abilities that exist and at least one subclass whose `class` is this class |
| An ability | `abilities` | `content/abilities/chrome_haymaker.json` | `sound` is an `audio` id; `effects` carry chain, taunt, poison, counter, aoe, summon_count |
| An enemy | `enemies` | `content/enemies/scav.json` | `family` is a biome (or `bastion` for party-side summons); `archetype` is rusher, ranged, summoner, stealther or controller |
| An item or affix | `items`, `affixes` | `content/items/`, `content/affixes/` | Drops roll from `rules/loot`; a merchant sells one through `stock[].effect.item` |
| A companion | `companions`, `dialogue`, `quests` | `content/companions/dax.json` | `dialogue.recruit` doubles as talk; `banter` is a dialogue of kind banter; the quest names the companion; `scenes` are Quarters scenes (romance scenes only on `romanceable`); place them on a map with `npcs: [{companion, cell, when?}]` |
| A dialogue | `dialogue` | `content/dialogue/kaj7_recruit.json` | Nodes need a speaker and choices; every node needs an unconditional choice; `act` is 1–3; `voice` borrows a companion's voice; choices carry the full effect vocabulary |
| A quest | `quests` | `content/quests/lost_crews.json` | Stages advance by `next` when objectives are done, by `branches`, or by an effect; `shard_site` places a pickup in the next Shard (`template` binds it to one); `start_when` starts the quest itself |
| A map | `maps` | `content/maps/relay_station.json` | ASCII rows over a legend of tile ids; `spawn_marker` cells (four for a full party); transitions, triggers (with `when` and the effect vocabulary), npcs, pickups, enemies, doors, buildings. Reach a new map with a transition on an existing map (override it) or a `transition` effect |
| A Shard template | `shards` | `content/shards/rusted_undercity.json` | Tile roles, rooms, corridors, enemy and pickup pools, `requires_unlock` / `requires_flag`; `remix` fills pools from other templates |
| A biome and tiles | `biomes`, `tiles` | `content/biomes/`, `content/tiles/` | A 16-colour palette; tiles carry layer, walkable, art role, cover, height, surface |
| A faction | `factions`, `npcs`, `merchants`, `maps` | `content/factions/lattice.json` | envoy npc, vendor merchant, area map, `join_reputation` (the casting rule) |
| An ending | `endings` | `content/endings/drift.json` | `when` conditions and a `priority`; `epilogue` per companion down the ladder (lost/dead, taken, romanced, loyal, alive, absent); `modifiers` paragraphs with conditions |
| An achievement | `achievements` | `content/achievements/warlord.json` | `steam_id` ACH_UPPER_CASE, `when` conditions |
| Lore | `lore` | `content/lore/` | `order` sorts the Archive; a `lore_fragment` pickup finds the next unfound one; a `lore` effect names one |
| Rules | `rules` | `content/rules/` | Override `combat`, `progression`, `loot`, `attributes`, `audio`, `demo`, `credits`, `appearance` whole |
| A difficulty | `difficulties` | `content/difficulties/tactician.json` | `rules` is an overlay {rules entry id: {field: value}} written over that entry when the story is on this difficulty; `order` sorts the title screen; only the base game marks a `default` |

Conditions (`requires`, `when`, `done_when`, `start_when`) and effects are listed at the bottom of [content schemas](content-schemas.md); the validator rejects any key outside them.

## Checking your mod loaded

Run the game: the boot screen lists every kind, every entry with its source, loaded mods, and any load errors (bad JSON, missing manifest, duplicate ids). Nothing in a mod can crash loading; broken files are skipped and reported. Saves carry a fingerprint of the content they were made with, so a save refuses to load a map or Shard template whose content changed underneath it (D-080).

## Steam Workshop (M4)

Workshop items will be mod folders uploaded as-is: `mod.json` becomes the item's metadata, `content/` its payload, and the game will scan the Workshop download directory as a fourth root behind `mods/` beside the executable. Nothing in the format changes; the validator is what the upload tool will run first.
