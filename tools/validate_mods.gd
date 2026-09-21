## Validates a mod folder from the command line (S45, D-100):
##
##   godot --headless --path . -s tools/validate_mods.gd -- --mods=<folder> [--all]
##
## `<folder>` holds mod folders (each with mod.json and content/), or is one
## such mod folder. Prints every load error and content problem with the
## kind, id and mod it belongs to, and exits 1 when there are any, 0 when
## the mod is clean, 2 on bad usage. `--all` reports base-game problems too.
extends SceneTree


func _init() -> void:
	var result := ContentValidator.run_cli(OS.get_cmdline_user_args())
	for line: String in result["lines"]:
		print(line)
	quit(int(result["code"]))
