# Base game content

Everything the game knows about lives here as data, loaded by the `Content`
autoload (`src/core/content_registry.gd`). **Hardcoded content is a bug.**

Layout: `content/<kind>/<id>.json`. One entry per file. The `id` is the file
stem unless the file sets `"id"` explicitly. Kinds are just folder names; the
registry does not care which exist, but systems expect the ones below.

| Kind | Status | Notes |
|---|---|---|
| `races` | M0: trueborn, synth | GDD §6 |
| `classes` | M0: scrap_knight, aetherbinder | GDD §8. `branches` lists branch ids; the first gives the class colour. |
| `branches` | arcane, tech, body | Neon colours (GDD §5). |
| `biomes` | rusted_undercity | `palette`: 16 named colours that tile art references by role. |
| `tiles` | 2 floors, wall, debris | `layer` ground/wall, `walkable`, `art` block (see `src/systems/world/placeholder_tiles.gd`). |
| `maps` | proto_yard | ASCII `rows` + `legend` (char to tile id) + `spawn_marker`. See `src/systems/world/map_data.gd`. |
| `parties` | prototype | Debug starting parties: 1–4 members with `race` and `class` ids. |
| `enemies` | scav, feral_drone, chrome_addict | `family` (biome id), `archetype` (rusher/ranged/…), `stats`, `abilities`, `awareness`, `art`. |
| `abilities` | strike, heavy_swing, arc_bolt, zap, chrome_fist | `ap`, `range`, `damage` [min,max], `accuracy`, `damage_type`, `requires_los`. |
| `rules` | combat | Tunables read by `CombatRules` (AP per turn, flanking, friendly fire, story-protected, awareness, engage radius). |
| `pickups` | salvage_cache, aether_shard | Collectibles: `grants` block (`salvage`/`aether`/`ciphers` as number or [min,max], `cipher_chance`, `xp`), `art.color`. Enemies use the same block under `loot`. |
| `shards` | rusted_undercity | Procgen templates: `size`, `rooms`, `corridors`, `tiles` roles, `grate_patch_chance`, `debris_density`, `enemies` pool. See `src/systems/procgen/shard_generator.gd`. |
| `items`, `companions`, `dialogue`, `loot_tables`, `quests`, `factions` | later milestones | |

Maps may also carry `"enemies": [{"type": "<enemy id>", "cell": [x, y]}]` and `"pickups": [{"type": "<pickup id>", "cell": [x, y]}]` placements, and generated Shards add `"extraction": [x, y]`. Classes carry `stats` and `abilities`; races carry `stat_mods`; tiles carry `blocks_sight`.

`tests/unit/test_content_integrity.gd` cross-checks every id reference above; add a check there when you add a referencing field.

Per-kind schemas will live in `docs/content-schemas.md` once each system lands.
Mods use the identical layout; see `docs/modding.md`.
