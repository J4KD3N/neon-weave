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
| `enemies` | pending M0 | 3 types for the prototype |
| `items`, `abilities`, `companions`, `dialogue`, `loot_tables`, `quests`, `factions` | later milestones | |

`tests/unit/test_content_integrity.gd` cross-checks every id reference above; add a check there when you add a referencing field.

Per-kind schemas will live in `docs/content-schemas.md` once each system lands.
Mods use the identical layout; see `docs/modding.md`.
