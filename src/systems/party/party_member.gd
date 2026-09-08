## One party member in the world. Position is the feet (cell centre when
## standing on a cell). Visuals are placeholder art tinted by class branch.
class_name PartyMember
extends WorldActor

var member_id: String = ""
var class_id: String = ""
var race_id: String = ""
var facing: Vector2 = Vector2.DOWN
## Derived combat stats (see StatBlock): hp, move, evasion, initiative.
var stats: Dictionary = {}
var abilities: Array[String] = []
## Extra max HP from the Bastion (Workshop). Applied on top of stats.hp.
var hp_bonus: int = 0


## Re-derives max HP from base stats plus `bonus`; current HP shifts by the
## same amount so an upgrade heals by exactly what it adds.
func set_hp_bonus(bonus: int) -> void:
	var base := maxi(int(stats.get("hp", 1)), 1)
	var new_max := maxi(base + bonus, 1)
	var delta := new_max - max_hp
	var was := hp
	hp_bonus = bonus
	max_hp = new_max
	hp = was + delta if was > 0 else 0


func setup(data: Dictionary, color: Color, p_stats: Dictionary = {}, p_abilities: Array[String] = []) -> void:
	member_id = String(data.get("id", ""))
	class_id = String(data.get("class", ""))
	race_id = String(data.get("race", ""))
	name = member_id if not member_id.is_empty() else "Member"
	stats = p_stats
	abilities.assign(p_abilities)
	max_hp = maxi(int(stats.get("hp", 1)), 1)
	hp = max_hp
	build_visuals(String(data.get("name", member_id)), color)
