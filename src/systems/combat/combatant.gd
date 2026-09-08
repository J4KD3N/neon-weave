## One participant in a combat. Pure data; the world actor node (if any) is
## looked up by [member id] in the controller, never touched here.
class_name Combatant
extends RefCounted

const TEAM_PARTY := "party"
const TEAM_ENEMY := "enemy"

var id: String = ""
var display_name: String = ""
var team: String = TEAM_ENEMY
var archetype: String = "rusher"
var cell: Vector2i = Vector2i.ZERO

var max_hp: int = 1
var hp: int = 1
var ap_max: int = 4
var ap: int = 4
var move_max: int = 6
var move_left: int = 6
var evasion: int = 0
var initiative_bonus: int = 0
var initiative: int = 0
var abilities: Array[String] = []
## Flat bonus added to every damage roll (Workshop edge-work).
var damage_bonus: int = 0
## Class resource (Surge, Heat): definition from the `resources` kind and
## the current stack count. Empty def = no resource.
var resource_id: String = ""
var resource_def: Dictionary = {}
var resource: int = 0
## Party members under Story-Protected rules are knocked out, not killed.
var downed: bool = false


static func make(p_id: String, p_name: String, p_team: String, p_cell: Vector2i, stats: Dictionary, p_abilities: Array[String], ap_per_turn: int) -> Combatant:
	var c := Combatant.new()
	c.id = p_id
	c.display_name = p_name
	c.team = p_team
	c.cell = p_cell
	c.max_hp = maxi(int(stats.get("hp", 1)), 1)
	c.hp = c.max_hp
	c.move_max = maxi(int(stats.get("move", 6)), 1)
	c.move_left = c.move_max
	c.evasion = int(stats.get("evasion", 0))
	c.initiative_bonus = int(stats.get("initiative", 0))
	c.ap_max = ap_per_turn
	c.ap = ap_per_turn
	c.abilities.assign(p_abilities)
	return c


## Alive and not knocked out: still takes turns and blocks cells.
func is_active() -> bool:
	return hp > 0 and not downed


func is_hostile_to(other: Combatant) -> bool:
	return team != other.team


func set_resource(def: Dictionary) -> void:
	resource_def = def
	resource_id = String(def.get("id", ""))
	resource = 0


func resource_max() -> int:
	return int(resource_def.get("max", 0))


func has_resource() -> bool:
	return not resource_def.is_empty()


func begin_turn() -> void:
	ap = ap_max
	move_left = move_max
