## Exploration scene root: loads a map (handcrafted or generated Shard), a
## party preset, enemies and pickups from the content registry, routes
## input, runs the extraction loop, and hands off to the
## [CombatController] when an encounter starts.
##
## Modes: "explore" (real-time), "combat" (turn-based), "defeated".
class_name ExploreWorld
extends Node2D

const HOME_MAP := "bastion"
const DEFAULT_SHARD := "rusted_undercity"

## The Shard template N launches: the last one chosen in the system menu.
var selected_shard: String = DEFAULT_SHARD

@export var map_id: String = HOME_MAP
## Where H, wipes and extraction return to. Tests pin it to the yard.
@export var home_map: String = HOME_MAP
## The demo party is the protagonist alone; companions fill the other three
## slots as they are recruited. Tests pin the three-member prototype party.
@export var party_id: String = "demo"
## 0 = random per encounter. Tests pin it.
@export var combat_seed: int = 0
## Where the Bastion ledger persists. Tests point this at a scratch file.
@export var ledger_path: String = "user://ledger.json"
## Save slots and the autosave live here. Tests point this at a scratch dir.
@export var saves_dir: String = "user://saves"
## Account-level unlocks across playthroughs (S35): outside every save.
@export var account_path: String = Account.DEFAULT_PATH
## Where the settings and the bindings live; tests point these at their own files (S55).
@export var settings_path: String = Settings.PATH
@export var input_path: String = InputActions.OVERRIDES_PATH

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
var weave_menu: WeaveMenu
var inventory_menu: InventoryMenu
var archive_menu: ArchiveMenu
var ending_menu: EndingMenu
## A scripted sequence is running: input is off, the party stands still (S36).
var sequence_running: bool = false
## Skip sequence pauses (tests and staging).
var instant_sequences: bool = false
var last_sequence: Array = []
var sequence_focus: Node2D
var account: Account
var merchant_menu: MerchantMenu
var current_merchant: String = ""
var journal_menu: JournalMenu
var roster_menu: RosterMenu
var saves_menu: SavesMenu
var color_filter: ColorFilter
var screen_fx: ScreenFx
var _saves_return_to_title: bool = false
var demo_end_menu: DemoEndMenu
var title_menu: TitleMenu
var settings_menu: SettingsMenu
var settings: Settings = Settings.new()
var audio: AudioDirector
var _last_step_cell := Vector2i(-1, -1)
var _settings_return_to_title: bool = false
## Cold starts show the title; tests (Engine meta) and CLI staging skip it.
@export var show_title_on_start: bool = true
## Set by a trigger's `victory_flag`: raised when the fight it started is won.
var pending_victory_flag: String = ""
var pending_victory_flags: Array[String] = [] # every flag a victory sets (S41: one or many)
## `-- --demo` turns the demo boundary on regardless of `rules/demo.enabled` (S39).
var demo_forced: bool = false
## The playtest log when launched with `-- --playtest` (S47, D-102); null otherwise.
var playtest: PlaytestLog = null
var _world_effects_seen: int = 0 # dialogue effect blocks already applied to the world
var _talk_log_start: int = 0 # where this talk's lines begin in the history (S52)
var _portraits: Dictionary = {} # speaker id -> ImageTexture, built once per world (S52)
var perf_hud: bool = false # `--perf`: fps and frame time on the status line (S53)
## A once-trigger that started a fight is spent only when that fight is won,
## so a wipe lets the player come back and try the boss again.
var pending_trigger_flag: String = ""
## The difficulty picked on the title screen, carried to the death-stakes page (S50).
var pending_difficulty: String = ""
## The new game waiting on the creator (S51): {"mortal", "iron", "difficulty"} while the creator is its first screen.
var pending_new_game: Dictionary = {}
## Bastion buildings standing on the home map (`buildings` sites).
var buildings: Array[BuildingActor] = []
## Set by travel(): where the party arrives on the next map instead of its spawns.
var _arrive_cell := Vector2i(-1, -1)
var dialogue: DialogueRunner
var enemies: Array[EnemyActor] = []
var pickups: Array[PickupActor] = []
## Party-side summoned actors alive in the current fight (D-086).
var summons: Array[EnemyActor] = []
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
	platform().pull_missing(saves_dir) # cloud saves this machine has not seen yet
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
	weave_menu = WeaveMenu.new()
	weave_menu.name = "WeaveMenu"
	add_child(weave_menu)
	inventory_menu = InventoryMenu.new()
	inventory_menu.name = "InventoryMenu"
	add_child(inventory_menu)
	archive_menu = ArchiveMenu.new()
	archive_menu.name = "ArchiveMenu"
	add_child(archive_menu)
	ending_menu = EndingMenu.new()
	ending_menu.name = "EndingMenu"
	add_child(ending_menu)
	sequence_focus = Node2D.new()
	sequence_focus.name = "SequenceFocus"
	add_child(sequence_focus)
	instant_sequences = Engine.has_meta("neon_weave_tests")
	account = Account.load_or_new(account_path)
	merchant_menu = MerchantMenu.new()
	merchant_menu.name = "MerchantMenu"
	add_child(merchant_menu)
	roster_menu = RosterMenu.new()
	roster_menu.name = "RosterMenu"
	add_child(roster_menu)
	saves_menu = SavesMenu.new()
	saves_menu.name = "SavesMenu"
	add_child(saves_menu)
	screen_fx = ScreenFx.new()
	screen_fx.name = "ScreenFx"
	add_child(screen_fx)
	color_filter = ColorFilter.new()
	color_filter.name = "ColorFilter"
	add_child(color_filter)
	journal_menu = JournalMenu.new()
	journal_menu.name = "JournalMenu"
	add_child(journal_menu)
	demo_end_menu = DemoEndMenu.new()
	demo_end_menu.name = "DemoEndMenu"
	add_child(demo_end_menu)
	title_menu = TitleMenu.new()
	title_menu.name = "TitleMenu"
	add_child(title_menu)
	settings_menu = SettingsMenu.new()
	settings_menu.name = "SettingsMenu"
	add_child(settings_menu)
	Loc.load_from(registry)
	settings = Settings.load_or_default(settings_path)
	settings.apply()
	UiScale.apply(self, [overlay])
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--fx="): # a screenshot's screen effects (S56)
			settings.screen_fx = arg.get_slice("=", 1)
		elif arg == "--no-lighting":
			settings.lighting = false
	settings.apply()
	apply_visual_settings()
	InputActions.load_overrides()
	audio = AudioDirector.new()
	audio.name = "Audio"
	add_child(audio)
	audio.setup(registry)
	spawn_npcs()
	spawn_buildings()
	auto_start_quests()
	restore_map_doors()
	restore_map_edits()
	combat = CombatController.new()
	combat.name = "Combat"
	add_child(combat)
	combat.setup(self, hud, highlighter)
	combat.ended.connect(_on_combat_ended)
	camera.target = party.leader()
	camera.snap()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--biome="):
			selected_shard = arg.get_slice("=", 1) # before --shard= on the command line
		elif arg.begins_with("--map="):
			enter_map(arg.get_slice("=", 1)) # a handcrafted map to stage the other flags on
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_screenshot_path = arg.get_slice("=", 1)
		if arg == "--demo":
			demo_forced = true # the Steam demo build: the boundary panel shows even when rules/demo is off
		elif arg == "--playtest": # the playtest log (S47): one JSON line per event under user://playtest
			playtest = PlaytestLog.new()
			playtest.start()
		elif arg == "--journal":
			open_journal()
		elif arg == "--perf": # fps and frame time on the status line, for a Deck in hand (S53)
			perf_hud = true
		elif arg.begins_with("--play="): # audition an audio entry in place (S57)
			if audio != null:
				var id := arg.get_slice("=", 1)
				if not audio.play(id):
					push_warning("--play: no audio entry '%s'" % id)
				else:
					print("--play %s: %s" % [id, String(audio.sources.get(id, "?"))])
		elif arg.begins_with("--shard="):
			enter_shard(selected_shard, int(arg.get_slice("=", 1)))
		elif arg == "--creator":
			open_creator()
		elif arg.begins_with("--talk="):
			talk_to(arg.get_slice("=", 1))
		elif arg == "--weave":
			ledger.path = "user://screenshot_ledger.json" # never touch the real books
			ledger.xp = 40 # level 3 so the subclass rows are live in the shot
			ledger.bank({"aether": 4})
			refresh_progression()
			open_weave()
	apply_death_stakes()
	var staged := not OS.get_cmdline_user_args().is_empty() and not OS.get_cmdline_user_args().has("--title")
	if show_title_on_start and not Engine.has_meta("neon_weave_tests") and not staged:
		show_title()
	refresh_music()


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
	map_view.build(map_data, registry.get_entry("biomes", map_data.biome_id), rules_entry("lighting"))


## Generates a Shard from a `shards` template and moves the party into it.
## `depth` 0 means the Beacon's current depth; loads pass the saved depth.
## Returns the generated map entry ({} when the template is unknown).
func enter_shard(template_id: String, seed_value: int, depth: int = 0, extras: Array[String] = []) -> Dictionary:
	var template: Dictionary = ShardGenerator.expand_remix(registry.get_entry("shards", template_id), registry)
	if template.is_empty():
		push_warning("unknown shard template %s" % template_id)
		return {}
	var sites := extras if not extras.is_empty() else quest_sites(template_id)
	var entry := ShardGenerator.generate(template, seed_value, depth if depth > 0 else bastion.depth(), sites)
	for err: String in ShardValidator.validate(entry, tiles_by_id()):
		push_warning("shard %s: %s" % [entry.get("id"), err])
	if _enter(entry):
		run.begin(String(entry["id"]), seed_value)
		if playtest != null:
			playtest.map(self)
		autosave()
		banter("enter_shard")
	return entry


## Pickup ids of quest sites that should appear in the next Shard: every
## quest whose current stage declares `shard_site`.
## Story sites for the Shard about to be generated: every started quest's
## current stage `shard_site`, skipping sites bound to another template
## (`shard_site.template`, S41: a Key delve belongs to its biome). An empty
## `template_id` lists them all.
func quest_sites(template_id: String = "") -> Array[String]:
	var out: Array[String] = []
	for quest_id: String in narrative.quests:
		var quest: Dictionary = registry.get_entry("quests", quest_id)
		var stages: Dictionary = quest.get("stages", {})
		var stage: Dictionary = stages.get(narrative.stage_of(quest_id), {})
		var site: Dictionary = stage.get("shard_site", {})
		var pickup := String(site.get("pickup", ""))
		var bound := String(site.get("template", ""))
		if not template_id.is_empty() and not bound.is_empty() and bound != template_id:
			continue
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
	var previous := map_id
	map_id = id # before _enter: door and trigger flags are keyed by map id
	if _enter(entry):
		run.begin("", 0)
		if playtest != null:
			playtest.map(self)
		if id == home_map:
			heal_party(bastion.heal_fraction())
	else:
		map_id = previous
	return true


func _enter(entry: Dictionary) -> bool:
	if mode == "combat":
		return false
	clear_summons()
	load_map_entry(entry)
	if party.members.is_empty():
		spawn_party(party_id)
		apply_bastion_bonuses()
	elif _arrive_cell.x >= 0 and map_data.is_walkable(_arrive_cell):
		var taken: Array[Vector2i] = []
		place_party(map_data.nearest_free_cells(_arrive_cell, party.members.size(), taken))
	else:
		place_party(map_data.spawn_cells())
	spawn_enemies()
	spawn_pickups()
	spawn_npcs()
	spawn_buildings()
	mode = "explore"
	restore_map_doors()
	restore_map_edits()
	_last_step_cell = Vector2i(-1, -1)
	if audio != null:
		refresh_music()
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
	if weave_menu != null:
		weave_menu.visible = false
	if inventory_menu != null:
		inventory_menu.visible = false
	if archive_menu != null:
		archive_menu.visible = false
	if ending_menu != null:
		ending_menu.visible = false
	close_merchant()
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
	enter_map(home_map)
	autosave()


# --- saves -----------------------------------------------------------------

func save_path(save_name: String) -> String:
	return SaveSystem.path_for(saves_dir, save_name)


## Save anywhere out of combat. ERR_UNAVAILABLE during a fight.
func save_to(save_name: String) -> Error:
	if mode == "combat":
		return ERR_UNAVAILABLE
	var err := SaveSystem.write(save_path(save_name), SaveSystem.capture(self))
	if err == OK:
		SaveSystem.write_thumbnail(self, save_path(save_name)) # the frame beside the file (S54)
		platform().push_save(save_path(save_name)) # cloud copy, when the platform has one
	return err


func save_slot(n: int) -> Error:
	if is_iron_weave():
		if overlay != null:
			overlay.toast(Loc.t("Iron Weave: one save. The autosave is the save."), 2.5)
		return ERR_UNAVAILABLE
	var err := save_to(SaveSystem.slot_name(n))
	if overlay != null:
		overlay.toast(Loc.t("Saved to slot %d") % n if err == OK else Loc.t("Save failed: %s") % (Loc.t("in combat") if err == ERR_UNAVAILABLE else error_string(err)), 2.0)
	return err


func autosave() -> Error:
	if loading:
		return OK
	advance_quests() # the save carries any stage the last beat completed
	grant_account_unlocks()
	if not is_iron_weave(): # one save means one; otherwise the last few autosaves stay (S54)
		SaveSystem.rotate_autosaves(saves_dir)
	var err := save_to(SaveSystem.AUTOSAVE)
	if err == OK:
		check_achievements() # every story beat autosaves, so this is where they land
	return err


## Loads a save by name. Returns the restore errors ("" entries never); an
## unreadable file yields a single error.
func load_from(save_name: String) -> Array[String]:
	var data := SaveSystem.read(save_path(save_name))
	if data.has("_error"):
		var one: Array[String] = [String(data["_error"])]
		if overlay != null:
			overlay.toast(Loc.t("Load failed: %s") % one[0], 2.5)
		return one
	var why := SaveSystem.content_check(SaveSystem.migrate(data), registry)
	if not why.is_empty():
		var refused: Array[String] = [why]
		if overlay != null:
			overlay.toast(Loc.t("Load refused: %s") % why, 4.0)
		push_warning("load %s refused: %s" % [save_name, why])
		return refused
	var errors := SaveSystem.restore(self, data)
	if overlay != null:
		overlay.toast(Loc.t("Loaded %s") % save_name if errors.is_empty() else Loc.t("Loaded %s with %d problem(s)") % [save_name, errors.size()], 2.5)
	for e: String in errors:
		push_warning("load %s: %s" % [save_name, e])
	return errors


func load_slot(n: int) -> Array[String]:
	if is_iron_weave():
		if overlay != null:
			overlay.toast(Loc.t("Iron Weave: no reloads."), 2.5)
		return ["Iron Weave: no reloads"]
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
		overlay.toast(Loc.t("%s: %s") % [bastion.name_of(id), why], 2.0)
		return false
	if not bastion.upgrade(id, ledger):
		return false
	ledger.buildings = bastion.to_dict()
	var err := ledger.save()
	if err != OK:
		push_warning("ledger save failed: %s" % error_string(err))
	apply_bastion_bonuses()
	narrative.set_flag("building_%s_l%d" % [id, bastion.level(id)], true) # quests read these
	overlay.toast(Loc.t("%s upgraded to L%d — %s") % [bastion.name_of(id), bastion.level(id), bastion.blurb(id)], 3.0)
	refresh_buildings()
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
	var specs := PartyBuilder.member_specs(registry, preset, protagonist, rules, positions, narrative.active_companions(), party_level(), ledger.builds)
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
		var raw: Array = p.get("cell", [0, 0])
		var cell := Vector2i(int(raw[0]), int(raw[1]))
		if p.has("npc"):
			var npc_id := String(p["npc"])
			var story: Dictionary = registry.get_entry("npcs", npc_id)
			if story.is_empty() or not map_data.is_walkable(cell):
				push_warning("map %s places unknown or blocked npc %s at %s" % [map_data.id, npc_id, cell])
				continue
			if not Conditions.passes(p.get("when", {}), dialogue_ctx()):
				continue
			var figure := NpcActor.new()
			figure.setup_npc(npc_id, story, cell, Color.html(String(Dictionary(story.get("art", {})).get("color", "#d8c46a"))))
			figure.position = map_view.cell_to_world(cell)
			npcs_node.add_child(figure)
			npcs.append(figure)
			continue
		if p.has("merchant"):
			var merchant_id := String(p["merchant"])
			var merchant: Dictionary = registry.get_entry("merchants", merchant_id)
			if merchant.is_empty() or not map_data.is_walkable(cell):
				push_warning("map %s places unknown or blocked merchant %s at %s" % [map_data.id, merchant_id, cell])
				continue
			var trader := NpcActor.new()
			trader.setup_merchant(merchant_id, merchant, cell, Color.html(String(Dictionary(merchant.get("art", {})).get("color", "#d8c46a"))))
			trader.position = map_view.cell_to_world(cell)
			npcs_node.add_child(trader)
			npcs.append(trader)
			continue
		var id := String(p.get("companion", ""))
		var entry: Dictionary = registry.get_entry("companions", id)
		if entry.is_empty() or narrative.is_recruited(id) or narrative.flag("%s_dead" % id):
			continue
		if not Conditions.passes(p.get("when", {}), dialogue_ctx()): # a companion can wait on a story beat (S38)
			continue
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
		# Six companions, a party of four (D-093): the newcomer waits at the Bastion.
		narrative.bench(id)
		_remove_stand_in(id)
		var c: Dictionary = registry.get_entry("companions", id)
		overlay.toast(Loc.t("The party is full. %s will wait at the Bastion; swap from the Roster at home.") % c.get("short_name", id), 3.5)
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
	_remove_stand_in(id)
	return true


func _remove_stand_in(id: String) -> void:
	for n: NpcActor in npcs:
		if is_instance_valid(n) and n.companion_id == id:
			n.queue_free()
	var kept: Array[NpcActor] = []
	for n: NpcActor in npcs:
		if is_instance_valid(n) and n.companion_id != id:
			kept.append(n)
	npcs = kept


