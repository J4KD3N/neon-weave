# Decisions log

Append-only. One entry per decision the GDD does not settle. Newest at the
bottom. Format: id, date, decision, alternatives considered, why, revisit-when.

---

## D-001 — Engine version: Godot 4.6 stable, GDScript only
**Date**: 2026-09-08
**Decision**: Target Godot 4.6-stable. `project.godot` declares the `4.6` feature. CI pins the same version.
**Alternatives**: 4.3 LTS-ish behaviour; tracking latest.
**Why**: 4.6 is what the author's other Godot project already runs, so one editor serves both. GDScript static typing, typed for-loops, and `--import` headless all exist here.
**Revisit when**: a 4.7 feature is needed for a system, or a 4.6 bug blocks exports.

## D-002 — Static typing enforced by the compiler
**Date**: 2026-09-08
**Decision**: `debug/gdscript/warnings/untyped_declaration = 2` (error). Unsafe access/cast/call warnings on at warn level.
**Why**: GDD §4 says static typing everywhere. Making it an error means CI catches it via the compile-all-scripts test instead of code review.
**Revisit when**: never, ideally. Promote unsafe warnings to errors once the codebase is large enough to judge the noise.

## D-003 — Renderer: Forward+
**Date**: 2026-09-08
**Decision**: Forward+ renderer.
**Alternatives**: Mobile; Compatibility (OpenGL).
**Why**: 2D lighting and WorldEnvironment glow (GDD §5) are best supported here, and all three desktop targets have Vulkan/Metal (via MoltenVK) drivers.
**Revisit when**: Steam Deck performance profiling (M4) or macOS glow issues suggest Compatibility. Switching is a project setting, not a code change, as long as no Forward+-only shader features are used.

## D-004 — Content format and layout
**Date**: 2026-09-08
**Decision**: Content is JSON, one entry per file, at `content/<kind>/<id>.json`. `id` = file stem unless the file sets `"id"`. Kinds are folder names. Every loaded entry gets `_kind`, `_source`, `_path` injected for provenance.
**Alternatives**: `.tres` Resources (typed, editor-friendly, but unfriendly to modders and diffs); one big file per kind.
**Why**: JSON is diff-friendly, mod-friendly, and needs no engine to author. Resources can be layered later for editor tooling by loading them into the same registry.
**Revisit when**: a kind needs editor-side authoring (e.g. dialogue graphs) — add a `.tres` loader alongside JSON, not instead of it.

## D-005 — Mod discovery and override precedence
**Date**: 2026-09-08
**Decision**: A mod is a folder with `mod.json` (`id`, `name`, `version`, `priority`) and a `content/` tree with the base layout. Roots scanned in order: `res://mods` (dev), `user://mods`, `<executable dir>/mods` (exported builds only). Mods load after base in ascending `priority`, ties broken by id; last write per (kind, id) wins, so the highest priority mod overrides. Duplicate mod ids are rejected after the first.
**Alternatives**: explicit load-order file; dependency resolution.
**Why**: Simple and predictable for M0–M2. Dependencies/conflicts UI can layer on top later.
**Revisit when**: mods need to depend on other mods, or Steam Workshop lands.

## D-006 — In-repo test harness instead of gdUnit4/GUT
**Date**: 2026-09-08
**Decision**: `tests/test_runner.gd` + `tests/test_case.gd`, ~150 lines, no addon dependency. Run with `godot --headless --path . -s tests/test_runner.gd`.
**Alternatives**: gdUnit4, GUT.
**Why**: Zero setup for contributors and CI; nothing to pin. Assertions cover what M0 needs.
**Revisit when**: we want parameterised tests, scene tests with input simulation, or JUnit output for CI annotations. Migration is mechanical.

## D-007 — Platform services behind `Platform` autoload
**Date**: 2026-09-08
**Decision**: `PlatformService` autoload with a `PlatformBackend` interface. Only `NullPlatformBackend` exists now. GodotSteam (GDExtension) is added at M2 as `SteamPlatformBackend`, selected when the `Steam` singleton exists.
**Why**: GDD §4: the open repo must run Steam-free.
**Revisit when**: M2.

## D-008 — Autoload naming
**Date**: 2026-09-08
**Decision**: Autoloads are `Content` (ContentRegistry) and `Platform` (PlatformService). Autoload names must differ from `class_name`s (Godot rejects the clash), and `Steam` is reserved for GodotSteam's own singleton.

