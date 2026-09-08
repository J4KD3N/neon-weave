# Neon Weave

An open-source, moddable, party-based, isometric arcane-cyberpunk CRPG built in Godot 4.6 (GDScript). Centuries after a hyper-advanced civilization collapsed, its technology fused with leaking magic. You lead a party of Weavers, scavenger-mages delving procedurally generated ruins while a handcrafted campaign uncovers what ended the old world.

Targets: Windows, Linux (Steam Deck friendly), macOS. Steam demo and 1.0 planned.

**Status**: M0 loop complete and M1 under way ([plan](docs/m1-plan.md)). A placeholder-art isometric yard with a four-Weaver party and three enemy types; walking into an enemy's awareness (or clicking one) starts turn-based combat. Press N for a procedurally generated Rusted Undercity Shard (guaranteed solvable), collect Salvage and Aether from caches and kills, reach the extraction pad and press E to bank the haul; get wiped and the haul is gone but the books survive in `user://ledger.json`. Back home, B opens the Bastion: the Beacon reaches deeper Shards, the Med-bay heals the wounds you carried back, the Workshop plates the party. Sera Voss waits in the yard; click her to talk, recruit her, and her village will turn up in a Shard. See the [milestone roadmap](docs/GDD.md#14-milestone-roadmap).

**Controls**: left-click to move the leader (the party trails), WASD/arrows to steer directly, mouse wheel to zoom, B Bastion (at home; 1–3 upgrade), C character creator (at home; arrows to choose, Enter to confirm), N new Shard, H home, E extract on the pad, F5 save / F9 load slot 1, F10 load the autosave (written on entering a Shard, at combat start, on extraction and on returning home), F1 to dump the content registry. Saves live in `user://saves/`. In combat: hover to preview a path or an attack (hit chance and damage), click a teal cell to move, click an enemy to attack, 1–4 pick an ability then click a target, Tab or click an ally to swap between party members whose turns are grouped, Space ends the turn, Esc clears, R restarts after a wipe.

## Build from source

1. Install [Godot 4.6](https://godotengine.org/download) (standard build; no .NET needed).
2. Clone this repo and open `project.godot` from the Godot project manager (**Import**).
3. Press **Play**. You get the Proto Yard with the prototype party; F1 lists loaded content and mods.

The first editor open generates `.uid` sidecar files next to scripts. Commit them.

## Run the tests

```bash
godot --headless --path . --import
godot --headless --path . -s tests/test_runner.gd
```

Exit code is non-zero on any failure. Tests live in `tests/unit/test_*.gd` and extend `tests/test_case.gd`.

## Export

Presets for all three platforms are in `export_presets.cfg`. Locally: **Project → Export**. In CI, pushing a `v*` tag builds all three and attaches them to a GitHub Release.

## Layout

```
content/    base game data (JSON, one entry per file)   — CC-BY-SA 4.0
mods/       development mod root + example mod
src/        GDScript: core/ (registry, platform), systems/, ui/  — MIT
scenes/     .tscn scenes
tests/      headless unit tests + fixtures
docs/       GDD.md (canonical design doc), decisions.md, gaps.md, modding.md
```

## Art

Sprites are raw PNG sheets with JSON sidecars under `content/sprites/`; the current ones are tool-generated placeholders. [docs/art-pipeline.md](docs/art-pipeline.md) is the contract for replacing them.

## Modding

Every race, class, enemy, item, quest and line of dialogue is a data file loaded by the content registry, and mods override by id. See [docs/modding.md](docs/modding.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Read `docs/GDD.md` and `docs/decisions.md` before starting anything.

## License

Code is [MIT](LICENSE). Content and art are [CC-BY-SA 4.0](LICENSE-CONTENT.md).
