## Writes the translation template (S55, D-110):
##
##   godot --headless --path . -s tools/extract_strings.gd [-- --out=user://locale_template.json]
##
## `ui`: every UI source string in the code (the literal inside Loc.t("…"),
## unescaped), each mapped to itself; `content`: every content text field
## (Loc.TEXT_FIELDS) of the base game, keyed kind.id.path. Copy the file to
## content/locales/<code>.json (or a mod's locales/), give it a `name`,
## replace the values, and the settings screen lists the language.
extends SceneTree


func _init() -> void:
	var out_path := "user://locale_template.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.get_slice("=", 1)
	var registry := ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [])
	var result := build(registry)
	registry.free()
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		print("cannot write %s: %s" % [out_path, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("locale template: %d ui strings, %d content strings -> %s" % [Dictionary(result["ui"]).size(), Dictionary(result["content"]).size(), out_path])
	quit(0)


## The template as a dictionary: {"name", "ui": {source: source}, "content": {key: source}}.
static func build(registry: ContentRegistry) -> Dictionary:
	var ui: Dictionary = {}
	for source: String in scan_ui_strings("res://src"):
		ui[source] = source
	var content := Loc.extract_content(registry)
	var sorted_content: Dictionary = {}
	var keys: Array = content.keys()
	keys.sort()
	for k: String in keys:
		sorted_content[k] = content[k]
	return {"name": "New language (rename me)", "summary": "Written by tools/extract_strings.gd. Replace every value; keep every %s, %d and newline where the source has one.", "ui": ui, "content": sorted_content}


## Every literal inside Loc.t("…") under a folder, unescaped, sorted, unique.
static func scan_ui_strings(root: String) -> Array[String]:
	var found: Dictionary = {}
	var pattern := RegEx.new()
	pattern.compile("Loc\\.t\\(\"((?:[^\"\\\\]|\\\\.)*)\"")
	for path: String in _gd_files(root):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		for m: RegExMatch in pattern.search_all(file.get_as_text()):
			var source := m.get_string(1).c_unescape()
			if not source.strip_edges().is_empty():
				found[source] = true
	var out: Array[String] = []
	out.assign(found.keys())
	out.sort()
	return out


static func _gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for d: String in dir.get_directories():
		out.append_array(_gd_files(root.path_join(d)))
	for f: String in dir.get_files():
		if f.ends_with(".gd"):
			out.append(root.path_join(f))
	return out
