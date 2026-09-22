## The playtest log (S47, D-102): with `-- --playtest` the game appends one
## JSON line per event to `user://playtest/session_<stamp>.jsonl`: the
## session, every map entered, every fight (result, rounds, HP left,
## downed, party level, enemies), every run (extracted or wiped, template,
## depth, haul), every dialogue choice and the ending. What the harness
## measures, measured on a person. `PlaytestReport` reads a folder of them.
class_name PlaytestLog
extends RefCounted

const DIR := "user://playtest"

var path: String = ""
var started_msec: int = 0
var lines_written: int = 0


func start(dir: String = DIR, stamp: String = "") -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var when := stamp if not stamp.is_empty() else Time.get_datetime_string_from_system(true, false).replace(":", "-")
	path = dir.path_join("session_%s.jsonl" % when)
	started_msec = Time.get_ticks_msec()
	write({"event": "start", "version": String(ProjectSettings.get_setting("application/config/version", "0.0.0")), "when": Time.get_datetime_string_from_system(true, true), "os": OS.get_name()})


func elapsed() -> float:
	return (Time.get_ticks_msec() - started_msec) / 1000.0


func write(record: Dictionary) -> void:
	if path.is_empty():
		return
	record["t"] = snappedf(elapsed(), 0.1)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(record))
	f.close()
	lines_written += 1


func map(world: ExploreWorld) -> void:
	var gen: Dictionary = world.map_entry.get("generation", {})
	write({"event": "map", "map": world.map_id, "template": String(gen.get("template", "")), "depth": world.map_depth(), "mode": "mortal" if world.is_mortal_mode() else "story"})


func fight(world: ExploreWorld, result: String) -> void:
	var s := world.combat.state
	var hp := 0
	var max_hp := 0
	var downed := 0
	for m: PartyMember in world.party.members:
		hp += maxi(m.hp, 0) if not m.downed else 0
		max_hp += m.max_hp
		if m.downed or m.hp <= 1:
			downed += 1
	var enemies: Array[String] = []
	if s != null:
		for c: Combatant in s.combatants:
			if c.team == Combatant.TEAM_ENEMY and not c.id.get_slice(":", 1).begins_with("s"): # e:<n>:<kind>; summons are e:s<n>:<kind>
				enemies.append(c.id.get_slice(":", 2))
	enemies.sort()
	var gen: Dictionary = world.map_entry.get("generation", {})
	write({"event": "fight", "map": world.map_id, "template": String(gen.get("template", "")), "depth": world.map_depth(), "result": result, "rounds": s.round_number if s != null else 0, "hp_left": snappedf(float(hp) / float(maxi(max_hp, 1)), 0.01), "downed": downed, "level": world.party_level(), "party": world.party.members.size(), "enemies": enemies})


func run_end(world: ExploreWorld, outcome: String, take: Dictionary) -> void:
	var gen: Dictionary = world.map_entry.get("generation", {})
	write({"event": "run", "outcome": outcome, "template": String(gen.get("template", "")), "depth": world.map_depth(), "haul": take, "kills": world.run.kills, "fights": world.run.fights if "fights" in world.run else 0, "level": world.party_level()})


func choice(dialogue_id: String, node: String, text: String) -> void:
	write({"event": "choice", "dialogue": dialogue_id, "node": node, "text": text})


func ending(id: String) -> void:
	write({"event": "ending", "ending": id})
