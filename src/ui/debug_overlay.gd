## Top-left debug text: a one-line status from the world, plus (F1) a dump
## of the content registry.
class_name DebugOverlay
extends Label

var registry: ContentRegistry
var show_registry: bool = false
var status: String = "":
	set(value):
		status = value
		_refresh()


func _ready() -> void:
	position = Vector2(16, 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 18)
	add_theme_color_override("font_color", Color(0.85, 0.8, 1.0))
	add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	add_theme_constant_override("shadow_offset_x", 1)
	add_theme_constant_override("shadow_offset_y", 1)
	_refresh()


func toggle_registry() -> void:
	show_registry = not show_registry
	_refresh()


func _refresh() -> void:
	text = status
	if show_registry and registry != null:
		text += "\n\n" + registry_summary(registry)


static func registry_summary(reg: ContentRegistry) -> String:
	var lines: PackedStringArray = []
	for kind: String in reg.kinds():
		var ids: PackedStringArray = []
		for entry: Dictionary in reg.get_all(kind):
			ids.append("%s (%s)" % [entry["id"], entry["_source"]])
		lines.append("%s [%d]: %s" % [kind, reg.count(kind), ", ".join(ids)])
	lines.append("mods loaded: %d" % reg.loaded_mods.size())
	for mod: Dictionary in reg.loaded_mods:
		lines.append("  %s %s (priority %d)" % [mod["id"], mod["version"], mod["priority"]])
	if not reg.load_errors.is_empty():
		lines.append("LOAD ERRORS:")
		for err: String in reg.load_errors:
			lines.append("  " + err)
	return "\n".join(lines)
