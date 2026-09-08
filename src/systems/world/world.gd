## Exploration scene root: loads a map (handcrafted or generated Shard), a
## party preset, enemies and pickups from the content registry, routes
## input, runs the extraction loop, and hands off to the
## [CombatController] when an encounter starts.
##
## Modes: "explore" (real-time), "combat" (turn-based), "defeated".
class_name ExploreWorld
extends Node2D

const HOME_MAP := "proto_yard"
const DEFAULT_SHARD := "rusted_undercity"

@export var map_id: String = HOME_MAP
@export var party_id: String = "prototype"
## 0 = random per encounter. Tests pin it.
@export var combat_seed: int = 0
## Where the Bastion ledger persists. Tests point this at a scratch file.
@export var ledger_path: String = "user://ledger.json"
## Save slots and the autosave live here. Tests point this at a scratch dir.
@export var saves_dir: String = "user://saves"

@onready var map_view: MapView = $Scene/MapView
@onready var party: Party = $Scene/Party
@onready var enemies_node: Node2D = $Scene/Enemies
@onready var pickups_node: Node2D = $Scene/Pickups
@onready var npcs_node: Node2D = $Scene/Npcs
@onready var camera: FollowCamera = $Camera
@onready var overlay: DebugOverlay = $Hud/DebugOverlay

var registry: ContentRegistry
var map_data: MapData
## The map entry currently loaded: a `maps` content entry or a generated Shard.
var map_entry: Dictionary = {}
var rules: CombatRules
var ledger: Ledger
var run := RunState.new()
var bastion := BastionState.new()
var bastion_menu: BastionMenu
## The created character (CharacterSheet dict) leading the party, or {} for
## the preset's default leader. Saved under "protagonist".
var protagonist: Dictionary = {}
var creator_menu: CreatorMenu
var creator_state: CreatorState
## Loaded sprite sheets by id (`sprites` content kind). Missing or invalid
## sheets fall back to the placeholder rig.
var sheets: Dictionary = {}
## Flags, approval, quest stages, recruits. Saved under "narrative".
var narrative := NarrativeState.new()
var npcs: Array[NpcActor] = []
var dialogue_menu: DialogueMenu
var system_menu: SystemMenu
var dialogue: DialogueRunner
var enemies: Array[EnemyActor] = []
var pickups: Array[PickupActor] = []
var combat: CombatController
var hud: CombatHud
var highlighter: CellHighlighter
var mode: String = "explore"
var hovered_cell := Vector2i(-1, -1)
var hover_override := Vector2i(-1, -1) # screenshots and tests stand in for the mouse
## True while SaveSystem.restore rebuilds the world; suppresses autosaves so
## a load never overwrites the checkpoint it is reading.
var loading: bool = false

var _owns_registry := false
var _screenshot_path := ""
var _frames := 0


func _ready() -> void:
	InputActions.ensure()
	registry = _resolve_registry()
	overlay.registry = registry
	rules = CombatRules.from_entry(registry.get_entry("rules", "combat"))
	ledger = Ledger.load_or_new(ledger_path)
	if not ledger.load_error.is_empty():
		push_warning(ledger.load_error)
	bastion.setup(registry.get_all("buildings"), ledger.buildings)
	load_sheets()
	load_map_entry(registry.get_entry("maps", map_id))
	highlighter = CellHighlighter.new()
	highlighter.name = "Highlighter"
	highlighter.map_view = map_view
	map_view.add_child(highlighter)
	run.begin("", 0)
	spawn_party(party_id)
	apply_bastion_bonuses()
	spawn_enemies()
	spawn_pickups()
	hud = CombatHud.new()
	hud.name = "CombatHud"
	add_child(hud)
	bastion_menu = BastionMenu.new()
	bastion_menu.name = "BastionMenu"
	add_child(bastion_menu)
	creator_menu = CreatorMenu.new()
	creator_menu.name = "CreatorMenu"
	add_child(creator_menu)
	dialogue_menu = DialogueMenu.new()
	dialogue_menu.name = "DialogueMenu"
	add_child(dialogue_menu)
	system_menu = SystemMenu.new()
	system_menu.name = "SystemMenu"
	add_child(system_menu)
	spawn_npcs()
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
		elif arg.begins_with("--shard="):
			enter_shard(DEFAULT_SHARD, int(arg.get_slice("=", 1)))
		elif arg == "--creator":
			open_creator()
		elif arg.begins_with("--talk="):
			talk_to(arg.get_slice("=", 1))


func _exit_tree() -> void:
	if _owns_registry and registry != null:
		registry.free()


# --- loading ---------------------------------------------------------------

func tiles_by_id() -> Dictionary:
	var out: Dictionary = {}
	for tile: Dictionary in registry.get_all("tiles"):
		out[tile["id"]] = tile
	return out


## The `resources` entry behind a member's class resource ({} when none).
func resource_def_for(m: PartyMember) -> Dictionary:
	if m.resource_id.is_empty():
		return {}
	return registry.get_entry("resources", m.resource_id)


func abilities_by_id() -> Dictionary:
	var out: Dictionary = {}
	for ability: Dictionary in registry.get_all("abilities"):
		out[ability["id"]] = ability
	return out


