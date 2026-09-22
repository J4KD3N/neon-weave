## Turns a folder of playtest logs into the triage table (S47, D-102):
## fights by map and enemy set with win rate, rounds, HP left and downed,
## beside the harness band for that map; runs by template and depth with
## extraction rate; time to each story map; dialogue choices by node;
## endings. `tools/playtest_report.gd` prints it; `docs/playtest.md` says
## how to read it.
class_name PlaytestReport
extends RefCounted

const STORY_MAPS: Array[String] = ["proto_yard", "gate_road", "relay_station", "undercity_throat", "throat_deep", "throat_source", "lattice_enclave", "rootched_grove", "ashfound_forge", "the_loom"]


## Every record from every `.jsonl` under `dir`, tagged with its session.
static func load_records(dir: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var files := Array(d.get_files())
	files.sort()
	for f: String in files:
		if f.get_extension() != "jsonl":
			continue
		var fa := FileAccess.open(dir.path_join(f), FileAccess.READ)
		if fa == null:
			continue
		while not fa.eof_reached():
			var line := fa.get_line().strip_edges()
			if line.is_empty():
				continue
			var parsed: Variant = JSON.parse_string(line)
			if parsed is Dictionary:
				var rec: Dictionary = parsed
				rec["_session"] = f
				out.append(rec)
		fa.close()
	return out


## The harness rows (test_balance.gd BEATS) keyed by map, so a fight on a
## story map prints beside its band. Empty when the test file is absent.
static func harness_bands() -> Dictionary:
	var out: Dictionary = {}
	if not ResourceLoader.exists("res://tests/unit/test_balance.gd"):
		return out
	var script: GDScript = load("res://tests/unit/test_balance.gd")
	if script == null or not script.get_script_constant_map().has("BEATS"):
		return out
	for beat: Dictionary in script.get_script_constant_map()["BEATS"]:
		var map := String(beat.get("map", ""))
		if not out.has(map):
			out[map] = []
		Array(out[map]).append({"id": String(beat.get("id", "")), "min": float(beat.get("min_win", 0.0)), "max": float(beat.get("max_win", 1.0))})
	return out


static func build(dir: String) -> String:
	var records := load_records(dir)
	var lines: PackedStringArray = []
	var sessions: Dictionary = {}
	for r: Dictionary in records:
		sessions[r["_session"]] = true
	lines.append("PLAYTEST REPORT  %d session%s, %d records, from %s" % [sessions.size(), "" if sessions.size() == 1 else "s", records.size(), dir])
	if records.is_empty():
		lines.append("  no logs found; run the game with -- --playtest and copy user://playtest/*.jsonl here")
		return "\n".join(lines)
	# Fights.
	var fights: Dictionary = {}
	for r: Dictionary in records:
		if String(r.get("event", "")) != "fight":
			continue
		var where := String(r.get("map", ""))
		if not String(r.get("template", "")).is_empty():
			where = "%s d%d" % [r["template"], int(r.get("depth", 1))]
		var key := "%s: %s" % [where, ", ".join(PackedStringArray(Array(r.get("enemies", []))))]
		var agg: Dictionary = fights.get(key, {"n": 0, "wins": 0, "rounds": 0.0, "hp": 0.0, "downed": 0.0, "levels": [], "map": String(r.get("map", ""))})
		agg["n"] = int(agg["n"]) + 1
		if String(r.get("result", "")) == "victory":
			agg["wins"] = int(agg["wins"]) + 1
			agg["hp"] = float(agg["hp"]) + float(r.get("hp_left", 0.0))
			agg["downed"] = float(agg["downed"]) + float(r.get("downed", 0))
		agg["rounds"] = float(agg["rounds"]) + float(r.get("rounds", 0))
		Array(agg["levels"]).append(int(r.get("level", 1)))
		fights[key] = agg
	var bands := harness_bands()
	lines.append("")
	lines.append("FIGHTS  (win %, rounds, HP left after a win, downed after a win, party level; harness band for the map beside it)")
	var keys: Array = fights.keys()
	keys.sort()
	for key: String in keys:
		var a: Dictionary = fights[key]
		var n := int(a["n"])
		var wins := int(a["wins"])
		var levels: Array = a["levels"]
		levels.sort()
		var band := ""
		for b: Dictionary in bands.get(String(a["map"]), []):
			band += "  [%s %d–%d%%]" % [b["id"], int(round(100.0 * float(b["min"]))), int(round(100.0 * float(b["max"])))]
		lines.append("  %-52s n %2d  win %3d%%  rounds %4.1f  hp %3d%%  downed %.1f  lvl %d–%d%s" % [key.substr(0, 52), n, int(round(100.0 * wins / n)), float(a["rounds"]) / n, int(round(100.0 * float(a["hp"]) / maxi(wins, 1))), float(a["downed"]) / maxi(wins, 1), levels[0], levels[levels.size() - 1], band])
	# Runs.
	var runs: Dictionary = {}
	for r: Dictionary in records:
		if String(r.get("event", "")) != "run":
			continue
		var key := "%s d%d" % [r.get("template", "?"), int(r.get("depth", 1))]
		var agg: Dictionary = runs.get(key, {"n": 0, "extracted": 0, "salvage": 0, "aether": 0})
		agg["n"] = int(agg["n"]) + 1
		if String(r.get("outcome", "")) == "extracted":
			agg["extracted"] = int(agg["extracted"]) + 1
			var haul: Dictionary = r.get("haul", {})
			agg["salvage"] = int(agg["salvage"]) + int(haul.get("salvage", 0))
			agg["aether"] = int(agg["aether"]) + int(haul.get("aether", 0))
		runs[key] = agg
	lines.append("")
	lines.append("RUNS  (extraction %, average haul of an extraction)")
	var run_keys: Array = runs.keys()
	run_keys.sort()
	for key: String in run_keys:
		var a: Dictionary = runs[key]
		var n := int(a["n"])
		var ex := int(a["extracted"])
		lines.append("  %-24s n %2d  extracted %3d%%  salvage %4.1f  aether %3.1f" % [key, n, int(round(100.0 * ex / n)), float(a["salvage"]) / maxi(ex, 1), float(a["aether"]) / maxi(ex, 1)])
	# Time to each story map, per session (first entry).
	lines.append("")
	lines.append("TIME  (minutes from launch to first entering each map, per session)")
	for session: String in sessions:
		var firsts: Dictionary = {}
		for r: Dictionary in records:
			if String(r["_session"]) != session or String(r.get("event", "")) != "map":
				continue
			var m := String(r.get("map", ""))
			if STORY_MAPS.has(m) and not firsts.has(m):
				firsts[m] = float(r.get("t", 0.0)) / 60.0
		var parts: PackedStringArray = []
		for m: String in STORY_MAPS:
			if firsts.has(m):
				parts.append("%s %.0f" % [m, firsts[m]])
		lines.append("  %s: %s" % [session, ", ".join(parts) if not parts.is_empty() else "no story maps entered"])
	# Choices.
	var choices: Dictionary = {}
	for r: Dictionary in records:
		if String(r.get("event", "")) != "choice":
			continue
		var key := "%s/%s: %s" % [r.get("dialogue", "?"), r.get("node", "?"), String(r.get("text", "")).substr(0, 40)]
		choices[key] = int(choices.get(key, 0)) + 1
	lines.append("")
	lines.append("CHOICES  (times each line was picked)")
	var choice_keys: Array = choices.keys()
	choice_keys.sort()
	for key: String in choice_keys:
		lines.append("  %3d  %s" % [choices[key], key])
	# Endings.
	var endings: Dictionary = {}
	for r: Dictionary in records:
		if String(r.get("event", "")) == "ending":
			endings[r.get("ending", "?")] = int(endings.get(r.get("ending", "?"), 0)) + 1
	lines.append("")
	lines.append("ENDINGS  %s" % ("none reached" if endings.is_empty() else str(endings)))
	return "\n".join(lines)
