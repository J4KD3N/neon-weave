## Combat overlay built in code: turn banner, initiative order, ability bar,
## end-turn button, rolling log and a big centre message. Design coordinates
## are the 1920×1080 canvas.
class_name CombatHud
extends CanvasLayer

signal ability_pressed(index: int)
signal end_turn_pressed

var turn_label: Label
var order_label: Label
var log_label: Label
var message_label: Label
var hint_label: Label
var bar: HBoxContainer
var end_button: Button
var _buttons: Array[Button] = []


func _ready() -> void:
	layer = 5
	turn_label = _label(Vector2(0, 44), Vector2(1920, 32), 24, HORIZONTAL_ALIGNMENT_CENTER)
	order_label = _label(Vector2(16, 84), Vector2(700, 200), 16, HORIZONTAL_ALIGNMENT_LEFT)
	log_label = _label(Vector2(1440, 84), Vector2(464, 700), 15, HORIZONTAL_ALIGNMENT_LEFT)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.85))
	hint_label = _label(Vector2(0, 960), Vector2(1920, 24), 15, HORIZONTAL_ALIGNMENT_CENTER)
	hint_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.7))
	message_label = _label(Vector2(0, 460), Vector2(1920, 120), 52, HORIZONTAL_ALIGNMENT_CENTER)
	message_label.visible = false

	bar = HBoxContainer.new()
	bar.position = Vector2(0, 996)
	bar.size = Vector2(1920, 56)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)
	end_button = Button.new()
	end_button.text = "End Turn  [Space]"
	end_button.custom_minimum_size = Vector2(200, 48)
	end_button.pressed.connect(func() -> void: end_turn_pressed.emit())
	bar.add_child(end_button)
	visible = false


func set_turn_text(text: String) -> void:
	turn_label.text = text


func set_order_text(text: String) -> void:
	order_label.text = text


func set_hint(text: String) -> void:
	hint_label.text = text


func set_log(lines: Array[String], keep: int = 12) -> void:
	var start := maxi(lines.size() - keep, 0)
	var shown: PackedStringArray = []
	for i: int in range(start, lines.size()):
		shown.append(lines[i])
	log_label.text = "\n".join(shown)


## `abilities`: [{"id", "name", "ap", "usable": bool}]
func set_abilities(abilities: Array[Dictionary], selected: String) -> void:
	for b: Button in _buttons:
		b.queue_free()
	_buttons.clear()
	for i: int in abilities.size():
		var a: Dictionary = abilities[i]
		var b := Button.new()
		b.text = "[%d] %s  %dAP" % [i + 1, a.get("name", a.get("id", "?")), int(a.get("ap", 1))]
		b.custom_minimum_size = Vector2(220, 48)
		b.toggle_mode = true
		b.button_pressed = String(a.get("id", "")) == selected
		b.disabled = not bool(a.get("usable", true))
		var index := i
		b.pressed.connect(func() -> void: ability_pressed.emit(index))
		bar.add_child(b)
		bar.move_child(b, i)
		_buttons.append(b)


func show_message(text: String) -> void:
	message_label.text = text
	message_label.visible = true


func hide_message() -> void:
	message_label.visible = false


func _label(pos: Vector2, size: Vector2, font_size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.9, 0.87, 1.0))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	add_child(l)
	return l