## Loads every `sprites` sidecar + image once; invalid ones are warned and skipped.
func load_sheets() -> void:
	sheets.clear()
	for entry: Dictionary in registry.get_all("sprites"):
		var sheet := SpriteSheet.load_entry(entry)
		if sheet.is_valid():
			sheets[sheet.id] = sheet
		else:
			push_warning("sprite sheet %s: %s" % [entry["id"], ", ".join(PackedStringArray(sheet.errors))])


func sheet_for(id: String) -> SpriteSheet:
	return sheets.get(id)


func load_map_entry(entry: Dictionary) -> void:
	map_entry = entry
	map_data = MapData.parse(entry, tiles_by_id())
	for err: String in map_data.errors:
		push_warning(err)
	map_view.build(map_data, registry.get_entry("biomes", map_data.biome_id))


## Generates a Shard from a `shards` template and moves the party into it.
## `depth` 0 means the Beacon's current depth; loads pass the saved depth.
## Returns the generated map entry ({} when the template is unknown).
func enter_shard(template_id: String, seed_value: int, depth: int = 0, extras: Array[String] = []) -> Dictionary:
	var template: Dictionary = registry.get_entry("shards", template_id)
	if template.is_empty():
		push_warning("unknown shard template '%s'" % template_id)
		return {}
	var sites := extras if not extras.is_empty() else quest_sites()
	var entry := ShardGenerator.generate(template, seed_value, depth if depth > 0 else bastion.depth(), sites)
	for err: String in ShardValidator.validate(entry, tiles_by_id()):
		push_warning("shard %s: %s" % [entry.get("id"), err])
	if _enter(entry):
		run.begin(String(entry["id"]), seed_value)
		autosave()
		banter("enter_shard")
	return entry


## Pickup ids of quest sites that should appear in the next Shard: every
## quest whose current stage declares `shard_site`.
func quest_sites() -> Array[String]:
	var out: Array[String] = []
	for quest_id: String in narrative.quests:
		var quest: Dictionary = registry.get_entry("quests", quest_id)
		var stages: Dictionary = quest.get("stages", {})
		var stage: Dictionary = stages.get(narrative.stage_of(quest_id), {})
		var site: Dictionary = stage.get("shard_site", {})
		var pickup := String(site.get("pickup", ""))
		if not pickup.is_empty() and registry.has_entry("pickups", pickup):
			out.append(pickup)
	return out


## Loads a handcrafted map by id and moves the party into it. Loot found on
## handcrafted maps banks immediately (no extraction risk). Arriving home
## runs the Med-bay.
func enter_map(id: String) -> bool:
	var entry: Dictionary = registry.get_entry("maps", id)
	if entry.is_empty():
		return false
	if _enter(entry):
		map_id = id
		run.begin("", 0)
		if id == HOME_MAP:
			heal_party(bastion.heal_fraction())
	return true


func _enter(entry: Dictionary) -> bool:
	if mode == "combat":
		return false
	load_map_entry(entry)
	if party.members.is_empty():
		spawn_party(party_id)
		apply_bastion_bonuses()
	else:
		place_party(map_data.spawn_cells())
	spawn_enemies()
	spawn_pickups()
	spawn_npcs()
	mode = "explore"
	party.active = true
	if dialogue_menu != null:
		dialogue_menu.visible = false
	dialogue = null
	if highlighter != null:
		highlighter.clear_all()
	if hud != null:
		hud.hide_message()
		hud.visible = false
	if bastion_menu != null:
		bastion_menu.visible = false
	if system_menu != null:
		system_menu.close()
	if combat != null:
		combat.release_cursor()
	if camera != null:
		camera.target = party.leader()
		camera.snap()
	return true


## After a wipe: back to the yard. The Med-bay revives whoever is down.
## Nothing banked is lost.
func return_home() -> void:
	if mode == "combat":
		return
	mode = "explore"
	enter_map(HOME_MAP)
	autosave()


# --- saves -----------------------------------------------------------------

func save_path(save_name: String) -> String:
	return SaveSystem.path_for(saves_dir, save_name)


## Save anywhere out of combat. ERR_UNAVAILABLE during a fight.
func save_to(save_name: String) -> Error:
	if mode == "combat":
		return ERR_UNAVAILABLE
	return SaveSystem.write(save_path(save_name), SaveSystem.capture(self))


func save_slot(n: int) -> Error:
	var err := save_to(SaveSystem.slot_name(n))
	if overlay != null:
		overlay.toast("Saved to slot %d" % n if err == OK else "Save failed: %s" % ("in combat" if err == ERR_UNAVAILABLE else error_string(err)), 2.0)
	return err


func autosave() -> Error:
	if loading:
		return OK
	return save_to(SaveSystem.AUTOSAVE)


## Loads a save by name. Returns the restore errors ("" entries never); an
## unreadable file yields a single error.
func load_from(save_name: String) -> Array[String]:
	var data := SaveSystem.read(save_path(save_name))
	if data.has("_error"):
		var one: Array[String] = [String(data["_error"])]
		if overlay != null:
			overlay.toast("Load failed: %s" % one[0], 2.5)
		return one
	var errors := SaveSystem.restore(self, data)
	if overlay != null:
		overlay.toast("Loaded %s" % save_name if errors.is_empty() else "Loaded %s with %d problem(s)" % [save_name, errors.size()], 2.5)
	for e: String in errors:
		push_warning("load %s: %s" % [save_name, e])
	return errors


