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

## D-027 — Session S3 scope: procgen Shard biome
**Date**: 2026-09-08
**Decision**: One generator (`ShardGenerator`) + one validator (`ShardValidator`) + one template (`content/shards/rusted_undercity.json`). Debug keys N (new Shard) and H (home) stand in for the Bastion's Beacon until it exists. Deferred: secrets, vaults, merchants, biome variety, the extraction loop itself (next session).

## D-028 — Generated Shards are map entries
**Date**: 2026-09-08
**Decision**: The generator emits a dictionary in the exact shape of `content/maps/*.json` (rows, legend, spawn marker, enemy placements) plus `extraction`, `rooms` and `generation` metadata. The world loads both through the same `load_map_entry`; MapData, MapView, NavGrid, encounters and combat do not know whether a map was handcrafted.
**Why**: One code path, one validator for both, and modders can author templates or hand maps with the same vocabulary.

## D-029 — Solvability by construction plus an independent validator
**Date**: 2026-09-08
**Decision**: Rooms and L-corridors connect every room in placement order (plus random loops). Debris is only placed on "simple points": cells whose walkable ring neighbours stay 4-connected through the ring, so removing the cell cannot split the map. A final 4-connected flood from the spawn walls off anything unreachable. The validator re-checks everything under the exploration movement rules (8-connected, no corner cutting): closed border, 4 spawns, extraction reachable, every walkable cell reachable, enemies reachable/distinct/off spawn and exit/at least `min_spawn_distance` away. `tests/unit/test_shard_generator.gd` sweeps 80 seeds and a heavy-debris variant.
**Why**: GDD §11 "guaranteed-solvable" and §4 "unit tests for procgen validity". The generator's local rule keeps generation O(cells); the validator is the safety net and also runs at load with warnings.

## D-030 — Shard template vocabulary
**Date**: 2026-09-08
**Decision**: Templates carry `size`, `rooms` (count/min/max/attempts), `corridors.extra_loops`, `tiles` roles (wall/floor/grate/debris/extraction), `grate_patch_chance`, `debris_density`, and `enemies` (groups, group_size, min_spawn_distance, weighted pool). Ranges are `[min, max]` inclusive and rolled from the seed.
**Revisit when**: a second biome needs different room shapes (caverns, datacore halls); add a `style` switch rather than a second generator.

## D-031 — Session S4 scope: the extraction loop
**Date**: 2026-09-08
**Decision**: Run haul + persistent ledger, loot on kills, pickups in Shards and on the yard, extraction on the pad, wipe = haul lost. This completes the M0 loop: yard → Shard → fight/collect → extract or wipe → yard. Deferred: XP spending/levels, Bastion buildings, merchants, item loot, the death-stakes setup UI.

## D-032 — Haul vs ledger
**Date**: 2026-09-08
**Decision**: `RunState` holds the unbanked haul (Salvage, Aether, Ciphers, XP, kills) for one expedition; `Ledger` holds banked totals and lifetime counts and is the only thing saved. Extraction banks and records a run; a wipe inside a Shard clears the haul, records the wipe, and still counts kills. On handcrafted maps (home) there is no extraction risk, so gains bank immediately.
**Why**: GDD §11: "unbanked resources lost on wipe, story progress never lost". Keeping the two objects separate makes the rule a data flow rather than a set of flags.

## D-033 — Grant blocks are the loot vocabulary
**Date**: 2026-09-08
**Decision**: Enemies carry `loot`, pickups carry `grants`; both use the same block: a number or `[min, max]` per resource, `cipher_chance` for a bonus Cipher, `xp`. Rolled by `RunState` with an RNG seeded from the Shard id and seed, so a seed reproduces its loot. No item drops yet; rarity/affixes (GDD §12) come with the item system.

## D-034 — Ledger persistence
**Date**: 2026-09-08
**Decision**: `user://ledger.json`, `{"version": 1, ...}`, saved on every bank/wipe. `Ledger.migrate` is the migration hook (a pre-versioned flat shape is upgraded as the first example). Corrupt files are reported and ignored, never overwritten until the next save. Steam Cloud sync of this file is an M2 concern behind `Platform`.
**Revisit when**: the full save system (slots, autosaves, party state) lands; the ledger becomes one section of it.

## D-035 — M1 is planned as sessions S5–S12
**Date**: 2026-09-08
**Decision**: `docs/m1-plan.md` fixes the order: Bastion → save/load → full combat → classes 3–4 → creator → art pipeline → Sera → controller. Each is one session/PR. The yard stays the Bastion's grounds until the art/companion sessions decide on a dedicated map.

## D-036 — Bastion buildings are levelled content entries
**Date**: 2026-09-08
**Decision**: `content/buildings/<id>.json` with `levels[]`; level 0 is free and always built; upgrading to level n pays `levels[n].cost` from the ledger. Effects are flat keys summed across buildings' current levels (`depth`, `heal_fraction`, `hp_bonus`, `damage_bonus`); the world applies them. Levels persist in the ledger (v2).
**Why**: GDD §12 wants buildings that visibly upgrade; keeping effects as summed keys means a new building is a JSON file and possibly one new key handled in the world, never a new class.
**Revisit when**: buildings need choices per level (branching upgrades) or visuals on the map.

## D-037 — Party HP persists between runs; the Med-bay is the heal
**Date**: 2026-09-08
**Decision**: The party is spawned once per scene; entering any map repositions the same nodes. Arriving home applies the Med-bay's `heal_fraction` of max HP (minimum 1) and revives the downed. Victory still leaves the downed at 1 HP. Workshop `hp_bonus` raises max HP and current HP by the same amount.
**Why**: Without persistence the Med-bay is meaningless and wounds have no weight; with it, "extract now or push on" becomes a real decision.

## D-038 — Beacon depth is the only difficulty knob for now
**Date**: 2026-09-08
**Decision**: `ShardGenerator.generate(template, seed, depth)` adds `depth-1` enemy groups and pickups; layout is unchanged for a given seed. Enemy stats do not scale yet.
**Revisit when**: S7 (full combat) or the balance pass wants scaling stats, elites, or per-depth pools.

## D-039 — Save model: deltas over deterministic content
**Date**: 2026-09-08
**Decision**: A save (`SaveSystem`, JSON, `version`) stores the ledger (which carries Bastion levels), the party's HP/downed/cells, the run haul, the location, and deltas against the loaded map: indices of dead enemies and collected pickups. A Shard location is `{template, seed, depth}` and regenerates on load; a handcrafted location is a map id. Loading applies the save's ledger and rewrites `user://ledger.json`, so the books never fork.
**Alternatives**: serialising every node; storing tile rows for Shards.
**Why**: Small files, no drift between save shape and scene shape, and procgen determinism is already tested. Placement indices are stable because both maps and the generator emit ordered arrays.
**Revisit when**: enemies move or spawn dynamically (indices become ids), or item inventories arrive.

