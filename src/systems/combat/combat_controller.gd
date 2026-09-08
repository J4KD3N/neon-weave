## Glues a [CombatState] to world actors, the [CombatHud] and the
## [CellHighlighter]: builds combatants from party members and enemies,
## routes player input, runs enemy turns, animates results. With
## `animate = false` everything resolves synchronously (tests, headless).
class_name CombatController
extends Node

signal started
signal ended(result: String)

const COLOR_REACH := Color(0.2, 0.88, 0.84, 0.18)
const COLOR_TARGET := Color(1.0, 0.48, 0.42, 0.28)
const COLOR_PATH := Color(0.71, 0.55, 1.0, 0.35)

var world: ExploreWorld
var hud: CombatHud
var highlighter: CellHighlighter
var state: CombatState
var animate: bool = true
var busy: bool = false
var selected_ability: String = ""
var actors: Dictionary = {} # combatant id -> WorldActor

var _enemy_loop_running := false


func setup(p_world: ExploreWorld, p_hud: CombatHud, p_highlighter: CellHighlighter) -> void:
	world = p_world
	hud = p_hud
	highlighter = p_highlighter
	hud.ability_pressed.connect(select_ability)
	hud.end_turn_pressed.connect(end_player_turn)


func is_active() -> bool:
	return state != null and not state.finished


func current_is_player() -> bool:
	var c := state.current() if state != null else null
	return c != null and c.team == Combatant.TEAM_PARTY


func begin(party: Array[PartyMember], party_cells: Array[Vector2i], enemies: Array[EnemyActor], first_strike: bool, seed_value: int) -> void:
	actors.clear()
	selected_ability = ""
	busy = false
	var combatants: Array[Combatant] = []
	for i: int in party.size():
		var m := party[i]
		var c := Combatant.make("p:" + m.member_id, m.display_name, Combatant.TEAM_PARTY, party_cells[i], m.stats, m.abilities, world.rules.ap_per_turn)
		c.hp = m.hp
		c.downed = m.downed
		combatants.append(c)
		actors[c.id] = m
		m.show_hp = true
	for i: int in enemies.size():
		var e := enemies[i]
		var c := Combatant.make("e:%d:%s" % [i, e.enemy_id], e.display_name, Combatant.TEAM_ENEMY, e.cell, e.stats, e.abilities, world.rules.ap_per_turn)
		c.hp = e.hp
		c.archetype = e.archetype
		combatants.append(c)
		actors[c.id] = e
		e.show_hp = true
	state = CombatState.new()
	state.setup(world.map_data, world.rules, world.abilities_by_id(), combatants, seed_value)
	state.event.connect(_on_event)
	hud.visible = true
	hud.hide_message()
	started.emit()
	state.start(Combatant.TEAM_PARTY if first_strike else "")
	_after_state_change()


## Left click during combat.
func player_click(cell: Vector2i) -> void:
	if busy or not is_active() or not current_is_player():
		return
	var actor := state.current()
	var target := state.occupant(cell)
	if not selected_ability.is_empty():
		var why := state.can_use(actor, selected_ability, cell)
		if why.is_empty():
			_do_ability(actor, selected_ability, cell)
		else:
			hud.set_hint(why.capitalize())
		return
	if target != null and target != actor:
		var id := EnemyBrain.usable_ability(state, actor, target)
		if id.is_empty():
			hud.set_hint("No usable ability on that target (select one, or move closer).")
		else:
			_do_ability(actor, id, cell)
		return
	var why_move := state.can_move(actor, cell)
	if why_move.is_empty():
		_do_move(actor, cell)
	else:
		hud.set_hint(why_move.capitalize())


func select_ability(index: int) -> void:
	if not is_active() or not current_is_player():
		return
	var actor := state.current()
	if index < 0 or index >= actor.abilities.size():
		return
	var id: String = actor.abilities[index]
	selected_ability = "" if selected_ability == id else id
	_refresh_player_ui()


func cancel_selection() -> void:
	selected_ability = ""
	if is_active():
		_refresh_player_ui()


func end_player_turn() -> void:
	if busy or not is_active() or not current_is_player():
		return
	selected_ability = ""
	state.end_turn()
	_after_state_change()


func _do_move(actor: Combatant, cell: Vector2i) -> void:
	var path := state.move_path(actor, cell)
	if not state.move(actor, cell):
		return
	var node: WorldActor = actors[actor.id]
	if animate and path.size() > 0:
		busy = true
		highlighter.clear_all()
		var tween := create_tween()
		for step: Vector2i in path:
			tween.tween_property(node, "position", world.map_view.cell_to_world(step), 0.12)
		tween.finished.connect(func() -> void:
			busy = false
			_after_state_change())
	else:
		node.position = world.map_view.cell_to_world(cell)
		_after_state_change()


func _do_ability(actor: Combatant, id: String, cell: Vector2i) -> void:
	var e := state.use_ability(actor, id, cell)
	if e.is_empty():
		return
	selected_ability = ""
	var node: WorldActor = actors[actor.id]
	var target_node: WorldActor = actors[e["target"]]
	if animate:
		busy = true
		highlighter.clear_all()
		var origin := node.position
		var toward := origin + (target_node.position - origin).normalized() * 14.0
		var tween := create_tween()
		tween.tween_property(node, "position", toward, 0.08)
		tween.tween_property(node, "position", origin, 0.12)
		tween.finished.connect(func() -> void:
			_show_hit_text(target_node, e)
			_sync_actor(e["target"])
			busy = false
			_after_state_change())
	else:
		_sync_actor(e["target"])
		_after_state_change()


