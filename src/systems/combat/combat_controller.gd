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
const COLOR_HOVER := Color(1.0, 0.95, 0.7, 0.22)
const COLOR_CURSOR := Color(1.0, 0.85, 0.3, 0.5)

var world: ExploreWorld
var hud: CombatHud
var highlighter: CellHighlighter
var state: CombatState
var animate: bool = true
var busy: bool = false
var selected_ability: String = ""
var hovered := Vector2i(-1, -1)
## Pad/keyboard cell cursor. While active it stands in for the mouse
## (through `world.hover_override`); any mouse motion releases it.
var cursor := Vector2i(-1, -1)
var cursor_active: bool = false
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
		c.damage_bonus = world.bastion.damage_bonus()
		c.set_resource(world.resource_def_for(m))
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
			_refuse("%s: %s" % [_ability_name(selected_ability), why])
		return
	if target != null and target != actor:
		if target.team == actor.team and not actor.is_hostile_to(target):
			var swap := state.switch_to(target.id)
			if swap.is_empty():
				_after_switch()
			else:
				_refuse("%s: %s" % [target.display_name, swap])
			return
		var id := EnemyBrain.usable_ability(state, actor, target)
		if id.is_empty():
			_refuse(_out_of_reach_reason(actor, target))
		else:
			_do_ability(actor, id, cell)
		return
	if target == actor:
		return
	var why_move := state.can_move(actor, cell)
	if why_move.is_empty():
		_do_move(actor, cell)
	else:
		_refuse("Cannot move there: %s" % why_move)


## Why no ability reaches `target`, phrased for the player: the nearest
## thing to a reason from each ability, preferring range over the rest.
func _out_of_reach_reason(actor: Combatant, target: Combatant) -> String:
	var reasons: PackedStringArray = []
	for id: String in actor.abilities:
		var why := state.can_use(actor, id, target.cell)
		if not why.is_empty():
			reasons.append("%s %s" % [_ability_name(id), why])
	if reasons.is_empty():
		return "Nothing can target %s" % target.display_name
	return "Cannot reach %s: %s" % [target.display_name, ", ".join(reasons)]


func _ability_name(id: String) -> String:
	var ability: Dictionary = state.abilities.get(id, {})
	return String(ability.get("name", id))


## Mouse over `cell` during the player turn: path preview for a move, hit
## chance and damage for an attack, a marker on anything else.
func hover(cell: Vector2i) -> void:
	if cell == hovered:
		return
	hovered = cell
	if busy or not is_active() or not current_is_player():
		return
	var actor := state.current()
	var target := state.occupant(cell)
	highlighter.clear_layer("c_path")
	highlighter.clear_layer("d_hover")
	if target != null and target != actor and actor.is_hostile_to(target):
		var id := selected_ability if not selected_ability.is_empty() else EnemyBrain.usable_ability(state, actor, target)
		if id.is_empty():
			hud.set_hint(_out_of_reach_reason(actor, target), CombatHud.HINT_WARN)
			return
		var p := state.preview(actor, id, cell)
		highlighter.set_layer("d_hover", [cell], COLOR_HOVER)
		hud.set_hint(describe_preview(p, target), CombatHud.HINT_WARN if not String(p["why"]).is_empty() else CombatHud.HINT_PREVIEW)
		return
	if target != null and target != actor:
		var swap := "click to swap" if state.switchable().has(target) else ("has acted" if state.has_acted(target) else "not in this turn group")
		hud.set_hint("%s: %s" % [target.display_name, swap], CombatHud.HINT_PREVIEW)
		return
	if selected_ability.is_empty():
		var path := state.move_path(actor, cell)
		if not path.is_empty():
			highlighter.set_layer("c_path", path, COLOR_PATH)
			hud.set_hint("Move %d → %d Move left" % [path.size(), actor.move_left - path.size()], CombatHud.HINT_PREVIEW)
			return
	if world.map_data.is_walkable(cell):
		highlighter.set_layer("d_hover", [cell], COLOR_HOVER)
	hud.set_hint(default_hint())


