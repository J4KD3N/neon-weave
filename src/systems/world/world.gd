## Exploration scene root: loads a map, party preset and enemies from the
## content registry, builds the view, routes input, and hands off to the
## [CombatController] when an encounter starts.
##
## Modes: "explore" (real-time), "combat" (turn-based), "defeated".
class_name ExploreWorld
extends Node2D

@export var map_id: String = "proto_yard"
@export var party_id: String = "prototype"
## 0 = random per encounter. Tests pin it.
@export var combat_seed: int = 0

@onready var map_view: MapView = $Scene/MapView
@onready var party: Party = $Scene/Party
@onready var enemies_node: Node2D = $Scene/Enemies
@onready var camera: FollowCamera = $Camera
@onready var overlay: DebugOverlay = $Hud/DebugOverlay

var registry: ContentRegistry
var map_data: MapData
var rules: CombatRules
var enemies: Array[EnemyActor] = []
var combat: CombatController
var hud: CombatHud
var highlighter: CellHighlighter
var mode: String = "explore"
var hovered_cell := Vector2i(-1, -1)

var _owns_registry := false
var _screenshot_path := ""
var _frames := 0


func _ready() -> void:
	InputActions.ensure()
	registry = _resolve_registry()
	overlay.registry = registry
	rules = CombatRules.from_entry(registry.get_entry("rules", "combat"))
	load_map(map_id)
	highlighter = CellHighlighter.new()
	highlighter.name = "Highlighter"
	highlighter.map_view = map_view
	map_view.add_child(highlighter)
	spawn_party(party_id)
	spawn_enemies()
	hud = CombatHud.new()
	hud.name = "CombatHud"
	add_child(hud)
	combat = CombatController.new()
	combat.name = "Combat"
	add_child(combat)
	combat.setup(self, hud, highlighter)
	combat.ended.connect(_on_combat_ended)
	camera.target = party.leader()
	camera.snap()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_screenshot_path = arg.get_slice("=", 1)


func _exit_tree() -> void:
	if _owns_registry and registry != null:
		registry.free()


func load_map(id: String) -> void:
	var entry: Dictionary = registry.get_entry("maps", id)
	var tiles_by_id: Dictionary = {}
	for tile: Dictionary in registry.get_all("tiles"):
		tiles_by_id[tile["id"]] = tile
	map_data = MapData.parse(entry, tiles_by_id)
	for err: String in map_data.errors:
		push_warning(err)
	map_view.build(map_data, registry.get_entry("biomes", map_data.biome_id))


func abilities_by_id() -> Dictionary:
	var out: Dictionary = {}
	for ability: Dictionary in registry.get_all("abilities"):
		out[ability["id"]] = ability
	return out


func spawn_party(id: String) -> void:
	var preset: Dictionary = registry.get_entry("parties", id)
	var member_entries: Array = preset.get("members", [])
	var spawns := map_data.spawn_cells()
	var specs: Array[Dictionary] = []
	for i: int in member_entries.size():
		var data: Dictionary = member_entries[i]
		var cls: Dictionary = registry.get_entry("classes", String(data.get("class", "")))
		var race: Dictionary = registry.get_entry("races", String(data.get("race", "")))
		var cell: Vector2i = spawns[mini(i, spawns.size() - 1)] if not spawns.is_empty() else Vector2i.ZERO
		specs.append({
			"data": data,
			"color": class_color(String(data.get("class", ""))),
			"position": map_view.cell_to_world(cell),
			"stats": StatBlock.for_member(cls, race, rules),
			"abilities": cls.get("abilities", []),
		})
	party.spawn_members(specs)


func spawn_enemies() -> void:
	for e: EnemyActor in enemies:
		e.queue_free()
	enemies.clear()
	var entry: Dictionary = registry.get_entry("maps", map_id)
	var placements: Array = entry.get("enemies", [])
	for p: Dictionary in placements:
		var type: String = String(p.get("type", ""))
		var enemy_entry: Dictionary = registry.get_entry("enemies", type)
		var raw_cell: Array = p.get("cell", [0, 0])
		var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		if enemy_entry.is_empty():
			push_warning("map %s places unknown enemy '%s'" % [map_id, type])
			continue
		if not map_data.is_walkable(cell):
			push_warning("map %s places %s on blocked cell %s" % [map_id, type, cell])
			continue
		var actor := EnemyActor.new()
		actor.setup(type, enemy_entry, cell, StatBlock.for_enemy(enemy_entry, rules), rules.awareness_default)
		actor.position = map_view.cell_to_world(cell)
		enemies_node.add_child(actor)
		enemies.append(actor)


## Neon colour of a class's primary branch (GDD §5: Arcane purple, Tech teal, Body coral).
func class_color(class_id: String) -> Color:
	var cls: Dictionary = registry.get_entry("classes", class_id)
	var branches: Array = cls.get("branches", [])
	if branches.is_empty():
		return Color.WHITE
	var branch: Dictionary = registry.get_entry("branches", String(branches[0]))
	return Color.html(String(branch.get("color", "#ffffff")))


func living_enemies() -> Array[EnemyActor]:
	var out: Array[EnemyActor] = []
	for e: EnemyActor in enemies:
		if is_instance_valid(e) and not e.dead:
			out.append(e)
	return out


func enemy_at(cell: Vector2i) -> EnemyActor:
	for e: EnemyActor in living_enemies():
		if e.cell == cell:
			return e
	return null


