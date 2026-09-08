# Contributing

## Before you start

1. Read [docs/GDD.md](docs/GDD.md). It is the canonical design document.
2. Read [docs/decisions.md](docs/decisions.md). Do not re-decide what is logged there; append a new entry if you change it.
3. Check [docs/gaps.md](docs/gaps.md) for known holes.

## Ground rules

- **One system or feature per PR.** Scaffolding, registry, combat math, procgen: each its own change.
- **Data-driven first.** Content in `content/`, never in code. If adding a race, class, enemy or item needs an engine change, the architecture is wrong; fix the architecture.
- **Static typing everywhere.** Untyped declarations are compile errors (`project.godot`). Typed for-loops (`for x: String in ...`), typed lambdas, typed returns.
- **Tests.** Every system ships a test scene and unit tests wherever there is math. `godot --headless --path . -s tests/test_runner.gd` must pass.
- **Never break the exports.** `export_presets.cfg` must keep exporting all three platforms.
- **Log decisions.** Anything the GDD leaves open gets an entry in `docs/decisions.md`. Update `docs/gaps.md` when you open or close a gap.
- Companion and faction quests must account for both death-stakes modes (Story-Protected and Mortal).

## Workflow

- Branch from `main`; name `feat/<thing>`, `fix/<thing>`, `docs/<thing>`.
- Conventional-commit style titles: `feat(registry): ...`, `fix(ci): ...`, `docs: ...`.
- CI (`ci` check) must be green. Fill in the PR template, including how you tested.
- Commit the `.uid` files Godot generates next to new scripts and scenes.

## Style

- Godot's [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html). Tabs for indentation.
- Files and folders `snake_case`; classes `PascalCase`; constants `UPPER_SNAKE`.
- Doc comments (`##`) on every class and public method.
- Neon is for meaning (spells, interactables, telegraphs, class colors). Environments stay dark and desaturated.

## Licensing of contributions

Code contributions are MIT; content and art contributions are CC-BY-SA 4.0. By opening a PR you agree to license your contribution under the license that covers the paths it touches.