## D-040 — Slots and checkpoints
**Date**: 2026-09-08
**Decision**: `user://saves/slot_1..3.json` and `autosave.json`. Save anywhere out of combat (refused during a fight). Autosave at: entering a Shard, combat start (the "combat checkpoint"), extraction, and returning home after a wipe. After a wipe, Esc reloads the checkpoint, R goes home. Loads suppress autosave so a load never overwrites the checkpoint it reads. Keys: F5 save slot 1, F9 load slot 1, F10 load autosave; a slot picker UI is not in M1.
**Why**: GDD §13 verbatim, minus Steam Cloud (M2, behind `Platform`).

## D-041 — Session S7 scope: full combat texture
**Date**: 2026-09-08
**Decision**: Cover, one storey of elevation, three surfaces and the two prototype class resources, all as tile/ability/resource data read by `CombatState`. Deferred: hackable turrets/doors, difficulty settings, Iron Weave, AI awareness of surfaces, movement cost for elevation.

## D-042 — Cover and elevation
**Date**: 2026-09-08
**Decision**: A tile with `cover: n` (debris) shields a target from ranged fire when it sits on the neighbouring cell in the attacker's direction (sign of the delta): −`cover_hit_penalty`. Melee ignores cover; attackers on higher ground ignore it. `height: 1` tiles (catwalk) give +`elevation_hit_bonus` and +`elevation_damage_bonus` when attacking down and −hit when attacking up. Movement between storeys is free (no stairs rule) so procgen validity is untouched.
**Why**: Cheap, legible, and both answer "does where I stand matter?" without a physics query.
**Revisit when**: real art needs visible ramps, or AI should seek cover/high ground.

## D-043 — Surfaces
**Date**: 2026-09-08
**Decision**: `surface` on a tile: `mana_pool` (arcane casts from it ×`mana_pool_amplify`), `conduit` (a tech/arcane hit on someone standing on it arcs `conduit_chain_damage` to every other occupant of the 4-connected conduit run, allies included), `corrosive` (`corrosive_damage` at turn start; can down or kill). Shard templates carve surface patches with their own legend chars; the yard has samples.
**Why**: GDD §9 names these three; each is one lookup in the engine and one field in data.

## D-044 — Class resources are `resources` entries
**Date**: 2026-09-08
**Decision**: `content/resources/<id>.json`: `builds_on` damage type, `max`, `gain_per_cast`, `damage_per_stack`, optional overload (`overload_at`, `overload_chance`, `overload_damage`: the cast fizzles, AP is spent, the caster takes damage, stacks reset) and optional lock (`lock_ap_at_max`: abilities costing that much AP are refused at max stacks) with a `vent_ability` (`effect: "vent"`, `targets: "self"`, resets stacks, heals). Classes point at a resource by id; enemies have none. Stacks start at 0 per fight.
**Why**: Surge and Heat are the GDD's two prototype resources and both fit "build on matching casts, pay out as damage, with a downside at the cap". Hexes, Scrap Charge, Null and Wireghost Heat (S8+) should extend this vocabulary rather than add engine branches.

## D-045 — Classes 3–4 and the resource vocabulary
**Date**: 2026-09-08
**Decision**: Circuit-Witch and Drone Shepherd are content entries. Their loops needed three generic additions to the ability/resource vocabulary, added once and reusable: (1) `effect: "mark"` + `mark` stacks a named mark on a hit target up to the caster resource's `max_per_target`; `effect: "detonate"` adds `damage_per_mark` × stacks and clears them; a resource with `kind: "marks"` reads as the live total of its mark; (2) `resource_cost` on an ability is checked in `can_use` and spent on cast; (3) `gain_on_kill` and `gain_on_surface` on a resource harvest charge. Surge/Heat are unchanged. Anyone may place marks; only mark-kind resources read them.
**Why**: GDD §15 says a new class must not need engine changes. The vocabulary did need three verbs, so the honest record is: the engine grew a vocabulary, and the classes are data. Null Blade (absorb magic as fuel) and Wireghost (Heat from stealth/hacks) should be expressible with `gain_on_*` style fields plus at most one new verb.

## D-046 — Prototype party is one of each class
**Date**: 2026-09-08
**Decision**: `parties/prototype.json` fields Scrap-Knight, Aetherbinder, Drone Shepherd, Circuit-Witch. Class colours follow the first branch (Circuit-Witch reads Arcane purple, Drone Shepherd Tech teal).

## D-047 — Session S9 scope: creator v1
**Date**: 2026-09-08
**Decision**: `CharacterSheet` (data) + `CreatorState` (pure model: rows, cycling, point buy, validation, text render, stat preview) + `CreatorMenu` (text panel, name field, 4× paper-doll preview) + `PartyBuilder` (preset + optional protagonist → member specs). The protagonist replaces the preset's first member with id `protagonist`, lives in saves under `protagonist`, and is respawned on load. C opens the creator at home; there is no title screen yet.
**Why**: Everything the screen shows is derived from data (races, origins, classes, `rules/attributes`), and the model is testable without nodes.

## D-048 — Races, origins, attributes as data
**Date**: 2026-09-08
**Decision**: The five M2 races (Trueborn, Chromed, Aetherborn, Synth, Rootkin) carry `stat_mods`, `faction_lean` and an `overlay` `{kind, color}` stamped onto the shared humanoid rig (`marks`, `chrome`, `bark`, `plating`, `none`) without changing its silhouette (GDD §5: one rig, race overlays). Origins carry `dialogue_tag` (for later gated dialogue) and `stat_mods`. Attributes are `rules/attributes`: three names mirroring the Weave branches, a point budget, a per-attribute cap, and per-point stat effects applied by `StatBlock`.
**Revisit when**: real art replaces the placeholder rig (S10) — overlays become sprite layers, the entry shape stays.

## D-049 — Session S10 scope: art pipeline with generated placeholders
**Date**: 2026-09-08
**Decision**: The pipeline (sidecar contract, loader, facing/mirroring, palette swaps, movement- and combat-driven animation) ships now; the art itself is generated by `tools/gen_placeholder_sheets.js` for one race (Trueborn) and one enemy (Scav). Every other actor keeps the placeholder capsule until it gets a sheet. `docs/art-pipeline.md` is the artist-facing contract.
**Why**: The M1 exit criterion "one fully animated actor" is met with placeholders that exercise every code path real art will use, without pretending generated capsules are final art.