func load_slot(n: int) -> Array[String]:
	return load_from(SaveSystem.slot_name(n))


## Moves the existing party (HP intact) onto a map's spawn cells.
func place_party(cells: Array[Vector2i]) -> void:
	for i: int in party.members.size():
		var cell: Vector2i = cells[mini(i, cells.size() - 1)] if not cells.is_empty() else Vector2i.ZERO
		party.members[i].position = map_view.cell_to_world(cell)
		party.members[i].show_hp = false
	party.stop()
	if party.leader() != null:
		party.trail.reset(party.leader().position)


## Med-bay: restores `fraction` of max HP to everyone and revives the downed.
func heal_party(fraction: float) -> void:
	for m: PartyMember in party.members:
		var amount := int(ceil(m.max_hp * fraction))
		m.downed = false
		m.hp = mini(m.max_hp, maxi(m.hp, 0) + amount)
		if m.hp <= 0:
			m.hp = 1


func apply_bastion_bonuses() -> void:
	for m: PartyMember in party.members:
		m.set_hp_bonus(bastion.hp_bonus())


func at_home() -> bool:
	return not run.in_shard


## Spends from the ledger, raises the building, persists, re-applies bonuses.
func upgrade_building(id: String) -> bool:
	var why := bastion.can_upgrade(id, ledger)
	if not why.is_empty():
		overlay.toast("%s: %s" % [bastion.name_of(id), why], 2.0)
		return false
	if not bastion.upgrade(id, ledger):
		return false
	ledger.buildings = bastion.to_dict()
	var err := ledger.save()
	if err != OK:
		push_warning("ledger save failed: %s" % error_string(err))
	apply_bastion_bonuses()
	overlay.toast("%s upgraded to L%d — %s" % [bastion.name_of(id), bastion.level(id), bastion.blurb(id)], 3.0)
	if bastion_menu != null and bastion_menu.visible:
		bastion_menu.refresh(bastion, ledger)
	return true


## Opens/closes the Bastion screen; only at home while exploring.
func toggle_bastion() -> bool:
	if bastion_menu == null:
		return false
	if bastion_menu.visible:
		bastion_menu.visible = false
		return false
	if mode != "explore" or not at_home():
		return false
	bastion_menu.refresh(bastion, ledger)
	bastion_menu.visible = true
	return true


## Extraction pad cell of the current map, or (-1,-1) when it has none.
func extraction_cell() -> Vector2i:
	if not map_entry.has("extraction"):
		return Vector2i(-1, -1)
	var raw: Array = map_entry["extraction"]
	return Vector2i(int(raw[0]), int(raw[1]))


# --- spawning --------------------------------------------------------------

func spawn_party(id: String) -> void:
	var preset: Dictionary = registry.get_entry("parties", id)
	var positions: Array[Vector2] = []
	for cell: Vector2i in map_data.spawn_cells():
		positions.append(map_view.cell_to_world(cell))
	var specs := PartyBuilder.member_specs(registry, preset, protagonist, rules, positions, narrative.recruited)
	for spec: Dictionary in specs:
		spec["sheet"] = sheet_for(String(spec.get("sheet_id", "")))
	party.spawn_members(specs)


## Companions standing on the map (`npcs` placements) who are not recruited.
func spawn_npcs() -> void:
	for n: NpcActor in npcs:
		if is_instance_valid(n):
			n.queue_free()
	npcs.clear()
	if npcs_node == null:
		return
	var placements: Array = map_entry.get("npcs", [])
	for p: Dictionary in placements:
		var id := String(p.get("companion", ""))
		var entry: Dictionary = registry.get_entry("companions", id)
		if entry.is_empty() or narrative.is_recruited(id):
			continue
		var raw: Array = p.get("cell", [0, 0])
		var cell := Vector2i(int(raw[0]), int(raw[1]))
		if not map_data.is_walkable(cell):
			push_warning("map %s places npc %s on blocked %s" % [map_data.id, id, cell])
			continue
		var race: Dictionary = registry.get_entry("races", String(entry.get("race", "")))
		var actor := NpcActor.new()
		actor.setup(id, entry, cell, class_color(String(entry.get("class", ""))), sheet_for(String(Dictionary(race.get("art", {})).get("sheet", ""))), race.get("overlay", {}))
		actor.position = map_view.cell_to_world(cell)
		npcs_node.add_child(actor)
		npcs.append(actor)


func npc_at(cell: Vector2i) -> NpcActor:
	for n: NpcActor in npcs:
		if is_instance_valid(n) and n.cell == cell:
			return n
	return null