# --- dialogue ----------------------------------------------------------------

## Evaluation context for conditions: narrative + the leader's origin tag,
## race and class.
func dialogue_ctx() -> Dictionary:
	var l := party.leader()
	var origin_tag := ""
	if l != null and not l.origin_id.is_empty():
		origin_tag = String(registry.get_entry("origins", l.origin_id).get("dialogue_tag", ""))
	var tags: Array = Dictionary(registry.get_entry("races", l.race_id).get("traits", {})).get("tags", []) if l != null else []
	# The walking party's races and tags (S44): NPCs react to a Hollow behind you.
	var party_races: Array[String] = []
	var party_tags: Array[String] = []
	for m: PartyMember in party.members:
		if not party_races.has(m.race_id):
			party_races.append(m.race_id)
		for t: Variant in Dictionary(registry.get_entry("races", m.race_id).get("traits", {})).get("tags", []):
			if not party_tags.has(String(t)):
				party_tags.append(String(t))
	var attributes: Dictionary = protagonist.get("attributes", {})
	# A disguise holds when the leader's race can reshape and their arcane control clears the bar (rules/attributes).
	var disguise_min := int(registry.get_entry("rules", "attributes").get("disguise_arcane_min", 2))
	var disguised := Array(tags).has("disguise") and int(attributes.get("arcane", 0)) >= disguise_min
	return {"narrative": narrative, "origin_tag": origin_tag, "race": l.race_id if l != null else "", "race_tags": tags, "class": l.class_id if l != null else "", "party_races": party_races, "party_race_tags": party_tags, "attributes": attributes, "disguised": disguised}


func speaker_names() -> Dictionary:
	var names: Dictionary = {"narrator": "—", "player": party.leader().display_name if party.leader() != null else "You"}
	for c: Dictionary in registry.get_all("companions"):
		names[c["id"]] = Loc.text(c, "short_name", String(c.get("name", c["id"])))
	for n: Dictionary in registry.get_all("npcs"):
		names[n["id"]] = Loc.text(n, "short_name", String(n.get("name", n["id"])))
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
	_world_effects_seen = 0
	party.stop()
	if roster_menu != null:
		roster_menu.close()
	_talk_log_start = narrative.log.size()
	log_node()
	dialogue_menu.open(runner, speaker_names(), Callable(self, "face_for"), Callable(self, "talk_history"))
	return true


func in_dialogue() -> bool:
	return dialogue != null and not dialogue.finished


## Talks to a companion by id (their recruit or talk dialogue).
func talk_to(companion_id: String) -> bool:
	var entry: Dictionary = registry.get_entry("companions", companion_id)
	if entry.is_empty():
		var story: Dictionary = registry.get_entry("npcs", companion_id)
		if story.is_empty():
			return false
		return open_dialogue(String(story.get("dialogue", "")))
	var d: Dictionary = entry.get("dialogue", {})
	var id := String(d.get("talk" if narrative.is_recruited(companion_id) else "recruit", ""))
	return open_dialogue(id)


## Picks the n-th available choice of the open dialogue.
func choose(index: int) -> bool:
	if not in_dialogue():
		return false
	if playtest != null:
		var options := dialogue.available_choices()
		if index >= 0 and index < options.size():
			playtest.choice(String(dialogue.dialogue.get("id", "")), dialogue.node_id, String(Dictionary(options[index]).get("text", "")))
	var picked := ""
	var choices := dialogue.available_choices()
	if index >= 0 and index < choices.size():
		picked = String(Dictionary(choices[index]).get("text", ""))
	if not dialogue.choose(index):
		return false
	narrative.log_line(party.leader().display_name if party.leader() != null else "You", "→ " + picked)
	var last: Dictionary = dialogue.applied[dialogue.applied.size() - 1] if not dialogue.applied.is_empty() else {}
	var applied_count := dialogue.applied.size()
	var finished := dialogue.finished
	for id: String in dialogue.recruited:
		add_companion(id)
	dialogue.recruited.clear()
	if finished:
		dialogue_menu.visible = false
	else:
		log_node()
		dialogue_menu.node_changed()
	if applied_count > _world_effects_seen:
		_world_effects_seen = applied_count
		_apply_world_effects(last) # the runner did the story part; the world part can start a fight, a sequence, or a transition that closes this dialogue (S39, S42)
	if finished:
		autosave()
		if mode == "explore" and not in_dialogue():
			spawn_npcs() # placements that wait on a flag the talk just set (S39)
		check_demo_end()
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
	for id: String in narrative.active_companions():
		var c: Dictionary = registry.get_entry("companions", id)
		var d: Dictionary = c.get("dialogue", {})
		var banter_entry: Dictionary = registry.get_entry("dialogue", String(d.get("banter", "")))
		if banter_entry.is_empty():
			continue
		var line := DialogueRunner.pick_banter(banter_entry, trigger, dialogue_ctx())
		if line.is_empty():
			continue
		overlay.toast(Loc.t("%s: %s") % [Loc.text(c, "short_name", id), Loc.any(String(line.get("text", "")))], 3.5)
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
	overlay.toast(Loc.t("%s leads the party.") % sheet.get("name", "The Weaver"), 2.5)
	return errors


## The creator as the first screen of a new game (S51): the title closes,
## the sheet starts fresh, and confirming starts the game with it; Esc
## returns to the death-stakes page with nothing begun.
func open_new_game_creator(mortal: bool, iron: bool) -> bool:
	if creator_menu == null:
		return new_game(mortal, pending_difficulty, iron)
	if title_menu != null:
		title_menu.close()
	pending_new_game = {"mortal": mortal, "iron": iron, "difficulty": pending_difficulty}
	creator_state = CreatorState.new()
	creator_state.setup(registry, rules, {}, account.unlocked if account != null else [])
	creator_state.for_new_game = true
	creator_menu.open(creator_state)
	return true


## Opens the creator; only at home while exploring.
func open_creator() -> bool:
	if creator_menu == null or mode != "explore" or not at_home():
		return false
	if bastion_menu != null:
		bastion_menu.visible = false
	creator_state = CreatorState.new()
	creator_state.setup(registry, rules, protagonist, account.unlocked if account != null else [])
	creator_menu.open(creator_state)
	return true


func close_creator() -> void:
	if creator_menu != null:
		creator_menu.visible = false
	if not pending_new_game.is_empty(): # backing out of a new game: nothing has begun
		pending_new_game = {}
		if title_menu != null:
			title_menu.show_rows(TitleMenu.PAGE_STAKES, stakes_rows())


## Confirms the creator's sheet as the protagonist. False when invalid.
## As the first screen of a new game, this is where the game begins.
func confirm_creator() -> bool:
	if creator_state == null or not creator_state.is_valid():
		return false
	if not pending_new_game.is_empty():
		var pending := pending_new_game
		pending_new_game = {}
		close_creator()
		return new_game(bool(pending["mortal"]), String(pending["difficulty"]), bool(pending["iron"]), creator_state.sheet.to_dict())
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
		enemies.append(_make_enemy(type, enemy_entry, cell, String(p.get("tier", ""))))


## Builds and places one enemy actor, scaled for this map's depth and the
## placement's tier (elite/boss) or the entry's own.
func _make_enemy(type: String, enemy_entry: Dictionary, cell: Vector2i, tier: String = "") -> EnemyActor:
	var actor := EnemyActor.new()
	var art: Dictionary = enemy_entry.get("art", {})
	var sheet_id := String(art.get("sheet", ""))
	actor.setup(type, enemy_entry, cell, StatBlock.for_enemy(enemy_entry, rules, map_depth(), tier), rules.awareness_default, sheet_for(sheet_id), biome_recolor(sheet_id))
	actor.position = map_view.cell_to_world(cell)
	enemies_node.add_child(actor)
	return actor


## Shard depth of the current map (handcrafted maps are depth 1).
func map_depth() -> int:
	var generation: Dictionary = map_entry.get("generation", {})
	return maxi(int(generation.get("depth", 1)), 1)


func enemies_by_id() -> Dictionary:
	var out: Dictionary = {}
	for e: Dictionary in registry.get_all("enemies"):
		out[e["id"]] = e
	return out


## A minion called in mid-fight by a summoner: placed, tracked with the
## other enemies (loot and XP on death), never part of the map entry.
func spawn_summoned(kind: String, cell: Vector2i, team: String = Combatant.TEAM_ENEMY) -> EnemyActor:
	var enemy_entry: Dictionary = registry.get_entry("enemies", kind)
	if enemy_entry.is_empty() or not map_data.is_walkable(cell):
		return null
	var actor := _make_enemy(kind, enemy_entry, cell)
	if team == Combatant.TEAM_PARTY:
		summons.append(actor) # a drone or turret: ours for the fight, never loot, gone after
	else:
		enemies.append(actor)
	return actor


## Frees the party side summons (they last one fight).
func clear_summons() -> void:
	for s: EnemyActor in summons:
		if is_instance_valid(s):
			s.queue_free()
	summons.clear()


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
		var rarity := String(p.get("rarity", "common"))
		if rarity != "common":
			actor.set_rarity(rarity, rarity_color(rarity))
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
			break # one site at a time: anything else underfoot waits for the next check (S38)
		run.pickups += 1
		play_event("explore.pickup")
		var grants := p.grants().duplicate()
		var heal := float(grants.get("heal", 0.0)) # a medkit (S48): heals the party by a fraction of max HP, never a haul
		grants.erase("heal")
		if heal > 0.0:
			heal_party(heal)
		var got := _gain(scale_grants(grants, rarity_multiplier(p.rarity)))
		if heal > 0.0:
			got["heal"] = heal
		if p.grants().has("item"):
			var inst := drop_item(p.rarity)
			if not inst.is_empty():
				got["item"] = inst
		if p.grants().has("lore"):
			var fragment := find_lore()
			if not fragment.is_empty():
				got["lore"] = fragment
		got["pickup"] = p.pickup_id
		got["rarity"] = p.rarity
		gained.append(got)
		var tag := "" if p.rarity == "common" else Loc.t(" (%s)") % p.rarity
		overlay.toast(Loc.t("%s%s: %s") % [p.entry.get("name", p.pickup_id), tag, RunState.describe(got)], 2.0)
	return gained


## Called by the combat controller when an enemy dies.
func on_enemy_killed(enemy: EnemyActor) -> Dictionary:
	run.kills += 1
	var loot: Dictionary = enemy.entry.get("loot", {}).duplicate()
	loot["xp"] = int(enemy.entry.get("xp", 0))
	var got := _gain(loot)
	var inst := roll_enemy_drop(enemy)
	if not inst.is_empty():
		got["item"] = inst
		overlay.toast(Loc.t("%s dropped %s") % [enemy.display_name, ItemSystem.display_name(registry, inst)], 2.5)
	return got


## Rolls a grant block into the run haul; banks straight away off-Shard.
func _gain(grants: Dictionary) -> Dictionary:
	var got := run.collect(grants)
	if not run.in_shard:
		_bank(run.take(), false)
		run.clear()
	return got


func _bank(take: Dictionary, count_run: bool) -> void:
	var level_before := party_level()
	var bonus := party_trait_total("salvage_bonus")
	if bonus > 0.0 and int(take.get("salvage", 0)) > 0:
		take = take.duplicate()
		take["salvage"] = int(round(int(take["salvage"]) * (1.0 + bonus)))
	ledger.bank(take)
	ledger.xp += int(take.get("xp", 0))
	if party_level() > level_before:
		_on_level_up(level_before, party_level())
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
	if playtest != null:
		playtest.run_end(self, "extracted", take)
	run.clear()
	overlay.toast(Loc.t("Extracted — %s · %d kills") % [RunState.describe(take), kills], 4.0)
	play_event("explore.extract")
	narrative.set_flag("first_extraction", true)
	narrative.set_flag("extracted_depth_%d" % map_depth(), true) # quests read these
	var sap := int(bastion.effect("aether_on_return", 0.0))
	if sap > 0:
		ledger.bank({"aether": sap})
		ledger.save()
	enter_map(home_map)
	Rumble.pulse("extract")
	banter("extract")
	autosave()
	return true


func status_line() -> String:
	var exit_note := ""
	var exit_cell := extraction_cell()
	if exit_cell.x >= 0:
		exit_note = Loc.t("  extraction %s (%d away)") % [exit_cell, LineOfSight.distance(leader_cell(), exit_cell)]
	var line1 := Loc.t("%s  |  %s  |  leader %s  hover %s%s  |  enemies %d  pickups %d") % [
		Loc.any(map_data.name), Loc.t(mode), leader_cell(), hovered_cell, exit_note, living_enemies().size(), remaining_pickups().size(),
	]
	if perf_hud:
		line1 = "fps %d · %.1f ms  |  %s" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, line1]
	var line2 := Loc.t("%s  |  %s") % [run.summary() if run.in_shard else Loc.t("at home: loot banks on pickup"), ledger.summary()]
	for id: String in narrative.recruited:
		var c: Dictionary = registry.get_entry("companions", id)
		line2 += Loc.t("  |  %s ♥%+d") % [Loc.text(c, "short_name", id), narrative.approval_of(id)]
	var line3 := Loc.t("LMB move/attack · WASD steer · wheel zoom · N new shard (depth %d) · H home · F5/F9 save/load · F10 autosave · F1 registry") % bastion.depth()
	if at_home():
		line3 = Loc.t("LMB move/attack · WASD steer · wheel zoom · B bastion · C creator · N new shard (depth %d) · F5/F9 save/load · F10 autosave · F1 registry") % bastion.depth()
	if can_extract():
		line3 = "▶ ON THE EXTRACTION PAD — press E to extract ◀"
	elif mode == "explore" and on_waypoint().x >= 0:
		line3 = "▶ RELAY WAYPOINT — press E to bank the haul and keep going ◀"
	elif mode == "explore" and adjacent_door().x >= 0 and map_data.door_kind(adjacent_door()) == "vault":
		line3 = "▶ VAULT DOOR — Enter / A opens it for %s ◀" % BastionState.describe_cost(vault_at(adjacent_door()).get("cost", {"ciphers": 1}))
	elif mode == "explore" and merchant_near() != null:
		line3 = "▶ %s — Enter / A to trade ◀" % merchant_near().display_name
	elif mode == "defeated" and is_iron_weave():
		line3 = "▶ The Iron Weave run is over · Enter: title screen ◀"
	elif mode == "defeated":
		line3 = "▶ R: return to the yard · Esc: reload the combat checkpoint ◀"
	var line4 := tracking_line()
	return "%s\n%s\n%s" % [line1, line2, line3] if line4.is_empty() else "%s\n%s\n%s\n%s" % [line1, line2, line3, line4]


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
	refresh_music()
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
	clear_summons()
	if playtest != null:
		playtest.fight(self, result)
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
				overlay.toast(Loc.t("%s is dead. The expedition ends here.") % m.display_name, 4.0)
				iron_run_lost()
				return
			if narrative.is_recruited(m.member_id):
				narrative.dismiss(m.member_id)
				narrative.set_flag("%s_dead" % m.member_id, true)
				narrative.lose_romance(m.member_id) # a dead partner ends the romance (D-092)
				overlay.toast(Loc.t("%s is dead.") % m.display_name, 4.0)
			party.remove_member(m)
		for m: PartyMember in party.members:
			if m.downed:
				m.downed = false
				m.hp = 1
		for m: PartyMember in party.members:
			var mend := float(m.traits.get("mend_after_combat", 0.0))
			if mend > 0.0 and m.hp > 0 and m.hp < m.max_hp:
				m.hp = mini(m.max_hp, m.hp + int(ceil(m.max_hp * mend)))
		if rules.rest_after_victory > 0.0: # the breather (S48)
			for m: PartyMember in party.members:
				if m.hp > 0 and m.hp < m.max_hp:
					m.hp = mini(m.max_hp, m.hp + int(ceil(m.max_hp * rules.rest_after_victory)))
		party.trail.reset(party.leader().position)
		party.active = true
		mode = "explore"
		refresh_music()
		for f: String in pending_victory_flags:
			narrative.set_flag(f, true)
		pending_victory_flags = []
		pending_victory_flag = ""
		spawn_npcs() # placements that wait on a victory flag appear now, not on re-entry (S39)
		if not pending_trigger_flag.is_empty():
			narrative.set_flag(pending_trigger_flag, true)
			pending_trigger_flag = ""
		autosave()
		banter("victory")
		Rumble.pulse("victory")
		check_demo_end()
		return
	mode = "defeated"
	Rumble.pulse("wipe")
	pending_victory_flag = ""
	pending_victory_flags = []
	if playtest != null:
		playtest.run_end(self, "wiped", run.haul.duplicate())
	iron_run_lost()
	pending_trigger_flag = "" # the fight was lost: its trigger stays live
	if run.in_shard:
		ledger.runs_wiped += 1
		ledger.kills += run.kills
		var lost := run.take()
		run.clear()
		var err := ledger.save()
		if err != OK:
			push_warning("ledger save failed: %s" % error_string(err))
		overlay.toast(Loc.t("Wiped — the haul is lost (%s)") % RunState.describe(lost), 4.0)


