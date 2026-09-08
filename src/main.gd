## Boot scene. For now it only proves the content registry and platform
## layer came up; the M0 map replaces this.
extends Node2D

@onready var _summary: Label = $Summary


func _ready() -> void:
	_summary.text = build_summary()
	Content.reloaded.connect(func() -> void: _summary.text = build_summary())


func build_summary() -> String:
	var lines: PackedStringArray = ["NEON WEAVE — boot", ""]
	lines.append("platform backend: %s" % Platform.backend.backend_name())
	lines.append("")
	for kind: String in Content.kinds():
		var ids: PackedStringArray = []
		for entry: Dictionary in Content.get_all(kind):
			ids.append("%s (%s)" % [entry["id"], entry["_source"]])
		lines.append("%s [%d]: %s" % [kind, Content.count(kind), ", ".join(ids)])
	lines.append("")
	lines.append("mods loaded: %d" % Content.loaded_mods.size())
	for mod: Dictionary in Content.loaded_mods:
		lines.append("  %s %s (priority %d)" % [mod["id"], mod["version"], mod["priority"]])
	if not Content.load_errors.is_empty():
		lines.append("")
		lines.append("LOAD ERRORS:")
		for err: String in Content.load_errors:
			lines.append("  " + err)
	return "\n".join(lines)
