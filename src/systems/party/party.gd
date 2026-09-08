## The exploring party: a leader who follows paths or direct steering, and
## followers who trail the leader's breadcrumbs. Keep this node at the origin
## of its Y-sorted parent; member positions are world positions.
class_name Party
extends Node2D

@export var speed: float = 170.0
## Path distance between consecutive members while trailing.
@export var spacing: float = 36.0
## When false (combat), _process does not tick; the controller owns positions.
var active: bool = true

var members: Array[PartyMember] = []
var trail := FormationTrail.new()

var _waypoints: Array[Vector2] = []
var _steered := false


## Each spec: {"data": Dictionary, "color": Color, "position": Vector2,
## "stats": Dictionary, "abilities": Array[String]}.
func spawn_members(specs: Array[Dictionary]) -> void:
	for m: PartyMember in members:
		m.queue_free()
	members.clear()
	for i: int in specs.size():
		var spec: Dictionary = specs[i]
		var member := PartyMember.new()
		var abilities: Array[String] = []
		abilities.assign(spec.get("abilities", []))
		member.setup(spec.get("data", {}), spec.get("color", Color.WHITE), spec.get("stats", {}), abilities, spec.get("overlay", {}), spec.get("sheet", null))
		member.position = spec.get("position", Vector2.ZERO)
		member.is_leader = i == 0
		add_child(member)
		members.append(member)
	if not members.is_empty():
		trail.reset(members[0].position)
	_waypoints.clear()


func leader() -> PartyMember:
	return members[0] if not members.is_empty() else null


func is_moving() -> bool:
	return not _waypoints.is_empty()


## Send the leader along world-space waypoints; followers trail automatically.
func set_path(points: Array[Vector2]) -> void:
	_waypoints.assign(points)


func stop() -> void:
	_waypoints.clear()


## Direct (keyboard) steering for the leader. `can_stand` is called with a
## candidate world position and must return bool; blocked moves slide along
## whichever axis is free.
func steer_leader(direction: Vector2, delta: float, can_stand: Callable) -> void:
	stop()
	var l := leader()
	if l == null or direction == Vector2.ZERO:
		return
	var step := direction.normalized() * speed * delta
	var candidates: Array[Vector2] = [
		l.position + step,
		l.position + Vector2(step.x, 0.0),
		l.position + Vector2(0.0, step.y),
	]
	for target: Vector2 in candidates:
		if target != l.position and bool(can_stand.call(target)):
			_move_leader_to(target)
			return


## Advance everyone by `delta` seconds. Called from _process; tests call it
## directly for determinism.
func tick(delta: float) -> void:
	var l := leader()
	if l == null:
		return
	var leader_from := l.position
	if not _waypoints.is_empty():
		var result: Dictionary = Mover.advance(l.position, _waypoints, speed * delta)
		_waypoints.assign(result["waypoints"])
		_move_leader_to(result["position"])
	l.set_motion(l.position != leader_from or _steered, l.facing)
	_steered = false
	for i: int in range(1, members.size()):
		var distance_back := spacing * i
		if not trail.has_distance(distance_back):
			continue
		var m := members[i]
		var single: Array[Vector2] = [trail.point_behind(distance_back)]
		var result: Dictionary = Mover.advance(m.position, single, speed * delta)
		var next: Vector2 = result["position"]
		var moved := next != m.position
		if moved:
			m.facing = (next - m.position).normalized()
			m.position = next
		m.set_motion(moved, m.facing)


func _process(delta: float) -> void:
	if active:
		tick(delta)


func _move_leader_to(target: Vector2) -> void:
	var l := leader()
	if target == l.position:
		return
	l.facing = (target - l.position).normalized()
	l.position = target
	trail.push(target)
	_steered = true
