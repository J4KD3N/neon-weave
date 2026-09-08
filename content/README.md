# Base game content

Everything the game knows about lives here as data, loaded by the `Content`
autoload (`src/core/content_registry.gd`). **Hardcoded content is a bug.**

Layout: `content/<kind>/<id>.json`. One entry per file. The `id` is the file
stem unless the file sets `"id"` explicitly. Kinds are just folder names; the
registry does not care which exist, but systems expect the ones below.

| Kind | Status | Notes |
|---|---|---|
| `races` | trueborn, chromed, aetherborn, synth, rootkin | GDD §6. `stat_mods`, `faction_lean`, `overlay` `{kind: none/marks/chrome/bark/plating, color}` on the shared rig. |
| `origins` | scav_runner, vault_child, corp_asset, choir_touched | Creator backgrounds: `dialogue_tag`, `stat_mods`. |
| `classes` | scrap_knight, aetherbinder, circuit_witch, drone_shepherd | GDD §8. `branches` lists branch ids; the first gives the class colour. `stats`, `abilities`, `resource.id`. |
| `branches` | arcane, tech, body | Neon colours (GDD §5). |
| `biomes` | rusted_undercity | `palette`: 16 named colours that tile art references by role. |
| `tiles` | floors, wall, debris, extraction_pad, catwalk, mana_pool, conduit, biogrowth | `layer` ground/wall, `walkable`, `blocks_sight`, `cover` (low obstacles), `height` (elevation storey), `surface` (mana_pool / conduit / corrosive), `art` block (see `src/systems/world/placeholder_tiles.gd`). |
| `maps` | proto_yard | ASCII `rows` + `legend` (char to tile id) + `spawn_marker`. See `src/systems/world/map_data.gd`. |
| `parties` | prototype | Debug starting parties: 1–4 members with `race` and `class` ids. |
| `enemies` | scav, feral_drone, chrome_addict | `family` (biome id), `archetype` (rusher/ranged/…), `stats`, `abilities`, `awareness`, `art`. |
| `abilities` | strike, heavy_swing, arc_bolt, zap, chrome_fist, vent, hex_bolt, detonate, scrap_shot, overcharge | `ap`, `range`, `damage` [min,max], `accuracy`, `damage_type`, `requires_los`; `targets: "self"` + `effect: "vent"` + `heal`; `effect: "mark"` + `mark`; `effect: "detonate"` + `mark` + `damage_per_mark`; `resource_cost`. |
| `resources` | surge, vent_heat, hexes, scrap_charge | Class resources: `builds_on`/`gain_per_cast`/`damage_per_stack` (build per cast), `overload_*`, `lock_ap_at_max` + `vent_ability`, `kind: "marks"` + `mark` + `max_per_target` (read live marks), `gain_on_kill`, `gain_on_surface`. Classes reference one via `resource.id`. |
| `rules` | combat, attributes | `combat`: tunables read by `CombatRules`. `attributes`: creator point buy (`names`, `points`, `max_per_attribute`, per-point `effects`). |
| `buildings` | beacon, medbay, workshop | Bastion buildings: `order`, `levels[]` of `{cost, effects, blurb}`; effect keys `depth`, `heal_fraction`, `hp_bonus`, `damage_bonus` (summed across buildings). |
| `pickups` | salvage_cache, aether_shard | Collectibles: `grants` block (`salvage`/`aether`/`ciphers` as number or [min,max], `cipher_chance`, `xp`), `art.color`. Enemies use the same block under `loot`. |
| `shards` | rusted_undercity | Procgen templates: `size`, `rooms`, `corridors`, `tiles` roles, `grate_patch_chance`, `debris_density`, `enemies` pool. See `src/systems/procgen/shard_generator.gd`. |
| `sprites` | trueborn, scav | Sprite-sheet sidecars next to their PNGs (`image`, `frame`, `origin`, `directions`, `mirror`, `palette`, `animations`). See `docs/art-pipeline.md`. Races/enemies reference one via `art.sheet`; biomes may `recolors` a sheet to a palette role. |
| `companions` | sera | `race`, `class`, `dialogue{recruit,talk,banter}`, `quest`, `faction`. |
| `dialogue` | sera_recruit, sera_village, sera_banter | Node graphs (`start`, `nodes` with `speaker/text/choices`; choices carry `requires`/`effects`/`next`/`end`) or banter (`kind: "banter"`, `lines`). See D-053. |
| `quests` | sera_purge_village | `companion`, `start`, `stages{id: {summary, shard_site{pickup}, complete}}`. |
| `items`, `loot_tables`, `factions` | later milestones | |

Maps may also carry `"enemies": [{"type": "<enemy id>", "cell": [x, y]}]`, `"pickups": [{"type": "<pickup id>", "cell": [x, y]}]` and `"npcs": [{"companion": "<id>", "cell": [x, y]}]` placements, and generated Shards add `"extraction": [x, y]`. Classes carry `stats` and `abilities`; races carry `stat_mods`; tiles carry `blocks_sight`.

`tests/unit/test_content_integrity.gd` cross-checks every id reference above; add a check there when you add a referencing field.

Per-kind schemas will live in `docs/content-schemas.md` once each system lands.
Mods use the identical layout; see `docs/modding.md`.
