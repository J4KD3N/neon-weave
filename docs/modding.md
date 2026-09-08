# Modding Neon Weave

All game content is data. A mod is a folder that adds or overrides entries.

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

`content/<kind>/<id>.json`, exactly like the base game (`content/` in the repo). One JSON object per file. `id` defaults to the filename stem. An override replaces the whole entry; there is no field-level merge yet.

## Checking your mod loaded

Run the game: the boot screen lists every kind, every entry with its source, loaded mods, and any load errors (bad JSON, missing manifest, duplicate ids). Nothing in a mod can crash loading; broken files are skipped and reported.

## Schemas

Per-kind field documentation will live in `docs/content-schemas.md` as each system lands. Until then, copy a base entry from `content/`.
