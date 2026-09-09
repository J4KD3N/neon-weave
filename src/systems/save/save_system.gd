## Versioned JSON saves (GDD §13): slots + autosave, save anywhere out of
## combat, checkpoints at combat start. A save holds the ledger (with Bastion
## levels), the party's HP and cells, the location, the run haul, and the
## deltas against the map (dead enemies, collected pickups). Shards are not
## stored as tiles: they regenerate from template + seed + depth.
##
## v2 (S27) stamps every save with the content it was made against: the
## fingerprint of the map or Shard template its deltas index into, and the
## fingerprint of the whole content set. A save whose location fingerprint
## no longer matches is refused rather than misloaded (D-080).
##
## Steam Cloud sync of the saves directory is behind `Platform`.
class_name SaveSystem
extends RefCounted

const VERSION := 2
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
		location = {"kind": "shard", "template": String(gen.get("template", "")), "seed": int(gen.get("seed", 0)), "depth": int(gen.get("depth", 1)), "extras": Array(gen.get("extra_pickups", [])).duplicate()}
	else:
		location = {"kind": "map", "id": world.map_id}
	location["fingerprint"] = location_fingerprint(world)
	return {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(true, true),
		"map_name": world.map_data.name,
		"content": {
			"game_version": String(ProjectSettings.get_setting("application/config/version", "0.0.0")),
			"fingerprint": world.registry.fingerprint(),
			"mods": world.registry.mod_ids(),
		},
		"ledger": world.ledger.to_dict(),
		"location": location,
		"run": {"haul": world.run.haul.duplicate(), "xp": world.run.xp, "kills": world.run.kills, "pickups": world.run.pickups, "opened": world.run.opened.duplicate(true), "waypoints_used": world.run.waypoints_used.duplicate(true)},
		"party": members,
		"protagonist": world.protagonist.duplicate(true),
		"narrative": world.narrative.to_dict(),
		"dead_enemies": dead,
		"collected_pickups": collected,
	}


## The fingerprint of whatever the deltas index into: the handcrafted map
## entry, or the Shard template plus the generator's layout version.
static func location_fingerprint(world: ExploreWorld) -> String:
	if world.run.in_shard:
		var gen: Dictionary = world.map_entry.get("generation", {})
		return shard_fingerprint(world.registry, String(gen.get("template", "")))
	return world.registry.entry_fingerprint("maps", world.map_id)


static func shard_fingerprint(registry: ContentRegistry, template: String) -> String:
	var f := registry.entry_fingerprint("shards", template)
	return "" if f.is_empty() else "%s@%d" % [f, ShardGenerator.LAYOUT_VERSION]


## Why `data` cannot be loaded against `registry`, or "" when it can. A
## save with no location fingerprint (v1) cannot be matched and is refused;
## so is one whose map or template has changed since it was written.
static func content_check(data: Dictionary, registry: ContentRegistry) -> String:
	var location: Dictionary = data.get("location", {})
	var saved := String(location.get("fingerprint", ""))
	if saved.is_empty():
		return "this save predates content checks and cannot be matched to the current content; start a new game"
	var current := ""
	var where := ""
	match String(location.get("kind", "map")):
		"shard":
			var template := String(location.get("template", ""))
			where = "Shard template '%s'" % template
			current = shard_fingerprint(registry, template)
		_:
			var id := String(location.get("id", ""))
			where = "map '%s'" % id
			current = registry.entry_fingerprint("maps", id)
	if current.is_empty():
		return "%s no longer exists in the current content; this save cannot be loaded" % where
	if current != saved:
		return "%s has changed since this save was written; loading it would misplace what happened there, so it is refused (start a new game or restore the old content)" % where
	return ""


## True when the save was written against a different content set than
## the one loaded (a balance patch, a mod added or removed). Such a save
## still loads when its location matches; the list marks it.
static func content_changed(data: Dictionary, registry: ContentRegistry) -> bool:
	var content: Dictionary = data.get("content", {})
	return String(content.get("fingerprint", "")) != registry.fingerprint()