## D-050 — Sheets are raw PNGs read by the game, not imported textures
**Date**: 2026-09-08
**Decision**: `content/sprites/` carries a `.gdignore`; the game reads PNG bytes and builds textures itself. Export presets include `content/*.png`. Mods ship sheets under their own `content/sprites/`.
**Why**: Sidecar-driven loading needs the exact pixels (palette swaps by colour equality); the importer would compress or mipmap them. Mods and artists only touch files, never the editor.

## D-051 — Facings and animation naming
**Date**: 2026-09-08
**Decision**: Facings are screen-space names (e, s, w, n and diagonals); sheets declare which rows they draw and which facings mirror onto them. Animations build as `<animation>_<row>`; the runtime resolves any direction vector to the nearest facing. Required set: idle, walk, attack, hit, death; optional cast (arcane abilities). Colour roles fill/outline/highlight are swapped from the actor tint; biomes may override an enemy sheet's tint via `recolors: {sheet: palette role}`.
**Revisit when**: real art wants per-direction frame counts, race overlay compositing, or shader-based palette swaps.

## D-052 — Session S11 scope: Sera and the narrative data model
**Date**: 2026-09-08
**Decision**: `companions`, `dialogue`, `quests` content kinds; `NarrativeState` (flags, approval, quest stages, recruits) saved under `narrative`; a text dialogue panel; Sera recruitable in the yard; her quest reaching into Shards as a placed site; banter on triggers; approval on the HUD. Both death-stakes paths are data. Deferred: romance, dialogue portraits/voice, companion AI personalities, a quest journal UI, dialogue on the map beyond companions.

## D-053 — Dialogue format
**Date**: 2026-09-08
**Decision**: A dialogue is `{start, nodes}`. `start` is a node id or an ordered list of `{node, requires}` (first passing wins; the last must be unconditional). A node is `{speaker, text, choices}`; a choice is `{text, requires, effects, next | end}`. `requires` keys: `flags`, `origin_tag`, `race`, `class`, `approval{min,max}`, `recruited`, `not_recruited`, `quest{id,stage}`. `effects` keys: `approval`, `flags`, `recruit`, `quest`. Banter dialogues are `{kind: "banter", lines: [{trigger, text, requires, effects, once}]}`; the first matching unspent line plays. Every node must keep at least one unconditional choice so no player can dead-end (enforced by the content test).
**Why**: Small enough to hand-write and validate in CI; expressive enough for gated lines, approval, recruitment and quest stages. The `DialogueRunner` is pure and the panel only renders it.

## D-054 — Quests and Shard sites
**Date**: 2026-09-08
**Decision**: A quest is `{companion, start, stages: {id: {summary, shard_site?, complete?}}}`; the narrative stores one stage per quest. A stage with `shard_site: {pickup}` asks the generator to place that pickup once in every new Shard; a pickup with `dialogue` opens it on touch instead of granting loot. Saves keep the placed extras in the location so a reload regenerates the same layout even after the stage moves on.
**Why**: "Companion quests intersect the main plot" starts with quests intersecting the loop. Sites as pickups reuse placement, validation, deltas and saves unchanged.

## D-055 — Death-stakes in data and in the roster
**Date**: 2026-09-08
**Decision**: With `story_protected` off, a companion killed in a won fight leaves the party, is un-recruited, and sets `<id>_dead`; a dead leader is a wipe. Quest dialogues branch on `sera_dead` / `recruited` from their start list, so every companion quest ships the Story-Protected path, the never-recruited path and the posthumous path as nodes (GDD §7, §15).

## D-056 — Party of four means three preset members plus a recruit
**Date**: 2026-09-08
**Decision**: `parties/prototype.json` is three members; `rules/combat.party_max` is 4; recruits append in order until full. Moth the Circuit-Witch leaves the debug preset (the creator can still make one).

## D-057 — Turn groups: consecutive allies act in any order
**Date**: 2026-09-08
**Decision**: Initiative still sorts every combatant, but a run of same-team combatants in the order forms a *turn group*. Within the group the player swaps freely (Tab, or click an ally) until each member has ended its turn; a member begins its turn (AP and Move restored, surface effects) the first time it gets control, keeps what it spent when swapped away from, and cannot be returned to once it pressed End Turn. Enemies use the same rule one at a time. Groups never span a round boundary.
**Why**: The first playtest could not tell who was acting or why it could not pick someone else. This is the BG3 grouping the GDD points at, without abandoning initiative.

## D-058 — Previews before commitment
**Date**: 2026-09-08
**Decision**: `CombatState.preview()` computes the to-hit chance and damage span for an ability on a target with every modifier the roll would use (flanking, cover, elevation, mana pool, resource stacks, marks, Workshop) and the reason it would be refused. The controller shows it on hover, along with a path preview for moves and a hover marker; refusals go to the hint line in red with the ability and reason spelled out. The preview and the roll share one bonus function so they cannot drift.
**Why**: A turn-based game with hidden odds is a guessing game. Same rule for every future ability: if it changes the roll, it changes the preview.

## D-059 — One action set for keyboard and pad, routed by mode
**Date**: 2026-09-08
**Decision**: Gamepad events join the existing keyboard actions in `InputActions.BINDINGS` rather than forming a second set. Bindings may overlap across actions (Esc is `cancel` and `menu`; Start is `end_turn` and `menu`) because `ExploreWorld` only checks the actions its current mode uses. Mouse-only paths get pad equivalents: a cell cursor in combat (stick/D-pad/WASD, Enter/A confirms, mouse motion releases it), Enter/A as "interact" in exploration (extract on the pad, talk to a companion within two cells), and cursors in the dialogue and Bastion menus. Every keyboard-only key (N, H, E, B, C, F1, F5, F9, F10) is an item of the system menu on Start/Esc; `PAD_ROUTES` documents each route and a test enforces that every action is pad-bound or routed.
**Why**: "Every input path has a pad binding" is the M1 exit criterion. A separate pad action set would double every routing branch; overlapping bindings cost nothing when routing is already per mode.

## D-060 — Steam Deck layout is the default pad layout
**Date**: 2026-09-08
**Decision**: The default pad layout is designed for the Deck first: left stick and D-pad move/cursor, A confirm, B cancel, X/Y/L1/R1 abilities 1–4, L2/R2 zoom, Start system menu / end turn, Select swap member. No Steam Input template ships until GodotSteam lands (M2); the layout above is what that template will mirror. Documented in `docs/controller.md`.
**Why**: The Deck is the reference pad device for the Steam target (GDD §3). Designing for its buttons first keeps the layout inside what every XInput pad also has.

