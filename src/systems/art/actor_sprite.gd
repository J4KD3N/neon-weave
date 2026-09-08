## An [AnimatedSprite2D] driven by a [SpriteSheet]: plays "<anim>_<row>"
## for a screen-space facing, mirroring undrawn facings, and falls back to
## idle after one-shot actions.
class_name ActorSprite
extends AnimatedSprite2D

var sheet: SpriteSheet
var facing := Vector2.DOWN
var current_action: String = "idle"
var moving: bool = false


func setup(p_sheet: SpriteSheet, swap: Dictionary = {}) -> void:
	sheet = p_sheet
	sprite_frames = sheet.build_frames(swap)
	centered = true
	offset = sheet.feet_offset()
	animation_finished.connect(_on_finished)
	play_state()


func set_facing(dir: Vector2) -> void:
	if dir.length_squared() > 0.0001:
		facing = dir
	if current_action == "idle" or current_action == "walk":
		play_state()


func set_moving(value: bool) -> void:
	if moving == value:
		return
	moving = value
	if current_action == "idle" or current_action == "walk":
		play_state()


## Plays a one-shot action (attack, cast, hit, death) toward `facing`.
## Unknown actions are ignored; death sticks on its last frame.
func play_action(action: String, dir: Vector2 = Vector2.ZERO) -> void:
	if sheet == null or not sheet.has_animation(action):
		return
	if dir.length_squared() > 0.0001:
		facing = dir
	current_action = action
	_play(action)


## Idle or walk according to `moving`.
func play_state() -> void:
	if sheet == null:
		return
	current_action = "walk" if moving and sheet.has_animation("walk") else "idle"
	_play(current_action)


func _play(anim: String) -> void:
	var f := sheet.facing_for(facing)
	var full := "%s_%s" % [anim, f["row"]]
	if sprite_frames == null or not sprite_frames.has_animation(full):
		return
	flip_h = bool(f["flip"])
	if animation != full or not is_playing():
		play(full)


func _on_finished() -> void:
	if current_action == "death":
		return
	current_action = "idle"
	play_state()
