## Smoothed camera that tracks a target node; mouse wheel zooms.
class_name FollowCamera
extends Camera2D

@export var target: Node2D
@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0
@export var zoom_step: float = 1.15


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0
	if zoom == Vector2.ONE:
		zoom = Vector2(1.5, 1.5)


func _process(delta: float) -> void:
	if target != null:
		global_position = target.global_position
	# Held zoom: triggers on a pad, = / - on the keyboard. Wheel steps below.
	if InputMap.has_action("zoom_in") and Input.is_action_pressed("zoom_in"):
		zoom_by(pow(zoom_step, delta * 4.0))
	elif InputMap.has_action("zoom_out") and Input.is_action_pressed("zoom_out"):
		zoom_by(pow(1.0 / zoom_step, delta * 4.0))


## Jump to the target without smoothing (after spawning or teleporting).
func snap() -> void:
	if target != null:
		global_position = target.global_position
	reset_smoothing()


func zoom_by(factor: float) -> void:
	var z := clampf(zoom.x * factor, min_zoom, max_zoom)
	zoom = Vector2(z, z)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_by(zoom_step)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_by(1.0 / zoom_step)