## Path the leader to `cell`. False when the cell is blocked or unreachable.
func command_move(cell: Vector2i) -> bool:
	var l := party.leader()
	if l == null or not map_data.is_walkable(cell):
		return false
	var points := map_view.path_to(l.position, cell)
	if points.is_empty() and map_view.world_to_cell(l.position) != cell:
		return false
	party.set_path(points)
	return true


func leader_cell() -> Vector2i:
	var l := party.leader()
	return map_view.world_to_cell(l.position) if l != null else Vector2i(-1, -1)


func member_cell(m: PartyMember) -> Vector2i:
	return map_view.world_to_cell(m.position)


## Put the leader on `cell` and the others on the nearest free cells (debug/tests).
func teleport_party(cell: Vector2i) -> void:
	var blocked: Array[Vector2i] = []
	for e: EnemyActor in living_enemies():
		blocked.append(e.cell)
	var preferred: Array[Vector2i] = []
	for _m: PartyMember in party.members:
		preferred.append(cell)
	var cells := CellSettler.settle(map_data, preferred, blocked)
	for i: int in party.members.size():
		party.members[i].position = map_view.cell_to_world(cells[i])
	party.stop()
	party.trail.reset(party.leader().position)


## Starts combat when any enemy can see a party member within its awareness.
func check_encounters() -> bool:
	if mode != "explore":
		return false
	for e: EnemyActor in living_enemies():
		for m: PartyMember in party.members:
			if m.downed:
				continue
			var mc := member_cell(m)
			if LineOfSight.distance(e.cell, mc) <= e.awareness and LineOfSight.clear(map_data, e.cell, mc):
				start_combat(false)
				return true
	return false


## Living enemies within the rules' engage radius of any party member.
func engaged_enemies() -> Array[EnemyActor]:
	var out: Array[EnemyActor] = []
	for e: EnemyActor in living_enemies():
		for m: PartyMember in party.members:
			if LineOfSight.distance(e.cell, member_cell(m)) <= rules.engage_radius:
				out.append(e)
				break
	return out


func start_combat(first_strike: bool) -> void:
	if mode != "explore":
		return
	var foes := engaged_enemies()
	if foes.is_empty():
		return
	mode = "combat"
	party.stop()
	party.active = false
	var preferred: Array[Vector2i] = []
	for m: PartyMember in party.members:
		preferred.append(member_cell(m))
	var blocked: Array[Vector2i] = []
	for e: EnemyActor in living_enemies():
		blocked.append(e.cell)
	var cells := CellSettler.settle(map_data, preferred, blocked)
	for i: int in party.members.size():
		party.members[i].position = map_view.cell_to_world(cells[i])
	var seed_value := combat_seed if combat_seed != 0 else int(randi())
	combat.begin(party.members, cells, foes, first_strike, seed_value)


func _on_combat_ended(result: String) -> void:
	if result == "victory":
		for m: PartyMember in party.members:
			if m.downed:
				m.downed = false
				m.hp = 1
		party.trail.reset(party.leader().position)
		party.active = true
		mode = "explore"
	else:
		mode = "defeated"


func status_line() -> String:
	return "%s  |  %s  |  leader %s  hover %s  |  enemies %d  |  LMB move/attack · WASD steer · wheel zoom · F1 registry" % [
		map_data.name, mode, leader_cell(), hovered_cell, living_enemies().size(),
	]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		overlay.toggle_registry()
		return
	var mb := event as InputEventMouseButton
	var clicked := mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	match mode:
		"explore":
			if clicked:
				var cell := map_view.world_to_cell(get_global_mouse_position())
				var enemy := enemy_at(cell)
				if enemy != null and LineOfSight.distance(leader_cell(), cell) <= enemy.awareness:
					start_combat(true)
				else:
					command_move(cell)
		"combat":
			if clicked:
				combat.player_click(map_view.world_to_cell(get_global_mouse_position()))
			elif event.is_action_pressed("end_turn"):
				combat.end_player_turn()
			elif event.is_action_pressed("cancel"):
				combat.cancel_selection()
			else:
				for i: int in 4:
					if event.is_action_pressed("ability_%d" % (i + 1)):
						combat.select_ability(i)
		"defeated":
			if event.is_action_pressed("restart"):
				get_tree().reload_current_scene()


func _process(delta: float) -> void:
	if mode == "explore":
		var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if dir != Vector2.ZERO:
			party.steer_leader(dir, delta, map_view.is_walkable_world)
		check_encounters()
	hovered_cell = map_view.world_to_cell(get_global_mouse_position())
	overlay.status = status_line()
	_maybe_screenshot()


func _resolve_registry() -> ContentRegistry:
	var existing := get_node_or_null("/root/Content") as ContentRegistry
	if existing != null:
		return existing
	var local := ContentRegistry.new()
	local.reload()
	_owns_registry = true
	return local


## `-- --screenshot=/abs/path.png` saves the viewport after a few frames and quits.
## `-- --screenshot-combat` first teleports the party next to the enemies and
## starts a fight, so the combat UI is what gets captured.
func _maybe_screenshot() -> void:
	if _screenshot_path.is_empty():
		return
	_frames += 1
	if _frames == 2 and OS.get_cmdline_user_args().has("--screenshot-combat"):
		combat.animate = false
		teleport_party(Vector2i(13, 4))
		check_encounters()
	if _frames < 12:
		return
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_screenshot_path)
	print("screenshot %s -> %s" % [_screenshot_path, error_string(err)])
	_screenshot_path = ""
	get_tree().quit(0 if err == OK else 1)