# --- input & frame ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if sequence_running:
		return # a scripted sequence owns the screen
	if ending_menu != null and ending_menu.visible:
		if event.is_action_pressed("cancel") or event.is_action_pressed("confirm"):
			close_ending()
		return
	# Menu sounds: any open text menu ticks, confirms and cancels the same way.
	var menu_open := in_title() or (settings_menu != null and settings_menu.visible) or (system_menu != null and system_menu.visible) \
		or (weave_menu != null and weave_menu.visible) or (inventory_menu != null and inventory_menu.visible) or (archive_menu != null and archive_menu.visible) or (bastion_menu != null and bastion_menu.visible) or (merchant_menu != null and merchant_menu.visible) \
		or (journal_menu != null and journal_menu.visible) or (roster_menu != null and roster_menu.visible) or (saves_menu != null and saves_menu.visible) or in_dialogue()
	if menu_open and audio != null and not (settings_menu != null and not settings_menu.rebinding.is_empty()):
		if event.is_action_pressed("confirm"):
			play_event("ui.confirm")
		elif event.is_action_pressed("cancel"):
			play_event("ui.cancel")
		elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
			play_event("ui.move")
	if settings_menu != null and settings_menu.visible:
		if not settings_menu.rebinding.is_empty():
			capture_rebind(event)
			return
		if event.is_action_pressed("cancel"):
			close_settings()
		elif event.is_action_pressed("confirm"):
			confirm_setting()
		elif event.is_action_pressed("ui_up"):
			settings_menu.move(-1)
		elif event.is_action_pressed("ui_down"):
			settings_menu.move(1)
		elif event.is_action_pressed("ui_left"):
			adjust_setting(-1)
		elif event.is_action_pressed("ui_right"):
			adjust_setting(1)
		return
	if in_title():
		if event.is_action_pressed("confirm"):
			activate_title()
		elif event.is_action_pressed("cancel") and title_menu.page == TitleMenu.PAGE_STAKES:
			show_difficulty_page()
		elif event.is_action_pressed("cancel") and title_menu.page == TitleMenu.PAGE_DIFFICULTY:
			title_menu.show_rows(TitleMenu.PAGE_MAIN, title_rows())
		elif event.is_action_pressed("ui_up"):
			title_menu.move(-1)
		elif event.is_action_pressed("ui_down"):
			title_menu.move(1)
		return
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
		if reload_allowed():
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
	if demo_end_menu != null and demo_end_menu.visible:
		if event.is_action_pressed("cancel") or event.is_action_pressed("confirm"):
			close_demo_end()
		return
	if journal_menu != null and journal_menu.visible:
		if event.is_action_pressed("cancel") or event.is_action_pressed("journal"):
			close_journal()
		elif event.is_action_pressed("ui_left"):
			track_next_quest(-1)
		elif event.is_action_pressed("ui_right"):
			track_next_quest(1)
		return
	if saves_menu != null and saves_menu.visible:
		if event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
			cancel_saves()
		elif event.is_action_pressed("confirm"):
			activate_saves_row()
		elif event.is_action_pressed("ui_up"):
			saves_menu.move(-1)
		elif event.is_action_pressed("ui_down"):
			saves_menu.move(1)
		return
	if roster_menu != null and roster_menu.visible:
		if event.is_action_pressed("cancel") or event.is_action_pressed("menu"):
			close_roster()
		elif event.is_action_pressed("confirm"):
			activate_roster_row()
		elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			roster_toggle()
		elif event.is_action_pressed("ui_up"):
			roster_menu.move(-1)
		elif event.is_action_pressed("ui_down"):
			roster_menu.move(1)
		return
	if merchant_menu != null and merchant_menu.visible:
		if event.is_action_pressed("cancel"):
			close_merchant()
		elif event.is_action_pressed("confirm"):
			confirm_merchant()
		elif event.is_action_pressed("ui_up"):
			merchant_menu.move(-1)
			refresh_merchant()
		elif event.is_action_pressed("ui_down"):
			merchant_menu.move(1)
			refresh_merchant()
		return
	if archive_menu != null and archive_menu.visible:
		if event.is_action_pressed("cancel") or event.is_action_pressed("confirm") or event.is_action_pressed("journal"):
			close_archive()
		return
	if inventory_menu != null and inventory_menu.visible:
		if event.is_action_pressed("inventory") or event.is_action_pressed("cancel"):
			close_inventory()
		elif event.is_action_pressed("confirm"):
			confirm_inventory()
		elif event.is_action_pressed("ui_up"):
			inventory_menu.move(-1)
			refresh_inventory()
		elif event.is_action_pressed("ui_down"):
			inventory_menu.move(1)
			refresh_inventory()
		elif event.is_action_pressed("ui_left"):
			inventory_member(-1)
		elif event.is_action_pressed("ui_right"):
			inventory_member(1)
		return
	if weave_menu != null and weave_menu.visible:
		if event.is_action_pressed("weave") or event.is_action_pressed("cancel"):
			close_weave()
		elif event.is_action_pressed("confirm"):
			confirm_weave()
		elif event.is_action_pressed("ui_up"):
			weave_menu.move(-1)
			refresh_weave()
		elif event.is_action_pressed("ui_down"):
			weave_menu.move(1)
			refresh_weave()
		elif event.is_action_pressed("ui_left"):
			weave_member(-1)
		elif event.is_action_pressed("ui_right"):
			weave_member(1)
		return
	if creator_menu != null and creator_menu.visible:
		if event.is_action_pressed("creator") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("cancel"):
			close_creator()
		elif event.is_action_pressed("ui_accept") or event.is_action_pressed("confirm"):
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
			enter_shard(selected_shard, int(randi() % 1000000))
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
			elif event.is_action_pressed("weave"):
				open_weave()
			elif event.is_action_pressed("inventory"):
				open_inventory()
			elif event.is_action_pressed("journal"):
				open_journal()
			elif event.is_action_pressed("confirm"):
				interact()
			elif clicked:
				var cell := map_view.world_to_cell(get_global_mouse_position())
				var enemy := enemy_at(cell)
				var npc := npc_at(cell)
				if not map_data.door_kind(cell).is_empty() and LineOfSight.distance(leader_cell(), cell) <= 1:
					interact()
				elif npc != null and npc.is_merchant() and LineOfSight.distance(leader_cell(), cell) <= 2:
					open_merchant(npc)
				elif npc != null and LineOfSight.distance(leader_cell(), cell) <= 2:
					talk_to(npc.npc_id if npc.is_story_npc() else npc.companion_id)
				elif enemy != null and LineOfSight.distance(leader_cell(), cell) <= enemy.awareness:
					start_combat(true)
				else:
					command_move(cell)
			elif event.is_action_pressed("extract"):
				if not extract():
					bank_at_waypoint()
			elif event.is_action_pressed("new_shard"):
				enter_shard(selected_shard, int(randi() % 1000000))
			elif event.is_action_pressed("go_home"):
				enter_map(home_map)
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
			if is_iron_weave():
				if event.is_action_pressed("restart") or event.is_action_pressed("confirm"):
					show_title()
			elif event.is_action_pressed("restart") or event.is_action_pressed("confirm"):
				return_home()
			elif event.is_action_pressed("cancel"):
				load_from(SaveSystem.AUTOSAVE)


func _process(delta: float) -> void:
	if mode == "explore" and not in_dialogue():
		var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if dir != Vector2.ZERO:
			party.steer_leader(dir, delta, map_view.is_walkable_world)
		var step := leader_cell()
		if step != _last_step_cell:
			if _last_step_cell.x >= 0 and audio != null:
				audio.play(footstep_sound(step))
			_last_step_cell = step
		check_pickups()
		check_secrets()
		check_triggers()
		if mode == "explore" and not check_transitions():
			check_encounters()
	elif mode == "combat":
		_tick_cursor(Input.get_vector("move_left", "move_right", "move_up", "move_down"), delta)
	hovered_cell = hover_override if hover_override.x >= 0 else map_view.world_to_cell(get_global_mouse_position())
	if mode == "combat":
		combat.hover(hovered_cell)
	if map_view.lighting != null and party.leader() != null:
		map_view.lighting.follow(party.leader().position)
	overlay.status = status_line()
	_maybe_screenshot()


func _resolve_registry() -> ContentRegistry:
	if registry != null: # handed one before entering the tree (a test loading a mod, S45)
		return registry
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

const SYSTEM_ITEM_IDS: Array[String] = ["resume", "extract", "new_shard", "go_home", "bastion", "creator", "weave", "inventory", "journal", "roster", "save_game", "load_game", "settings", "platform", "title", "registry"]
const CURSOR_FIRST_REPEAT := 0.28
const CURSOR_REPEAT := 0.11

var _cursor_hold := 0.0


## Every keyboard-only action as a menu item, enabled where the key would work.
func system_items() -> Array[Dictionary]:
	var home := at_home()
	var items: Array[Dictionary] = []
	items.append({"id": "resume", "label": Loc.t("Resume"), "enabled": true})
	items.append({"id": "extract", "label": Loc.t("Extract (bank the haul)"), "enabled": can_extract(), "why": Loc.t("not on the extraction pad")})
	items.append({"id": "new_shard", "label": Loc.t("Launch a new Shard: %s (depth %d)") % [shard_name(selected_shard), bastion.depth()], "enabled": true})
	for t: Dictionary in registry.get_all("shards"):
		var id := String(t["id"])
		if id == selected_shard:
			continue
		var locked := shard_locked_reason(id)
		items.append({"id": "shard_" + id, "label": Loc.t("Launch instead: %s") % Loc.text(t, "name", id), "enabled": locked.is_empty(), "why": locked})
	items.append({"id": "go_home", "label": Loc.t("Return to the yard (haul is lost)"), "enabled": not home, "why": Loc.t("already home")})
	items.append({"id": "bastion", "label": Loc.t("The Bastion"), "enabled": home, "why": Loc.t("only at home")})
	items.append({"id": "creator", "label": Loc.t("Character creator"), "enabled": home, "why": Loc.t("only at home")})
	items.append({"id": "weave", "label": Loc.t("The Weave (level %d · %s)") % [party_level(), xp_line()], "enabled": home, "why": Loc.t("only at home")})
	items.append({"id": "inventory", "label": Loc.t("The pack (%d banked item%s)") % [ledger.items.size(), "" if ledger.items.size() == 1 else Loc.t("s")], "enabled": home, "why": Loc.t("only at home")})
	items.append({"id": "journal", "label": Loc.t("Journal (%d quests)") % narrative.quests.size(), "enabled": true})
	items.append({"id": "roster", "label": Loc.t("Roster & Quarters (%d with you, %d waiting)") % [narrative.active_companions().size(), narrative.benched.size()], "enabled": home and roster_rows().size() > 1, "why": Loc.t("only at home") if not home else Loc.t("nobody recruited")})
	items.append({"id": "save_game", "label": Loc.t("Save game…"), "enabled": mode != "combat" and reload_allowed(), "why": Loc.t("Iron Weave: one save") if not reload_allowed() else Loc.t("in combat")})
	var any_loadable := false
	for row: Dictionary in SaveSystem.list_saves(saves_dir, registry, true):
		if bool(row["loadable"]):
			any_loadable = true
	items.append({"id": "load_game", "label": Loc.t("Load game…"), "enabled": any_loadable and reload_allowed(), "why": Loc.t("Iron Weave: no reloads") if not reload_allowed() else Loc.t("no saves yet")})
	items.append({"id": "settings", "label": Loc.t("Settings"), "enabled": true})
	items.append({"id": "platform", "label": platform().status_line(), "enabled": false, "why": Loc.t("%d achievements this session") % platform().unlocked_this_session.size()})
	items.append({"id": "title", "label": Loc.t("Title screen"), "enabled": mode != "combat", "why": Loc.t("in combat")})
	items.append({"id": "registry", "label": Loc.t("Content registry dump (debug)"), "enabled": true})
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
			overlay.toast(Loc.t("%s: %s") % [item["label"], item.get("why", "unavailable")], 1.5)
			return false
	system_menu.close()
	match id:
		"resume":
			return true
		"extract":
			return extract()
		"new_shard":
			return not enter_shard(selected_shard, int(randi() % 1000000)).is_empty()
		"go_home":
			return enter_map(home_map)
		"bastion":
			return toggle_bastion()
		"creator":
			return open_creator()
		"weave":
			return open_weave()
		"inventory":
			return open_inventory()
		"journal":
			return open_journal()
		"save_game":
			return open_saves(SavesMenu.PAGE_SAVE)
		"load_game":
			return open_saves(SavesMenu.PAGE_LOAD)
		"save_1", "save_2", "save_3":
			return save_slot(int(id.get_slice("_", 1))) == OK
		"load_1", "load_2", "load_3":
			return load_slot(int(id.get_slice("_", 1))).is_empty()
		"load_autosave":
			return reload_allowed() and load_from(SaveSystem.AUTOSAVE).is_empty()
		"registry":
			overlay.toggle_registry()
			return true
		"settings":
			return open_settings()
		"title":
			autosave()
			show_title()
			return true
	if id.begins_with("shard_"):
		return launch_shard(id.trim_prefix("shard_"))
	if id.begins_with("scene_"):
		return play_scene(id.trim_prefix("scene_"))
	if id == "roster":
		return open_roster()
	if id.begins_with("bench_"):
		return bench_companion(id.trim_prefix("bench_"))
	if id.begins_with("take_"):
		return take_companion(id.trim_prefix("take_"))
	return false


## Confirm (Enter / A) while exploring: extract on the pad, otherwise talk
## to a companion within two cells. False when there is nothing to do.
func interact() -> bool:
	if mode != "explore" or in_dialogue():
		return false
	if can_extract():
		return extract()
	if on_waypoint().x >= 0:
		return bank_at_waypoint()
	var door := adjacent_door()
	if door.x >= 0 and map_data.door_kind(door) == "vault":
		var why := open_vault(door)
		if not why.is_empty():
			overlay.toast(Loc.t("Vault: %s") % why, 2.0)
		return why.is_empty()
	if door.x >= 0 and map_data.door_kind(door) == "locked":
		var why := open_locked(door)
		if not why.is_empty():
			overlay.toast(Loc.t("Gate: %s") % why, 2.5)
		return why.is_empty()
	var building := adjacent_building()
	if building != null:
		return interact_building(building)
	var trader := merchant_near()
	if trader != null:
		return open_merchant(trader)
	var here := leader_cell()
	var best: NpcActor = null
	for npc: NpcActor in npcs:
		if not is_instance_valid(npc) or not npc.visible:
			continue
		var d := LineOfSight.distance(here, npc.cell)
		if d <= 2 and (best == null or d < LineOfSight.distance(here, best.cell)):
			best = npc
	if best != null:
		return talk_to(best.npc_id if best.is_story_npc() else best.companion_id)
	overlay.toast(Loc.t("Nothing to interact with here"), 1.2)
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
## The combat cursor under a stick: a first step, a pause, then a glide
## whose pace follows the tilt (S53): a nudge creeps, a full tilt races.
func _tick_cursor(dir: Vector2, delta: float) -> void:
	if dir == Vector2.ZERO:
		_cursor_hold = 0.0
		return
	if _cursor_hold <= 0.0:
		combat.move_cursor(dir)
		_cursor_hold = CURSOR_FIRST_REPEAT if _cursor_hold == 0.0 else glide_repeat(dir)
	else:
		_cursor_hold -= delta
		if _cursor_hold <= 0.0:
			combat.move_cursor(dir)
			_cursor_hold = glide_repeat(dir)


static func glide_repeat(dir: Vector2) -> float:
	return CURSOR_REPEAT / clampf(dir.length(), 0.35, 1.0)


# --- progression: party level, builds, the Weave menu -----------------------

func progression_rules() -> Dictionary:
	return rules_entry("progression")


func party_level() -> int:
	return Progression.level_for_xp(ledger.xp, progression_rules())


func xp_line() -> String:
	var next := Progression.xp_to_next(ledger.xp, progression_rules())
	return Loc.t("XP %d, cap reached") % ledger.xp if next < 0 else Loc.t("XP %d, %d to next") % [ledger.xp, next]


func build_for(member_id: String) -> Dictionary:
	var b: Dictionary = ledger.builds.get(member_id, {})
	return {"subclass": String(b.get("subclass", "")), "talents": Array(b.get("talents", [])).duplicate(), "equipment": Dictionary(b.get("equipment", {})).duplicate(true), "multiclass": Dictionary(b.get("multiclass", {})).duplicate(true)}


func can_respec() -> bool:
	return bastion.effect("respec", 0.0) >= 1.0


## Re-derives every member from the current level and builds without
## respawning: stats, abilities, subclass, damage bonus. Max HP shifts and
## current HP moves with it, like a Workshop upgrade.
func refresh_progression() -> void:
	var preset: Dictionary = registry.get_entry("parties", party_id)
	var none: Array[Vector2] = []
	var specs := PartyBuilder.member_specs(registry, preset, protagonist, rules, none, narrative.active_companions(), party_level(), ledger.builds)
	for spec: Dictionary in specs:
		var data: Dictionary = spec["data"]
		for m: PartyMember in party.members:
			if m.member_id != String(data.get("id", "")):
				continue
			m.stats = spec["stats"]
			m.abilities.assign(spec["abilities"])
			m.level = int(data.get("level", 1))
			m.subclass_id = String(data.get("subclass", ""))
			m.damage_bonus = int(data.get("damage_bonus", 0))
			m.traits = Dictionary(data.get("traits", {})).duplicate(true)
			m.set_hp_bonus(bastion.hp_bonus())


func _on_level_up(from_level: int, to_level: int) -> void:
	refresh_progression()
	var note := Loc.t("Level %d!") % to_level
	var sub_lv := int(progression_rules().get("subclass_level", 3))
	if from_level < sub_lv and to_level >= sub_lv:
		note += Loc.t(" Subclasses open in the Weave (T at home).")
	overlay.toast(note, 4.0)
	play_event("explore.level_up")


## Empty string on success, else the reason. Changing an existing subclass
## needs the Arcanum; talents are kept.
func choose_subclass(member_id: String, sub_id: String) -> String:
	var m := member_by_id(member_id)
	if m == null:
		return Loc.t("no such member")
	var cls: Dictionary = registry.get_entry("classes", m.class_id)
	var why := Progression.can_choose_subclass(registry, cls, party_level(), build_for(member_id), sub_id, progression_rules(), can_respec())
	if not why.is_empty():
		return why
	var b := build_for(member_id)
	b["subclass"] = sub_id
	ledger.builds[member_id] = b
	ledger.save()
	refresh_progression()
	return ""


func buy_talent(member_id: String, talent_id: String) -> String:
	if member_by_id(member_id) == null:
		return Loc.t("no such member")
	var cost_mod := int(member_by_id(member_id).traits.get("talent_cost_mod", 0))
	var why := Progression.can_buy_talent(registry, party_level(), build_for(member_id), talent_id, progression_rules(), ledger.total("aether"), cost_mod)
	if not why.is_empty():
		return why
	var cost := Progression.talent_cost(registry, talent_id, cost_mod)
	if not ledger.spend({"aether": cost}):
		return Loc.t("needs %d Aether") % cost
	var b := build_for(member_id)
	b["talents"].append(talent_id)
	ledger.builds[member_id] = b
	ledger.save()
	refresh_progression()
	return ""


