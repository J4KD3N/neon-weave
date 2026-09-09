# Neon Weave

An open-source, moddable, party-based, isometric arcane-cyberpunk CRPG built in Godot 4.7 (GDScript). Centuries after a hyper-advanced civilization collapsed, its technology fused with leaking magic. You lead a party of Weavers, scavenger-mages delving procedurally generated ruins while a handcrafted campaign uncovers what ended the old world.

Targets: Windows, Linux (Steam Deck friendly), macOS. Steam demo and 1.0 planned.

**Status**: M0, M1 and M2 complete ([M1 plan](docs/m1-plan.md), [M2 plan](docs/m2-plan.md)); M3, content complete, is planned ([M3 plan](docs/m3-plan.md)): first tagged build `v0.2.0-demo` on the [Releases page](https://github.com/J4KD3N/neon-weave/releases) for Windows, Linux and macOS (placeholder art and audio; notes in [docs/release-notes](docs/release-notes/v0.2.0-demo.md)); six classes, progression, two biomes with features, five AI archetypes, and the first story map. You start on the Bastion plaza; the gate leads to a placeholder-art yard where Sera and Dax wait, and the road east is the first story map with Kaj-7 at its end; you start alone and recruit up to three; once the road is open the three faction envoys wait on the plaza with offers you can warm to or refuse, and from Act 2 you can swear to one, which locks the other two and opens its area and vendor off the plaza; east of the road lies Relay Station Nine, and under the yard the throat where the demo ends at first contact with the Choir; walking into an enemy's awareness (or clicking one) starts turn-based combat. Press N for a procedurally generated Shard (guaranteed solvable; the Rusted Undercity first, the Verdant Datacore from Beacon depth 2, the Ghost Markets from depth 3, the Null Cathedral and the Loom Approach once the story finds them), collect Salvage, Aether and gear (weapons, armour, trinkets, cyberware for the Chromed, with affixes by rarity) from caches, crates and kills, reach the extraction pad and press E to bank the haul; get wiped and the haul is gone but the books survive in `user://ledger.json`. Back home, B opens the Bastion: the Beacon reaches deeper Shards, the Med-bay heals the wounds you carried back, the Workshop plates the party. Sera Voss waits in the yard; click her to talk, recruit her, and her village will turn up in a Shard. See the [milestone roadmap](docs/GDD.md#14-milestone-roadmap).

**Controls**: left-click to move the leader (the party trails), WASD/arrows to steer directly, mouse wheel to zoom, J journal, B Bastion (at home; 1–4 upgrade), T the Weave (at home; subclass, a second class from level 5 and where its levels go, talents in three branches, Arcanum respec), I the pack (at home; equip what you found, craft at the Workshop), C character creator (at home; arrows to choose, Enter to confirm; all ten GDD races, each with a mechanical trait), N new Shard, H home, E extract on the pad or bank the haul at a relay waypoint, Enter opens a vault door beside you (costs a Cipher) or a merchant within two cells, F5 save / F9 load slot 1, F10 load the autosave (written on entering a Shard, at combat start, on extraction and on returning home), F1 to dump the content registry. Saves live in `user://saves/` and carry a fingerprint of the map or Shard template they were made on; a save whose map has changed since is refused and marked in the list rather than loaded wrong (D-080). Every sound and music loop is synthesised from `content/audio/*.json`; drop a real file beside a sidecar and add `"file"` to replace it. Steam (achievements, cloud saves) lives behind `Platform`; the repo runs Steam-free and `steam/README.md` explains wiring GodotSteam. In combat: four action points a turn and movement is free; an attack costs 2 AP, a heavy attack 3, a self action like venting 1. Hover to preview a path or an attack (hit chance and damage), click a teal cell to move, click an enemy to attack, 1–4 pick an ability then click a target, Tab or click an ally to swap between party members whose turns are grouped, Space ends the turn, Esc clears, R restarts after a wipe. Gamepad: left stick / D-pad move or drive the combat cursor, A confirm (interact, act on the cursor), B cancel, X/Y/L1/R1 abilities 1–4, L2/R2 zoom, Start opens the system menu (every key above as a list) or ends the turn in combat, Select swaps party member. Full layout in `docs/controller.md`.

## Download

Tagged builds for Windows, Linux and macOS are on the [Releases page](https://github.com/J4KD3N/neon-weave/releases). Unzip and run; on macOS right-click → Open the first time (the build is ad-hoc signed, not notarized). Each release has notes under [docs/release-notes](docs/release-notes).

## Build from source

1. Install [Godot 4.7.2](https://godotengine.org/download) (standard build; no .NET needed).
2. Clone this repo and open `project.godot` from the Godot project manager (**Import**).
3. Press **Play**. The title screen offers New game (choose Story-Protected or Mortal), Continue, Load and Settings; F1 in game lists loaded content and mods.

The first editor open generates `.uid` sidecar files next to scripts. Commit them.

## Run the tests

```bash
godot --headless --path . --import
godot --headless --path . -s tests/test_runner.gd
godot --headless --path . -s tests/test_runner.gd -- --only=soak   # one file
```

Exit code is non-zero on any failure. Tests live in `tests/unit/test_*.gd` and extend `tests/test_case.gd`.

## Export

Presets for all three platforms are in `export_presets.cfg`. Locally: **Project → Export**. In CI, pushing a `v*` tag runs the tests, builds all three, smoke-boots the Linux build to the title under Xvfb, and attaches the archives to a GitHub Release. `steam/app_build.vdf` maps the same folders onto Steam depots; `docs/store-page.md` lists the store assets.

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
