# Base game content

Everything the game knows about lives here as data, loaded by the `Content`
autoload (`src/core/content_registry.gd`). **Hardcoded content is a bug.**

Layout: `content/<kind>/<id>.json`. One entry per file. The `id` is the file
stem unless the file sets `"id"` explicitly. Kinds are just folder names; the
registry does not care which exist, but systems expect the ones below.

| Kind | Status | Notes |
|---|---|---|
| `races` | M0: trueborn, synth | GDD §6 |
| `classes` | M0: scrap_knight, aetherbinder | GDD §8 |
| `enemies` | pending M0 | 3 types for the prototype |
| `items`, `abilities`, `companions`, `dialogue`, `biomes`, `loot_tables`, `quests`, `factions` | later milestones | |

Per-kind schemas will live in `docs/content-schemas.md` once each system lands.
Mods use the identical layout; see `docs/modding.md`.