## Adds a recruited companion to the party next to the leader (no respawn,
## so nobody's HP resets) and removes their NPC stand-in.
func add_companion(id: String) -> bool:
	if party.members.size() >= rules.party_max:
		overlay.toast("The party is full.", 2.0)
		return false
	var preset := {"members": []}
	var specs := PartyBuilder.member_specs(registry, preset, {}, rules, [], [id])
	if specs.is_empty():
		return false
	var spec := specs[0]
	spec["sheet"] = sheet_for(String(spec.get("sheet_id", "")))
	var blocked: Array[Vector2i] = []
	for m: PartyMember in party.members:
		blocked.append(member_cell(m))
	var free := map_data.nearest_free_cells(leader_cell(), 1, blocked)
	spec["position"] = map_view.cell_to_world(free[0]) if not free.is_empty() else party.leader().position
	var member := party.add_member(spec)
	member.set_hp_bonus(bastion.hp_bonus())
	for n: NpcActor in npcs:
		if is_instance_valid(n) and n.companion_id == id:
			n.queue_free()
	var kept: Array[NpcActor] = []
	for n: NpcActor in npcs:
		if is_instance_valid(n) and n.companion_id != id:
			kept.append(n)
	npcs = kept
	return true


# --- dialogue ----------------------------------------------------------------

## Evaluation context for conditions: narrative + the leader's origin tag,
## race and class.
func dialogue_ctx() -> Dictionary:
	var l := party.leader()
	var origin_tag := ""
	if l != null and not l.origin_id.is_empty():
		origin_tag = String(registry.get_entry("origins", l.origin_id).get("dialogue_tag", ""))
	return {"narrative": narrative, "origin_tag": origin_tag, "race": l.race_id if l != null else "", "class": l.class_id if l != null else ""}


func speaker_names() -> Dictionary:
	var names: Dictionary = {"narrator": "—", "player": party.leader().display_name if party.leader() != null else "You"}
	for c: Dictionary in registry.get_all("companions"):
		names[c["id"]] = String(c.get("short_name", c.get("name", c["id"])))
	return names


## Opens a `dialogue` entry. False when unknown, in combat, or no start node applies.
func open_dialogue(dialogue_id: String) -> bool:
	if mode != "explore":
		return false
	var entry: Dictionary = registry.get_entry("dialogue", dialogue_id)
	if entry.is_empty():
		push_warning("unknown dialogue '%s'" % dialogue_id)
		return false
	var runner := DialogueRunner.new()
	if not runner.start(entry, dialogue_ctx()):
		return false
	dialogue = runner
	party.stop()
	dialogue_menu.open(runner, speaker_names())
	return true


func in_dialogue() -> bool:
	return dialogue != null and not dialogue.finished


## Talks to a companion by id (their recruit or talk dialogue).
func talk_to(companion_id: String) -> bool:
	var entry: Dictionary = registry.get_entry("companions", companion_id)
	if entry.is_empty():
		return false
	var d: Dictionary = entry.get("dialogue", {})
	var id := String(d.get("talk" if narrative.is_recruited(companion_id) else "recruit", ""))
	return open_dialogue(id)


## Picks the n-th available choice of the open dialogue.
func choose(index: int) -> bool:
	if not in_dialogue():
		return false
	if not dialogue.choose(index):
		return false
	for id: String in dialogue.recruited:
		add_companion(id)
	dialogue.recruited.clear()
	if dialogue.finished:
		dialogue_menu.visible = false
		autosave()
	else:
		dialogue_menu.node_changed()
	return true


func leave_dialogue() -> bool:
	if not in_dialogue():
		return false
	var exit := dialogue.exit_choice()
	if exit < 0:
		return false
	return choose(exit)


## Banter for a trigger from every recruited companion (first matching line
## each). Returns the lines shown.
func banter(trigger: String) -> Array[Dictionary]:
	var shown: Array[Dictionary] = []
	for id: String in narrative.recruited:
		var c: Dictionary = registry.get_entry("companions", id)
		var d: Dictionary = c.get("dialogue", {})
		var banter_entry: Dictionary = registry.get_entry("dialogue", String(d.get("banter", "")))
		if banter_entry.is_empty():
			continue
		var line := DialogueRunner.pick_banter(banter_entry, trigger, dialogue_ctx())
		if line.is_empty():
			continue
		overlay.toast("%s: %s" % [c.get("short_name", id), line.get("text", "")], 3.5)
		shown.append(line)
	return shown


## Fresh party (full HP) from the preset and the current protagonist.
func respawn_party() -> void:
	spawn_party(party_id)
	apply_bastion_bonuses()
	if camera != null:
		camera.target = party.leader()


## Installs a created character as the party leader. Returns validation
## errors; on success the party is respawned and the game autosaved.
func set_protagonist(sheet: Dictionary, save: bool = true) -> Array[String]:
	var errors := CharacterSheet.from_dict(sheet).validate(registry, registry.get_entry("rules", "attributes"))
	if not errors.is_empty():
		return errors
	protagonist = sheet.duplicate(true)
	respawn_party()
	if camera != null:
		camera.snap()
	if save:
		autosave()
	overlay.toast("%s leads the party." % sheet.get("name", "The Weaver"), 2.5)
	return errors


## Opens the creator; only at home while exploring.
func open_creator() -> bool:
	if creator_menu == null or mode != "explore" or not at_home():
		return false
	if bastion_menu != null:
		bastion_menu.visible = false
	creator_state = CreatorState.new()
	creator_state.setup(registry, rules, protagonist)
	creator_menu.open(creator_state)
	return true


func close_creator() -> void:
	if creator_menu != null:
		creator_menu.visible = false