## D-009 — Base resolution and pixel sampling
**Date**: 2026-09-08
**Decision**: 1920×1080 viewport, `canvas_items` stretch, `expand` aspect, nearest-neighbour default texture filter.
**Revisit when**: the isometric camera/tile system lands (M0) and integer-scaling needs are known.

## D-010 — Licenses
**Date**: 2026-09-08
**Decision**: Code (`src/`, `tests/`, `.github/`, `project.godot`) under MIT. Content and art (`content/`, `assets/`, `docs/` story material) under CC-BY-SA 4.0. See `LICENSE` and `LICENSE-CONTENT.md`.

## D-011 — CI shape
**Date**: 2026-09-08
**Decision**: `ci.yml` on PR/push-to-main: download Godot 4.6 Linux, headless import, run unit tests, Trivy secret+misconfig scan, SBOM. `release.yml` on `v*` tags: install export templates, export Windows/Linux/macOS, attach to a GitHub Release. `security-scan.yml` weekly rescan. Adapted from the author's dev-workflow standard; commitlint step dropped because there is no Node toolchain in this repo.
**Revisit when**: first tag proves or breaks the release job (see gaps).

## D-012 — Session scope: S0 = scaffolding + content registry
**Date**: 2026-09-08
**Decision**: This first session delivered repo scaffolding, the content registry (the architectural spine for moddability), the platform abstraction, tests, docs, and CI. No gameplay. Next session: M0 isometric map + party movement.

## D-013 — Session S1 scope: M0 isometric map + party movement
**Date**: 2026-09-08
**Decision**: One handcrafted map rendered through `TileMapLayer`, click-to-move pathfinding, WASD steering, a four-member party with trail-following. No combat, no procgen, no elevation, no real art.

## D-014 — Projection delegated to TileMapLayer
**Date**: 2026-09-08
**Decision**: The `TileSet` is isometric, diamond-down, 64×32. All cell<->world conversions go through `TileMapLayer.map_to_local` / `local_to_map` (wrapped by `MapView`); the game keeps no parallel projection math. Pathfinding runs in cell space (`AStarGrid2D`), so it is projection-independent.
**Why**: One source of truth; the engine's conversions are already tested. `tests/unit/test_iso_projection.gd` pins the axis directions so a layout change cannot slip by.

## D-015 — Placeholder art is generated at runtime from data
**Date**: 2026-09-08
**Decision**: Tiles carry an `art` block (`floor` or `block` shape, palette roles); `PlaceholderTiles` draws 64×64 regions into an atlas at startup using the biome palette. Party members are tinted capsules from `PlaceholderActorArt`.
**Why**: No art pipeline yet (M1). Keeping the palette-per-biome and role indirection in data means real art slots into the same entries. The `art` block is the contract, the drawing code is disposable.
**Revisit when**: M1 art pipeline. Replace `PlaceholderTiles.build` with an atlas loader; keep the entry shape.

## D-016 — Y-sort strategy
**Date**: 2026-09-08
**Decision**: `Scene` is Y-sorted and contains `MapView` (Y-sorted; `Ground` layer at z_index −1, `Walls` layer Y-sorted) and `Party` (Y-sorted). Wall tiles and actors interleave by y; ground is forced beneath everything by z_index.
**Revisit when**: elevation or multi-storey maps arrive; those need `y_sort_origin` per tile or separate layers per level.

## D-017 — Movement model
**Date**: 2026-09-08
**Decision**: Leader: click-to-move along an A* cell path (diagonals allowed, no corner-cutting) or direct WASD steering with axis-sliding against walls. Followers: target points a fixed path-distance behind the leader on a breadcrumb trail (`FormationTrail`), so they only ever walk where the leader walked and never need their own collision. Speed 170 px/s, spacing 36 px, both exported on `Party`.
**Alternatives**: NavigationAgent2D + avoidance; formation slots with per-follower pathing.
**Why**: Deterministic, testable without physics, and cannot desync followers into walls. Good enough until combat needs per-member positioning (which is turn-based and grid-snapped anyway).
**Revisit when**: real-time exploration needs followers to route around each other, or free-form formations are wanted.

## D-018 — Input actions registered in code
**Date**: 2026-09-08
**Decision**: `InputActions.ensure()` adds actions to `InputMap` at scene start instead of an `[input]` block in `project.godot`.
**Why**: Diffable, headless-safe, and settings UI can rebind at runtime later. Avoids hand-editing serialized `InputEventKey` blobs.