## "Strike → Scav: 85% to hit, 3–5 damage (flanked)" or the refusal.
static func describe_preview(p: Dictionary, target: Combatant) -> String:
	var name := String(p.get("name", p.get("ability", "?")))
	if int(p.get("heal", 0)) > 0:
		return "%s: vent Heat, +%d HP" % [name, int(p["heal"])]
	var why := String(p.get("why", ""))
	if not why.is_empty() and int(p.get("chance", 0)) == 0:
		return "%s → %s: %s" % [name, target.display_name, why]
	var tags: PackedStringArray = p.get("tags", PackedStringArray())
	var tag_text := "" if tags.is_empty() else " (%s)" % ", ".join(tags)
	var dmg := "%d" % int(p["max"]) if int(p["min"]) == int(p["max"]) else "%d–%d" % [int(p["min"]), int(p["max"])]
	var s := "%s → %s: %d%% to hit, %s damage%s" % [name, target.display_name, int(p["chance"]), dmg, tag_text]
	if bool(p.get("kills", false)):
		s += " · lethal"
	if not why.is_empty():
		s += " · %s" % why
	return s


func default_hint() -> String:
	if not is_active() or not current_is_player():
		return ""
	var others := state.switchable()
	var swap := ""
	if not others.is_empty():
		var names: PackedStringArray = []
		for c: Combatant in others:
			names.append(c.display_name)
		swap = " · Tab or click swaps to %s" % ", ".join(names)
	var undo := " · Esc undoes the move" if state.can_undo_move(state.current()) else ""
	return "Click a teal cell to move · click an enemy to attack, or [1-4] then a target · Space ends the turn%s%s" % [swap, undo]


func switch_to(id: String) -> bool:
	if busy or not is_active() or not current_is_player():
		return false
	var why := state.switch_to(id)
	if not why.is_empty():
		_refuse(why.capitalize())
		return false
	_after_switch()
	return true


## Tab: the next group member after the current one in initiative order.
func next_member() -> bool:
	if busy or not is_active() or not current_is_player():
		return false
	var others := state.switchable()
	if others.is_empty():
		_refuse("Nobody else to swap to this turn")
		return false
	var cur := state.turn_index
	var pick: Combatant = others[0]
	for c: Combatant in others:
		if state.order.find(c) > cur:
			pick = c
			break
	return switch_to(pick.id)


func _after_switch() -> void:
	selected_ability = ""
	hovered = Vector2i(-1, -1)
	_after_state_change()


func _refuse(text: String) -> void:
	hud.set_hint(text, CombatHud.HINT_WARN)


## Steps the cell cursor in a screen direction (stick, D-pad, WASD). The
## first step also shows it, starting from the acting combatant. Returns
## the cursor cell; unchanged outside the player turn.
func move_cursor(dir: Vector2) -> Vector2i:
	if busy or not is_active() or not current_is_player():
		return cursor
	if not cursor_active or not world.map_data.in_bounds(cursor):
		cursor = state.current().cell
		cursor_active = true
	var next := cursor + IsoCursor.step(dir)
	if world.map_data.in_bounds(next):
		cursor = next
	world.hover_override = cursor
	hovered = Vector2i(-1, -1)
	hover(cursor)
	highlighter.set_layer("e_cursor", [cursor], COLOR_CURSOR)
	return cursor


## Confirm (Enter / A): acts on the cursor cell as a click would.
func confirm() -> bool:
	if not cursor_active:
		return false
	player_click(cursor)
	return true


## Mouse motion, or leaving combat: the mouse is the pointer again.
func release_cursor() -> void:
	cursor_active = false
	world.hover_override = Vector2i(-1, -1)
	highlighter.clear_layer("e_cursor")


func select_ability(index: int) -> void:
	if not is_active() or not current_is_player():
		return
	var actor := state.current()
	if index < 0 or index >= actor.abilities.size():
		return
	var id: String = actor.abilities[index]
	selected_ability = "" if selected_ability == id else id
	_refresh_player_ui()


## Esc / B: clears the aimed ability; with nothing aimed, takes back the
## last move instead.
func cancel_selection() -> void:
	if selected_ability.is_empty() and not busy and is_active() and current_is_player() and state.can_undo_move(state.current()):
		undo_move()
		return
	selected_ability = ""
	if is_active():
		_refresh_player_ui()


func undo_move() -> bool:
	if busy or not is_active() or not current_is_player():
		return false
	var actor := state.current()
	if not state.undo_move():
		return false
	var node: WorldActor = actors[actor.id]
	node.position = world.map_view.cell_to_world(actor.cell)
	_after_state_change()
	return true