## Confirms the creator's sheet as the protagonist. False when invalid.
func confirm_creator() -> bool:
	if creator_state == null or not creator_state.is_valid():
		return false
	var errors := set_protagonist(creator_state.sheet.to_dict())
	if not errors.is_empty():
		return false
	close_creator()
	return true


func spawn_enemies() -> void:
	for e: EnemyActor in enemies:
		if is_instance_valid(e):
			e.queue_free()
	enemies.clear()
	var placements: Array = map_entry.get("enemies", [])
	for p: Dictionary in placements:
		var type: String = String(p.get("type", ""))
		var enemy_entry: Dictionary = registry.get_entry("enemies", type)
		var raw_cell: Array = p.get("cell", [0, 0])
		var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		if enemy_entry.is_empty():
			push_warning("map %s places unknown enemy '%s'" % [map_data.id, type])
			continue
		if not map_data.is_walkable(cell):
			push_warning("map %s places %s on blocked cell %s" % [map_data.id, type, cell])
			continue
		var actor := EnemyActor.new()
		var art: Dictionary = enemy_entry.get("art", {})
		var sheet_id := String(art.get("sheet", ""))
		actor.setup(type, enemy_entry, cell, StatBlock.for_enemy(enemy_entry, rules), rules.awareness_default, sheet_for(sheet_id), biome_recolor(sheet_id))
		actor.position = map_view.cell_to_world(cell)
		enemies_node.add_child(actor)
		enemies.append(actor)


func spawn_pickups() -> void:
	for p: PickupActor in pickups:
		if is_instance_valid(p):
			p.queue_free()
	pickups.clear()
	var placements: Array = map_entry.get("pickups", [])
	for p: Dictionary in placements:
		var type: String = String(p.get("type", ""))
		var entry: Dictionary = registry.get_entry("pickups", type)
		var raw_cell: Array = p.get("cell", [0, 0])
		var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
		if entry.is_empty():
			push_warning("map %s places unknown pickup '%s'" % [map_data.id, type])
			continue
		var actor := PickupActor.new()
		actor.setup(type, entry, cell)
		actor.position = map_view.cell_to_world(cell)
		pickups_node.add_child(actor)
		pickups.append(actor)


## Biome recolour for a sheet id: the biome's `recolors` maps sheet -> palette
## role. Transparent when the biome has no opinion.
func biome_recolor(sheet_id: String) -> Color:
	if sheet_id.is_empty():
		return Color.TRANSPARENT
	var biome: Dictionary = registry.get_entry("biomes", map_data.biome_id)
	var recolors: Dictionary = biome.get("recolors", {})
	if not recolors.has(sheet_id):
		return Color.TRANSPARENT
	var palette: Dictionary = biome.get("palette", {})
	var role := String(recolors[sheet_id])
	if not palette.has(role):
		return Color.TRANSPARENT
	return Color.html(String(palette[role]))


## Neon colour of a class's primary branch (GDD §5: Arcane purple, Tech teal, Body coral).
func class_color(class_id: String) -> Color:
	return PartyBuilder.class_color(registry, class_id)


func living_enemies() -> Array[EnemyActor]:
	var out: Array[EnemyActor] = []
	for e: EnemyActor in enemies:
		if is_instance_valid(e) and not e.dead:
			out.append(e)
	return out


func remaining_pickups() -> Array[PickupActor]:
	var out: Array[PickupActor] = []
	for p: PickupActor in pickups:
		if is_instance_valid(p) and not p.collected:
			out.append(p)
	return out


func enemy_at(cell: Vector2i) -> EnemyActor:
	for e: EnemyActor in living_enemies():
		if e.cell == cell:
			return e
	return null


# --- movement --------------------------------------------------------------

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


# --- the loop: pickups, loot, extraction, wipes ------------------------------

## Collects any pickup a party member is standing on. Returns what was gained.
func check_pickups() -> Array[Dictionary]:
	var gained: Array[Dictionary] = []
	if mode != "explore":
		return gained
	var cells: Array[Vector2i] = []
	for m: PartyMember in party.members:
		cells.append(member_cell(m))
	for p: PickupActor in remaining_pickups():
		if not cells.has(p.cell):
			continue
		p.collected = true
		p.queue_free()
		var site_dialogue := String(p.entry.get("dialogue", ""))
		if not site_dialogue.is_empty():
			open_dialogue(site_dialogue)
			gained.append({"pickup": p.pickup_id, "dialogue": site_dialogue})
			continue
		run.pickups += 1
		var got := _gain(p.grants())
		got["pickup"] = p.pickup_id
		gained.append(got)
		overlay.toast("%s: %s" % [p.entry.get("name", p.pickup_id), RunState.describe(got)], 2.0)
	return gained


## Called by the combat controller when an enemy dies.
func on_enemy_killed(enemy: EnemyActor) -> Dictionary:
	run.kills += 1
	var loot: Dictionary = enemy.entry.get("loot", {}).duplicate()
	loot["xp"] = int(enemy.entry.get("xp", 0))
	return _gain(loot)


## Rolls a grant block into the run haul; banks straight away off-Shard.
func _gain(grants: Dictionary) -> Dictionary:
	var got := run.collect(grants)
	if not run.in_shard:
		_bank(run.take(), false)
		run.clear()
	return got