func _show_hit_text(target_node: WorldActor, e: Dictionary) -> void:
	var text := "MISS" if not bool(e["hit"]) else "-%d" % int(e["damage"])
	var l := Label.new()
	l.text = text
	l.position = Vector2(-30, -PlaceholderActorArt.BODY_SIZE.y - 30)
	l.size = Vector2(60, 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(1, 0.35, 0.3) if bool(e["hit"]) else Color(0.8, 0.8, 0.85))
	target_node.add_child(l)
	var tween := target_node.create_tween()
	tween.tween_property(l, "position:y", l.position.y - 24.0, 0.6)
	tween.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	tween.finished.connect(l.queue_free)


func _sync_actor(id: String) -> void:
	var c := state.by_id(id)
	var node: WorldActor = actors.get(id)
	if c == null or node == null:
		return
	node.hp = c.hp
	node.downed = c.downed
	if c.hp <= 0 and not c.downed and not node.dead:
		node.dead = true
		var enemy := node as EnemyActor
		if enemy != null:
			world.on_enemy_killed(enemy)
		if animate:
			var tween := node.create_tween()
			tween.tween_property(node, "modulate:a", 0.0, 0.4)
			tween.finished.connect(node.queue_free)
		else:
			node.queue_free()


func _on_event(e: Dictionary) -> void:
	hud.set_log(state.history)
	match String(e["type"]):
		"move":
			if not animate:
				var node: WorldActor = actors[e["actor"]]
				node.position = world.map_view.cell_to_world(e["to"])
		"ability":
			if not animate:
				_sync_actor(e["target"])


func _after_state_change() -> void:
	if state == null:
		return
	if state.finished:
		_finish()
		return
	if current_is_player():
		_refresh_player_ui()
	else:
		highlighter.clear_all()
		_run_enemy_turns()


func _run_enemy_turns() -> void:
	if _enemy_loop_running:
		return
	_enemy_loop_running = true
	while is_active() and not current_is_player():
		var actor := state.current()
		var action := EnemyBrain.next_action(state, actor)
		hud.set_turn_text("Round %d — %s acts" % [state.round_number, actor.display_name])
		match String(action["type"]):
			"move":
				var node: WorldActor = actors[actor.id]
				var path := state.move_path(actor, action["to"])
				state.move(actor, action["to"])
				if animate:
					var tween := create_tween()
					for step: Vector2i in path:
						tween.tween_property(node, "position", world.map_view.cell_to_world(step), 0.1)
					await tween.finished
				else:
					node.position = world.map_view.cell_to_world(action["to"])
			"ability":
				var e := state.use_ability(actor, action["id"], action["target"])
				if animate and not e.is_empty():
					var node: WorldActor = actors[actor.id]
					var target_node: WorldActor = actors[e["target"]]
					var origin := node.position
					var tween := create_tween()
					tween.tween_property(node, "position", origin + (target_node.position - origin).normalized() * 14.0, 0.08)
					tween.tween_property(node, "position", origin, 0.12)
					await tween.finished
					_show_hit_text(target_node, e)
				_sync_actor(e.get("target", ""))
			_:
				state.end_turn()
		if animate and not state.finished:
			await get_tree().create_timer(0.25).timeout
	_enemy_loop_running = false
	_after_state_change()


func _refresh_player_ui() -> void:
	var actor := state.current()
	var reach: Array[Vector2i] = []
	reach.assign(state.reachable_cells(actor).keys())
	highlighter.set_layer("a_reach", reach, COLOR_REACH)
	var targets: Array[Vector2i] = []
	if not selected_ability.is_empty():
		for c: Combatant in state.active():
			if state.can_use(actor, selected_ability, c.cell).is_empty():
				targets.append(c.cell)
	highlighter.set_layer("b_targets", targets, COLOR_TARGET)
	hud.set_turn_text("Round %d — %s  |  AP %d/%d  Move %d/%d" % [state.round_number, actor.display_name, actor.ap, actor.ap_max, actor.move_left, actor.move_max])
	var order: PackedStringArray = []
	for i: int in state.order.size():
		var c := state.order[i]
		var mark := "▶ " if i == state.turn_index else "   "
		var hp := "%d/%d" % [c.hp, c.max_hp] if c.is_active() else ("down" if c.downed else "dead")
		order.append("%s%s (%s)" % [mark, c.display_name, hp])
	hud.set_order_text("\n".join(order))
	var abilities: Array[Dictionary] = []
	for id: String in actor.abilities:
		var ability: Dictionary = state.abilities.get(id, {})
		abilities.append({"id": id, "name": ability.get("name", id), "ap": int(ability.get("ap", 1)), "usable": actor.ap >= int(ability.get("ap", 1))})
	hud.set_abilities(abilities, selected_ability)
	hud.set_hint("Click a highlighted cell to move · click an enemy or pick an ability [1-4] then a target · Space ends the turn · Esc clears")
	hud.set_log(state.history)


func _finish() -> void:
	highlighter.clear_all()
	hud.set_abilities([], "")
	if state.result == "victory":
		hud.show_message("Victory")
		hud.set_hint("")
	else:
		hud.show_message("The party is wiped out\n[R] restart")
		hud.set_hint("")
	for id: String in actors:
		var node: WorldActor = actors[id]
		if is_instance_valid(node):
			node.show_hp = false
	ended.emit(state.result)
	if animate and state.result == "victory":
		await get_tree().create_timer(1.6).timeout
		hud.hide_message()
		hud.visible = false
	elif state.result == "victory":
		hud.hide_message()
		hud.visible = false
