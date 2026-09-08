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