func _bank(take: Dictionary, count_run: bool) -> void:
	ledger.bank(take)
	ledger.xp += int(take.get("xp", 0))
	ledger.kills += run.kills
	if count_run:
		ledger.runs_completed += 1
	var err := ledger.save()
	if err != OK:
		push_warning("ledger save failed: %s" % error_string(err))


func can_extract() -> bool:
	return mode == "explore" and run.in_shard and leader_cell() == extraction_cell()


## Banks the haul, records the run, and brings the party home.
func extract() -> bool:
	if not can_extract():
		return false
	var take := run.take()
	var kills := run.kills
	_bank(take, true)
	run.clear()
	overlay.toast("Extracted — %s · %d kills" % [RunState.describe(take), kills], 4.0)
	enter_map(HOME_MAP)
	banter("extract")
	autosave()
	return true


func status_line() -> String:
	var exit_note := ""
	var exit_cell := extraction_cell()
	if exit_cell.x >= 0:
		exit_note = "  extraction %s (%d away)" % [exit_cell, LineOfSight.distance(leader_cell(), exit_cell)]
	var line1 := "%s  |  %s  |  leader %s  hover %s%s  |  enemies %d  pickups %d" % [
		map_data.name, mode, leader_cell(), hovered_cell, exit_note, living_enemies().size(), remaining_pickups().size(),
	]
	var line2 := "%s  |  %s" % [run.summary() if run.in_shard else "at home: loot banks on pickup", ledger.summary()]
	for id: String in narrative.recruited:
		var c: Dictionary = registry.get_entry("companions", id)
		line2 += "  |  %s ♥%+d" % [c.get("short_name", id), narrative.approval_of(id)]
	var line3 := "LMB move/attack · WASD steer · wheel zoom · N new shard (depth %d) · H home · F5/F9 save/load · F10 autosave · F1 registry" % bastion.depth()
	if at_home():
		line3 = "LMB move/attack · WASD steer · wheel zoom · B bastion · C creator · N new shard (depth %d) · F5/F9 save/load · F10 autosave · F1 registry" % bastion.depth()
	if can_extract():
		line3 = "▶ ON THE EXTRACTION PAD — press E to extract ◀"
	elif mode == "defeated":
		line3 = "▶ R: return to the yard · Esc: reload the combat checkpoint ◀"
	return "%s\n%s\n%s" % [line1, line2, line3]


# --- encounters ------------------------------------------------------------

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
	# Combat checkpoint (GDD §13): the state just before the fight.
	mode = "explore"
	autosave()
	mode = "combat"
	var seed_value := combat_seed if combat_seed != 0 else int(randi())
	combat.begin(party.members, cells, foes, first_strike, seed_value)


func _on_combat_ended(result: String) -> void:
	if result == "victory":
		# Mortal mode: the dead stay dead. Companions leave the roster with a
		# `<id>_dead` flag their quests can read; a dead leader is a wipe.
		var fallen: Array[PartyMember] = []
		for m: PartyMember in party.members:
			if m.dead or (m.hp <= 0 and not m.downed):
				fallen.append(m)
		for m: PartyMember in fallen:
			if m == party.leader():
				mode = "defeated"
				overlay.toast("%s is dead. The expedition ends here." % m.display_name, 4.0)
				return
			if narrative.is_recruited(m.member_id):
				narrative.dismiss(m.member_id)
				narrative.set_flag("%s_dead" % m.member_id, true)
				overlay.toast("%s is dead." % m.display_name, 4.0)
			party.remove_member(m)
		for m: PartyMember in party.members:
			if m.downed:
				m.downed = false
				m.hp = 1
		party.trail.reset(party.leader().position)
		party.active = true
		mode = "explore"
		banter("victory")
		return
	mode = "defeated"
	if run.in_shard:
		ledger.runs_wiped += 1
		ledger.kills += run.kills
		var lost := run.take()
		run.clear()
		var err := ledger.save()
		if err != OK:
			push_warning("ledger save failed: %s" % error_string(err))
		overlay.toast("Wiped — the haul is lost (%s)" % RunState.describe(lost), 4.0)


