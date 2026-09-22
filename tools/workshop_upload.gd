## Publishes a mod folder to the Workshop (S58, D-113):
##
##   godot --headless --path . -s tools/workshop_upload.gd -- --mod=<folder> [--title=..] [--description=..] [--item=<id>]
##
## Validates the folder first (the same check as tools/validate_mods.gd)
## and refuses a broken mod. With GodotSteam and a running client the
## Steam backend creates or updates the item; without, the null backend
## publishes to user://workshop_null/<id>/, which the game loads as a mod
## on the next start, so the whole path runs before Steam exists. Exit 0
## on success, 1 when the mod is broken or the upload failed, 2 on usage.
class_name WorkshopUpload
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := ""
	var title := ""
	var description := ""
	var item_id := 0
	for arg: String in args:
		if arg.begins_with("--mod="):
			folder = arg.get_slice("=", 1)
		elif arg.begins_with("--title="):
			title = arg.get_slice("=", 1)
		elif arg.begins_with("--description="):
			description = arg.get_slice("=", 1)
		elif arg.begins_with("--item="):
			item_id = int(arg.get_slice("=", 1))
	var result := await run(folder, title, description, item_id)
	for line: String in result["lines"]:
		print(line)
	quit(int(result["code"]))


## The whole path as a function, so a test can run it: {"lines", "code", "item_id"}.
static func run(folder: String, title: String = "", description: String = "", item_id: int = 0, backend: PlatformBackend = null) -> Dictionary:
	var lines: Array[String] = []
	if folder.is_empty():
		lines.append("usage: -- --mod=<folder> [--title=..] [--description=..] [--item=<id>]")
		return {"lines": lines, "code": 2, "item_id": 0}
	if not FileAccess.file_exists(folder.path_join("mod.json")):
		lines.append("%s has no mod.json" % folder)
		return {"lines": lines, "code": 2, "item_id": 0}
	var check := ContentValidator.run_cli(PackedStringArray(["--mods=" + folder]))
	lines.append_array(check["lines"])
	if int(check["code"]) != 0:
		lines.append("not uploaded: fix the problems above first")
		return {"lines": lines, "code": 1, "item_id": 0}
	if backend == null:
		if Engine.has_singleton("Steam"):
			var steam := SteamPlatformBackend.new()
			if steam.setup(PlatformService.load_steam_config(), []):
				backend = steam
		if backend == null:
			backend = NullPlatformBackend.new()
	if title.is_empty():
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("mod.json")))
		title = String(Dictionary(manifest).get("name", folder.get_file())) if manifest is Dictionary else folder.get_file()
	var outcome: Dictionary = await backend.workshop_publish(folder, title, description, item_id)
	if bool(outcome["ok"]):
		lines.append("published %s as item %d on the %s backend" % [folder, int(outcome["item_id"]), backend.backend_name()])
		return {"lines": lines, "code": 0, "item_id": int(outcome["item_id"])}
	lines.append("upload failed on the %s backend: %s" % [backend.backend_name(), outcome["why"]])
	return {"lines": lines, "code": 1, "item_id": 0}