## D-061 — Engine version moves to Godot 4.7.2 (supersedes D-001)
**Date**: 2026-09-08
**Decision**: Target Godot 4.7.2-stable. `project.godot` declares the `4.7` feature; `ci.yml` and `release.yml` download 4.7.2-stable and its export templates. No code changed: 4.7.2 ran the 4.6 project and all 240 tests unmodified.
**Why**: The first playtest ran on the 4.7.2 editor, which rewrites `project.godot` (feature tag, comment stripping) on every open. Pinning CI and the editor to one version stops that churn and keeps "never break exports" checkable locally.
**Revisit when**: a 4.8 feature is needed, or a 4.7 export bug blocks a release.

## D-062 — M2 is three tracks: systems, content, then art and store
**Date**: 2026-09-08
**Decision**: `docs/m2-plan.md` schedules fifteen sessions (S13 playtest triage → S27 demo tuning) in dependency order: progression and the last two classes before the enemy AI and second biome; campaign tooling before companions, the Lattice and the Act 1 slice; front end and audio before Steam; release before tuning. Art and the store page are parallel tracks with an explicit decision point at S22 on shipping the demo with placeholder art. The demo slice ends before first contact with the Choir fragment; the level cap is 6 in the demo; Dax ships as a companion-only Vaultkin entry.
**Why**: M1 proved the systems are data; M2 is judged by strangers on Steam. Keeping content sessions after their tooling avoids authoring twice, and naming art as a non-code gate keeps every session unblocked until the last possible moment.

## D-063 — S13 triage ships a soak test alongside the fixes
**Date**: 2026-09-08
**Decision**: `tests/unit/test_soak.gd` plays three seeded runs of the whole loop headless (yard, Shard, fights with swaps/undo/aiming, mid-run save and load, extraction or wipe, Bastion upgrades, Sera) and checks invariants after every action. It runs on every PR like any other test. The playtest items the plan named are in: the camera follows whoever is acting in combat and returns to the leader; Esc/B with nothing aimed undoes the last move (until any ability, swap or turn end); the system menu lists all three save slots and the autosave with their summaries.
**Why**: The author is the only playtester and cannot be on call for every PR. A scripted playtester finds the crashes; a human finds the feel. Both are S13.

## D-064 — Party-wide level from banked XP; builds live in the ledger
**Date**: 2026-09-08
**Decision**: XP is party-wide (it was already banked on extraction into the ledger), so the party has one level, read from `rules/progression.xp_curve` with `level_cap` (6 for the demo). Per-class `growth` scales stats per level and `unlocks` adds abilities by level. At `subclass_level` each member picks one of the two `subclasses` entries of its class (abilities, stat mods, damage bonus). Talents (`talents` kind: branch, tier, Aether cost, effects, requires) are bought per member with banked Aether; tiers open by level. Per-member choices persist as `Ledger.builds` (ledger v3), so they survive wipes like everything banked and ride along in saves with the ledger. The Arcanum is the fourth Bastion building: level 1 allows respec with a 50% Aether refund, level 2 refunds in full. Progression math is pure (`Progression`), applied by `PartyBuilder`, and re-derived in place on level-up or a Weave change so HP shifts like a Workshop upgrade instead of respawning the party.
**Why**: Per-character XP in a party game punishes swapping members and adds bookkeeping the GDD never asks for. Keeping builds in the ledger means one migration path and no new save section.
**Revisit when**: multiclassing (level 5 in the GDD) or per-character levels are needed; the Weave Tree needs more than flat stat talents.

## D-065 — Stealth, ambush, absorption and silence as resource/ability vocabulary
**Date**: 2026-09-08
**Decision**: Four generic mechanics carry the last two classes. `effect: "stealth"` (self) sets `hidden`: hostile abilities and the enemy brain cannot target a hidden combatant; attacking from hiding is an ambush (`rules.ambush_hit_bonus`, `ambush_damage_mult`) and reveals; any damage taken reveals. A resource may declare `gain_on_stealth` and `reveal_at_max` (Wireghost Heat: hiding heats, the cap lights you up until the `vent_ability` cools you). A resource may declare `absorb: {type, fraction}` and `gain_per_absorbed` (Null Blade: half of arcane damage, chain shocks included, becomes Null for the lash). `effect: "silence"` with `duration` puts `statuses.silenced` on the target; arcane abilities are refused while it lasts and it counts down at the target's turn start. Abilities may declare `cooldown` (turns, counted down at the user's turn start; Shadow Step: 3) so a stealther is exposed for a turn between windows and cannot stall a fight by re-hiding forever. The `stealther` archetype hides when nothing is in reach, closes in unseen and ambushes; the Wire-Lurker uses it in the Undercity pool. Scrap-Knight Heat is renamed Vent Heat so the two resources read apart.
**Why**: GDD §8 gives Wireghost and Null Blade identities that need engine support; naming the mechanics generically means Razor/Phantom/Voidfencer/Suppressor and future enemies get them for free (GDD §15).

## D-066 — Enemies approach by walking distance, not straight-line distance
**Date**: 2026-09-08
**Decision**: `CombatState.distance_field(goal)` is a BFS over walkable cells (movement adjacency, occupants ignored); `EnemyBrain._closest_reachable` picks the reachable cell with the smallest walking distance, falling back to straight-line only when the goal is cut off. The soak test policy uses the same field. `tests/test_runner.gd` accepts `-- --only=<fragment>` to run one file.
**Why**: The soak test stalled a fight at round 366: a scav and the last party member stood three cells apart with a wall between them, and the greedy approach could not find the way round. A stealth window and cooldown (D-065) stop hidden enemies from stalling; this stops visible ones. Full AI awareness of cover, elevation and surfaces is still S16.

## D-067 — Enemy AI v2: five archetypes over one texture score
**Date**: 2026-09-08
**Decision**: `EnemyBrain.position_score` rates a cell against the target: cover between the two (`ai_cover_weight`), high ground (`ai_elevation_weight`, negative when below), a mana pool for arcane casters (`ai_mana_pool_weight`), corrosive biogrowth (`ai_corrosive_penalty`). Rushers approach by walking distance with texture breaking ties; ranged enemies fire from any cell in the kite band unless a reachable cell has strictly better texture, then relocate first; stealthers hide, close and ambush; summoners call minions to their `summon_max` then fight as ranged; controllers land fresh control effects (root, silence) on the nearest unaffected target then fight as ranged. Control effects are never re-applied to a target that already has them. New vocabulary: `effect: "summon"` (`summon`, `summon_max`, `cooldown`; minions get `summoned_by`, join the order and the world as real enemies with loot and XP), `effect: "root"` (no movement for `duration` own turns). Statuses now count down when the affected combatant's turn ends, so "silenced 2" is two silenced turns.
**Why**: S7 built cover, elevation and surfaces that only the player used. One scoring function, weighted from `rules/combat`, gives every archetype the same awareness and keeps the archetypes themselves small. Each archetype has a scripted fight it wins against a party that only swings back.

