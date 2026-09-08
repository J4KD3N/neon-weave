# Neon Weave — session guide

Godot 4.7 / GDScript CRPG. Read these first, every session:

1. `docs/GDD.md` — canonical design document. It is the prompt.
2. `docs/decisions.md` — settled decisions. Append, never silently deviate.
3. `docs/gaps.md` — known holes and assumptions. Update when you open or close one.

## Working agreement (GDD §15)

- One system or feature per session. Log the session's scope as a decision entry.
- Data-driven first: content lives in `content/<kind>/<id>.json`, loaded by the `Content` autoload (`src/core/content_registry.gd`). Hardcoded content is a bug.
- Static typing everywhere; untyped declarations are compile errors.
- Every system ships a test scene and unit tests where there is math. Tests: `tests/unit/test_*.gd` extending `TestCase`; run with `godot --headless --path . -s tests/test_runner.gd`.
- Never break `export_presets.cfg` (Windows, Linux, macOS).
- Companion/faction quests cover both death-stakes modes.
- New races/classes/companions are registry entries; if they need engine changes, fix the architecture.

## Layout

`src/core/` registry + platform abstraction · `src/systems/` gameplay systems (one folder each) · `src/ui/` · `scenes/` · `content/` · `mods/` · `tests/` · `docs/`

## Conventions

Tabs in GDScript, `snake_case` files, `PascalCase` classes, `##` doc comments. Conventional-commit titles. Commit generated `.uid` files.