## Drops the subclass and every talent; refunds Aether at the Arcanum rate.
func respec(member_id: String) -> String:
	if member_by_id(member_id) == null:
		return Loc.t("no such member")
	if not can_respec():
		return Loc.t("needs the Arcanum")
	var b := build_for(member_id)
	if String(b["subclass"]).is_empty() and Array(b["talents"]).is_empty() and Dictionary(b.get("multiclass", {})).is_empty():
		return Loc.t("nothing to reset")
	var refund := Progression.refund_for(registry, b, bastion.effect("respec_refund", 0.0), int(member_by_id(member_id).traits.get("talent_cost_mod", 0)))
	ledger.resources["aether"] = ledger.total("aether") + refund
	ledger.builds[member_id] = {"subclass": "", "talents": [], "equipment": Dictionary(b.get("equipment", {})).duplicate(true), "multiclass": {}} # gear stays on; the multiclass resets too
	ledger.save()
	refresh_progression()
	overlay.toast(Loc.t("%s reset; %d Aether returned") % [member_by_id(member_id).display_name, refund], 2.5)
	return ""


func member_by_id(member_id: String) -> PartyMember:
	for m: PartyMember in party.members:
		if m.member_id == member_id:
			return m
	return null


## Rows for one member: subclass options, talents, respec.
func weave_rows(member_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var m := member_by_id(member_id)
	if m == null:
		return rows
	var cls: Dictionary = registry.get_entry("classes", m.class_id)
	var build := build_for(member_id)
	var level := party_level()
	var prules := progression_rules()
	for sub_id: String in cls.get("subclasses", []):
		var sub := registry.get_entry("subclasses", sub_id)
		var why := Progression.can_choose_subclass(registry, cls, level, build, sub_id, prules, can_respec())
		var label := Loc.t("%s — %s") % [Loc.text(sub, "name", sub_id), Loc.text(sub, "summary")]
		if String(build["subclass"]) == sub_id:
			label = "✓ " + label
		rows.append({"kind": "subclass", "id": sub_id, "label": label, "enabled": why.is_empty(), "why": why})
	rows.append_array(multiclass_rows(member_id))
	var talents := registry.get_all("talents")
	talents.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("tier", 1)) != int(b.get("tier", 1)):
			return int(a.get("tier", 1)) < int(b.get("tier", 1))
		return String(a["id"]) < String(b["id"]))
	for t: Dictionary in talents:
		var id := String(t["id"])
		var why := Progression.can_buy_talent(registry, level, build, id, prules, ledger.total("aether"))
		var cost := int(Dictionary(t.get("cost", {})).get("aether", 0))
		var label := Loc.t("T%d %s — %s (%d Aether)") % [int(t.get("tier", 1)), Loc.text(t, "name", id), Loc.text(t, "summary"), cost]
		if Array(build["talents"]).has(id):
			label = "✓ " + label
		rows.append({"kind": "talent", "id": id, "label": label, "enabled": why.is_empty(), "why": why})
	var respec_why := "" if can_respec() else Loc.t("needs the Arcanum")
	var refund_pct := int(round(bastion.effect("respec_refund", 0.0) * 100.0))
	rows.append({"kind": "respec", "id": member_id, "label": Loc.t("Reset subclass and talents (%d%% Aether back)") % refund_pct, "enabled": respec_why.is_empty(), "why": respec_why})
	return rows


func open_weave() -> bool:
	if weave_menu == null or mode != "explore" or not at_home() or in_dialogue():
		return false
	if (creator_menu != null and creator_menu.visible) or (bastion_menu != null and bastion_menu.visible):
		return false
	if system_menu != null:
		system_menu.close()
	weave_menu.member_index = clampi(weave_menu.member_index, 0, party.members.size() - 1)
	refresh_weave()
	return true


func close_weave() -> void:
	if weave_menu != null:
		weave_menu.visible = false


func weave_member(delta: int) -> void:
	if weave_menu == null or party.members.is_empty():
		return
	weave_menu.member_index = posmod(weave_menu.member_index + delta, party.members.size())
	weave_menu.cursor = 0
	refresh_weave()


func refresh_weave() -> void:
	if weave_menu == null or party.members.is_empty():
		return
	var m := party.members[clampi(weave_menu.member_index, 0, party.members.size() - 1)]
	var sub := String(build_for(m.member_id)["subclass"])
	var sub_name := Loc.t("no subclass") if sub.is_empty() else Loc.text(registry.get_entry("subclasses", sub), "name", sub)
	var header := Loc.t("Party level %d · %s · Aether %d\n%s — %s %s (%s) · HP %d/%d · abilities: %s") % [
		party_level(), xp_line(), ledger.total("aether"), m.display_name, Loc.text(registry.get_entry("races", m.race_id), "name", m.race_id),
		Loc.text(registry.get_entry("classes", m.class_id), "name", m.class_id), sub_name, m.hp, m.max_hp, ability_names(m.abilities)]
	weave_menu.show_rows(header, weave_rows(m.member_id))


## Enter / A on the Weave screen: runs the selected row for the shown member.
func confirm_weave() -> bool:
	if weave_menu == null or not weave_menu.visible or party.members.is_empty():
		return false
	var row := weave_menu.selected()
	if row.is_empty():
		return false
	var m := party.members[clampi(weave_menu.member_index, 0, party.members.size() - 1)]
	var why := ""
	match String(row.get("kind", "")):
		"subclass":
			why = choose_subclass(m.member_id, String(row["id"]))
		"multiclass":
			why = choose_multiclass(m.member_id, String(row["id"]))
		"multiclass_level":
			why = add_multiclass_level(m.member_id)
		"talent":
			why = buy_talent(m.member_id, String(row["id"]))
		"respec":
			why = respec(m.member_id)
	if not why.is_empty():
		overlay.toast(Loc.t("%s: %s") % [row.get("label", row.get("id", "")), why], 2.0)
	refresh_weave()
	return why.is_empty()


# --- shard selection --------------------------------------------------------

func shard_name(template_id: String) -> String:
	return Loc.text(registry.get_entry("shards", template_id), "name", template_id)


## Why a template cannot be launched now; empty when it can.
func shard_locked_reason(template_id: String) -> String:
	var t: Dictionary = registry.get_entry("shards", template_id)
	if t.is_empty():
		return Loc.t("unknown Shard")
	if not bastion.has_unlocked(String(t.get("requires_unlock", ""))):
		return Loc.t("the Beacon has not found it yet")
	var flag := String(t.get("requires_flag", ""))
	if not flag.is_empty() and not narrative.flag(flag):
		return Loc.t("the story has not opened it yet")
	return ""


## Picks a template for N and launches it. False (with a toast) when locked.
func launch_shard(template_id: String) -> bool:
	var why := shard_locked_reason(template_id)
	if not why.is_empty():
		overlay.toast(Loc.t("%s: %s") % [shard_name(template_id), why], 2.0)
		return false
	selected_shard = template_id
	return not enter_shard(selected_shard, int(randi() % 1000000)).is_empty()



# --- shard features: doors, vaults, waypoints, merchant, rarity -------------

func loot_rules() -> Dictionary:
	return rules_entry("loot")


func rarity_multiplier(rarity: String) -> float:
	return float(Dictionary(loot_rules().get("rarities", {})).get(rarity, 1.0))


func rarity_color(rarity: String) -> Color:
	var colors: Dictionary = loot_rules().get("colors", {})
	if colors.has(rarity):
		return Color.html(String(colors[rarity]))
	return Color.TRANSPARENT


## Grants scaled by rarity: ranges and numbers alike, XP included.
static func scale_grants(grants: Dictionary, mult: float) -> Dictionary:
	var out: Dictionary = {}
	for key: String in grants:
		var v: Variant = grants[key]
		if v is Array:
			var arr: Array = v
			out[key] = [int(round(float(arr[0]) * mult)), int(round(float(arr[arr.size() - 1]) * mult))]
		elif key == "cipher_chance":
			out[key] = minf(float(v) * mult, 1.0)
		elif v is int or v is float:
			out[key] = int(round(float(v) * mult))
		else:
			out[key] = v
	return out


## The floor tile the current map uses for opened doors (its own floor).
func _floor_tile_entry() -> Dictionary:
	var legend: Dictionary = map_entry.get("legend", {})
	var marker := String(map_entry.get("spawn_marker", "P"))
	var id := String(legend.get(marker, legend.get(".", "floor_concrete")))
	return registry.get_entry("tiles", id)


## Turns a closed door into floor. `silent` for restores. False when the
## cell is not a door.
func open_door(cell: Vector2i, silent: bool = false) -> bool:
	var kind := map_data.door_kind(cell)
	if kind.is_empty():
		return false
	map_data.set_tile(cell, _floor_tile_entry())
	map_view.build(map_data, registry.get_entry("biomes", map_data.biome_id), rules_entry("lighting"))
	if highlighter != null:
		highlighter.map_view = map_view
	var raw: Array = [cell.x, cell.y]
	if map_entry.has("generation"):
		if not run.opened.has(raw):
			run.opened.append(raw)
	else:
		narrative.set_flag(door_flag(map_id, cell), true) # handcrafted maps remember for good
	if not silent:
		var line := Loc.t("A hidden passage opens.")
		if kind == "vault":
			line = "The vault door grinds open."
		elif kind == "locked":
			line = "The gate unlocks and swings wide."
		overlay.toast(line, 2.5)
		play_event("explore.door")
	return true


## Secret doors give when a party member stands beside them.
func check_secrets() -> int:
	if mode != "explore":
		return 0
	var doors := map_data.door_cells("secret")
	if doors.is_empty():
		return 0
	var opened_now := 0
	for m: PartyMember in party.members:
		var here := member_cell(m)
		for door: Vector2i in doors:
			if LineOfSight.distance(here, door) == 1 and map_data.door_kind(door) == "secret":
				if open_door(door):
					opened_now += 1
	return opened_now


## The vault entry whose door is `cell`, or {}.
func vault_at(cell: Vector2i) -> Dictionary:
	for v: Dictionary in map_entry.get("vaults", []):
		var raw: Array = v.get("door", [])
		if raw.size() == 2 and Vector2i(int(raw[0]), int(raw[1])) == cell:
			return v
	return {}


## Spends the vault cost from the banked ledger and opens the door. Empty
## string on success, else the reason.
func open_vault(cell: Vector2i) -> String:
	if map_data.door_kind(cell) != "vault":
		return Loc.t("not a vault door")
	var vault := vault_at(cell)
	var cost: Dictionary = vault.get("cost", {"ciphers": 1})
	if not ledger.can_afford(cost):
		return Loc.t("needs %s") % BastionState.describe_cost(cost)
	ledger.spend(cost)
	ledger.save()
	open_door(cell)
	return ""


## A closed door next to any party member, nearest first; (-1, -1) when none.
func adjacent_door() -> Vector2i:
	for m: PartyMember in party.members:
		var here := member_cell(m)
		for door: Vector2i in map_data.door_cells():
			if LineOfSight.distance(here, door) == 1:
				return door
	return Vector2i(-1, -1)


func on_waypoint() -> Vector2i:
	var here := leader_cell()
	if map_data.is_waypoint(here) and not run.waypoints_used.has([here.x, here.y]):
		return here
	return Vector2i(-1, -1)


## Banks the haul at a relay waypoint without leaving the Shard; the run
## goes on with an empty haul. One use per waypoint.
func bank_at_waypoint() -> bool:
	var here := on_waypoint()
	if here.x < 0 or mode != "explore":
		return false
	var take := run.take()
	_bank(take, false)
	run.clear_haul()
	run.waypoints_used.append([here.x, here.y])
	overlay.toast(Loc.t("Relay: banked %s") % RunState.describe(take), 3.0)
	autosave()
	return true


func merchant_near() -> NpcActor:
	var here := leader_cell()
	var best: NpcActor = null
	for npc: NpcActor in npcs:
		if not is_instance_valid(npc) or not npc.is_merchant():
			continue
		var d := LineOfSight.distance(here, npc.cell)
		if d <= 2 and (best == null or d < LineOfSight.distance(here, best.cell)):
			best = npc
	return best


func merchant_rows(merchant: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for item: Dictionary in merchant.get("stock", []):
		var cost: Dictionary = item.get("cost", {})
		var why := "" if ledger.can_afford(cost) else Loc.t("needs %s") % BastionState.describe_cost(cost)
		rows.append({"id": String(item.get("id", "")), "label": Loc.t("%s — %s") % [Loc.any(String(item.get("label", item.get("id", "?")))), BastionState.describe_cost(cost)], "enabled": why.is_empty(), "why": why})
	return rows


func open_merchant(npc: NpcActor) -> bool:
	if merchant_menu == null or npc == null or not npc.is_merchant() or mode != "explore":
		return false
	current_merchant = npc.merchant_id
	refresh_merchant()
	return true


func close_merchant() -> void:
	if merchant_menu != null:
		merchant_menu.close()
	current_merchant = ""


func refresh_merchant() -> void:
	var merchant: Dictionary = registry.get_entry("merchants", current_merchant)
	if merchant.is_empty():
		close_merchant()
		return
	var header := "%s\n%s\n%s" % [Loc.text(merchant, "name", current_merchant), Loc.text(merchant, "summary"), ledger.summary()]
	merchant_menu.show_rows(header, merchant_rows(merchant))


## Buys one stock item by id from the open merchant. Empty string on
## success, else the reason.
func buy(item_id: String) -> String:
	var merchant: Dictionary = registry.get_entry("merchants", current_merchant)
	for item: Dictionary in merchant.get("stock", []):
		if String(item.get("id", "")) != item_id:
			continue
		var cost: Dictionary = item.get("cost", {})
		if not ledger.can_afford(cost):
			return Loc.t("needs %s") % BastionState.describe_cost(cost)
		ledger.spend(cost)
		var effect: Dictionary = item.get("effect", {})
		var heal := float(effect.get("heal_fraction", 0.0))
		if heal > 0.0:
			for m: PartyMember in party.members:
				if not m.downed:
					m.hp = mini(m.max_hp, m.hp + int(ceil(m.max_hp * heal)))
		var grant: Dictionary = effect.get("grant", {})
		if not grant.is_empty():
			ledger.bank(grant)
		var bought := String(effect.get("item", ""))
		if not bought.is_empty() and registry.has_entry("items", bought):
			ledger.items.append(ItemSystem.make(bought, [], "common", int(randi())))
		ledger.save()
		overlay.toast(Loc.t("Bought: %s") % item.get("label", item_id), 2.0)
		return ""
	return Loc.t("no such item")


func confirm_merchant() -> bool:
	if merchant_menu == null or not merchant_menu.visible:
		return false
	var row := merchant_menu.selected()
	if row.is_empty():
		return false
	var why := buy(String(row["id"]))
	if not why.is_empty():
		overlay.toast(Loc.t("%s: %s") % [row.get("label", row["id"]), why], 2.0)
	refresh_merchant()
	return why.is_empty()



# --- campaign tooling: buildings, transitions, triggers, locked doors, journal

## Places a BuildingActor for every `buildings` site on the map (the Bastion).
func spawn_buildings() -> void:
	for b: BuildingActor in buildings:
		if is_instance_valid(b):
			b.queue_free()
	buildings.clear()
	if npcs_node == null:
		return
	for site: Dictionary in map_entry.get("buildings", []):
		var id := String(site.get("id", ""))
		if not bastion.has(id):
			push_warning("map %s places unknown building %s" % [map_data.id, id])
			continue
		var raw: Array = site.get("cell", [0, 0])
		var cell := Vector2i(int(raw[0]), int(raw[1]))
		var actor := BuildingActor.new()
		actor.setup(id, bastion.name_of(id), cell, class_color_for_building(id))
		actor.position = map_view.cell_to_world(cell)
		npcs_node.add_child(actor)
		buildings.append(actor)
	refresh_buildings()


func class_color_for_building(id: String) -> Color:
	match id:
		"beacon":
			return Color.html("#b58cff")
		"medbay":
			return Color.html("#ff7a6b")
		"workshop":
			return Color.html("#33e0d6")
		"arcanum":
			return Color.html("#c9a23a")
	return Color(0.55, 0.5, 0.65)


func refresh_buildings() -> void:
	for b: BuildingActor in buildings:
		if is_instance_valid(b):
			b.set_level(bastion.level(b.building_id), bastion.max_level(b.building_id))


func building_at(cell: Vector2i) -> BuildingActor:
	for b: BuildingActor in buildings:
		if is_instance_valid(b) and b.cell == cell:
			return b
	return null


## Quests with `auto_start` begin at their start stage the first time a
## world exists without them (new game); saved games already carry them.
func auto_start_quests() -> void:
	for q: Dictionary in registry.get_all("quests"):
		if bool(q.get("auto_start", false)) and narrative.stage_of(String(q["id"])).is_empty():
			narrative.set_stage(String(q["id"]), String(q.get("start", "")))


## Persisted door state on handcrafted maps lives in narrative flags.
static func door_flag(map_name: String, cell: Vector2i) -> String:
	return "door_%s_%d_%d" % [map_name, cell.x, cell.y]


func restore_map_doors() -> void:
	if map_entry.has("generation"): # Shards keep their own run deltas
		return
	for door: Vector2i in map_data.door_cells():
		if narrative.flag(door_flag(map_id, door)):
			open_door(door, true)


## The `doors` entry for a locked door cell, or {}.
func locked_door_at(cell: Vector2i) -> Dictionary:
	for d: Dictionary in map_entry.get("doors", []):
		var raw: Array = d.get("cell", [])
		if raw.size() == 2 and Vector2i(int(raw[0]), int(raw[1])) == cell:
			return d
	return {}


## Opens a locked gate when its key flag is set. Empty string on success.
func open_locked(cell: Vector2i) -> String:
	if map_data.door_kind(cell) != "locked":
		return Loc.t("not a locked door")
	var entry := locked_door_at(cell)
	var key := String(entry.get("key_flag", ""))
	if not key.is_empty() and not narrative.flag(key):
		return Loc.t("locked: %s") % String(entry.get("hint", "something on this map opens it"))
	open_door(cell)
	var opens := String(entry.get("opens_flag", ""))
	if not opens.is_empty():
		narrative.set_flag(opens, true)
	return ""


## Transitions: the leader standing on a marked cell travels to another map.
func transition_at(cell: Vector2i) -> Dictionary:
	for t: Dictionary in map_entry.get("transitions", []):
		var raw: Array = t.get("cell", [])
		if raw.size() == 2 and Vector2i(int(raw[0]), int(raw[1])) == cell:
			return t
	return {}


func check_transitions() -> bool:
	if mode != "explore" or in_dialogue() or map_entry.has("generation"):
		return false
	var t := transition_at(leader_cell())
	if t.is_empty() or not Conditions.passes(t.get("when", {}), dialogue_ctx()):
		return false
	var raw: Array = t.get("arrive", [])
	var arrive := Vector2i(int(raw[0]), int(raw[1])) if raw.size() == 2 else Vector2i(-1, -1)
	return travel(String(t.get("to", "")), arrive, String(t.get("label", "")))


## Loads `to` and places the party at `arrive` (or its spawn cells).
func travel(to: String, arrive: Vector2i, label: String = "") -> bool:
	if run.in_shard and registry.has_entry("maps", to): # a door out of a Shard (S42): the haul banks at the threshold
		var take := run.take()
		_bank(take, true)
		run.clear()
		overlay.toast(Loc.t("Banked at the threshold: %s") % RunState.describe(take), 3.0)
	_arrive_cell = arrive
	var ok := enter_map(to)
	_arrive_cell = Vector2i(-1, -1)
	if ok:
		overlay.toast(label if not label.is_empty() else map_data.name, 2.0)
		autosave()
	return ok


## Triggers: scripted cells. `once` triggers remember firing in a flag.
static func trigger_flag(map_name: String, id: String) -> String:
	return "trigger_%s_%s" % [map_name, id]


func check_triggers() -> int:
	if mode != "explore" or in_dialogue():
		return 0
	var cells: Array[Vector2i] = []
	for m: PartyMember in party.members:
		cells.append(member_cell(m))
	var fired := 0
	for t: Dictionary in map_entry.get("triggers", []):
		var on := false
		var raw_cells: Array = t.get("cells", [])
		if t.has("cell"):
			raw_cells = [t["cell"]]
		for raw: Array in raw_cells:
			if cells.has(Vector2i(int(raw[0]), int(raw[1]))):
				on = true
		if on and fire_trigger(t):
			fired += 1
			if mode != "explore" or in_dialogue():
				break
	return fired


## Runs one trigger if its conditions hold and it has not spent itself.
func fire_trigger(t: Dictionary) -> bool:
	var id := String(t.get("id", ""))
	if bool(t.get("once", true)) and narrative.flag(trigger_flag(map_id, id)):
		return false
	if not Conditions.passes(t.get("when", {}), dialogue_ctx()):
		return false
	var effects: Dictionary = t.get("effects", {})
	if bool(t.get("once", true)):
		if effects.has("victory_flag"):
			pending_trigger_flag = trigger_flag(map_id, id) # spent only once the fight is won
		else:
			narrative.set_flag(trigger_flag(map_id, id), true)
	apply_effects(effects)
	autosave()
	check_demo_end()
	return true


## Journal entries for every started quest, objectives ticked against the state.
func journal_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ctx := dialogue_ctx()
	var ids: Array = narrative.quests.keys()
	ids.sort()
	for quest_id: String in ids:
		var quest: Dictionary = registry.get_entry("quests", quest_id)
		if quest.is_empty():
			continue
		var stage_id := narrative.stage_of(quest_id)
		var stage: Dictionary = Dictionary(quest.get("stages", {})).get(stage_id, {})
		var objectives: Array[Dictionary] = []
		var raw_objectives: Array = stage.get("objectives", [])
		for i: int in raw_objectives.size():
			var o: Dictionary = raw_objectives[i]
			objectives.append({"text": Loc.content("quests", quest_id, "stages.%s.objectives.%d.text" % [stage_id, i], String(o.get("text", ""))), "done": Conditions.passes(o.get("done_when", {}), ctx)})
		out.append({"id": quest_id, "name": Loc.text(quest, "name", quest_id), "main": bool(quest.get("main", false)), "stage": stage_id, "stage_summary": Loc.content("quests", quest_id, "stages.%s.summary" % stage_id, String(stage.get("summary", ""))), "complete": bool(stage.get("complete", false)), "objectives": objectives})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["main"]) != bool(b["main"]):
			return bool(a["main"])
		return String(a["id"]) < String(b["id"]))
	return out


