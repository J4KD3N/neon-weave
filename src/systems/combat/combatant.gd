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
## Marks placed on this combatant by hex-type abilities: mark id -> stacks.
var marks: Dictionary = {}
## Party members under Story-Protected rules are knocked out, not killed.
var downed: bool = false
## Stealth: hostile abilities cannot target a hidden combatant; attacking
## from hiding is an ambush and reveals; taking damage reveals.
var hidden: bool = false
## Timed statuses: name -> turns left, counted down when this combatant's turn ends.
var statuses: Dictionary = {}
## Id of the summoner that called this combatant in, if any.
var summoned_by: String = ""
## Set once a rusher has broken off (S28): a retreat happens once per fight.
var retreated: bool = false
## Generic traits from race, origin or entry data (D-085): resist, regen_on_surface,
## detect_hidden, ability_damage_bonus, heal_immune_types, ... Read by CombatState.
var traits: Dictionary = {}
## Who this combatant must attack while `taunted` runs (D-086).
var taunted_by: String = ""
## {"damage", "spread", "source", "type"} while `poisoned` runs.
var poison: Dictionary = {}
## Damage span of the counter stance while `counter` runs.
var counter_damage: Array = []


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


## Fraction of `damage_type` this combatant shrugs off (negative = weakness).
func resist(damage_type: String) -> float:
	return clampf(float(Dictionary(traits.get("resist", {})).get(damage_type, 0.0)), -1.0, 1.0)


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


func mark_count(mark: String) -> int:
	return int(marks.get(mark, 0))


func is_silenced() -> bool:
	return int(statuses.get("silenced", 0)) > 0


## Hides for `turns` of this combatant's own turns (2 = through the next
## enemy round and the whole of the next own turn). Hiding is always a
## window, never permanent, so a stuck hidden enemy cannot stall a fight.
func hide(turns: int) -> void:
	hidden = true
	statuses["hidden"] = maxi(turns, 1)


func reveal() -> void:
	hidden = false
	statuses.erase("hidden")


func is_rooted() -> bool:
	return int(statuses.get("rooted", 0)) > 0


func begin_turn() -> void:
	ap = ap_max
	move_left = 0 if is_rooted() else move_max


## Statuses last N of this combatant's own turns: they count down when its
## turn ends, so "silenced 2" is two silenced turns and a stealth window of
## 2 covers the enemy round and the whole of the next own turn.
func tick_statuses() -> void:
	for key: String in statuses.keys():
		statuses[key] = int(statuses[key]) - 1
		if int(statuses[key]) <= 0:
			statuses.erase(key)
	if hidden and not statuses.has("hidden"):
		hidden = false
	if not statuses.has("taunted"):
		taunted_by = ""
	if not statuses.has("poisoned"):
		poison = {}
	if not statuses.has("counter"):
		counter_damage = []
