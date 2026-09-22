## Prints the playtest triage table from a folder of logs (S47, D-102):
##
##   godot --headless --path . -s tools/playtest_report.gd -- --logs=<folder>
##
## `<folder>` holds the `session_*.jsonl` files testers sent back (they live
## under the game's `user://playtest/` while playing with `-- --playtest`).
## See docs/playtest.md for the kit and how to read the table.
extends SceneTree


func _init() -> void:
	var dir := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--logs="):
			dir = arg.get_slice("=", 1)
	if dir.is_empty():
		print("usage: godot --headless --path . -s tools/playtest_report.gd -- --logs=<folder of session_*.jsonl>")
		quit(2)
		return
	print(PlaytestReport.build(dir))
	quit(0)