func journal_text() -> String:
	return JournalMenu.render(journal_entries(), tracked_quest_id(), narrative.log) + "\n" + standing_text()


## "Standing: The Lattice +2 · The Ashfound -1" for every faction with a score.
func standing_text() -> String:
	var parts: PackedStringArray = []
	for f: Dictionary in registry.get_all("factions"):
		var rep := narrative.reputation_of(String(f["id"]))
		if rep != 0:
			parts.append("%s %+d" % [Loc.text(f, "name", String(f["id"])), rep])
	var sworn := "" if not narrative.has_joined() else Loc.t("Sworn to %s. ") % faction_name(narrative.faction)
	if parts.is_empty():
		return sworn + Loc.t("Standing: no faction has an opinion of you yet.")
	return sworn + Loc.t("Standing: ") + " · ".join(parts)


func open_journal() -> bool:
	if journal_menu == null or mode == "combat" or in_dialogue():
		return false
	if (creator_menu != null and creator_menu.visible) or (bastion_menu != null and bastion_menu.visible) or (weave_menu != null and weave_menu.visible):
		return false
	if system_menu != null:
		system_menu.close()
	journal_menu.show_text(journal_text())
	return true


func close_journal() -> void:
	if journal_menu != null:
		journal_menu.close()



# --- factions ---------------------------------------------------------------

func faction_name(id: String) -> String:
	return Loc.text(registry.get_entry("factions", id), "name", id)


## The casting rule as a mechanic: when an effect block moves a faction's
## reputation, every recruited companion who leans that way approves and
## every one leaning toward a rival is wounded, one point per step, and
## the change is toasted. Approval written directly by the same block is
## left alone (it already said who approves).
func react_to_reputation(effects: Dictionary) -> void:
	var reputation: Dictionary = effects.get("reputation", {})
	if reputation.is_empty():
		return
	var explicit: Dictionary = effects.get("approval", {})
	for faction: String in reputation:
		var delta := int(reputation[faction])
		if delta == 0:
			continue
		var step := 1 if delta > 0 else -1
		var rivals: Array = registry.get_entry("factions", faction).get("rivals", [])
		var notes: PackedStringArray = ["%s %+d" % [faction_name(faction), delta]]
		for id: String in narrative.recruited:
			if explicit.has(id):
				continue
			var lean := String(registry.get_entry("companions", id).get("faction", ""))
			var change := 0
			if lean == faction:
				change = step
			elif rivals.has(lean):
				change = -step
			if change != 0:
				narrative.add_approval(id, change)
				notes.append("%s %s" % [String(registry.get_entry("companions", id).get("short_name", id)), "approves" if change > 0 else "disapproves"])
		overlay.toast(" · ".join(notes), 3.0)



# --- the demo boundary and building interactions ----------------------------

func demo_end_flag() -> String:
	return String(registry.get_entry("rules", "demo").get("end_flag", "demo_complete"))


## Shows the end panel once the end flag is set (checked after dialogues,
## triggers and fights). Returns true when it was shown this call.
func check_demo_end() -> bool:
	if demo_end_menu == null or in_dialogue() or mode == "combat":
		return false
	if not narrative.flag(demo_end_flag()) or narrative.flag("demo_end_seen"):
		return false
	if not bool(registry.get_entry("rules", "demo").get("enabled", true)) and not demo_forced:
		return false # the full game: Act 1 ends and the story goes on (S39)
	narrative.set_flag("demo_end_seen", true)
	demo_end_menu.show_text(DemoEndMenu.render(demo_stats()))
	autosave()
	return true


func demo_stats() -> Dictionary:
	var names: Array = []
	for id: String in narrative.recruited:
		names.append(Loc.text(registry.get_entry("companions", id), "short_name", id))
	var choice := ""
	if narrative.flag("choir_refused"):
		choice = Loc.t("You backed away from the Choir without a word. It will remember the silence.")
	elif narrative.flag("choir_heard_truth"):
		choice = Loc.t("You made the Choir say who drowned it. That answer is going to cost someone.")
	elif narrative.flag("choir_named_player"):
		choice = Loc.t("Kaj-7 asked to go up, and you went. The Choir was calling you, not it.")
	return {"level": party_level(), "runs": ledger.runs_completed, "wipes": ledger.runs_wiped, "kills": ledger.kills, "companions": names, "standing": standing_text(), "choice": choice}


## Enter / A / Esc on the end panel: back to the Bastion, story intact.
func close_demo_end() -> void:
	if demo_end_menu == null:
		return
	demo_end_menu.close()
	if map_id != home_map:
		enter_map(home_map)


## A Bastion building beside the leader (any building within one cell).
func adjacent_building() -> BuildingActor:
	var here := leader_cell()
	for b: BuildingActor in buildings:
		if is_instance_valid(b) and LineOfSight.distance(here, b.cell) <= 1:
			return b
	return null


## Interact with a building: the Beacon launches Shards, the Workshop opens
## the Bastion screen, the Arcanum the Weave, the Med-bay heals.
func interact_building(b: BuildingActor) -> bool:
	match b.building_id:
		"beacon":
			return open_beacon_menu()
		"workshop":
			return toggle_bastion()
		"arcanum":
			return open_weave()
		"medbay":
			heal_party(maxf(bastion.heal_fraction(), 0.25))
			overlay.toast(Loc.t("The Med-bay patches the party up."), 2.0)
			return true
		"archive":
			return open_archive()
		"garden":
			return tend_garden()
		"quarters":
			return open_quarters()
	return false


## The Beacon's own list: launch the chosen Shard or switch templates.
func open_beacon_menu() -> bool:
	if system_menu == null or mode != "explore":
		return false
	var items: Array[Dictionary] = []
	items.append({"id": "new_shard", "label": Loc.t("Launch: %s (depth %d)") % [shard_name(selected_shard), bastion.depth()], "enabled": true})
	for t: Dictionary in registry.get_all("shards"):
		var id := String(t["id"])
		if id == selected_shard:
			continue
		items.append({"id": "shard_" + id, "label": Loc.t("Launch instead: %s") % t.get("name", id), "enabled": shard_locked_reason(id).is_empty(), "why": Loc.t("the Beacon has not found it yet")})
	items.append({"id": "resume", "label": Loc.t("Step back"), "enabled": true})
	system_menu.open(items)
	return true



# --- front end: title, new game, settings, rebinding -------------------------

func title_rows() -> Array[Dictionary]:
	var saves := SaveSystem.list_saves(saves_dir, registry)
	var has_auto := bool(saves[SaveSystem.SLOTS]["loadable"])
	var any_slot := false
	for n: int in SaveSystem.SLOTS:
		if bool(saves[n]["loadable"]):
			any_slot = true
	var rows: Array[Dictionary] = []
	rows.append({"id": "new", "label": Loc.t("New game"), "enabled": true})
	rows.append({"id": "continue", "label": Loc.t("Continue"), "enabled": has_auto, "why": Loc.t("no autosave yet")})
	var iron_underway := account != null and account.iron_active
	rows.append({"id": "load", "label": Loc.t("Load"), "enabled": any_slot and not iron_underway, "why": Loc.t("Iron Weave: no reloads while the run stands") if iron_underway else Loc.t("no saves yet")})
	rows.append({"id": "settings", "label": Loc.t("Settings"), "enabled": true})
	rows.append({"id": "quit", "label": Loc.t("Quit"), "enabled": true})
	return rows


## The difficulty page with the cursor on the pending choice (the default on a fresh New game).
func show_difficulty_page() -> void:
	title_menu.show_rows(TitleMenu.PAGE_DIFFICULTY, difficulty_rows())
	title_menu.select_id("diff_" + pending_difficulty)


func difficulty_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for d: Dictionary in difficulties():
		rows.append({"id": "diff_" + String(d["id"]), "label": Loc.text(d, "name", String(d["id"])), "enabled": true, "blurb": Loc.text(d, "summary")})
	rows.append({"id": "back", "label": Loc.t("Back"), "enabled": true})
	return rows


func stakes_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	rows.append({"id": "story", "label": Loc.t("Story-Protected"), "enabled": true, "blurb": Loc.t("Companions fall and get back up. The story never loses anyone it did not mean to.")})
	rows.append({"id": "mortal", "label": Loc.t("Mortal"), "enabled": true, "blurb": Loc.t("The dead stay dead. Companion quests carry on without them. A dead leader ends the expedition.")})
	var iron_underway := account != null and account.iron_active
	rows.append({"id": "iron", "label": Loc.t("Iron Weave"), "enabled": not iron_underway, "why": Loc.t("a run is underway: Continue it, or start another game to give it up"), "blurb": Loc.t("Mortal, with one save and no reloads. A wipe ends the run and its save with it. Starting any other game gives it up. The account remembers every attempt.")})
	rows.append({"id": "back", "label": Loc.t("Back"), "enabled": true})
	return rows


func show_title() -> void:
	if title_menu == null:
		return
	party.stop()
	title_menu.show_rows(TitleMenu.PAGE_MAIN, title_rows())
	refresh_music()


func in_title() -> bool:
	return title_menu != null and title_menu.visible


## Enter / A on the title screen. New game asks the difficulty, then the
## death-stakes (S50).
func activate_title() -> bool:
	if not in_title():
		return false
	var id := title_menu.selected_id()
	if title_menu.page == TitleMenu.PAGE_DIFFICULTY:
		if id == "back":
			title_menu.show_rows(TitleMenu.PAGE_MAIN, title_rows())
			return true
		if id.begins_with("diff_"):
			pending_difficulty = id.trim_prefix("diff_")
			title_menu.show_rows(TitleMenu.PAGE_STAKES, stakes_rows())
			return true
		return false
	if title_menu.page == TitleMenu.PAGE_STAKES:
		match id:
			"story":
				return open_new_game_creator(false, false)
			"mortal":
				return open_new_game_creator(true, false)
			"iron":
				return open_new_game_creator(true, true)
			"back":
				show_difficulty_page()
				return true
		return false
	match id:
		"new":
			pending_difficulty = default_difficulty()
			show_difficulty_page()
			return true
		"continue":
			return continue_game()
		"load":
			title_menu.close()
			_saves_return_to_title = true
			return open_saves(SavesMenu.PAGE_LOAD)
		"settings":
			return open_settings()
		"quit":
			get_tree().quit()
			return true
	return false


## A fresh story: narrative, protagonist and party reset, the books wiped,
## the difficulty and death-stakes chosen. The old autosave is overwritten
## by the first one. Iron Weave (S50) is Mortal with one save and no
## reloads, recorded on the account; any new game gives up a run underway.
func new_game(mortal: bool, difficulty: String = "", iron: bool = false, sheet: Dictionary = {}) -> bool:
	if title_menu != null:
		title_menu.close()
	if account != null and account.iron_active:
		account.end_iron() # the one save is about to be overwritten
	narrative = NarrativeState.new()
	narrative.difficulty = difficulty if registry.has_entry("difficulties", difficulty) else default_difficulty()
	narrative.set_flag("mortal_mode", mortal or iron)
	narrative.set_flag("iron_weave", iron)
	protagonist = {}
	if not sheet.is_empty() and CharacterSheet.from_dict(sheet).validate(registry, registry.get_entry("rules", "attributes")).is_empty():
		protagonist = sheet.duplicate(true) # the creator's sheet leads from the first step (S51)
	ledger = Ledger.new()
	ledger.path = ledger_path
	ledger.save()
	bastion.setup(registry.get_all("buildings"), ledger.buildings)
	selected_shard = DEFAULT_SHARD
	apply_death_stakes()
	respawn_party()
	enter_map(home_map)
	auto_start_quests()
	spawn_npcs()
	autosave()
	if iron and account != null:
		account.begin_iron(narrative.difficulty)
	var stakes := Loc.t("Iron Weave: one save, no reloads, the dead stay dead.") if iron else (Loc.t("Mortal mode: the dead stay dead.") if mortal else Loc.t("Story-Protected: the story keeps its people."))
	overlay.toast(Loc.t("%s · %s") % [String(difficulty_entry().get("name", "Balanced")), stakes], 3.0)
	return true


func continue_game() -> bool:
	if not FileAccess.file_exists(save_path(SaveSystem.AUTOSAVE)):
		return false
	if title_menu != null:
		title_menu.close()
	return load_from(SaveSystem.AUTOSAVE).is_empty()


## The death-stakes rule and the difficulty follow the story (S50): the
## combat rules are rebuilt from `rules/combat` under the story's
## difficulty overlay, then the mode goes on top. Saved as narrative state.
func apply_death_stakes() -> void:
	rules = CombatRules.from_entry(rules_entry("combat"))
	rules.story_protected = not narrative.flag("mortal_mode")


func is_mortal_mode() -> bool:
	return narrative.flag("mortal_mode")


# --- difficulty and Iron Weave (S50, D-105) ----------------------------------

## Every `difficulties` entry, by `order`: a name, a summary and a `rules`
## overlay ({rules entry id: {field: value}}). A mod adds one by adding a file.
func difficulties() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	rows.assign(registry.get_all("difficulties"))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 0)) < int(b.get("order", 0)))
	return rows


## The entry marked `default`, else the first by order, else "".
func default_difficulty() -> String:
	var rows := difficulties()
	for d: Dictionary in rows:
		if bool(d.get("default", false)):
			return String(d["id"])
	return String(rows[0]["id"]) if not rows.is_empty() else ""


