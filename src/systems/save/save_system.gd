## Versioned JSON saves (GDD §13): slots + autosave, save anywhere out of
## combat, checkpoints at combat start. A save holds the ledger (with Bastion
## levels), the party's HP and cells, the location, the run haul, and the
## deltas against the map (dead enemies, collected pickups). Shards are not
## stored as tiles: they regenerate from template + seed + depth.
##
## Steam Cloud sync of the saves directory is an M2 concern behind `Platform`.
class_name SaveSystem
extends RefCounted

const VERSION := 1
const SLOTS := 3
const AUTOSAVE := "autosave"


static func slot_name(n: int) -> String:
	return "slot_%d" % n


static func path_for(dir: String, save_name: String) -> String:
	return dir.path_join(save_name + ".json")


# --- capture ---------------------------------------------------------------

static func capture(world: ExploreWorld) -> Dictionary:
	var members: Array = []
	for m: PartyMember in world.party.members:
		var cell := world.member_cell(m)
		members.append({"id": m.member_id, "hp": m.hp, "downed": m.downed, "cell": [cell.x, cell.y]})
	var dead: Array = []
	for i: int in world.enemies.size():
		var e := world.enemies[i]
		if not is_instance_valid(e) or e.dead:
			dead.append(i)
	var collected: Array = []
	for i: int in world.pickups.size():
		var p := world.pickups[i]
		if not is_instance_valid(p) or p.collected:
			collected.append(i)
	var location: Dictionary
	if world.run.in_shard:
		var gen: Dictionary = world.map_entry.get("generation", {})
		location = {"kind": "shard", "template": String(gen.get("template", "")), "seed": int(gen.get("seed", 0)), "depth": int(gen.get("depth", 1))}
	else:
		location = {"kind": "map", "id": world.map_id}
	return {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(true, true),
		"map_name": world.map_data.name,
		"ledger": world.ledger.to_dict(),
		"location": location,
		"run": {"haul": world.run.haul.duplicate(), "xp": world.run.xp, "kills": world.run.kills, "pickups": world.run.pickups},
		"party": members,
		"protagonist": world.protagonist.duplicate(true),
		"dead_enemies": dead,
		"collected_pickups": collected,
	}


# --- restore ---------------------------------------------------------------

## Rebuilds the world from `data`. Returns problems found; an empty array
## means a clean restore. Refuses while combat is running.
static func restore(world: ExploreWorld, raw: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if world.mode == "combat":
		errors.append("cannot load during combat")
		return errors
	var data := migrate(raw)
	if int(data.get("version", 0)) > VERSION:
		errors.append("save version %d is newer than this build (%d)" % [int(data["version"]), VERSION])
		return errors

	world.ledger.apply(data.get("ledger", {}))
	var err := world.ledger.save()
	if err != OK:
		errors.append("ledger save failed: %s" % error_string(err))
	world.bastion.setup(world.registry.get_all("buildings"), world.ledger.buildings)
	world.protagonist = Dictionary(data.get("protagonist", {})).duplicate(true)
	world.respawn_party()

	world.mode = "explore"
	world.loading = true
	var location: Dictionary = data.get("location", {})
	var entered := true
	match String(location.get("kind", "map")):
		"shard":
			var entry := world.enter_shard(String(location.get("template", "")), int(location.get("seed", 0)), maxi(int(location.get("depth", 1)), 1))
			if entry.is_empty():
				errors.append("unknown shard template '%s'" % location.get("template"))
				entered = false
		_:
			if not world.enter_map(String(location.get("id", ExploreWorld.HOME_MAP))):
				errors.append("unknown map '%s'" % location.get("id"))
				entered = false
	world.loading = false
	if not entered:
		return errors

	var run: Dictionary = data.get("run", {})
	var haul: Dictionary = run.get("haul", {})
	for key: String in Ledger.RESOURCES:
		world.run.haul[key] = int(haul.get(key, 0))
	world.run.xp = int(run.get("xp", 0))
	world.run.kills = int(run.get("kills", 0))
	world.run.pickups = int(run.get("pickups", 0))

	world.apply_bastion_bonuses()
	var by_id: Dictionary = {}
	for m: PartyMember in world.party.members:
		by_id[m.member_id] = m
	var saved_party: Array = data.get("party", [])
	for entry: Dictionary in saved_party:
		var id := String(entry.get("id", ""))
		if not by_id.has(id):
			errors.append("saved member '%s' is not in the party" % id)
			continue
		var m: PartyMember = by_id[id]
		m.downed = bool(entry.get("downed", false))
		m.hp = int(entry.get("hp", m.max_hp))
		var raw_cell: Array = entry.get("cell", [])
		if raw_cell.size() == 2:
			var cell := Vector2i(int(raw_cell[0]), int(raw_cell[1]))
			if world.map_data.is_walkable(cell):
				m.position = world.map_view.cell_to_world(cell)
			else:
				errors.append("member '%s' saved on blocked cell %s" % [id, cell])
	world.party.stop()
	if world.party.leader() != null:
		world.party.trail.reset(world.party.leader().position)

	var dead: Array = data.get("dead_enemies", [])
	for raw_i: Variant in dead:
		var i := int(raw_i)
		if i < 0 or i >= world.enemies.size():
			errors.append("dead enemy index %d out of range" % i)
			continue
		var e := world.enemies[i]
		if is_instance_valid(e) and not e.dead:
			e.dead = true
			e.queue_free()
	var collected: Array = data.get("collected_pickups", [])
	for raw_i: Variant in collected:
		var i := int(raw_i)
		if i < 0 or i >= world.pickups.size():
			errors.append("collected pickup index %d out of range" % i)
			continue
		var p := world.pickups[i]
		if is_instance_valid(p) and not p.collected:
			p.collected = true
			p.queue_free()

	if world.camera != null:
		world.camera.snap()
	return errors


# --- files -----------------------------------------------------------------

static func write(path: String, data: Dictionary) -> Error:
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "  "))
	return OK


## Reads a save. On failure the result is {"_error": "<reason>"}.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"_error": "no save at %s" % path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"_error": "cannot open %s: %s" % [path, error_string(FileAccess.get_open_error())]}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {"_error": "save JSON error line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if not json.data is Dictionary:
		return {"_error": "save is not a JSON object"}
	return json.data


## Brings older saves up to VERSION. Append a step per version bump.
static func migrate(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	var version := int(d.get("version", 0))
	if version < 1:
		# Pre-release saves had no version; the shape is otherwise v1.
		d["version"] = 1
	if d.has("ledger"):
		d["ledger"] = Ledger.migrate(d["ledger"])
	return d


static func summarize(data: Dictionary) -> String:
	if data.has("_error"):
		return String(data["_error"])
	var ledger := Ledger.new()
	ledger.apply(Ledger.migrate(data.get("ledger", {})))
	return "%s — %s — %s" % [data.get("map_name", "?"), data.get("saved_at", "?"), ledger.summary()]


## One line per slot plus the autosave: {"name", "path", "exists", "summary"}.
static func list_saves(dir: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var names: Array[String] = []
	for n: int in range(1, SLOTS + 1):
		names.append(slot_name(n))
	names.append(AUTOSAVE)
	for save_name: String in names:
		var path := path_for(dir, save_name)
		var exists := FileAccess.file_exists(path)
		out.append({"name": save_name, "path": path, "exists": exists, "summary": summarize(read(path)) if exists else "empty"})
	return out