# --- input & frame ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		overlay.toggle_registry()
		return
	if event.is_action_pressed("quick_save"):
		save_slot(1)
		return
	if event.is_action_pressed("quick_load"):
		load_slot(1)
		return
	if event.is_action_pressed("load_autosave"):
		load_from(SaveSystem.AUTOSAVE)
		return
	if event is InputEventMouseMotion and hover_override.x >= 0:
		combat.release_cursor() # the mouse moved: it is the pointer again
	var mb := event as InputEventMouseButton
	var clicked := mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if in_dialogue():
		if event.is_action_pressed("cancel"):
			leave_dialogue()
		elif event.is_action_pressed("confirm"):
			confirm_dialogue()
		elif event.is_action_pressed("ui_up"):
			dialogue_menu.move(-1)
		elif event.is_action_pressed("ui_down"):
			dialogue_menu.move(1)
		else:
			for i: int in 4:
				if event.is_action_pressed("ability_%d" % (i + 1)):
					choose(i)
		return
	if system_menu != null and system_menu.visible:
		if event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
			close_system_menu()
		elif event.is_action_pressed("confirm"):
			activate_system_item(system_menu.selected_id())
		elif event.is_action_pressed("ui_up"):
			system_menu.move(-1)
		elif event.is_action_pressed("ui_down"):
			system_menu.move(1)
		return
	if creator_menu != null and creator_menu.visible:
		if event.is_action_pressed("creator") or event.is_action_pressed("ui_cancel"):
			close_creator()
		elif event.is_action_pressed("ui_accept"):
			confirm_creator()
		elif event.is_action_pressed("ui_up"):
			creator_state.move_row(-1)
			creator_menu.refresh()
		elif event.is_action_pressed("ui_down"):
			creator_state.move_row(1)
			creator_menu.refresh()
		elif event.is_action_pressed("ui_left"):
			if creator_state.adjust(-1):
				creator_menu.refresh()
		elif event.is_action_pressed("ui_right"):
			if creator_state.adjust(1):
				creator_menu.refresh()
		return
	if bastion_menu != null and bastion_menu.visible:
		if event.is_action_pressed("bastion") or event.is_action_pressed("cancel"):
			toggle_bastion()
		elif event.is_action_pressed("new_shard"):
			bastion_menu.visible = false
			enter_shard(DEFAULT_SHARD, int(randi() % 1000000))
		elif event.is_action_pressed("confirm"):
			confirm_bastion()
		elif event.is_action_pressed("ui_up"):
			bastion_menu.move(-1)
			bastion_menu.refresh(bastion, ledger)
		elif event.is_action_pressed("ui_down"):
			bastion_menu.move(1)
			bastion_menu.refresh(bastion, ledger)
		else:
			for i: int in mini(bastion.order.size(), 4):
				if event.is_action_pressed("ability_%d" % (i + 1)):
					upgrade_building(bastion.order[i])
		return
	match mode:
		"explore":
			if event.is_action_pressed("menu"):
				open_system_menu()
			elif event.is_action_pressed("bastion"):
				toggle_bastion()
			elif event.is_action_pressed("creator"):
				open_creator()
			elif event.is_action_pressed("confirm"):
				interact()
			elif clicked:
				var cell := map_view.world_to_cell(get_global_mouse_position())
				var enemy := enemy_at(cell)
				var npc := npc_at(cell)
				if npc != null and LineOfSight.distance(leader_cell(), cell) <= 2:
					talk_to(npc.companion_id)
				elif enemy != null and LineOfSight.distance(leader_cell(), cell) <= enemy.awareness:
					start_combat(true)
				else:
					command_move(cell)
			elif event.is_action_pressed("extract"):
				extract()
			elif event.is_action_pressed("new_shard"):
				enter_shard(DEFAULT_SHARD, int(randi() % 1000000))
			elif event.is_action_pressed("go_home"):
				enter_map(HOME_MAP)
		"combat":
			if clicked:
				combat.player_click(map_view.world_to_cell(get_global_mouse_position()))
			elif event.is_action_pressed("end_turn"):
				combat.end_player_turn()
			elif event.is_action_pressed("next_member"):
				combat.next_member()
			elif event.is_action_pressed("confirm"):
				combat.confirm()
			elif event.is_action_pressed("cancel"):
				combat.cancel_selection()
			else:
				for i: int in 4:
					if event.is_action_pressed("ability_%d" % (i + 1)):
						combat.select_ability(i)
		"defeated":
			if event.is_action_pressed("restart") or event.is_action_pressed("confirm"):
				return_home()
			elif event.is_action_pressed("cancel"):
				load_from(SaveSystem.AUTOSAVE)


func _process(delta: float) -> void:
	if mode == "explore" and not in_dialogue():
		var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if dir != Vector2.ZERO:
			party.steer_leader(dir, delta, map_view.is_walkable_world)
		check_pickups()
		check_encounters()
	elif mode == "combat":
		_tick_cursor(Input.get_vector("move_left", "move_right", "move_up", "move_down"), delta)
	hovered_cell = hover_override if hover_override.x >= 0 else map_view.world_to_cell(get_global_mouse_position())
	if mode == "combat":
		combat.hover(hovered_cell)
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
	var combat_shot := OS.get_cmdline_user_args().has("--screenshot-combat")
	if _frames == 2 and combat_shot:
		# Staged: everyone rolls 1 and the party strikes first, so the whole
		# party is one turn group and the swap hint is in the shot.
		combat.animate = false
		combat_seed = 1234
		rules.initiative_die = 1
		teleport_party(Vector2i(13, 4))
		start_combat(true)
		camera.snap() # deterministic framing regardless of frame timing
	if _frames == 4 and combat_shot and mode == "combat" and combat.current_is_player():
		var foe := EnemyBrain.nearest_hostile(combat.state, combat.state.current())
		if foe != null:
			hover_override = foe.cell # the attack preview instead of wherever the mouse is
	if _frames < 12:
		return
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_screenshot_path)
	print("screenshot %s -> %s" % [_screenshot_path, error_string(err)])
	_screenshot_path = ""
	get_tree().quit(0 if err == OK else 1)


# --- gamepad paths: system menu, interact, menu cursors, combat cursor -------

const SYSTEM_ITEM_IDS: Array[String] = ["resume", "extract", "new_shard", "go_home", "bastion", "creator", "save_1", "save_2", "save_3", "load_1", "load_2", "load_3", "load_autosave", "registry"]
const CURSOR_FIRST_REPEAT := 0.28
const CURSOR_REPEAT := 0.11