## The story's difficulty id: what it was started on, or the default when
## the save predates difficulties or names one that no longer loads.
func difficulty_id() -> String:
	if registry.has_entry("difficulties", narrative.difficulty):
		return narrative.difficulty
	return default_difficulty()


func difficulty_entry() -> Dictionary:
	var id := difficulty_id()
	return registry.get_entry("difficulties", id) if not id.is_empty() else {}


## A rules entry under the difficulty's overlay: the base entry with the
## overlay's fields written over it. The registry's own dictionary when the
## difficulty has nothing to say about that entry.
func rules_entry(rule_id: String) -> Dictionary:
	var base: Dictionary = registry.get_entry("rules", rule_id)
	var overlays: Dictionary = difficulty_entry().get("rules", {})
	var overlay: Variant = overlays.get(rule_id, {})
	if not overlay is Dictionary or (overlay as Dictionary).is_empty():
		return base
	var merged := base.duplicate(true)
	for k: String in overlay:
		merged[k] = overlay[k]
	return merged


## Iron Weave: one save, Mortal, no reloads. The save carries the flag (so
## the menus know) and the account carries the run (so a swapped save
## cannot restart it).
func is_iron_weave() -> bool:
	return narrative.flag("iron_weave")


func reload_allowed() -> bool:
	return not is_iron_weave()


## The Iron Weave run is lost: the one save is removed, the account is
## told, and the only way on is the title screen.
func iron_run_lost() -> void:
	if not is_iron_weave():
		return
	var auto := ProjectSettings.globalize_path(save_path(SaveSystem.AUTOSAVE))
	if FileAccess.file_exists(auto):
		DirAccess.remove_absolute(auto)
	if account != null:
		account.end_iron()
	if overlay != null:
		overlay.toast(Loc.t("The Iron Weave run is over. There is no save to return to."), 5.0)


## An Iron Weave run reached an ending: the account keeps it as a key.
func iron_run_complete(ending_id: String) -> void:
	if not is_iron_weave():
		return
	narrative.set_flag("iron_weave_complete", true)
	if account != null:
		account.end_iron(ending_id)


func open_settings() -> bool:
	if settings_menu == null:
		return false
	if title_menu != null and title_menu.visible:
		title_menu.close()
		_settings_return_to_title = true
	else:
		_settings_return_to_title = false
	if system_menu != null:
		system_menu.close()
	refresh_settings()
	return true


func refresh_settings() -> void:
	settings_menu.show_rows(SettingsMenu.build_rows(settings))


func close_settings() -> void:
	if settings_menu == null:
		return
	settings_menu.close()
	settings.save(settings_path)
	InputActions.save_overrides(input_path)
	if _settings_return_to_title:
		show_title()


## The palette, the screen effects and the lighting follow the settings (S54, S56).
func apply_visual_settings() -> void:
	if color_filter != null:
		color_filter.set_mode(settings.palette)
	if screen_fx != null:
		screen_fx.set_mode(settings.screen_fx)
	if map_view != null and map_view.lighting != null:
		map_view.lighting.set_enabled(settings.lighting)


## Left / right on a settings row.
func adjust_setting(direction: int) -> bool:
	var row := settings_menu.selected()
	match String(row.get("id", "")):
		"fullscreen":
			settings.fullscreen = not settings.fullscreen
		"volume":
			settings.step_volume(direction)
		"glyphs":
			settings.cycle_glyphs(direction)
		"rumble":
			settings.rumble = not settings.rumble
			if settings.rumble:
				Rumble.enabled = true
				Rumble.pulse("hit") # so the toggle can be felt
		"text_scale":
			settings.cycle_text_scale(direction)
		"music":
			settings.step_music(direction)
		"sfx":
			settings.step_sfx(direction)
			play_event("ui.confirm") # so the level can be heard
		"palette":
			settings.cycle_palette(direction)
		"language":
			settings.cycle_locale(direction)
		"lighting":
			settings.lighting = not settings.lighting
		"screen_fx":
			settings.cycle_screen_fx(direction)
		_:
			return false
	settings.apply()
	UiScale.apply(self, [overlay])
	apply_visual_settings()
	refresh_settings()
	return true


## Enter / A on a settings row: toggles, starts a rebind, resets, or backs out.
func confirm_setting() -> bool:
	var row := settings_menu.selected()
	var id := String(row.get("id", ""))
	if id.begins_with("rebind:"):
		settings_menu.rebinding = id.trim_prefix("rebind:")
		settings_menu.refresh()
		return true
	match id:
		"fullscreen", "glyphs", "rumble", "text_scale", "palette", "language", "lighting", "screen_fx":
			return adjust_setting(1)
		"music", "sfx":
			return adjust_setting(1)
		"volume":
			return adjust_setting(1)
		"reset":
			InputActions.reset_overrides()
			refresh_settings()
			overlay.toast(Loc.t("Bindings reset to default."), 2.0)
			return true
		"back":
			close_settings()
			return true
	return false


## The next key or pad button while a rebind is armed becomes the binding.
func capture_rebind(event: InputEvent) -> bool:
	if settings_menu == null or settings_menu.rebinding.is_empty():
		return false
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		settings_menu.rebinding = ""
		settings_menu.refresh()
		return true
	if not (event is InputEventKey or event is InputEventJoypadButton) or not event.is_pressed():
		return false
	var action := settings_menu.rebinding
	if InputActions.rebind(action, event):
		InputActions.save_overrides()
		overlay.toast(Loc.t("%s is now %s") % [action.replace("_", " "), InputActions.describe(action)], 2.5)
	settings_menu.rebinding = ""
	refresh_settings()
	return true


# --- audio ------------------------------------------------------------------

## Music for where the party is: the title, the Bastion, a biome, or a fight.
func refresh_music() -> void:
	if audio == null:
		return
	var act := act_number()
	if in_title():
		audio.set_state("title", "", act)
	elif mode == "combat":
		audio.set_state("combat", "", act, "boss" if boss_engaged() else "")
	elif map_id == home_map and not map_entry.has("generation"):
		audio.set_state("bastion", "", act)
	else:
		audio.set_state("explore", map_data.biome_id if map_data != null else "", act)


## A boss is in the fight (the music's "boss" variant, S57).
func boss_engaged() -> bool:
	for e: EnemyActor in engaged_enemies():
		if String(e.tier) == "boss":
			return true
	return false


## The footstep sound of a cell: the tile's own `sound`, else the default.
func footstep_sound(cell: Vector2i) -> String:
	var tile := map_data.tile_at(cell)
	var own := String(tile.get("sound", ""))
	if not own.is_empty():
		return own
	return String(Dictionary(audio.rules.get("explore", {})).get("footstep", ""))


func play_sound(id: String) -> void:
	if audio != null:
		audio.play(id)


func play_event(path: String) -> void:
	if audio != null:
		audio.event(path)



# --- platform: achievements and cloud saves ---------------------------------

var _local_platform: PlatformService


## The Platform autoload, or a local service when the scene runs alone.
func platform() -> PlatformService:
	var service := get_node_or_null("/root/Platform") as PlatformService
	if service != null:
		return service
	if _local_platform == null:
		_local_platform = PlatformService.new()
		_local_platform.name = "LocalPlatform"
		add_child(_local_platform)
	return _local_platform


## Unlocks every achievement whose conditions now hold. Called at story
## beats (every autosave) and after banking. Returns the ids unlocked now.
func check_achievements() -> Array[String]:
	var service := platform()
	var entries: Array[Dictionary] = registry.get_all("achievements")
	var due := PlatformService.due_achievements(entries, dialogue_ctx(), service.backend)
	var got: Array[String] = []
	for id: String in due:
		if service.unlock_achievement(id):
			got.append(id)
			overlay.toast(Loc.t("Achievement: %s") % registry.get_entry("achievements", id).get("name", id), 3.0)
	return got


## Quest stages that declare `next` advance once every objective of the
## current stage is done: the data hand-off between beats (D-081), so no
## map trigger has to know the quest. A stage may also declare `branches`
## ([{"when": conditions, "next": stage, "toast"?}], S36): the first whose
## conditions hold wins, `next` is the fallback, and a stage with branches
## but no objectives forks as soon as one holds. Runs before every autosave, so the
## save carries the new stage. Returns the quest ids that moved.
func advance_quests() -> Array[String]:
	var moved: Array[String] = []
	# Quests with `start_when` (S40, D-095) begin at their start stage when the conditions first hold.
	for q: Dictionary in registry.get_all("quests"):
		if q.has("start_when") and narrative.stage_of(String(q["id"])).is_empty() and Conditions.passes(q["start_when"], dialogue_ctx()):
			narrative.set_stage(String(q["id"]), String(q.get("start", "")))
			moved.append(String(q["id"]))
			log_quest(String(q["id"]), String(q.get("start_toast", "")))
			if q.has("start_toast") and overlay != null:
				overlay.toast(Loc.any(String(q["start_toast"])), 4.0)
	for _pass: int in 8: # a stage may complete the next one at once
		var moved_now := false
		var ctx := dialogue_ctx()
		var ids: Array = narrative.quests.keys()
		ids.sort()
		for quest_id: String in ids:
			var quest: Dictionary = registry.get_entry("quests", quest_id)
			var stages: Dictionary = quest.get("stages", {})
			var stage: Dictionary = stages.get(narrative.stage_of(quest_id), {})
			var next := String(stage.get("next", ""))
			var branches: Array = stage.get("branches", [])
			if next.is_empty() and branches.is_empty():
				continue
			var objectives: Array = stage.get("objectives", [])
			if objectives.is_empty() and branches.is_empty():
				continue # a bare `next` needs objectives to finish; a fork stage may have none
			var done := true
			for o: Dictionary in objectives:
				if not Conditions.passes(o.get("done_when", {}), ctx):
					done = false
					break
			if not done:
				continue
			# Branches (S36, D-091): the first whose `when` holds wins; `next` is the fallback.
			var target := ""
			var toast := String(stage.get("next_toast", ""))
			for b: Dictionary in branches:
				if Conditions.passes(b.get("when", {}), ctx):
					target = String(b.get("next", ""))
					toast = String(b.get("toast", toast))
					break
			if target.is_empty():
				target = next
			if target.is_empty() or not stages.has(target):
				continue
			narrative.set_stage(quest_id, target)
			moved.append(quest_id)
			moved_now = true
			log_quest(quest_id, toast)
			if not toast.is_empty() and overlay != null:
				overlay.toast(Loc.any(toast), 4.0)
		if not moved_now:
			break
	return moved



# --- items: the pack, equipment, drops, crafting (S29, D-084) ---------------

func inventory_slots(m: PartyMember) -> Array[String]:
	return ItemSystem.slot_keys(registry, registry.get_entry("races", m.race_id))


func equipment_of(member_id: String) -> Dictionary:
	return Dictionary(ledger.builds.get(member_id, {})).get("equipment", {})


## Moves a banked instance (by uid) into a slot of a member; whatever was
## there goes back to the pack. Empty string on success, else the reason.
func equip(member_id: String, slot_key: String, uid: int) -> String:
	var m := member_by_id(member_id)
	if m == null:
		return Loc.t("no such member")
	if not inventory_slots(m).has(slot_key):
		return Loc.t("no such slot")
	var i := ItemSystem.find_uid(ledger.items, uid)
	if i < 0:
		return Loc.t("not in the pack")
	var inst: Dictionary = ledger.items[i]
	if not ItemSystem.fits(registry, inst, slot_key):
		return Loc.t("does not fit the %s slot") % ItemSystem.slot_base(slot_key)
	var b := build_for(member_id)
	var equipment: Dictionary = Dictionary(b.get("equipment", {})).duplicate(true)
	if equipment.has(slot_key):
		ledger.items.append(equipment[slot_key])
	ledger.items.remove_at(i)
	equipment[slot_key] = inst
	b["equipment"] = equipment
	ledger.builds[member_id] = b
	ledger.save()
	refresh_progression()
	return ""


func unequip(member_id: String, slot_key: String) -> String:
	var b := build_for(member_id)
	var equipment: Dictionary = Dictionary(b.get("equipment", {})).duplicate(true)
	if not equipment.has(slot_key):
		return Loc.t("nothing there")
	ledger.items.append(equipment[slot_key])
	equipment.erase(slot_key)
	b["equipment"] = equipment
	ledger.builds[member_id] = b
	ledger.save()
	refresh_progression()
	return ""


## Why an item cannot be crafted now; empty when it can.
func craft_reason(item_id: String) -> String:
	var item := registry.get_entry("items", item_id)
	var recipe: Dictionary = item.get("craft", {})
	if item.is_empty() or recipe.is_empty():
		return Loc.t("not craftable")
	if not at_home():
		return Loc.t("only at home")
	var need := int(recipe.get("workshop", 1))
	if bastion.level("workshop") < need:
		return Loc.t("needs Workshop level %d") % need
	if not ledger.can_afford(recipe.get("cost", {})):
		return Loc.t("needs %s") % BastionState.describe_cost(recipe.get("cost", {}))
	return ""


## Crafts a common instance at the Workshop into the pack.
func craft(item_id: String) -> String:
	var why := craft_reason(item_id)
	if not why.is_empty():
		return why
	var item := registry.get_entry("items", item_id)
	ledger.spend(Dictionary(item.get("craft", {})).get("cost", {}))
	ledger.items.append(ItemSystem.make(item_id, [], "common", int(randi())))
	ledger.save()
	return ""


## Rolls an item drop of `rarity` into the run haul (banked at once off-Shard).
func drop_item(rarity: String, family: String = "") -> Dictionary:
	var inst := ItemSystem.roll_drop(registry, run.rng, rarity, family)
	if inst.is_empty():
		return inst
	run.items.append(inst)
	if not run.in_shard:
		_bank(run.take(), false)
		run.clear()
	return inst


## Drop chance and rarity for an enemy by tier (`rules/loot`); the entry's
## own `loot.item_chance` / `loot.item_rarity` win when present.
func roll_enemy_drop(enemy: EnemyActor) -> Dictionary:
	var loot: Dictionary = enemy.entry.get("loot", {})
	var tier := enemy.tier if not enemy.tier.is_empty() else "normal"
	var chance := float(loot.get("item_chance", Dictionary(loot_rules().get("drop_chance_by_tier", {})).get(tier, 0.0)))
	if chance <= 0.0 or run.rng.randf() >= chance:
		return {}
	var rarity := String(loot.get("item_rarity", Dictionary(loot_rules().get("drop_rarity_by_tier", {})).get(tier, "common")))
	return drop_item(rarity, String(enemy.entry.get("family", "")))


func open_inventory() -> bool:
	if inventory_menu == null or mode != "explore" or not at_home() or in_dialogue():
		return false
	if (creator_menu != null and creator_menu.visible) or (bastion_menu != null and bastion_menu.visible) or (weave_menu != null and weave_menu.visible):
		return false
	if system_menu != null:
		system_menu.close()
	inventory_menu.member_index = clampi(inventory_menu.member_index, 0, party.members.size() - 1)
	refresh_inventory()
	return true


func close_inventory() -> void:
	if inventory_menu != null:
		inventory_menu.close()


func inventory_member(delta: int) -> void:
	if inventory_menu == null or party.members.is_empty():
		return
	inventory_menu.member_index = posmod(inventory_menu.member_index + delta, party.members.size())
	inventory_menu.cursor = 0
	refresh_inventory()


func refresh_inventory() -> void:
	if inventory_menu == null or party.members.is_empty():
		return
	var m := party.members[clampi(inventory_menu.member_index, 0, party.members.size() - 1)]
	var eq := ItemSystem.equipment_mods(registry, equipment_of(m.member_id))
	var header := Loc.t("%s · pack %d\n%s — %s %s · HP %d/%d · move %d · evasion %d · initiative %d · from gear: %s") % [
		ledger.summary(), ledger.items.size(), m.display_name, Loc.text(registry.get_entry("races", m.race_id), "name", m.race_id),
		Loc.text(registry.get_entry("classes", m.class_id), "name", m.class_id), m.hp, m.max_hp, int(m.stats.get("move", 0)), int(m.stats.get("evasion", 0)), int(m.stats.get("initiative", 0)), ItemSystem.describe_mods(eq)]
	inventory_menu.show_rows(header, inventory_rows(m.member_id))