## Combat follows whoever is acting; exploration follows the leader.
func _pan_to(id: String) -> void:
	if world.camera == null:
		return
	var node: WorldActor = actors.get(id)
	if node != null and is_instance_valid(node):
		world.camera.target = node


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
	var target_node: WorldActor = actors[String(e.get("target", actor.id))]
	_sync_all()
	if animate and e["type"] == "ability":
		busy = true
		highlighter.clear_all()
		var origin := node.position
		var toward := origin + (target_node.position - origin).normalized() * 14.0
		_play_attack(node, target_node, id, e)
		var tween := create_tween()
		tween.tween_property(node, "position", toward, 0.08)
		tween.tween_property(node, "position", origin, 0.12)
		tween.finished.connect(func() -> void:
			_show_hit_text(target_node, e)
			_sync_all()
			busy = false
			_after_state_change())
	else:
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
		"chain", "surface", "overload", "vent":
			if not animate:
				_sync_actor(String(e.get("target", e.get("actor", ""))))


func _after_state_change() -> void:
	if state == null:
		return
	if state.finished:
		_finish()
		return
	hovered = Vector2i(-1, -1)
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
		_pan_to(actor.id)
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
				_sync_all()
				if animate and not e.is_empty() and e["type"] == "ability":
					var node: WorldActor = actors[actor.id]
					var target_node: WorldActor = actors[e["target"]]
					var origin := node.position
					_play_attack(node, target_node, String(action["id"]), e)
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
	_pan_to(actor.id)
	var reach: Array[Vector2i] = []
	reach.assign(state.reachable_cells(actor).keys())
	highlighter.set_layer("a_reach", reach, COLOR_REACH)
	var targets: Array[Vector2i] = []
	if not selected_ability.is_empty():
		for c: Combatant in state.active():
			if state.can_use(actor, selected_ability, c.cell).is_empty():
				targets.append(c.cell)
	highlighter.set_layer("b_targets", targets, COLOR_TARGET)
	var res_text := ""
	if actor.has_resource():
		res_text = "  %s %d/%d" % [actor.resource_def.get("name", actor.resource_id), actor.resource, actor.resource_max()]
	hud.set_turn_text("Round %d — %s  |  AP %d/%d  Move %d/%d%s" % [state.round_number, actor.display_name, actor.ap, actor.ap_max, actor.move_left, actor.move_max, res_text])
	var order: PackedStringArray = []
	if not state.switchable().is_empty():
		order.append("⇄ Tab / Select swaps")
	for i: int in state.order.size():
		var c := state.order[i]
		var mark := "   "
		if i == state.turn_index:
			mark = "▶ "
		elif state.group.has(c) and state.has_acted(c):
			mark = "✓ "
		elif state.group.has(c) and c.is_active():
			mark = "⇄ "
		var hp := "%d/%d" % [c.hp, c.max_hp] if c.is_active() else ("down" if c.downed else "dead")
		var res := ""
		if c.has_resource() and c.is_active():
			res = " · %s %d" % [c.resource_def.get("name", c.resource_id), c.resource]
		order.append("%s%s (%s)%s" % [mark, c.display_name, hp, res])
	hud.set_order_text("\n".join(order))
	var abilities: Array[Dictionary] = []
	for id: String in actor.abilities:
		var ability: Dictionary = state.abilities.get(id, {})
		abilities.append({"id": id, "name": ability.get("name", id), "ap": int(ability.get("ap", 1)), "usable": actor.ap >= int(ability.get("ap", 1))})
	hud.set_abilities(abilities, selected_ability)
	hud.set_hint(default_hint())
	hud.set_log(state.history)
	if cursor_active and world.map_data.in_bounds(cursor):
		highlighter.set_layer("e_cursor", [cursor], COLOR_CURSOR)


func _finish() -> void:
	highlighter.clear_all()
	hud.set_abilities([], "")
	if world.camera != null and world.party.leader() != null:
		world.camera.target = world.party.leader()
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


## Pushes every combatant's HP/downed/dead state to its node (chains,
## surfaces and overloads can touch anyone, not just the ability's target).
func _sync_all() -> void:
	if state == null:
		return
	for c: Combatant in state.combatants:
		_sync_actor(c.id)


## Sheet-driven actors: attacker plays attack/cast toward the target, the
## target plays hit (or death when it dies). Placeholder actors ignore this.
func _play_attack(node: WorldActor, target_node: WorldActor, ability_id: String, e: Dictionary) -> void:
	var dir := (target_node.position - node.position)
	var ability: Dictionary = state.abilities.get(ability_id, {})
	var action := "cast" if String(ability.get("damage_type", "")) == "arcane" else "attack"
	node.play_action(action, dir)
	if bool(e.get("hit", false)):
		target_node.play_action("death" if bool(e.get("killed", false)) else "hit", -dir)