## D-068 — Elites, bosses and depth scaling (closes D-038)
**Date**: 2026-09-08
**Decision**: `StatBlock.for_enemy(entry, rules, depth, tier)`: elite x1.5 HP +1 damage; boss x3 HP +2 damage +1 AP; every enemy gets HP x (1 + 0.15 x (depth - 1)) and +1 damage per two depths past the first. A placement may carry `tier`; an entry may declare its own (the Undercity Warlord is a boss). The generator rolls elites per placement (`elite_chance_per_depth`, capped) and, from `boss.min_depth`, posts the template boss on the floor cell nearest the extraction pad. Depth 3 is measurably harder than depth 1 in the scene test: more bodies, more than 1.3x the total HP, and a boss on the pad.
**Why**: D-038 said depth only adds bodies. The demo needs a difficulty ramp the Beacon controls, and a boss at the pad turns extraction into a decision.

## D-069 — Biomes are templates plus a palette; the Beacon unlocks them
**Date**: 2026-09-08
**Decision**: A second biome is a `biomes` palette (same sixteen roles), its own tiles (moss floor, root wall, sap pool, data vine, rootrot, canopy, spore bed) and a `shards` template that names them, its enemy family and its boss. Templates can ask for `rooms.style: "oval"` (ellipse hollows) and `corridors.width` (1–3). A template with `requires_unlock` is launchable only when a reached Bastion level lists that id under `unlocks` (Beacon level 2 finds the Verdant Datacore); the system menu lists every template and N launches the last chosen one. `--biome=<template>` before `--shard=` renders it in CI. No engine change was needed for the family: hybrids, constructs, a summoner and a controller boss reuse S15/S16 vocabulary.
**Why**: The second biome is an M2 exit criterion and the first proof that biomes are data (GDD §15). Beacon-gated unlocks make the Bastion the place where the world grows.

## D-070 — Spores: a surface that shrouds whoever stands in it
**Date**: 2026-09-08
**Decision**: `rules/combat.surface_evasion` maps a surface to evasion granted to a target standing on it (`spore`: 10). It applies in `attack_modifiers` (tag "spores" in previews and the log) and the enemy brain values such cells at half the bonus. Rootrot, sap pools and data vines are corrosive, mana-pool and conduit tiles under new names, so the Datacore reads differently without new mechanics.
**Why**: One new surface mechanic per biome keeps the vocabulary growing slowly and the validator honest.

## D-071 — Shard features are carved data with validator rules
**Date**: 2026-09-08
**Decision**: A template's `features` block asks for secrets, vaults, waypoints, a merchant, a rarity table and a ramp fraction. The generator carves them first, after the walk graph is final, so the layout never depends on depth or quest extras: secrets are one-cell pockets behind a `secret_door` tile that gives when a party member stands beside it; vaults are two-cell pockets behind a `vault_door` that costs banked Ciphers (E / A / click) and hold loot of at least the vault rarity; relay waypoints are `waypoint` tiles on the way to the pad where E banks the haul without leaving, once each; the merchant is an NPC placement (`merchants` kind, stock paid from the banked ledger) at the halfway point. The difficulty ramp is `ramp_far_distance` in the generator's own four-way metric: groups past it are one larger and only they roll elites. Pickups carry `rarity` (common/rare/epic, `rules/loot`) which multiplies every grant and tints the gem. Opened doors and used relays are run deltas in saves. Every feature has a validator rule: pockets must be sealed until their door opens and open with it, vaults need a cost and loot, waypoints must be real tiles on the open path, the merchant on reachable floor, elites past the ramp, rarities known.
**Why**: GDD §11 lists these as what makes Shards replayable, and Ciphers finally have a sink. Carving before population keeps the "layout is seed-only" guarantee the save system relies on. Item affixes wait for an item system (M3).

## D-072 — Campaign tooling: map format v2, quest objectives, the Bastion map
**Date**: 2026-09-08
**Decision**: Handcrafted maps gain `transitions` (leader on a cell travels to another map and arrives at a named cell; optional `when` conditions), `triggers` (cells that fire once or every time, gated by `when`, with effects: the dialogue effect keys plus `toast`, `open_doors`, `enemies` that spawn and start a fight, `dialogue`, `transition`), `doors` (`locked_door` tiles opened by Interact when a `key_flag` is set, optionally setting `opens_flag`), and `buildings` (Bastion sites). Door state on handcrafted maps and spent once-triggers live in narrative flags (`door_<map>_<x>_<y>`, `trigger_<map>_<id>`), so they persist with the story rather than the run. Quest stages gain `objectives` (`text`, `done_when` conditions) and a quest may be `main` (no companion) and `auto_start`; the journal (J, or the system menu) ticks objectives against the narrative state. The home map is now `bastion`, a plaza with the four buildings standing on it as `BuildingActor` blocks that grow a storey per level; the yard is a handcrafted map through the gate, and the gate road east of it is the first authored story map: a lever trigger, a locked gate, an ambush, and the end of the road closing the main quest's first stage. `home_map` is an export so tests keep the yard as home.
**Why**: S20–S22 author companions, the Lattice and Act 1 on top of this. One story map that plays end to end in a test (lever → gate → ambush → road end → journal done → reload) proves the format before content depends on it.

## D-073 — Three companions, one protagonist: the demo party
**Date**: 2026-09-08
**Decision**: The default party preset is `demo`: the protagonist alone, with Sera (the yard), Dax (the yard gate) and Kaj-7 (the gate road, once the road is open) filling the other three slots as they are recruited, which is exactly `party_max`. Tests pin the three-member `prototype` preset. Kaj-7 (Synth Drone Shepherd, Lattice-courted) and Dax (Vaultkin Null Blade, Ashfound-leaning) are registry entries with recruit/talk/banter dialogue and a personal quest each, both quests intersecting the main plot: Kaj-7's maker-signal is a Choir thread (its recruit waits on the main quest opening the road; the relay names the Choir), Dax's seal runs on Weft-light he cannot touch. The casting rule holds on every recruit and quest choice: one companion approves, another is wounded. Vaultkin is a race entry with `playable: false`, kept off the creator (one generic filter). Both quests ship all three death-stakes paths.
**Why**: Three companions is the M2 exit criterion, and the S11 data model held: no engine change beyond the playable flag.