# --- restore ---------------------------------------------------------------

## Rebuilds the world from `data`. Returns problems found; an empty array
## means a clean restore. Refuses while combat is running, and refuses a
## save whose content check fails before touching the world.
static func restore(world: ExploreWorld, raw: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if world.mode == "combat":
		errors.append("cannot load during combat")
		return errors
	var data := migrate(raw)
	if int(data.get("version", 0)) > VERSION:
		errors.append("save version %d is newer than this build (%d)" % [int(data["version"]), VERSION])
		return errors
	var why := content_check(data, world.registry)
	if not why.is_empty():
		errors.append(why)
		return errors

	world.ledger.apply(data.get("ledger", {}))
	var err := world.ledger.save()
	if err != OK:
		errors.append("ledger save failed: %s" % error_string(err))
	world.bastion.setup(world.registry.get_all("buildings"), world.ledger.buildings)
	world.protagonist = Dictionary(data.get("protagonist", {})).duplicate(true)
	world.narrative = NarrativeState.from_dict(data.get("narrative", {}))
	world.apply_death_stakes() # the mode rides with the story
	world.respawn_party()

	world.mode = "explore"
	world.loading = true
	var location: Dictionary = data.get("location", {})
	var entered := true
	match String(location.get("kind", "map")):
		"shard":
			var extras: Array[String] = []
			extras.assign(location.get("extras", []))
			var entry := world.enter_shard(String(location.get("template", "")), int(location.get("seed", 0)), maxi(int(location.get("depth", 1)), 1), extras)
			if entry.is_empty():
				errors.append("unknown shard template '%s'" % location.get("template"))
				entered = false
		_:
			if not world.enter_map(String(location.get("id", world.home_map))):
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
	for raw_w: Variant in run.get("waypoints_used", []):
		var w: Array = raw_w
		if w.size() == 2:
			world.run.waypoints_used.append([int(w[0]), int(w[1])])
	for raw_o: Variant in run.get("opened", []):
		var o: Array = raw_o
		if o.size() == 2 and not world.open_door(Vector2i(int(o[0]), int(o[1])), true):
			errors.append("saved door at %s is not a door" % [o])

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
	if version < 2:
		# v2 stamps content fingerprints. A v1 save has none and cannot be
		# given one after the fact: content_check refuses it.
		d["content"] = d.get("content", {})
		d["version"] = 2
	if d.has("ledger"):
		d["ledger"] = Ledger.migrate(d["ledger"])
	return d


## One line for the save lists. With a registry, marks a save the current
## content refuses (✗) or one written against other content that still loads.
static func summarize(data: Dictionary, registry: ContentRegistry = null) -> String:
	if data.has("_error"):
		return String(data["_error"])
	var ledger := Ledger.new()
	ledger.apply(Ledger.migrate(data.get("ledger", {})))
	var note := ""
	if registry != null:
		if not content_check(migrate(data), registry).is_empty():
			note = " · ✗ content changed, needs a new game"
		elif content_changed(data, registry):
			note = " · content changed"
	return "%s — %s — %s%s" % [data.get("map_name", "?"), data.get("saved_at", "?"), ledger.summary(), note]


## One line per slot plus the autosave: {"name", "path", "exists", "summary", "loadable"}.
static func list_saves(dir: String, registry: ContentRegistry = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var names: Array[String] = []
	for n: int in range(1, SLOTS + 1):
		names.append(slot_name(n))
	names.append(AUTOSAVE)
	for save_name: String in names:
		var path := path_for(dir, save_name)
		var exists := FileAccess.file_exists(path)
		var data := read(path) if exists else {}
		var loadable := exists and not data.has("_error") and (registry == null or content_check(migrate(data), registry).is_empty())
		out.append({"name": save_name, "path": path, "exists": exists, "summary": summarize(data, registry) if exists else "empty", "loadable": loadable})
	return out