func inventory_rows(member_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var m := member_by_id(member_id)
	if m == null:
		return rows
	var equipment := equipment_of(member_id)
	var slots := inventory_slots(m)
	for slot_key: String in slots:
		var held: Dictionary = equipment.get(slot_key, {})
		var label := Loc.t("%s: %s") % [Loc.t(slot_key.capitalize()), ItemSystem.describe(registry, held) if not held.is_empty() else Loc.t("empty")]
		rows.append({"kind": "slot", "id": slot_key, "label": label, "enabled": not held.is_empty(), "why": Loc.t("empty")})
	for inst: Dictionary in ledger.items:
		var fits := false
		for slot_key: String in slots:
			if ItemSystem.fits(registry, inst, slot_key):
				fits = true
		var slot_name := String(registry.get_entry("items", String(inst.get("item", ""))).get("slot", "?"))
		rows.append({"kind": "item", "id": int(inst.get("uid", 0)), "label": ItemSystem.describe(registry, inst), "enabled": fits, "why": Loc.t("no %s slot") % slot_name})
	for item: Dictionary in registry.get_all("items"):
		if not item.has("craft"):
			continue
		var why := craft_reason(String(item["id"]))
		var recipe: Dictionary = item["craft"]
		rows.append({"kind": "craft", "id": String(item["id"]), "label": Loc.t("%s (%s): %s — %s") % [Loc.text(item, "name", String(item["id"])), Loc.t(String(item.get("slot", "?"))), ItemSystem.describe_mods(ItemSystem.mods(registry, ItemSystem.make(String(item["id"])))), BastionState.describe_cost(recipe.get("cost", {}))], "enabled": why.is_empty(), "why": why})
	return rows


## Enter / A on the pack screen: unequip a slot, equip a pack item into an
## empty slot that fits (else swap into the first that fits), or craft.
func confirm_inventory() -> bool:
	if inventory_menu == null or not inventory_menu.visible or party.members.is_empty():
		return false
	var row := inventory_menu.selected()
	if row.is_empty():
		return false
	var m := party.members[clampi(inventory_menu.member_index, 0, party.members.size() - 1)]
	var why := ""
	match String(row.get("kind", "")):
		"slot":
			why = unequip(m.member_id, String(row["id"]))
		"item":
			var uid := int(row["id"])
			var i := ItemSystem.find_uid(ledger.items, uid)
			if i < 0:
				why = "not in the pack"
			else:
				var equipment := equipment_of(m.member_id)
				var target := ""
				for slot_key: String in inventory_slots(m):
					if not ItemSystem.fits(registry, ledger.items[i], slot_key):
						continue
					if target.is_empty() or (equipment.has(target) and not equipment.has(slot_key)):
						target = slot_key
				why = equip(m.member_id, target, uid) if not target.is_empty() else Loc.t("no slot fits")
		"craft":
			why = craft(String(row["id"]))
	if not why.is_empty():
		overlay.toast(Loc.t("%s: %s") % [row.get("label", row.get("id", "")), why], 2.0)
	refresh_inventory()
	return why.is_empty()


## Sum of a numeric trait across the living party (D-085): salvage_bonus etc.
func party_trait_total(key: String) -> float:
	var total := 0.0
	for m: PartyMember in party.members:
		if not m.downed:
			total += float(m.traits.get(key, 0.0))
	return total



# --- multiclassing (S31, D-086) ---------------------------------------------

## Takes a second class for a member (from `multiclass_level`); levels move
## into it one at a time with `add_multiclass_level`. Empty string on
## success, else the reason.
func choose_multiclass(member_id: String, class_id: String) -> String:
	var m := member_by_id(member_id)
	if m == null:
		return Loc.t("no such member")
	var cls: Dictionary = registry.get_entry("classes", m.class_id)
	var why := Progression.can_multiclass(registry, cls, party_level(), build_for(member_id), class_id, progression_rules(), can_respec())
	if not why.is_empty():
		return why
	var b := build_for(member_id)
	b["multiclass"] = {"class": class_id, "levels": 0}
	ledger.builds[member_id] = b
	ledger.save()
	refresh_progression()
	return ""


func add_multiclass_level(member_id: String) -> String:
	if member_by_id(member_id) == null:
		return Loc.t("no such member")
	var b := build_for(member_id)
	var why := Progression.can_add_multiclass_level(party_level(), b, progression_rules())
	if not why.is_empty():
		return why
	var mc: Dictionary = b["multiclass"]
	mc["levels"] = int(mc.get("levels", 0)) + 1
	b["multiclass"] = mc
	ledger.builds[member_id] = b
	ledger.save()
	refresh_progression()
	return ""


## "Scrap-Knight 7 / Aetherbinder 3" for headers.
func class_levels_text(member_id: String) -> String:
	var m := member_by_id(member_id)
	if m == null:
		return ""
	var split := Progression.class_levels(party_level(), build_for(member_id), progression_rules())
	var text := Loc.t("%s %d") % [registry.get_entry("classes", m.class_id).get("name", m.class_id), int(split["main"])]
	if int(split["second"]) > 0:
		text += Loc.t(" / %s %d") % [registry.get_entry("classes", String(split["class"])).get("name", split["class"]), int(split["second"])]
	return text


## Rows for the second class: take one (any other class) and put levels into it.
func multiclass_rows(member_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var m := member_by_id(member_id)
	if m == null:
		return rows
	var cls: Dictionary = registry.get_entry("classes", m.class_id)
	var build := build_for(member_id)
	var level := party_level()
	var prules := progression_rules()
	var current := String(Dictionary(build.get("multiclass", {})).get("class", ""))
	for other: Dictionary in registry.get_all("classes"):
		var id := String(other["id"])
		if id == m.class_id:
			continue
		var why := Progression.can_multiclass(registry, cls, level, build, id, prules, can_respec())
		var label := Loc.t("Second class: %s") % Loc.text(other, "name", id)
		if current == id:
			label = "✓ " + label
		rows.append({"kind": "multiclass", "id": id, "label": label, "enabled": why.is_empty(), "why": why})
	if not current.is_empty():
		var why := Progression.can_add_multiclass_level(level, build, prules)
		var split := Progression.class_levels(level, build, prules)
		rows.append({"kind": "multiclass_level", "id": member_id, "label": Loc.t("Put a level into %s (%d there, %d in %s)") % [Loc.text(registry.get_entry("classes", current), "name", current), int(split["second"]), int(split["main"]), cls.get("name", m.class_id)], "enabled": why.is_empty(), "why": why})
	return rows


# --- factions v2: joining (S32, D-087) ---------------------------------------

## Commits the party to a faction: exclusive, gated on the act flag the
## faction names (`joinable_act`), moves reputation by the faction's
## `join_reputation` so every companion reacts per the casting rule
## (D-074), and opens its area and vendor through `faction` conditions.
## Empty string on success, else the reason.
func join_faction(id: String) -> String:
	var f: Dictionary = registry.get_entry("factions", id)
	if f.is_empty():
		return Loc.t("no such faction")
	if narrative.has_joined():
		return Loc.t("already sworn to %s") % faction_name(narrative.faction)
	var act_flag := "act%d" % int(f.get("joinable_act", 2))
	if not narrative.flag(act_flag):
		return Loc.t("not before %s") % act_flag
	narrative.join_faction(id)
	var deltas: Dictionary = f.get("join_reputation", {id: 3})
	Conditions.apply({"reputation": deltas}, narrative)
	react_to_reputation({"reputation": deltas})
	overlay.toast(Loc.t("You have joined %s.") % faction_name(id), 4.0)
	autosave()
	return ""


## Runs a `join_faction` effect key from a dialogue choice or a trigger.
func handle_join_effect(effects: Dictionary) -> void:
	var id := String(effects.get("join_faction", ""))
	if id.is_empty():
		return
	var why := join_faction(id)
	if not why.is_empty():
		overlay.toast(Loc.t("Cannot join %s: %s") % [faction_name(id), why], 3.0)



# --- Bastion v2: the Archive, the Garden, the Quarters, the account (S35, D-090)

## Every lore fragment in history order, marked found or not.
func archive_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in registry.get_all("lore"):
		out.append({"id": String(f["id"]), "name": Loc.text(f, "name", String(f["id"])), "order": int(f.get("order", 0)), "source": Loc.text(f, "source"), "text": Loc.text(f, "text"), "found": narrative.lore.has(String(f["id"]))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["order"]) != int(b["order"]):
			return int(a["order"]) < int(b["order"])
		return String(a["id"]) < String(b["id"]))
	return out


func archive_text() -> String:
	return ArchiveMenu.render(archive_entries(), bastion.level("archive"))


## The first fragment in history order not yet found, or "" when the record is complete.
func next_lore_fragment() -> String:
	for e: Dictionary in archive_entries():
		if not bool(e["found"]):
			return String(e["id"])
	return ""


## Brings a fragment home: found in a Shard it rides the story, not the
## haul (a wipe never loses it); the Archive at level 2 pays an Aether of
## insight per fragment. Returns the fragment id, "" when none is left.
func find_lore() -> String:
	var id := next_lore_fragment()
	if id.is_empty():
		return ""
	narrative.lore.append(id)
	var insight := int(bastion.effect("aether_per_fragment", 0.0))
	if insight > 0:
		ledger.bank({"aether": insight})
		ledger.save()
	overlay.toast(Loc.t("Fragment: %s") % Loc.text(registry.get_entry("lore", id), "name", id), 3.0)
	return id


func open_archive() -> bool:
	if archive_menu == null or mode != "explore" or not at_home() or in_dialogue():
		return false
	if system_menu != null:
		system_menu.close()
	archive_menu.show_text(archive_text())
	return true


func close_archive() -> void:
	if archive_menu != null:
		archive_menu.close()


## Tending the Garden: the extra heal its level grants, doubled for Rootkin
## (regen_on_surface is their trait; the Garden is overgrowth by design).
func tend_garden() -> bool:
	if bastion.level("garden") <= 0:
		overlay.toast(Loc.t("The Garden is one stubborn vine. Raise it at the Workshop."), 2.5)
		return false
	var garden: Dictionary = Dictionary(bastion.buildings.get("garden", {})).get("levels", [])[bastion.level("garden")].get("effects", {})
	var fraction := float(garden.get("heal_fraction", 0.0))
	for m: PartyMember in party.members:
		var f := fraction * (2.0 if m.traits.has("regen_on_surface") else 1.0)
		if not m.downed and m.hp < m.max_hp:
			m.hp = mini(m.max_hp, m.hp + int(ceil(m.max_hp * f)))
	overlay.toast(Loc.t("The Garden closes what it can."), 2.0)
	return true


## Companions with a Quarters scene they qualify for and have not had.
## A scene marked `dead` is for a companion who died (`<id>_dead`) rather
## than one in the party. A scene marked `romance` is offered only by a
## romanceable companion and only while nobody else holds the leader's
## heart: exclusivity without jealousy (D-092). `once: false` leaves a
## scene on the list until its own `requires` close it.
func quarters_scenes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ctx := dialogue_ctx()
	for c: Dictionary in registry.get_all("companions"):
		var id := String(c["id"])
		for scene: Dictionary in c.get("scenes", []):
			var scene_id := String(scene.get("id", ""))
			if scene_id.is_empty():
				continue
			if bool(scene.get("dead", false)):
				if not narrative.flag("%s_dead" % id):
					continue
			elif not narrative.is_recruited(id):
				continue
			if bool(scene.get("romance", false)):
				if not bool(c.get("romanceable", false)):
					continue
				if not narrative.romance.is_empty() and narrative.romance != id:
					continue
			if bool(scene.get("once", true)) and narrative.flag("scene_%s_seen" % scene_id):
				continue
			if int(scene.get("quarters", 1)) > bastion.level("quarters"):
				continue
			if not Conditions.passes(scene.get("requires", {}), ctx):
				continue
			out.append({"companion": id, "scene": scene_id, "dialogue": String(scene.get("dialogue", "")), "label": Loc.t("%s — %s") % [Loc.text(c, "short_name", id), Loc.any(String(scene.get("label", scene_id)))]})
	return out


## The Quarters from the Bastion screen: the same Roster screen (S52),
## once the Quarters stand.
func open_quarters() -> bool:
	if mode != "explore" or not at_home():
		return false
	if bastion.level("quarters") <= 0:
		overlay.toast(Loc.t("Bunks in a container. Raise the Quarters at the Workshop."), 2.5)
		return false
	if bastion_menu != null:
		bastion_menu.visible = false
	return open_roster()


## Plays a Quarters scene by id; it is marked seen when it opens.
func play_scene(scene_id: String) -> bool:
	for s: Dictionary in quarters_scenes():
		if String(s["scene"]) != scene_id:
			continue
		narrative.set_flag("scene_%s_seen" % scene_id, true)
		return open_dialogue(String(s["dialogue"]))
	return false


# --- saves screen (S54, D-109) ----------------------------------------------

## What a save is called in the lists: who leads, where, which act, what level.
func save_title() -> String:
	var who := party.leader().display_name if party.leader() != null else Loc.t("The Weaver")
	return Loc.t("%s · %s · Act %d · level %d") % [who, Loc.any(map_data.name), act_number(), party_level()]


## 1 until first contact, 2 until the catastrophe, 3 after.
func act_number() -> int:
	if narrative.flag("catastrophe_seen"):
		return 3
	if narrative.flag("act2"):
		return 2
	return 1


## The rows of the saves screen: the three slots on the save page; the
## slots, the autosave and its older copies on the load page.
func saves_rows(page: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var listing := SaveSystem.list_saves(saves_dir, registry, page == SavesMenu.PAGE_LOAD)
	for row: Dictionary in listing:
		var save_name := String(row["name"])
		var is_slot := save_name.begins_with("slot_")
		if page == SavesMenu.PAGE_SAVE and not is_slot:
			continue
		var exists := bool(row["exists"])
		var what := Loc.t("Slot %s") % save_name.get_slice("_", 1) if is_slot else (Loc.t("Autosave") if save_name == SaveSystem.AUTOSAVE else Loc.t("Older autosave %s") % save_name.get_slice("_", 1))
		var title := String(row.get("title", ""))
		var label := Loc.t("%s — %s") % [what, title if not title.is_empty() else (String(row["summary"]) if exists else Loc.t("empty"))]
		var detail := ""
		if exists:
			detail = "%s · %s" % [String(row.get("saved_at", "")), String(row["summary"])]
		var enabled := true
		var why := ""
		if page == SavesMenu.PAGE_LOAD:
			enabled = bool(row["loadable"]) and reload_allowed()
			why = Loc.t("Iron Weave: no reloads") if not reload_allowed() else (Loc.t("needs a new game") if exists else Loc.t("empty"))
		else:
			enabled = mode != "combat" and reload_allowed()
			why = Loc.t("Iron Weave: one save") if not reload_allowed() else Loc.t("in combat")
		rows.append({"id": save_name, "label": label, "detail": detail, "enabled": enabled, "why": why, "exists": exists, "thumbnail": String(row.get("thumbnail", ""))})
	rows.append({"id": "back", "label": Loc.t("Back"), "enabled": true, "exists": false})
	return rows


## Opens the saves screen on a page: from the pause menu, or from the
## title's Load (which it returns to).
func open_saves(page: String) -> bool:
	if saves_menu == null or mode == "combat":
		return false
	if system_menu != null:
		system_menu.close()
	saves_menu.open(page, saves_rows(page))
	return true


## Esc: answers "no" to an overwrite, else closes (back to the title when
## it came from there).
func cancel_saves() -> void:
	if saves_menu == null:
		return
	if not saves_menu.pending.is_empty():
		saves_menu.pending = ""
		saves_menu.refresh()
		return
	saves_menu.close()
	if _saves_return_to_title:
		_saves_return_to_title = false
		show_title()


## Enter on the saves screen: saves into the slot (asking first when it
## holds something), or loads the row, or backs out.
func activate_saves_row() -> bool:
	if saves_menu == null or not saves_menu.visible:
		return false
	var row := saves_menu.selected()
	var id := String(row.get("id", ""))
	if id == "back" or id.is_empty():
		cancel_saves()
		return true
	if not bool(row.get("enabled", true)):
		return false
	if saves_menu.page == SavesMenu.PAGE_SAVE:
		if bool(row.get("exists", false)) and saves_menu.pending != id:
			saves_menu.pending = id # ask first
			saves_menu.refresh()
			return true
		saves_menu.pending = ""
		var ok := save_slot(int(id.get_slice("_", 1))) == OK
		if ok:
			saves_menu.open(SavesMenu.PAGE_SAVE, saves_rows(SavesMenu.PAGE_SAVE), true)
		return ok
	var errors := load_from(id)
	if errors.is_empty():
		_saves_return_to_title = false
		saves_menu.close()
		return true
	saves_menu.refresh()
	return false


# --- surfaces: faces, the history, quest tracking, the Roster screen (S52, D-107) ---

## A face for a speaker id: the leader for "player", a companion by race
## and class, an NPC by its art colour; null for the narrator, the Choir
## and anyone else without a body. Built once per world.
func portrait_for(speaker: String) -> ImageTexture:
	if speaker.is_empty() or speaker == "narrator":
		return null
	if speaker == "player":
		var l := party.leader()
		if l == null:
			return null
		var race: Dictionary = registry.get_entry("races", l.race_id)
		return PlaceholderActorArt.portrait_texture(PartyBuilder.class_color(registry, l.class_id), race.get("overlay", {}), l.appearance)
	if _portraits.has(speaker):
		return _portraits[speaker]
	var tex: ImageTexture = null
	var c: Dictionary = registry.get_entry("companions", speaker)
	if not c.is_empty():
		var race: Dictionary = registry.get_entry("races", String(c.get("race", "")))
		tex = PlaceholderActorArt.portrait_texture(PartyBuilder.class_color(registry, String(c.get("class", ""))), race.get("overlay", {}))
	else:
		var n: Dictionary = registry.get_entry("npcs", speaker)
		if not n.is_empty():
			var art: Dictionary = n.get("art", {})
			var race: Dictionary = registry.get_entry("races", String(n.get("race", "")))
			tex = PlaceholderActorArt.portrait_texture(Color.html(String(art.get("color", "#9a9a9a"))), race.get("overlay", {}))
	_portraits[speaker] = tex
	return tex


## The face the panel shows: the speaker's, else the voice's (the Choir in
## Sera's voice wears Sera's face).
func face_for(speaker: String, voice: String = "") -> ImageTexture:
	var face := portrait_for(speaker)
	if face == null and not voice.is_empty():
		face = portrait_for(voice)
	return face


## The lines of the open talk so far, without the one on screen.
func talk_history() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stop := narrative.log.size() - 1
	for i: int in range(_talk_log_start, stop):
		out.append(narrative.log[i])
	return out


## Writes the open dialogue's current line into the history.
func log_node() -> void:
	if not in_dialogue():
		return
	var names := speaker_names()
	var who := String(names.get(dialogue.speaker(), dialogue.speaker().capitalize()))
	if not dialogue.voice().is_empty():
		who = "%s, in %s's voice" % [who, String(names.get(dialogue.voice(), dialogue.voice().capitalize()))]
	narrative.log_line(who, dialogue.text())


## Writes a quest start or stage change into the history: the toast when
## the content wrote one, else the stage's summary.
func log_quest(quest_id: String, toast: String) -> void:
	var quest: Dictionary = registry.get_entry("quests", quest_id)
	var stage: Dictionary = Dictionary(quest.get("stages", {})).get(narrative.stage_of(quest_id), {})
	var text := Loc.any(toast) if not toast.is_empty() else Loc.content("quests", quest_id, "stages.%s.summary" % narrative.stage_of(quest_id), String(stage.get("summary", "")))
	if text.is_empty():
		return
	narrative.log_line(Loc.t("Journal"), "%s — %s" % [Loc.text(quest, "name", quest_id), text])


## The quest the HUD tracks: the one chosen in the journal while it is
## still active, else the first active main quest, else the first active.
## The fallback sticks (it is written to the narrative), so a quest that
## starts later does not steal the line until the player moves the mark.
func tracked_quest_id() -> String:
	var entries := journal_entries()
	for e: Dictionary in entries:
		if String(e["id"]) == narrative.tracked_quest and not bool(e["complete"]):
			return narrative.tracked_quest
	var pick := ""
	for e: Dictionary in entries:
		if bool(e["main"]) and not bool(e["complete"]):
			pick = String(e["id"])
			break
	if pick.is_empty():
		for e: Dictionary in entries:
			if not bool(e["complete"]):
				pick = String(e["id"])
				break
	narrative.tracked_quest = pick
	return pick


## The HUD's fourth line: "★ Waking — the stage · the next thing to do".
func tracking_line() -> String:
	var id := tracked_quest_id()
	if id.is_empty():
		return ""
	for e: Dictionary in journal_entries():
		if String(e["id"]) != id:
			continue
		var next := ""
		for o: Dictionary in e["objectives"]:
			if not bool(o["done"]):
				next = String(o["text"])
				break
		var line := Loc.t("%s %s — %s") % ["★" if bool(e["main"]) else "•", e["name"], e["stage_summary"]]
		return line if next.is_empty() else Loc.t("%s · %s") % [line, next]
	return ""


## ←→ in the journal: the next active quest becomes the tracked one (saved).
func track_next_quest(delta: int) -> String:
	var active: Array[String] = []
	for e: Dictionary in journal_entries():
		if not bool(e["complete"]):
			active.append(String(e["id"]))
	if active.is_empty():
		return ""
	var i := active.find(tracked_quest_id())
	narrative.tracked_quest = active[posmod(i + delta, active.size())]
	if journal_menu != null and journal_menu.visible:
		journal_menu.show_text(journal_text())
	return narrative.tracked_quest


## The Roster screen's rows: one per companion the story has given you
## (walking, waiting, or fallen), then that companion's Quarters scenes
## while the Quarters stand; a note when they do not.
func roster_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var room := narrative.active_companions().size() < rules.party_max - 1
	var scenes: Array[Dictionary] = []
	if bastion.level("quarters") > 0:
		scenes = quarters_scenes()
	var ids: Array[String] = []
	for c: Dictionary in registry.get_all("companions"):
		var id := String(c["id"])
		if narrative.is_recruited(id) or narrative.flag("%s_dead" % id):
			ids.append(id)
	for id: String in ids:
		var c: Dictionary = registry.get_entry("companions", id)
		var name := Loc.text(c, "short_name", id)
		var dead := narrative.flag("%s_dead" % id)
		var tags: PackedStringArray = []
		if narrative.romance == id:
			tags.append("your partner")
		elif narrative.flag("romance_%s_lost" % id):
			tags.append("what was")
		if narrative.flag("%s_loyal" % id):
			tags.append("loyal")
		var status := "fallen" if dead else (Loc.t("waits at the Bastion") if narrative.is_benched(id) else Loc.t("walks with you"))
		var label := Loc.t("%s — %s · ♥%+d%s") % [name, status, narrative.approval_of(id), "" if tags.is_empty() else " · " + " · ".join(tags)]
		var row: Dictionary = {"id": "companion:%s" % id, "kind": "companion", "companion": id, "label": label, "enabled": true, "portrait": portrait_for(id), "dead": dead}
		if dead:
			row["toggle"] = ""
		elif narrative.is_benched(id):
			row["toggle"] = "take"
			row["enabled"] = true
			row["can_toggle"] = room
			row["why"] = "the party is full"
		else:
			row["toggle"] = "bench"
			row["can_toggle"] = true
		rows.append(row)
		for s: Dictionary in scenes:
			if String(s["companion"]) == id:
				rows.append({"id": "scene:%s" % s["scene"], "kind": "scene", "companion": id, "scene": String(s["scene"]), "label": Loc.t("    ↳ %s") % String(s["label"]).get_slice(" — ", 1), "enabled": true})
	if not ids.is_empty() and bastion.level("quarters") <= 0:
		rows.append({"id": "note", "kind": "note", "label": Loc.t("Bunks in a container: raise the Quarters at the Workshop for their scenes."), "enabled": false, "why": Loc.t("no Quarters yet")})
	rows.append({"id": "close", "kind": "note", "label": Loc.t("Done"), "enabled": true})
	return rows


func close_roster() -> void:
	if roster_menu != null:
		roster_menu.close()


## Enter on the Roster: a companion row swaps walking and waiting, a scene
## row plays the scene, Done closes.
func activate_roster_row() -> bool:
	if roster_menu == null or not roster_menu.visible:
		return false
	var row := roster_menu.selected()
	match String(row.get("kind", "")):
		"companion":
			return roster_toggle()
		"scene":
			close_roster()
			return play_scene(String(row.get("scene", "")))
		_:
			if String(row.get("id", "")) == "close":
				close_roster()
				return true
	return false


## ←→ on the Roster: the companion under the cursor walks or waits.
func roster_toggle() -> bool:
	if roster_menu == null or not roster_menu.visible:
		return false
	var row := roster_menu.selected()
	var id := roster_menu.selected_companion()
	if id.is_empty() or bool(row.get("dead", false)):
		return false
	var ok := false
	match String(row.get("toggle", "")):
		"bench":
			ok = bench_companion(id)
		"take":
			if not bool(row.get("can_toggle", true)):
				overlay.toast(Loc.t("The party is full: leave someone at the Bastion first."), 2.5)
				return false
			ok = take_companion(id)
	if ok:
		roster_menu.open(roster_rows(), true)
	return ok


## Keys this playthrough has earned for the account (origins by flag).
func grant_account_unlocks() -> Array[String]:
	if account == null:
		return []
	var fresh := account.grant_from(narrative, registry)
	for key: String in fresh:
		var origin := registry.get_entry("origins", key.get_slice(":", 1))
		overlay.toast(Loc.t("Unlocked for every playthrough: %s") % origin.get("name", key), 4.0)
	return fresh



# --- campaign tooling v2: sequences, map edits, endings (S36, D-091) ---------

## Applies one effects block: the trigger vocabulary (approval, flags,
## recruit, quest, reputation, romance, join_faction, victory_flag, grant,
## lore, toast, open_doors, enemies, dialogue, transition) plus map_edits,
## sequence and ending. Triggers and sequence steps come here whole;
## dialogue choices apply the story part in the runner and the world part
## through `_apply_world_effects` (S39).
func apply_effects(effects: Dictionary) -> void:
	for companion: String in Conditions.apply(effects, narrative):
		add_companion(companion)
	_apply_world_effects(effects)


## Everything in an effects block that touches the world rather than the
## story: reputation reactions, joining, flags set on victory, loot, a lore
## fragment by id, toasts, doors, a fight (`enemies` cells are map cells, or
## `offset` from the leader so a Shard-site dialogue can spawn around the
## party), a dialogue (never over an open one), a transition, map edits, a
## sequence, the ending.
func _apply_world_effects(effects: Dictionary) -> void:
	react_to_reputation(effects)
	handle_join_effect(effects)
	if effects.has("victory_flag"):
		var vf: Variant = effects["victory_flag"]
		pending_victory_flags = []
		if vf is Array:
			for f: Variant in vf:
				pending_victory_flags.append(String(f))
		else:
			pending_victory_flags.append(String(vf))
		pending_victory_flag = pending_victory_flags[0] if not pending_victory_flags.is_empty() else ""
	if effects.has("dismiss"):
		_drop_member(String(effects["dismiss"])) # the story took someone (S41)
	if effects.has("grant"):
		var got := _gain(effects["grant"])
		overlay.toast(Loc.t("Found: %s") % RunState.describe(got), 2.5)
	if effects.has("lore"):
		find_lore_by_id(String(effects["lore"]))
	if effects.has("toast"):
		overlay.toast(Loc.any(String(effects["toast"])), 3.5)
	for raw: Array in effects.get("open_doors", []):
		open_door(Vector2i(int(raw[0]), int(raw[1])))
	for edit: Dictionary in effects.get("map_edits", []):
		apply_map_edit(edit)
	var placed: Array = effects.get("enemies", [])
	if not placed.is_empty():
		var taken: Array[Vector2i] = []
		for m: PartyMember in party.members:
			taken.append(member_cell(m))
		for e: EnemyActor in living_enemies():
			taken.append(e.cell)
		for p: Dictionary in placed:
			var entry: Dictionary = registry.get_entry("enemies", String(p.get("type", "")))
			if entry.is_empty():
				continue
			var cell := Vector2i(-1, -1)
			if p.has("offset"):
				var off: Array = p["offset"]
				var want := leader_cell() + Vector2i(int(off[0]), int(off[1]))
				if map_data.is_walkable(want) and not taken.has(want):
					cell = want
				else: # the offset hit a wall or a body: the nearest free cell to the leader instead (a wall seeds no search)
					var free := map_data.nearest_free_cells(leader_cell(), 1, taken)
					cell = free[0] if not free.is_empty() else Vector2i(-1, -1)
			else:
				var raw: Array = p.get("cell", [0, 0])
				cell = Vector2i(int(raw[0]), int(raw[1]))
			if cell.x < 0 or not map_data.is_walkable(cell) or enemy_at(cell) != null:
				continue
			taken.append(cell)
			enemies.append(_make_enemy(String(p["type"]), entry, cell, String(p.get("tier", ""))))
		start_combat(false)
	if effects.has("dialogue") and mode == "explore" and not in_dialogue():
		open_dialogue(String(effects["dialogue"]))
	if effects.has("transition"):
		var tr: Dictionary = effects["transition"]
		var raw_a: Array = tr.get("arrive", [])
		travel(String(tr.get("to", "")), Vector2i(int(raw_a[0]), int(raw_a[1])) if raw_a.size() == 2 else Vector2i(-1, -1), String(tr.get("label", "")))
	if effects.has("sequence"):
		run_sequence(effects["sequence"])
	if bool(effects.get("ending", false)):
		show_ending()


## A named lore fragment found by the story (a dialogue or trigger `lore`
## effect): into the Archive like one from a Shard, once.
func find_lore_by_id(id: String) -> bool:
	if id.is_empty() or narrative.lore.has(id) or not registry.has_entry("lore", id):
		return false
	narrative.lore.append(id)
	overlay.toast(Loc.t("Fragment: %s") % String(registry.get_entry("lore", id).get("name", id)), 3.0)
	return true


## A scripted sequence: steps run in order, each an effects block plus an
## optional `camera` ([x, y] cell, or "leader") and `pause` (seconds).
## Input is off and the party stands still while it runs; pauses are
## skipped under tests. A `dialogue` or `enemies` step must be the last:
## the sequence hands over to the dialogue or the fight. Returns the number
## of steps that ran. `last_sequence` keeps a record for tests.
func run_sequence(steps: Array) -> int:
	if sequence_running:
		return 0
	sequence_running = true
	party.active = false
	party.stop()
	last_sequence = []
	var ran := 0
	for raw: Variant in steps:
		var step: Dictionary = raw
		if step.has("when") and not Conditions.passes(step["when"], dialogue_ctx()):
			continue # a conditional step (S41): the catastrophe reads prior choices
		ran += 1
		var record := {"step": ran, "camera": Vector2i(-1, -1)}
		if step.has("camera"):
			var focus: Variant = step["camera"]
			if focus is Array and Array(focus).size() == 2:
				var cell := Vector2i(int(Array(focus)[0]), int(Array(focus)[1]))
				sequence_focus.position = map_view.cell_to_world(cell)
				if camera != null:
					camera.target = sequence_focus
				record["camera"] = cell
			elif String(focus) == "leader" and camera != null and party.leader() != null:
				camera.target = party.leader()
				record["camera"] = leader_cell()
		var body := step.duplicate()
		body.erase("camera")
		body.erase("pause")
		body.erase("when")
		apply_effects(body)
		last_sequence.append(record)
		if in_dialogue() or mode != "explore":
			break # the dialogue or the fight takes it from here
		var pause := float(step.get("pause", 0.0))
		if pause > 0.0 and not instant_sequences:
			await get_tree().create_timer(pause).timeout
	if camera != null and party.leader() != null and not (mode == "combat"):
		camera.target = party.leader()
	if mode == "explore":
		party.active = true
	sequence_running = false
	return ran


## A persistent change to a handcrafted map: {"map"?: id, "cell": [x, y],
## "tile": tile id}. Recorded in the story (NarrativeState.map_edits) and
## applied now when the map is the current one, else on the next entry.
func apply_map_edit(edit: Dictionary) -> bool:
	var target := String(edit.get("map", map_id))
	var raw: Array = edit.get("cell", [])
	var tile_id := String(edit.get("tile", ""))
	if raw.size() != 2 or tile_id.is_empty() or not registry.has_entry("tiles", tile_id) or not registry.has_entry("maps", target):
		return false
	var cell := Vector2i(int(raw[0]), int(raw[1]))
	var edits: Array = narrative.map_edits.get(target, [])
	var kept: Array = []
	for e: Variant in edits:
		var old: Array = e
		if old.size() == 3 and int(old[0]) == cell.x and int(old[1]) == cell.y:
			continue # the latest edit of a cell wins
		kept.append(old)
	kept.append([cell.x, cell.y, tile_id])
	narrative.map_edits[target] = kept
	if target == map_id and not map_entry.has("generation"):
		_set_map_tile(cell, tile_id)
	return true


func _set_map_tile(cell: Vector2i, tile_id: String) -> void:
	if not map_data.in_bounds(cell):
		return
	map_data.set_tile(cell, registry.get_entry("tiles", tile_id))
	map_view.build(map_data, registry.get_entry("biomes", map_data.biome_id), rules_entry("lighting"))
	if highlighter != null:
		highlighter.map_view = map_view


## Re-applies the story's edits to a handcrafted map on entry.
func restore_map_edits() -> void:
	if map_entry.has("generation"):
		return
	for e: Variant in narrative.map_edits.get(map_id, []):
		var edit: Array = e
		if edit.size() == 3:
			_set_map_tile(Vector2i(int(edit[0]), int(edit[1])), String(edit[2]))


## The ending the state machine resolves for the current story.
func resolve_ending() -> Dictionary:
	return Endings.resolve(registry, dialogue_ctx())


## Shows the resolved ending once: flags `ending_<id>` and `ending_seen`,
## the fates from its epilogue, the run in numbers.
func show_ending() -> bool:
	if ending_menu == null or narrative.flag("ending_seen"):
		return false
	var ending := resolve_ending()
	if ending.is_empty():
		return false
	narrative.set_flag("ending_%s" % String(ending["id"]), true)
	narrative.set_flag("ending_seen", true)
	iron_run_complete(String(ending["id"]))
	if playtest != null:
		playtest.ending(String(ending["id"]))
	var credits: Array[String] = []
	credits.assign(credit_lines())
	ending_menu.show_text(EndingMenu.render(ending, Endings.fates(registry, ending, narrative), demo_stats(), Endings.modifiers(ending, dialogue_ctx()), credits))
	autosave()
	return true


## The credits, each line through the table.
## Ability names for a header, each through the table.
func ability_names(ids: Array) -> String:
	var names: PackedStringArray = []
	for id: String in ids:
		names.append(Loc.text(registry.get_entry("abilities", id), "name", id))
	return ", ".join(names)


func credit_lines() -> Array[String]:
	var out: Array[String] = []
	var raw: Array = registry.get_entry("rules", "credits").get("lines", [])
	for i: int in raw.size():
		out.append(Loc.content("rules", "credits", "lines.%d" % i, String(raw[i])))
	return out


func close_ending() -> void:
	if ending_menu == null:
		return
	ending_menu.close()
	if title_menu != null and not Engine.has_meta("neon_weave_tests"):
		show_title()


# --- the roster (S38, D-093) -------------------------------------------------

## Who walks with the party and who waits at the Bastion: every recruited
## companion, with a bench or take item. Three walk (`party_max` less the
## leader); the rest wait. Swapping respawns the party at the plaza.
func roster_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var room := narrative.active_companions().size() < rules.party_max - 1
	for id: String in narrative.recruited:
		var c: Dictionary = registry.get_entry("companions", id)
		var name := String(c.get("short_name", id))
		if narrative.is_benched(id):
			items.append({"id": "take_%s" % id, "label": Loc.t("%s waits at the Bastion: take along") % name, "enabled": room, "why": Loc.t("the party is full")})
		else:
			items.append({"id": "bench_%s" % id, "label": Loc.t("%s walks with you: leave at the Bastion") % name, "enabled": true})
	items.append({"id": "resume", "label": Loc.t("Done"), "enabled": true})
	return items


func open_roster() -> bool:
	if roster_menu == null or mode != "explore" or not at_home():
		return false
	var rows := roster_rows()
	if rows.size() <= 1:
		return false # nobody recruited and nobody fallen
	if system_menu != null:
		system_menu.close()
	roster_menu.open(rows)
	return true


func bench_companion(id: String) -> bool:
	if not at_home() or mode != "explore" or not narrative.is_recruited(id) or narrative.is_benched(id):
		return false
	narrative.bench(id)
	respawn_party()
	overlay.toast(Loc.t("%s waits at the Bastion.") % registry.get_entry("companions", id).get("short_name", id), 2.0)
	return true


func take_companion(id: String) -> bool:
	if not at_home() or mode != "explore" or not narrative.is_benched(id) or narrative.active_companions().size() >= rules.party_max - 1:
		return false
	narrative.unbench(id)
	respawn_party()
	overlay.toast(Loc.t("%s walks with you.") % registry.get_entry("companions", id).get("short_name", id), 2.0)
	return true


## The story took a companion (S41 `dismiss` effect): off the roster in the
## narrative already (Conditions.apply); here the party member goes too.
## The leader can never be dropped.
func _drop_member(id: String) -> void:
	var m := member_by_id(id)
	if m != null and m != party.leader():
		party.remove_member(m)
	if party.leader() != null:
		party.trail.reset(party.leader().position)