## D-074 — Factions are reputation plus a casting rule; joining waits for Act 2
**Date**: 2026-09-08
**Decision**: `factions` is a content kind (name, colour, `rivals`, `joinable_act`). `NarrativeState.reputation` holds a score per faction, saved with the story; conditions take `reputation: {faction: {min, max}}` and effects take `reputation: {faction: delta}`. When an effect block moves a faction's reputation, every recruited companion leaning that way (`companions.faction`) gains a point of approval and every one leaning toward a rival loses one, unless the same block set their approval explicitly. Story NPCs are a kind (`npcs`: name, faction, dialogue, art) placed on maps with `npc` and an optional `when`; Envoy Calder of the Lattice arrives on the plaza once the road is open. Her dialogue starts the Lattice quest, offers to "restore" Kaj-7 (a tension Kaj-7 raises afterwards), and takes an answer either way; the join choice requires the `act2` flag, so Act 1 can only warm or cool the relationship. The journal shows standing.
**Why**: "Lattice introduced" is an exit criterion and Act 2 needs the faction shape settled now. Reputation as numbers plus the casting rule as a mechanic means every future faction line changes companion feelings without hand-written approval blocks.

## D-075 — The demo slice: five stages, one boundary, no debug keys
**Date**: 2026-09-08
**Decision**: The Waking runs gate → relay → deeper → throat → choir: the gate road, Relay Station Nine (Pell, the hive, Halden's log), the Beacon raised to depth 2 and a depth-2 extraction, the Undercity Throat (the Warlord, then the first lucid Choir fragment). The fragment's dialogue sets `rules/demo.end_flag`; the end panel shows once with the run in numbers and the choice made, then the party is home with the story intact. Generic hooks added for it: trigger effects `victory_flag` (raised when the fight the trigger started is won) and `grant`; a once-trigger that starts a fight is spent only on victory, so a wipe lets the player return for the boss; extraction sets `extracted_depth_<n>` and upgrades set `building_<id>_l<n>` so quests can read them; Bastion buildings are interactable (the Beacon launches Shards, the Workshop opens the Bastion screen, the Arcanum the Weave, the Med-bay heals). The "deeper" to "throat" step still needs a hand-off the slice does not author yet (a trigger or dialogue after the depth-2 extraction); the test sets the stage. `docs/content-schemas.md` and `test_content_schemas.gd` pin the required fields of every kind.
**Why**: "Playable start to demo end without the debug keys" needed the Beacon to be a place and the boss to be retryable. The slice is authored thin (one map per beat) so the tooling is proven before the writing pass; length is nowhere near the planned 2–3 hours and is logged as such.

## D-076 — Front end: title, death-stakes at new game, settings with rebinding
**Date**: 2026-09-08
**Decision**: A cold start shows the title (New game → Story-Protected or Mortal, Continue from the autosave, Load via the slot list, Settings, Quit) inside the world scene; tests and CLI staging skip it (`Engine` meta set by the test runner, any `--` argument except `--title`). New game wipes the books and the story and stores the death-stakes choice as the narrative flag `mortal_mode`; `rules.story_protected` follows that flag on every load, so the mode rides with the save. The system menu is the pause menu and gains Settings and Title screen. Settings (fullscreen, master volume, pad glyph style) persist in `user://settings.json`; bindings can be rebound per action (press the new key or button; Esc keeps the old) and persist in `user://input.json` as overrides on top of `InputActions.BINDINGS`; a reset restores defaults. `Glyphs` names pad buttons for footers in Xbox or PlayStation terms, detected from the first connected pad unless the player picks one.
**Why**: A demo starts at a title screen, not in a yard; the death-stakes choice belongs at the start of a story, not in a rules file; and a controller-first game needs its bindings and glyphs to be the player's.

## D-077 — Audio is a content kind with synthesised placeholders
**Date**: 2026-09-08
**Decision**: `audio` entries (kind sfx or music) carry a `synth` spec that `SynthWave` turns into a stream at first use; adding `file` beside the sidecar replaces it without touching code. Abilities and walkable tiles carry their own `sound`; every other event (UI confirm/cancel/move/toast, combat hit/miss/death/turn/summon/stealth/vent, explore footstep/pickup/door/extract/level-up) is a name in `rules/audio` mapped to an entry. `AudioDirector` plays one-shots from a small pool, keeps a log for tests, and crossfades music between two players when the state changes: title, Bastion, explore per biome, combat. Footsteps follow the leader's cell.
**Why**: A silent demo reads as broken, and no audio assets exist. Synthesised placeholders make every event audible now and make the missing-asset list a grep for entries without `file`.

## D-078 — Steam behind Platform: one contract, two backends, Steam never required
**Date**: 2026-09-09
**Decision**: `PlatformBackend` is the full contract (availability, user, achievements, stats, cloud files); the null backend keeps achievements in memory and a cloud folder under `user://cloud_null/`, and `SteamPlatformBackend` talks to the GodotSteam singleton through dynamic calls so the scripts load without the extension. `PlatformService` picks Steam only when the singleton exists and `steamInitEx` succeeds with the app id from `steam/steam.json` (0 in the repo, so nothing initialises by accident). Achievements are content (`achievements` kind: name, Steam API name, conditions on the narrative); the world evaluates them at every autosave and after banking. Saves push to the cloud store as they are written and missing ones are pulled at startup; local files always win. `steam/steam_input_template.vdf` mirrors `docs/controller.md`. Both backends run the same contract test; the Steam half only asserts live behaviour when a client is up, which CI never has.
**Why**: GDD §4: all Steam calls behind an interface so the game runs Steam-free from the open repo. Achievements as conditions on flags means every future story beat is one JSON file away from an achievement.

## D-079 — Release: one tag, three builds, Linux smoked in CI, macOS ad-hoc, placeholders ship
**Date**: 2026-09-09
**Decision**: `v0.2.0-demo` is the first tag. The first tag run found the macOS universal export refusing to build without ETC2/ASTC textures enabled (`rendering/textures/vram_compression/import_etc2_astc`), which is now on in project.godot; the tag was moved to the fix. `release.yml` runs the tests, exports Windows, Linux and macOS from the same commit, boots the Linux export under Xvfb with `--screenshot --title` and fails the job if no frame is written (the `smoke-title` artifact keeps the frame), then packages and attaches the three archives to a GitHub Release. The exports carry `content/*.json`, the example mod and `steam/*.json` so the registry and the platform config load from the pack. macOS is ad-hoc signed and not notarized (no Apple developer account; Godot's Linux export cannot notarize anyway), which the release notes explain with the right-click → Open workaround; a real signing path is an M4 task once an account exists. The Steam demo depot layout is `steam/app_build.vdf` (three depots, ids 0, mapping `build/<platform>/`), unusable until Steamworks assigns ids. The art decision from D-075 lands here by default: no artist is attached, so the demo ships generated placeholders, and the title screen says "placeholder art and audio, real ones in progress" with the version. `docs/store-page.md` lists every store asset with its size and source; the only ones the repo can supply are the CI screenshots.
**Why**: "Never break the exports" had never been tested by a tag, and the smoke step turns a green export into evidence that the binary boots. Ad-hoc macOS and placeholder art are the honest options available today; both are logged in gaps as owed.

## D-080 — Saves are stamped with the content they index into; a mismatch is refused
**Date**: 2026-09-09
**Decision**: Save format v2 carries two fingerprints from the content registry: the whole content set (every entry of every kind, mods included, provenance stripped so a pack and a checkout hash alike) and the one entry the save's deltas index into: the handcrafted map, or the Shard template plus `ShardGenerator.LAYOUT_VERSION`. `SaveSystem.content_check` runs before the world is touched: a save whose location fingerprint is missing (v1), whose map or template no longer exists, or whose map or template has changed is refused with the reason, in the load toast and in every save list, which marks it "✗ content changed, needs a new game" and disables the row. A save written against other content whose location still matches (a balance number, a mod added) loads and is marked "content changed". The generator's layout version is bumped by hand when the same template, seed and depth would lay out differently.
**Why**: The exit criterion was "a save from a different content set is refused, not misloaded": dead-enemy and collected-pickup deltas are indexes into a map's placement lists, so a changed map silently moves them. Refusing only on the entry that matters keeps a balance patch from bricking every save, which a whole-set check would have done; the whole-set fingerprint is kept for the list and for support ("which content wrote this?").

## D-081 — Balance is a harness first: bands on naive play, and the Warlord learned to punch
**Date**: 2026-09-09
**Decision**: `test_balance.gd` plays every story fight of the demo (gate ambush, relay hive, the Warlord at level 2 and 3), the road as a player walks it (two fights, no Med-bay), and a Shard at each demo depth, twenty combat seeds each, with the Act 1 policy (hit the nearest thing, else walk at it), and prints a table: win rate, rounds, HP left, members downed. Each row holds a band; the naive policy is the floor, so the low edge means "winnable played badly" and the high edge "not a walkover". Tuned against it: the gate ambush is three scavs (was two, over before the enemy moved), the hive keeps two drones plus the mother, and the Warlord is 24 HP × 3 with evasion 15, a Chrome-Addict escort, and a new 2-AP finisher (`chrome_haymaker`, 5–9) instead of four 1-AP fists, which lands at a 75% naive win over two and a half rounds with half the party's HP gone. Found on the way: the controller archetype fell back to ranged kiting after its control effects, so the Warlord, whose only damage was a fist, spent every turn netting and walking away and lost every fight; a controller whose damage is melee now closes like a rusher. The `deeper` stage of the main quest hands off to `throat` in data: a stage with `next` advances when its objectives are done (checked before every autosave, with `next_toast`), so the test no longer sets the stage by hand.
**Why**: "Two external playtesters finish the slice" needs people the repo does not have; the harness is what can run on every PR and what a human pass will be measured against. The biggest finding is not tuned here on purpose: with 4 AP and 1-AP basic attacks, every body swings four times a turn for ~10 damage against 12–20 HP, so trash fights end in one or two rounds and initiative decides them (the naive party still wipes 30% of depth-1 Shards through chained fights with no healing). Pricing basic attacks at 2 AP with cheap 1-AP utility is the obvious experiment and touches every ability and a dozen tests; it is a feel decision for a human with the harness, logged in gaps, not a blind change.

## D-082 — M3 is systems, then content authored thin and wired; writing is a track, not a session
**Date**: 2026-09-09
**Decision**: `docs/m3-plan.md` schedules nineteen sessions in two phases. Phase A (S28–S37) builds what the campaign cannot be authored without: the combat-economy decision from D-081 taken first with the harness and a playtest; items, affixes and cyberware; races 6–10 with their hooks as generic rules; progression to level 12 with multiclassing and the subclass mechanics that are still strings; faction joining with vendors, areas and locks; the Ghost Markets and the Null Cathedral; the Archive, Garden and Quarters plus account unlocks; campaign tooling for branches, scripted sequences and an ending state machine; romance. Phase B (S38–S46) authors the game in story order: companions 4–6, Act 1 complete, Act 2 in two halves, Act 3, endings, the race-reactivity pass, modding docs with a validator, and a close that tags `v0.3.0` behind a scripted full-campaign test. Writing, art, audio, playtesting and the Steam and Apple accounts are parallel tracks that need people; sessions never block on them. "Content complete" is defined as every beat wired in data and walked by a test in both death-stakes modes; hours and prose are the writing track's and are logged as measured.
**Why**: The GDD's M3 line is thirty hours of campaign; no session authors that. S22 showed a session can wire a beat thin and prove it, and M2 showed art as a named track kept fourteen sessions unblocked. Taking the AP decision first avoids retuning three acts; systems before content avoids authoring twice; story order keeps every session's test building on the last.

## D-083 — Every attack costs at least 2 of 4 AP; the AI focuses fire and rushers break off once
**Date**: 2026-09-09
**Decision**: Every ability that deals damage costs one more AP than it did (basic attacks 1 → 2, heavy attacks 2 → 3); abilities with no damage (vent, cool down, shadow step, summons, shields) keep their price. With 4 AP a turn that reads as two attacks, or one heavy attack and a self action, movement free. The experiment ran first as runtime overrides in the balance harness, content untouched, and the table decided it: naive-policy rounds went from 1.6 to 2.0 on the gate ambush, 1.6 to 2.1 at the hive and 2.4 to 5.5 against the Warlord, members downed per win fell on every row, and both sides' damage halved together, so the tactical vocabulary (cover, flanks, marks, roots) is a larger share of each fight. Retuned on the new economy: the Warlord is 16 HP × 3 with evasion 10 (a 70% naive win over four rounds with half the party's HP gone, then 60–65% once the AI focused fire); Rusted Undercity gangs are one or two bodies at depth 1 (`group_size` [1, 2]), depth still adding groups and elites. AI: every archetype now targets the lowest-HP hostile it can reach this turn (walk plus longest range) instead of the nearest; a rusher at or under `ai_retreat_hp_fraction` (0.3) of its HP, with an ally still up and a hostile within two cells, breaks off once toward its allies, gaining at least two cells; a lone survivor never runs and a retreat happens once per fight, so nothing can stall. Harness after the session: gate 100% / 2.0 rounds, hive 95% / 2.8, Warlord 60–65% / 4.2, road chain 95%, Shards 60% / 55%.
**Why**: With 1-AP attacks every body swung four times a turn for ~10 damage against 12–20 HP; fights ended before positions mattered and initiative decided them (D-081). Two actions a turn is the genre's shape for a reason. The experiment-first method (overrides in the harness, then content) is how the next economy question should be run too. Focus fire and retreat were the two AI gaps every playtest note would have listed first; both are bounded so the soak stays green. No external playtest existed to triage, which is still the top gap.

## D-084 — Items are instances of content: bases, affixes by rarity, slots from rules and race
**Date**: 2026-09-09
**Decision**: Two kinds. An `items` entry is a base with a slot (weapon, armour, trinket, cyberware), stat mods, a damage bonus, a drop weight, a merchant price, an optional `min_rarity`, optional `families`, and an optional Workshop recipe. An `affixes` entry is a prefix or suffix with its own mods, the slots it may sit on (or `any`), a weight and a minimum rarity. What the player owns is an instance: `{uid, item, affixes, rarity}`, rolled by `ItemSystem.roll_drop` from the run's seeded RNG (a weighted base that fits the rarity, then as many affixes as `rules/loot.affixes_by_rarity` allows, no repeats, each allowed on the slot). Instances ride the run haul (`RunState.items`, lost on a wipe) and bank into `Ledger.items` on extraction; off-Shard drops bank at once. Equipment is `Ledger.builds[member].equipment` keyed by slot key, so a loadout saves with the books and `PartyBuilder.member_specs` adds its stats and damage bonus beside growth, subclass and talents. Slot keys come from `rules/loot.slots` (weapon, armour, two trinkets) plus a race's `cyberware_slots` (Chromed: 2, the GDD's extra equipment slots as data). Drops: enemies by tier (`drop_chance_by_tier`, `drop_rarity_by_tier`; an entry's own `loot.item_chance` / `item_rarity` win), loot crates as a pickup whose `grants.item` drops at the pickup's rarity (so vaults hold rare-plus gear through D-071), the Fence stocks items (`effect.item`), and the Workshop crafts recipes at its level for Salvage. The pack screen (I at home, or the system menu) lists slots, the pack and the recipes per member; Enter unequips, equips into an empty fitting slot or swaps, or crafts.
**Why**: GDD §12 and D-071 left rarity with nothing rare to give and Chromed with a hook and no equipment. Bases plus affixes is the smallest shape that makes a rare drop read as one, and keeping every number in content means the S28 method (override in the harness, then edit) covers gear too. Two bugs the tests caught on the way: reading the rules' slot array by reference and appending to it, and `build_for` dropping keys it did not know, so equipment must be carried by every writer of a build.

## D-085 — Race hooks are a trait vocabulary any entry can carry
**Date**: 2026-09-09
**Decision**: The five M1/M2 races carried their GDD hooks as strings nothing read. They are now `traits`, a block of generic keys with one reader each: `resist {damage_type: fraction}` (negative is a weakness; surfaces deal typed `corrosive` damage now), `regen_on_surface {surface: hp}`, `detect_hidden N` (hidden hostiles within N cells with line of sight are revealed when the detector's turn begins), `ability_damage_bonus {ability: n}`, `heal_immune_types [types]` (a vent-style heal of that damage type does nothing), `bonus_abilities [ids]` (added beside the class list), `salvage_bonus f` (summed across the standing party when a haul is banked), `mend_after_combat f` (a fraction of max HP back on victory), `talent_cost_mod n` (Aether price shift, floored at 0), and `tags [..]` (read by the new `race_tag` condition; the reactivity hook for S44). Traits flow race → origin merge (`PartyBuilder.merge_traits`: numbers add, arrays union) → PartyMember → Combatant, and any `enemies` entry can carry the same block. The ten races: Trueborn (cheaper talents), Chromed (cyberware slots, D-084), Aetherborn (an innate `weft_spark` whatever the class, weak to tech), Synth (immune to corrosion, arcane heals do nothing), Rootkin (biogrowth feeds them), Hollow (immune to corrosion, a quarter off arcane, tagged unnerving), Splicekin (senses hiders at two cells, +1 on strikes), Vaultkin (playable now: sees hiders at three, half corrosion, a fifth more Salvage), Skyborn (agile, tagged old_world), Swarmborn (mends a quarter after every fight, tagged disguise). Four overlay kinds join the paper-doll (echo, pelt, sky, swarm).
**Why**: GDD §15: a race is a registry entry, and "if adding one requires engine changes the architecture is wrong". Ten entries with a shared vocabulary is the test of that; the vocabulary's readers are the only code, and each is a rule an origin, a subclass or an enemy family can use next. Left as tags on purpose: Synth repair with parts, Skyborn knowledge checks, Swarmborn disguise and Hollow unnerving are dialogue and NPC reactions, which is the S44 pass over finished lines.

## D-086 — Progression v2: levels split between two classes, capstones at eight, subclass identities as effects
**Date**: 2026-09-09
**Decision**: The party level runs to 12 on a twelve-step curve, with talent tiers at 1, 4, 7 and 10 and two new talents per branch above tier 2; the Weave Tree was already cross-class (any member buys any branch) and stays so. Multiclassing is a build choice from `multiclass_level` (5): a member names a second class and then moves levels into it one at a time at the Weave, never more than the levels past the gate, so the main class always keeps five. `Progression.class_levels` splits the party level; the second class contributes its base abilities (not strike), its growth per level held there and its own `unlocks` at that count. A class `capstone` ability unlocks at `capstone_level` (8) levels in that class, so a pure build reaches it at 8 and a 12 split 8/4 still does; the Arcanum resets the split with the subclass and talents. Six capstones ship. The subclass identities that were plain attacks are now effects the vocabulary carries: `chain` (Storm Lance arcs half its damage to the nearest hostiles within two cells of the mark, never chaining from a chain), `taunt` (Shield Bash: the target's brain must attack the taunter while it lasts), `poison` with `spread` (Plague Hex ticks at the end of the victim's own turn and jumps to adjacent teammates with one turn less, so it burns out), `counter` (Riposte is a self stance: any adjacent attack, hit or miss, is answered), `aoe` (Null Field silences everyone within a cell of the target; friendly fire follows the rule), and `summon_count` on summons with party-side summons (Drone Swarm calls two drones, Deploy Turret one turret; they are the player's combatants, drop nothing, and are freed with the fight). One attack roll is one `_strike`, used by the primary, every area target and nothing else.
**Why**: GDD §8 in full: levels 1–12, multiclassing from 5, capstones at 8+, subclasses that are what their names say. Splitting levels rather than tracking XP per class keeps the single party level (D-064) and makes the choice reversible at the Arcanum. Every new effect is a key on an ability, so an enemy family can use chain, taunt or poison next session without code. Left open: the second class has no subclass and no resource loop of its own; the demo cap of 6 is gone because the demo content cannot reach past level 4 anyway.