var _cursor_hold := 0.0


## Every keyboard-only action as a menu item, enabled where the key would work.
func system_items() -> Array[Dictionary]:
	var home := at_home()
	var items: Array[Dictionary] = []
	items.append({"id": "resume", "label": "Resume", "enabled": true})
	items.append({"id": "extract", "label": "Extract (bank the haul)", "enabled": can_extract(), "why": "not on the extraction pad"})
	items.append({"id": "new_shard", "label": "Launch a new Shard (depth %d)" % bastion.depth(), "enabled": true})
	items.append({"id": "go_home", "label": "Return to the yard (haul is lost)", "enabled": not home, "why": "already home"})
	items.append({"id": "bastion", "label": "The Bastion", "enabled": home, "why": "only at home"})
	items.append({"id": "creator", "label": "Character creator", "enabled": home, "why": "only at home"})
	var saves := SaveSystem.list_saves(saves_dir)
	for n: int in SaveSystem.SLOTS:
		var slot: Dictionary = saves[n]
		items.append({"id": "save_%d" % (n + 1), "label": "Save slot %d — %s" % [n + 1, slot["summary"]], "enabled": mode != "combat", "why": "in combat"})
	for n: int in SaveSystem.SLOTS:
		var slot: Dictionary = saves[n]
		items.append({"id": "load_%d" % (n + 1), "label": "Load slot %d — %s" % [n + 1, slot["summary"]], "enabled": bool(slot["exists"]), "why": "empty"})
	var auto: Dictionary = saves[SaveSystem.SLOTS]
	items.append({"id": "load_autosave", "label": "Load the autosave — %s" % auto["summary"], "enabled": bool(auto["exists"]), "why": "no autosave yet"})
	items.append({"id": "registry", "label": "Content registry dump (debug)", "enabled": true})
	return items


## Start / Esc while exploring. Refused in combat, dialogue and other menus.
func open_system_menu() -> bool:
	if system_menu == null or mode != "explore" or in_dialogue():
		return false
	if (creator_menu != null and creator_menu.visible) or (bastion_menu != null and bastion_menu.visible):
		return false
	system_menu.open(system_items())
	return true


func close_system_menu() -> void:
	if system_menu != null:
		system_menu.close()


## Runs a system menu item by id; the menu closes first. False when the
## id is unknown or the item is disabled right now.
func activate_system_item(id: String) -> bool:
	if system_menu == null:
		return false
	for item: Dictionary in system_items():
		if String(item["id"]) == id and not bool(item.get("enabled", true)):
			overlay.toast("%s: %s" % [item["label"], item.get("why", "unavailable")], 1.5)
			return false
	system_menu.close()
	match id:
		"resume":
			return true
		"extract":
			return extract()
		"new_shard":
			return not enter_shard(DEFAULT_SHARD, int(randi() % 1000000)).is_empty()
		"go_home":
			return enter_map(HOME_MAP)
		"bastion":
			return toggle_bastion()
		"creator":
			return open_creator()
		"save_1", "save_2", "save_3":
			return save_slot(int(id.get_slice("_", 1))) == OK
		"load_1", "load_2", "load_3":
			return load_slot(int(id.get_slice("_", 1))).is_empty()
		"load_autosave":
			return load_from(SaveSystem.AUTOSAVE).is_empty()
		"registry":
			overlay.toggle_registry()
			return true
	return false


## Confirm (Enter / A) while exploring: extract on the pad, otherwise talk
## to a companion within two cells. False when there is nothing to do.
func interact() -> bool:
	if mode != "explore" or in_dialogue():
		return false
	if can_extract():
		return extract()
	var here := leader_cell()
	var best: NpcActor = null
	for npc: NpcActor in npcs:
		if not is_instance_valid(npc) or not npc.visible:
			continue
		var d := LineOfSight.distance(here, npc.cell)
		if d <= 2 and (best == null or d < LineOfSight.distance(here, best.cell)):
			best = npc
	if best != null:
		return talk_to(best.companion_id)
	overlay.toast("Nothing to interact with here", 1.2)
	return false


func confirm_dialogue() -> bool:
	if not in_dialogue():
		return false
	return choose(dialogue_menu.cursor)


func confirm_bastion() -> bool:
	if bastion_menu == null or not bastion_menu.visible:
		return false
	if bastion_menu.cursor < 0 or bastion_menu.cursor >= bastion.order.size():
		return false
	return upgrade_building(bastion.order[bastion_menu.cursor])


## Held stick / D-pad / WASD steps the combat cursor with key-repeat pacing.
func _tick_cursor(dir: Vector2, delta: float) -> void:
	if dir == Vector2.ZERO:
		_cursor_hold = 0.0
		return
	if _cursor_hold <= 0.0:
		combat.move_cursor(dir)
		_cursor_hold = CURSOR_FIRST_REPEAT if _cursor_hold == 0.0 else CURSOR_REPEAT
	else:
		_cursor_hold -= delta
		if _cursor_hold <= 0.0:
			combat.move_cursor(dir)
			_cursor_hold = CURSOR_REPEAT
