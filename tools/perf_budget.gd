## The performance budget, measured (S53, D-108):
##
##   godot --headless --path . -s tools/perf_budget.gd [-- --frames=120 --strict]
##
## Every Shard template at its largest size and highest population (depth
## 3, six seeds) and every handcrafted map: cells, nodes, enemies, pickups,
## and the game's own per-frame logic in milliseconds, against
## `rules/performance`. Counts over budget always fail (exit 1); the logic
## time fails only with `--strict` (it depends on the machine). No
## rendering happens headless, so the frame budget is for the `--perf`
## counter in a build on the target.
class_name PerfBudget
extends SceneTree

const LEDGER := "user://perf_budget_ledger.json"
const SAVES := "user://perf_budget_saves"


## Runs on the first frame (the tree is up by then) and exits with the code.
func _process(_delta: float) -> bool:
	var frames := 120
	var strict := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="):
			frames = maxi(int(arg.get_slice("=", 1)), 1)
		elif arg == "--strict":
			strict = true
	var result := measure(root, frames, strict)
	for line: String in result["lines"]:
		print(line)
	quit(int(result["code"]))
	return true


static func count_nodes(n: Node) -> int:
	if n.is_queued_for_deletion():
		return 0
	var c := 1
	for ch: Node in n.get_children():
		c += count_nodes(ch)
	return c


## Runs the whole table on a fresh world under `parent`. Returns
## {"lines": [...], "rows": [...], "code": 0|1}.
static func measure(parent: Node, frames: int = 120, strict: bool = false) -> Dictionary:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var world := packed.instantiate() as ExploreWorld
	world.combat_seed = 1234
	world.ledger_path = LEDGER
	world.saves_dir = SAVES
	parent.add_child(world)
	world.combat.animate = false
	var budget: Dictionary = world.registry.get_entry("rules", "performance")
	var lines: PackedStringArray = []
	var rows: Array[Dictionary] = []
	var code := 0
	lines.append("perf budget: cells <= %d, nodes <= %d, enemies <= %d, pickups <= %d, logic <= %.1f ms (%s)" % [int(budget.get("max_cells", 0)), int(budget.get("max_nodes", 0)), int(budget.get("max_enemies", 0)), int(budget.get("max_pickups", 0)), float(budget.get("logic_ms", 0.0)), "strict" if strict else "counts only"])
	world.narrative.set_flag("null_cathedral_found", true)
	world.narrative.set_flag("loom_located", true)
	for t: Dictionary in world.registry.get_all("shards"):
		var id := String(t["id"])
		var big := t.duplicate(true)
		var size: Dictionary = big.get("size", {})
		big["size"] = {"width": [int(size["width"][1]), int(size["width"][1])], "height": [int(size["height"][1]), int(size["height"][1])]}
		world.registry.put("shards", "perf_" + id, big)
		var row := {"id": id, "kind": "shard", "cells": 0, "nodes": 0, "enemies": 0, "pickups": 0, "logic_ms": 0.0}
		for s: int in 6:
			var entry := world.enter_shard("perf_" + id, 100 + s, 3)
			if entry.is_empty():
				continue
			row["cells"] = maxi(int(row["cells"]), world.map_data.width * world.map_data.height)
			row["nodes"] = maxi(int(row["nodes"]), count_nodes(world))
			row["enemies"] = maxi(int(row["enemies"]), world.enemies.size())
			row["pickups"] = maxi(int(row["pickups"]), world.pickups.size())
			row["logic_ms"] = maxf(float(row["logic_ms"]), _logic_ms(world, frames))
		world.registry._entries["shards"].erase("perf_" + id)
		rows.append(row)
	world.registry._fingerprint_cache = ""
	for m: Dictionary in world.registry.get_all("maps"):
		var id := String(m["id"])
		if not world.enter_map(id):
			continue
		rows.append({"id": id, "kind": "map", "cells": world.map_data.width * world.map_data.height, "nodes": count_nodes(world), "enemies": world.enemies.size(), "pickups": world.pickups.size(), "logic_ms": _logic_ms(world, frames)})
	for row: Dictionary in rows:
		var problems: PackedStringArray = []
		if int(row["cells"]) > int(budget.get("max_cells", 0)):
			problems.append("cells")
		if int(row["nodes"]) > int(budget.get("max_nodes", 0)):
			problems.append("nodes")
		if int(row["enemies"]) > int(budget.get("max_enemies", 0)):
			problems.append("enemies")
		if int(row["pickups"]) > int(budget.get("max_pickups", 0)):
			problems.append("pickups")
		if strict and float(row["logic_ms"]) > float(budget.get("logic_ms", 0.0)):
			problems.append("logic")
		if not problems.is_empty():
			code = 1
		lines.append("  %-5s %-18s cells %5d  nodes %4d  enemies %3d  pickups %3d  logic %.2f ms%s" % [row["kind"], row["id"], row["cells"], row["nodes"], row["enemies"], row["pickups"], row["logic_ms"], "" if problems.is_empty() else "  OVER BUDGET: " + ", ".join(problems)])
	lines.append("perf budget: %s" % ("every row in budget" if code == 0 else "over budget"))
	parent.remove_child(world)
	world.free()
	return {"lines": lines, "rows": rows, "code": code}


static func _logic_ms(world: ExploreWorld, frames: int) -> float:
	var t0 := Time.get_ticks_usec()
	for f: int in frames:
		world._process(1.0 / 60.0)
	return (Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
