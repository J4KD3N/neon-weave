## Every action has a keyboard event, and every input path has a pad
## binding: either a joypad event on the action itself or a documented
## route through the system menu / confirm button (GDD M1 exit criterion).
extends TestCase


func before_each() -> void:
	InputActions.ensure()


func test_every_action_is_registered_with_a_key() -> void:
	for action: String in InputActions.BINDINGS:
		assert_true(InputMap.has_action(action), action)
		var keys := 0
		for e: InputEvent in InputMap.action_get_events(action):
			if e is InputEventKey:
				keys += 1
		assert_true(keys >= 1, "%s has a key" % action)


func test_every_action_has_a_pad_path() -> void:
	for action: String in InputActions.BINDINGS:
		if InputActions.has_pad_binding(action):
			assert_false(InputActions.PAD_ROUTES.has(action), "%s is pad-bound, no route needed" % action)
		else:
			assert_true(InputActions.PAD_ROUTES.has(action), "%s has neither a pad event nor a route" % action)
	for item: String in InputActions.routed_menu_items():
		assert_true(ExploreWorld.SYSTEM_ITEM_IDS.has(item), "route to unknown menu item %s" % item)


func test_pad_events_are_the_documented_layout() -> void:
	assert_eq(_buttons("confirm"), [JOY_BUTTON_A])
	assert_eq(_buttons("cancel"), [JOY_BUTTON_B])
	assert_eq(_buttons("menu"), [JOY_BUTTON_START])
	assert_eq(_buttons("end_turn"), [JOY_BUTTON_START])
	assert_eq(_buttons("next_member"), [JOY_BUTTON_BACK])
	assert_eq(_buttons("ability_1"), [JOY_BUTTON_X])
	assert_eq(_buttons("ability_2"), [JOY_BUTTON_Y])
	assert_eq(_buttons("ability_3"), [JOY_BUTTON_LEFT_SHOULDER])
	assert_eq(_buttons("ability_4"), [JOY_BUTTON_RIGHT_SHOULDER])
	assert_eq(_buttons("move_up"), [JOY_BUTTON_DPAD_UP])
	assert_eq(_axes("move_up"), [[JOY_AXIS_LEFT_Y, -1.0]])
	assert_eq(_axes("move_right"), [[JOY_AXIS_LEFT_X, 1.0]])
	assert_eq(_axes("zoom_in"), [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	assert_eq(_axes("zoom_out"), [[JOY_AXIS_TRIGGER_LEFT, 1.0]])


func test_ensure_is_idempotent() -> void:
	var before := InputMap.action_get_events("confirm").size()
	InputActions.ensure()
	assert_eq(InputMap.action_get_events("confirm").size(), before)


func test_iso_cursor_steps_follow_the_screen() -> void:
	assert_eq(IsoCursor.step(Vector2(1, 0)), Vector2i(1, -1), "screen right")
	assert_eq(IsoCursor.step(Vector2(-1, 0)), Vector2i(-1, 1), "screen left")
	assert_eq(IsoCursor.step(Vector2(0, -1)), Vector2i(-1, -1), "screen up")
	assert_eq(IsoCursor.step(Vector2(0, 1)), Vector2i(1, 1), "screen down")
	assert_eq(IsoCursor.step(Vector2(1, -1)), Vector2i(0, -1), "up-right is one grid column")
	assert_eq(IsoCursor.step(Vector2(-1, -1)), Vector2i(-1, 0))
	assert_eq(IsoCursor.step(Vector2(1, 1)), Vector2i(1, 0))
	assert_eq(IsoCursor.step(Vector2(-1, 1)), Vector2i(0, 1))
	assert_eq(IsoCursor.step(Vector2(0.1, 0.1)), Vector2i.ZERO, "dead zone")
	assert_eq(IsoCursor.step(Vector2(0.9, 0.1)), Vector2i(1, -1), "slight tilt snaps")
	# The projection check (a step "right" lands to the right on screen) lives in test_world_scene.gd.


func test_system_menu_render_and_cursor() -> void:
	var items: Array[Dictionary] = [
		{"id": "a", "label": "Alpha", "enabled": false, "why": "nope"},
		{"id": "b", "label": "Beta", "enabled": true},
		{"id": "c", "label": "Gamma", "enabled": true},
	]
	var text := SystemMenu.render(items, 1)
	assert_contains(text, "   Alpha  (unavailable: nope)")
	assert_contains(text, "▶ Beta")
	assert_contains(text, "   Gamma")
	assert_contains(text, "Enter or A confirm")
	var menu := SystemMenu.new()
	menu._ready()
	menu.open(items)
	assert_eq(menu.cursor, 1, "opens on the first enabled item")
	assert_eq(menu.selected_id(), "b")
	assert_eq(menu.move(1), 2)
	assert_eq(menu.move(1), 1, "wraps past the disabled item")
	assert_eq(menu.move(-1), 2)
	menu.close()
	assert_false(menu.visible)
	menu.free()


func _buttons(action: String) -> Array:
	var out: Array = []
	for e: InputEvent in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			out.append((e as InputEventJoypadButton).button_index)
	return out


func _axes(action: String) -> Array:
	var out: Array = []
	for e: InputEvent in InputMap.action_get_events(action):
		if e is InputEventJoypadMotion:
			var m := e as InputEventJoypadMotion
			out.append([m.axis, m.axis_value])
	return out
