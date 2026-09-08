## Exploration scene root: loads a map and a party preset from the content
## registry, builds the view, and routes input (click-to-move, WASD, F1).
class_name ExploreWorld
extends Node2D

@export var map_id: String = "proto_yard"
@export var party_id: String = "prototype"

@onready var map_view: MapView = $Scene/MapView
@onready var party: Party = $Scene/Party
@onready var camera: FollowCamera = $Camera
@onready var overlay: DebugOverlay = $Hud/DebugOverlay

var registry: ContentRegistry
var map_data: MapData
var hovered_cell := Vector2i(-1, -1)

var _owns_registry := false
var _screenshot_path := ""
var _frames := 0


func _ready() -> void:
	InputActions.ensure()
	registry = _resolve_registry()
	overlay.registry = registry
	load_map(map_id)
	spawn_party(party_id)
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


func spawn_party(id: String) -> void:
	var preset: Dictionary = registry.get_entry("parties", id)
	var member_entries: Array = preset.get("members", [])
	var datas: Array[Dictionary] = []
	var colors: Array[Color] = []
	var positions: Array[Vector2] = []
	var spawns := map_data.spawn_cells()
	for i: int in member_entries.size():
		var data: Dictionary = member_entries[i]
		datas.append(data)
		colors.append(class_color(String(data.get("class", ""))))
		var cell: Vector2i = spawns[mini(i, spawns.size() - 1)] if not spawns.is_empty() else Vector2i.ZERO
		positions.append(map_view.cell_to_world(cell))
	party.spawn_members(datas, colors, positions)


## Neon colour of a class's primary branch (GDD §5: Arcane purple, Tech teal, Body coral).
func class_color(class_id: String) -> Color:
	var cls: Dictionary = registry.get_entry("classes", class_id)
	var branches: Array = cls.get("branches", [])
	if branches.is_empty():
		return Color.WHITE
	var branch: Dictionary = registry.get_entry("branches", String(branches[0]))
	return Color.html(String(branch.get("color", "#ffffff")))


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


func status_line() -> String:
	return "%s  |  leader %s  hover %s  |  %s  |  LMB move · WASD steer · wheel zoom · F1 registry" % [
		map_data.name, leader_cell(), hovered_cell,
		"moving" if party.is_moving() else "idle",
	]


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		command_move(map_view.world_to_cell(get_global_mouse_position()))
	elif event.is_action_pressed("toggle_debug"):
		overlay.toggle_registry()


func _process(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir != Vector2.ZERO:
		party.steer_leader(dir, delta, map_view.is_walkable_world)
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
func _maybe_screenshot() -> void:
	if _screenshot_path.is_empty():
		return
	_frames += 1
	if _frames < 10:
		return
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_screenshot_path)
	print("screenshot %s -> %s" % [_screenshot_path, error_string(err)])
	_screenshot_path = ""
	get_tree().quit(0 if err == OK else 1)