## D-019 — CI screenshot job
**Date**: 2026-09-08
**Decision**: `ci.yml` gains a best-effort `screenshot` job: Xvfb + Mesa software GL, `--rendering-method gl_compatibility`, the scene saves the viewport after ten frames via `-- --screenshot=<path>` and quits; the PNG is an artifact. Not a required check.
**Why**: No local Godot on the build machine. This is the only visual verification loop until the editor is opened.

## D-020 — Runtime script errors fail CI; tests run in the first frame
**Date**: 2026-09-08
**Decision**: The runner executes tests from the first `_process` frame, not `_initialize`, because the root window is not in the tree during initialisation and scene nodes added then never get `_ready`. Since a GDScript runtime error aborts a method without recording a failure, the CI test step also fails on any `SCRIPT ERROR` in the log.
**Why**: Discovered in S1: the scene tests "passed" while every line after the first error was skipped.
**Revisit when**: moving to gdUnit4/GUT (D-006), which handle both.

## D-021 — Session S2 scope: enemies + turn-based combat
**Date**: 2026-09-08
**Decision**: Three Rusted Undercity enemies, encounter triggers, a pure turn-based engine, rusher/ranged AI, a code-built HUD. Deferred: cover, elevation, surfaces, class resources (Surge/Vent Heat), stealth openers, XP/loot, extraction.

## D-022 — Combat engine is pure and event-driven
**Date**: 2026-09-08
**Decision**: `CombatState` owns all rules over `MapData` + `Combatant` data + ability entries and emits `event` dictionaries; `CombatController` (a Node) maps combatant ids to `WorldActor`s, animates, and drives the HUD. With `animate = false` a whole fight resolves synchronously, which is how the scene test and the CI combat screenshot run.
**Why**: Unit tests for every rule without nodes or timing; AI can be tested against the same object; determinism via a seeded `RandomNumberGenerator`.

## D-023 — Turn economy and range metric
**Date**: 2026-09-08
**Decision**: Per turn: `ap_per_turn` (4) action points for abilities plus `move` cells of free movement. Reach is a BFS over walkable, unoccupied cells, diagonals allowed, no corner cutting (consistent with exploration pathing). Range and adjacency use Chebyshev distance. Line of sight is a Bresenham walk; only tiles with `blocks_sight` (walls) break it; low debris and combatants do not.
**Alternatives**: AP-for-movement (XCOM style); Euclidean ranges.
**Why**: GDD §9 says free movement + 4 AP. Chebyshev keeps melee 8-directional and matches the diagonal BFS.

## D-024 — To-hit, flanking, friendly fire, knock-outs
**Date**: 2026-09-08
**Decision**: hit chance = ability `accuracy` − target `evasion` (+ `flank_hit_bonus` when another combatant hostile to the target is adjacent), clamped to [5, 95]; damage is uniform in `[min, max]`, ×`flank_damage_mult` when flanked. Abilities may target anyone but self (friendly fire on, rule-toggleable). Party members at 0 HP are `downed` under Story-Protected rules (default) and revived at 1 HP after a victory; Mortal mode kills. All numbers live in `content/rules/combat.json`.
**Why**: Enough tactical texture (positioning matters via flanking and LOS) for M0's "is it fun?" without cover/elevation yet. Story-Protected vs Mortal is the GDD §7 setup choice; only the rule flag exists so far, no setup UI.

## D-025 — Encounters
**Date**: 2026-09-08
**Decision**: An enemy that has a party member within its `awareness` (Chebyshev) with line of sight starts combat. Clicking an enemy within the leader's reach of its awareness starts combat with a first-strike initiative bonus for the party. Only enemies within `engage_radius` (7) of any party member join; the rest idle for later. Party members snap to distinct free cells (`CellSettler`) at combat start.
**Revisit when**: stealth (GDD §9) lands — awareness should become a cone/noise model, and first strike should be a proper opener.

## D-026 — Enemy AI is per-action, not per-turn
**Date**: 2026-09-08
**Decision**: `EnemyBrain.next_action(state, actor)` returns one action (move / ability / end); the controller executes it, animates, and asks again. Archetypes: `rusher` (close to nearest hostile, use highest-damage usable ability) and `ranged` (kite to distance 2..range with LOS, then shoot). Unknown archetypes fall back to rusher.
**Why**: Each decision sees the true state after the previous action, and the view gets natural animation beats. Summoner/stealther/controller wait on their mechanics.
