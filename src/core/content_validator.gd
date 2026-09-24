## Validates loaded content: every kind's required keys, every id a file
## points at, and the campaign vocabulary (condition keys, effect keys,
## dialogue graphs, quest stages, map placements). One static pass over a
## registry returns problems as plain strings, each naming the kind, id and
## source, so a modder reads what is wrong and where. `tools/validate_mods.gd`
## runs it from the command line; the content tests run it over the base
## game so the base is always clean (S45, D-100).
class_name ContentValidator
extends RefCounted

## kind -> required keys. A key written "a|b" means at least one of them.
## Mirrors docs/content-schemas.md; extend both together.
const SCHEMAS: Dictionary = {
	"abilities": ["name", "sound", "ap", "range", "damage", "accuracy"],
	"achievements": ["name", "steam_id", "when"],
	"audio": ["name", "kind", "synth|file"],
	"biomes": ["name", "palette"],
	"branches": ["name", "color"],
	"buildings": ["name", "order", "levels"],
	"classes": ["name", "branches", "resource", "stats", "abilities", "subclasses"],
	"companions": ["name", "race", "class", "dialogue", "quest"],
	"difficulties": ["name", "rules"],
	"dialogue": ["name", "nodes|lines"],
	"enemies": ["name", "family", "archetype", "stats", "abilities", "art"],
	"factions": ["name", "color", "rivals", "joinable_act"],
	"items": ["name", "slot", "art"],
	"loadouts": ["name", "items"],
	"locales": ["name"],
	"lore": ["name", "text", "order"],
	"endings": ["name", "summary", "when"],
	"affixes": ["name", "slots", "weight"],
	"maps": ["name", "biome", "spawn_marker", "legend", "rows"],
	"merchants": ["name", "stock"],
	"npcs": ["name", "dialogue"],
	"origins": ["name", "dialogue_tag"],
	"parties": ["name", "members"],
	"pickups": ["name", "grants|dialogue", "art"],
	"quests": ["name", "start", "stages"],
	"races": ["name", "overlay"],
	"resources": ["name", "max"],
	"rules": ["name"],
	"shards": ["name", "biome", "tiles", "rooms", "enemies"],
	"sprites": ["image|sheet", "frame"],
	"subclasses": ["name", "class", "abilities"],
	"talents": ["name", "branch", "tier", "cost", "effects"],
	"tiles": ["name", "layer", "walkable", "art"],
}

## The condition vocabulary (`requires`, `when`, `done_when`, `start_when`).
const REQUIRES_KEYS: Array[String] = ["flags", "origin_tag", "race", "race_tag", "class", "approval", "recruited", "not_recruited", "quest", "reputation", "faction", "not_faction", "romance", "not_romance", "romance_open", "party_approval_min", "party_race", "party_race_tag", "attribute", "disguised"]
## The effect vocabulary (dialogue choices, triggers, sequence steps).
const EFFECT_KEYS: Array[String] = ["approval", "flags", "recruit", "quest", "reputation", "join_faction", "romance", "dismiss", "lore", "toast", "grant", "enemies", "victory_flag", "open_doors", "dialogue", "transition", "map_edits", "sequence", "ending"]
const BANTER_TRIGGERS: Array[String] = ["enter_shard", "victory", "extract"]
const GRANT_KEYS: Array[String] = ["salvage", "aether", "ciphers", "cipher_chance", "xp", "item", "lore", "heal"]
const ARCHETYPES: Array[String] = ["rusher", "ranged", "summoner", "stealther", "controller"]
const BUILDING_EFFECTS: Array[String] = ["depth", "heal_fraction", "hp_bonus", "damage_bonus", "respec", "respec_refund", "archive", "aether_per_fragment", "garden", "aether_on_return", "quarters"]
const EPILOGUE_KEYS: Array[String] = ["alive", "dead", "absent", "taken", "loyal", "romanced", "lost"]
const SCENE_KEYS: Array[String] = ["id", "label", "dialogue", "requires", "quarters", "once", "romance", "dead"]


## Every problem in the registry. `sources` narrows the report to entries
## from those sources (mod ids); cross-references always resolve against
## everything loaded. Empty means clean.
static func validate(registry: ContentRegistry, sources: Array[String] = []) -> Array[String]:
	var v := ContentValidator.new()
	v._registry = registry
	v._sources = sources
	v._run()
	return v._problems


var _registry: ContentRegistry
var _sources: Array[String] = []
var _problems: Array[String] = []
var _tiles: Dictionary = {}


func _wanted(e: Dictionary) -> bool:
	return _sources.is_empty() or _sources.has(String(e.get("_source", "")))


func _flag(e: Dictionary, message: String) -> void:
	if _wanted(e):
		_problems.append("%s/%s (%s): %s" % [e.get("_kind", "?"), e.get("id", "?"), e.get("_source", "?"), message])


func _has(kind: String, id: String) -> bool:
	return _registry.has_entry(kind, id)


func _ref(e: Dictionary, kind: String, id: String, what: String) -> void:
	if not _has(kind, id):
		_flag(e, "%s points at %s '%s', which does not exist" % [what, kind, id])


func _keys_known(e: Dictionary, block: Dictionary, known: Array[String], what: String) -> void:
	for k: String in block:
		if not known.has(k):
			_flag(e, "%s has an unknown key '%s' (known: %s)" % [what, k, ", ".join(known)])


func _run() -> void:
	for t: Dictionary in _registry.get_all("tiles"):
		_tiles[t["id"]] = t
	for kind: String in _registry.kinds():
		if not SCHEMAS.has(kind):
			for e: Dictionary in _registry.get_all(kind):
				_flag(e, "unknown content kind '%s'; the known kinds are listed in docs/content-schemas.md" % kind)
	var valid_id := RegEx.new()
	valid_id.compile("^[a-z0-9_]+$")
	for kind: String in SCHEMAS:
		for e: Dictionary in _registry.get_all(kind):
			if valid_id.search(String(e.get("id", ""))) == null:
				_flag(e, "id must be lowercase snake_case (a-z, 0-9, _)")
			for key: String in SCHEMAS[kind]:
				var ok := false
				for alt: String in key.split("|"):
					if e.has(alt):
						ok = true
				if not ok:
					_flag(e, "missing required key '%s'" % key)
			if e.has("name") and String(e["name"]).strip_edges().is_empty():
				_flag(e, "name is empty")
	_abilities()
	_classes()
	_subclasses()
	_talents()
	_enemies()
	_races()
	_parties()
	_companions()
	_dialogue()
	_quests()
	_maps()
	_shards()
	_pickups()
	_buildings()
	_factions()
	_npcs()
	_merchants()
	_items()
	_endings()
	_achievements()
	_difficulties()
	_misc()


func _abilities() -> void:
	var has_audio := _registry.count("audio") > 0
	for a: Dictionary in _registry.get_all("abilities"):
		var self_only := String(a.get("targets", "other")) == "self"
		if int(a.get("ap", 0)) < (0 if self_only else 1):
			_flag(a, "ap must be at least 1 (0 for self-targeted)")
		if int(a.get("range", 0)) < (0 if self_only else 1):
			_flag(a, "range must be at least 1 (0 for self-targeted)")
		var dmg: Array = a.get("damage", [])
		if dmg.size() != 2:
			_flag(a, "damage must be [min, max]")
		elif int(dmg[0]) > int(dmg[1]):
			_flag(a, "damage min is above max")
		var acc := int(a.get("accuracy", 0))
		if acc < 1 or acc > 100:
			_flag(a, "accuracy must be 1..100")
		if has_audio and a.has("sound") and not _has("audio", String(a["sound"])):
			_flag(a, "sound points at audio '%s', which does not exist" % a["sound"])


func _classes() -> void:
	for c: Dictionary in _registry.get_all("classes"):
		var branches: Array = c.get("branches", [])
		if branches.is_empty():
			_flag(c, "needs at least one branch")
		for b: Variant in branches:
			_ref(c, "branches", String(b), "branches")
		var abilities: Array = c.get("abilities", [])
		if abilities.is_empty():
			_flag(c, "needs at least one ability")
		for a: Variant in abilities:
			_ref(c, "abilities", String(a), "abilities")
		var stats: Dictionary = c.get("stats", {})
		for key: String in StatBlock.KEYS:
			if not stats.has(key):
				_flag(c, "stats lacks '%s'" % key)
		var res: Dictionary = c.get("resource", {})
		if res.has("id"):
			_ref(c, "resources", String(res["id"]), "resource")
		for s: Variant in c.get("subclasses", []):
			_ref(c, "subclasses", String(s), "subclasses")
			var sub := _registry.get_entry("subclasses", String(s))
			if not sub.is_empty() and String(sub.get("class", "")) != String(c["id"]):
				_flag(c, "subclass '%s' belongs to class '%s'" % [s, sub.get("class", "")])
		if c.has("capstone"):
			_ref(c, "abilities", String(c["capstone"]), "capstone")


func _subclasses() -> void:
	for s: Dictionary in _registry.get_all("subclasses"):
		_ref(s, "classes", String(s.get("class", "")), "class")
		for a: Variant in s.get("abilities", []):
			_ref(s, "abilities", String(a), "abilities")


func _talents() -> void:
	for t: Dictionary in _registry.get_all("talents"):
		_ref(t, "branches", String(t.get("branch", "")), "branch")
		if int(t.get("tier", 0)) < 1:
			_flag(t, "tier must be at least 1")
		var cost: Variant = t.get("cost", {})
		if cost is Dictionary:
			for key: String in cost:
				if not Ledger.RESOURCES.has(key):
					_flag(t, "cost key '%s' unknown" % key)
		elif int(cost) < 0:
			_flag(t, "cost must not be negative")


func _enemies() -> void:
	for e: Dictionary in _registry.get_all("enemies"):
		var e_fluid := String(Dictionary(e.get("traits", {})).get("fluid", "blood"))
		if not DecalLayer.FLUIDS.has(e_fluid):
			_flag(e, "traits.fluid must be blood, oil or none (S61)")
		var e_traits: Dictionary = e.get("traits", {})
		if e_traits.has("hackable") and not (e_traits["hackable"] is bool):
			_flag(e, "traits.hackable must be true or false (S63)")
		_check_art(e)
		var family := String(e.get("family", ""))
		if not _has("biomes", family) and family != "bastion":
			_flag(e, "family '%s' is not a biome (or 'bastion' for party-side summons)" % family)
		if not ARCHETYPES.has(String(e.get("archetype", ""))):
			_flag(e, "archetype must be one of %s" % ", ".join(ARCHETYPES))
		var abilities: Array = e.get("abilities", [])
		if abilities.is_empty():
			_flag(e, "needs at least one ability")
		for a: Variant in abilities:
			_ref(e, "abilities", String(a), "abilities")
		if int(Dictionary(e.get("stats", {})).get("hp", 0)) < 1:
			_flag(e, "stats.hp must be at least 1")
		if not Color.html_is_valid(String(Dictionary(e.get("art", {})).get("color", ""))):
			_flag(e, "art.color must be an html colour")
		for key: String in e.get("loot", {}):
			if not GRANT_KEYS.has(key):
				_flag(e, "loot key '%s' unknown (known: %s)" % [key, ", ".join(GRANT_KEYS)])
		for a: Variant in Dictionary(e.get("traits", {})).get("bonus_abilities", []):
			_ref(e, "abilities", String(a), "traits.bonus_abilities")


func _races() -> void:
	for r: Dictionary in _registry.get_all("races"):
		_check_art(r)
		var overlay: Dictionary = r.get("overlay", {})
		if not overlay.has("kind"):
			_flag(r, "overlay needs a kind")
		for a: Variant in Dictionary(r.get("traits", {})).get("bonus_abilities", []):
			_ref(r, "abilities", String(a), "traits.bonus_abilities")


func _parties() -> void:
	for p: Dictionary in _registry.get_all("parties"):
		var members: Array = p.get("members", [])
		if members.is_empty() or members.size() > 4:
			_flag(p, "members must be 1..4")
		for m: Dictionary in members:
			_ref(p, "races", String(m.get("race", "")), "member race")
			_ref(p, "classes", String(m.get("class", "")), "member class")


func _companions() -> void:
	for c: Dictionary in _registry.get_all("companions"):
		_ref(c, "races", String(c.get("race", "")), "race")
		_ref(c, "classes", String(c.get("class", "")), "class")
		var d: Dictionary = c.get("dialogue", {})
		for key: String in ["recruit", "talk", "banter"]:
			_ref(c, "dialogue", String(d.get(key, "")), "dialogue.%s" % key)
		_ref(c, "quests", String(c.get("quest", "")), "quest")
		var lean := String(c.get("faction", ""))
		if not lean.is_empty():
			_ref(c, "factions", lean, "faction")
		var ids: Array[String] = []
		for s: Dictionary in c.get("scenes", []):
			var sid := String(s.get("id", ""))
			if sid.is_empty() or ids.has(sid):
				_flag(c, "scene ids must be unique and non-empty")
			ids.append(sid)
			_keys_known(c, s, SCENE_KEYS, "scene %s" % sid)
			_ref(c, "dialogue", String(s.get("dialogue", "")), "scene %s dialogue" % sid)
			_keys_known(c, s.get("requires", {}), REQUIRES_KEYS, "scene %s requires" % sid)
			if bool(s.get("romance", false)) and not bool(c.get("romanceable", false)):
				_flag(c, "scene %s is a romance scene but the companion is not romanceable" % sid)


func _check_requires(e: Dictionary, block: Dictionary, what: String) -> void:
	_keys_known(e, block, REQUIRES_KEYS, what)
	for who: String in ["recruited", "not_recruited", "romance_open", "not_romance"]:
		if block.has(who) and not String(block[who]).is_empty():
			_ref(e, "companions", String(block[who]), "%s.%s" % [what, who])
	if block.has("race") and not String(block["race"]).is_empty():
		_ref(e, "races", String(block["race"]), "%s.race" % what)
	if block.has("quest"):
		var q: Dictionary = block["quest"]
		var quest := _registry.get_entry("quests", String(q.get("id", "")))
		if quest.is_empty():
			_flag(e, "%s.quest points at quest '%s', which does not exist" % [what, q.get("id", "")])
		elif not String(q.get("stage", "")).is_empty() and not Dictionary(quest.get("stages", {})).has(String(q.get("stage", ""))):
			_flag(e, "%s.quest stage '%s' is not a stage of '%s'" % [what, q.get("stage", ""), q.get("id", "")])


func _check_effects(e: Dictionary, fx: Dictionary, what: String) -> void:
	_keys_known(e, fx, EFFECT_KEYS, what)
	if fx.has("recruit"):
		_ref(e, "companions", String(fx["recruit"]), "%s.recruit" % what)
	if fx.has("dismiss"):
		_ref(e, "companions", String(fx["dismiss"]), "%s.dismiss" % what)
	if fx.has("lore"):
		_ref(e, "lore", String(fx["lore"]), "%s.lore" % what)
	if fx.has("dialogue"):
		_ref(e, "dialogue", String(fx["dialogue"]), "%s.dialogue" % what)
	if fx.has("join_faction"):
		_ref(e, "factions", String(fx["join_faction"]), "%s.join_faction" % what)
	if fx.has("quest"):
		var q: Dictionary = fx["quest"]
		var quest := _registry.get_entry("quests", String(q.get("id", "")))
		if quest.is_empty():
			_flag(e, "%s.quest points at quest '%s', which does not exist" % [what, q.get("id", "")])
		elif not Dictionary(quest.get("stages", {})).has(String(q.get("stage", ""))):
			_flag(e, "%s.quest stage '%s' is not a stage of '%s'" % [what, q.get("stage", ""), q.get("id", "")])
	for c: Variant in fx.get("approval", {}):
		_ref(e, "companions", String(c), "%s.approval" % what)
	for f: Variant in fx.get("reputation", {}):
		_ref(e, "factions", String(f), "%s.reputation" % what)
	for p: Dictionary in fx.get("enemies", []):
		_ref(e, "enemies", String(p.get("type", "")), "%s.enemies" % what)
	if fx.has("transition"):
		_ref(e, "maps", String(Dictionary(fx["transition"]).get("to", "")), "%s.transition" % what)
	for edit: Dictionary in fx.get("map_edits", []):
		_ref(e, "tiles", String(edit.get("tile", "")), "%s.map_edits" % what)
		if edit.has("map"):
			_ref(e, "maps", String(edit["map"]), "%s.map_edits" % what)
	var i := 0
	for step: Dictionary in fx.get("sequence", []):
		i += 1
		var body := step.duplicate()
		body.erase("camera")
		body.erase("pause")
		body.erase("when")
		_check_requires(e, step.get("when", {}), "%s.sequence step %d when" % [what, i])
		_check_effects(e, body, "%s.sequence step %d" % [what, i])


func _dialogue() -> void:
	for d: Dictionary in _registry.get_all("dialogue"):
		if String(d.get("kind", "")) == "banter":
			for line: Dictionary in d.get("lines", []):
				if not BANTER_TRIGGERS.has(String(line.get("trigger", ""))):
					_flag(d, "banter trigger must be one of %s" % ", ".join(BANTER_TRIGGERS))
				if String(line.get("text", "")).is_empty():
					_flag(d, "a banter line has no text")
				_check_requires(d, line.get("requires", {}), "banter requires")
				_check_effects(d, line.get("effects", {}), "banter effects")
			continue
		var nodes: Dictionary = d.get("nodes", {})
		if nodes.is_empty():
			_flag(d, "needs nodes (or kind \"banter\" with lines)")
			continue
		var starts: Array = []
		var start: Variant = d.get("start", "")
		if start is String:
			starts.append({"node": start})
		else:
			starts.assign(start)
		if starts.is_empty():
			_flag(d, "needs a start node (a string, or a list of {node, requires})")
		else:
			var last: Dictionary = starts[starts.size() - 1]
			if not Dictionary(last.get("requires", {})).is_empty():
				_flag(d, "the last start entry must be unconditional or some players dead-end")
		for s: Dictionary in starts:
			if not nodes.has(String(s.get("node", ""))):
				_flag(d, "start node '%s' does not exist" % s.get("node", ""))
			_check_requires(d, s.get("requires", {}), "start requires")
		for node_id: String in nodes:
			var node: Dictionary = nodes[node_id]
			if String(node.get("speaker", "")).is_empty():
				_flag(d, "node %s has no speaker" % node_id)
			var voice := String(node.get("voice", ""))
			if not voice.is_empty() and voice != "player" and not _has("companions", voice):
				_flag(d, "node %s borrows the voice of '%s', who is not a companion" % [node_id, voice])
			var choices: Array = node.get("choices", [])
			if choices.is_empty():
				_flag(d, "node %s has no choices" % node_id)
			var unconditional := false
			for c: Dictionary in choices:
				if c.has("next"):
					if not nodes.has(String(c["next"])):
						_flag(d, "node %s -> '%s' does not exist" % [node_id, c["next"]])
				elif not bool(c.get("end", false)):
					_flag(d, "node %s has a choice with neither next nor end" % node_id)
				if Dictionary(c.get("requires", {})).is_empty():
					unconditional = true
				_check_requires(d, c.get("requires", {}), "node %s requires" % node_id)
				_check_effects(d, c.get("effects", {}), "node %s effects" % node_id)
			if not unconditional and not choices.is_empty():
				_flag(d, "node %s could dead-end: every choice is conditional" % node_id)


func _quests() -> void:
	for q: Dictionary in _registry.get_all("quests"):
		var stages: Dictionary = q.get("stages", {})
		if not stages.has(String(q.get("start", ""))):
			_flag(q, "start stage '%s' does not exist" % q.get("start", ""))
		if bool(q.get("main", false)):
			if not String(q.get("companion", "")).is_empty():
				_flag(q, "a main quest has no companion")
		else:
			_ref(q, "companions", String(q.get("companion", "")), "companion")
		if q.has("faction"):
			_ref(q, "factions", String(q["faction"]), "faction")
		_check_requires(q, q.get("start_when", {}), "start_when")
		for stage_id: String in stages:
			var stage: Dictionary = stages[stage_id]
			for o: Dictionary in stage.get("objectives", []):
				if String(o.get("text", "")).is_empty():
					_flag(q, "stage %s has an objective without text" % stage_id)
				_check_requires(q, o.get("done_when", {}), "stage %s done_when" % stage_id)
			var site: Dictionary = stage.get("shard_site", {})
			if not site.is_empty():
				_ref(q, "pickups", String(site.get("pickup", "")), "stage %s shard_site" % stage_id)
				var pickup := _registry.get_entry("pickups", String(site.get("pickup", "")))
				if not pickup.is_empty() and not pickup.has("dialogue"):
					_flag(q, "stage %s shard_site pickup must open a dialogue" % stage_id)
				if site.has("template"):
					_ref(q, "shards", String(site["template"]), "stage %s shard_site.template" % stage_id)
			if stage.has("next") and not stages.has(String(stage["next"])):
				_flag(q, "stage %s next '%s' does not exist" % [stage_id, stage["next"]])
			for b: Dictionary in stage.get("branches", []):
				if not stages.has(String(b.get("next", ""))):
					_flag(q, "stage %s branch next '%s' does not exist" % [stage_id, b.get("next", "")])
				_check_requires(q, b.get("when", {}), "stage %s branch when" % stage_id)


func _maps() -> void:
	for m: Dictionary in _registry.get_all("maps"):
		var map := MapData.parse(m, _tiles)
		for err: String in map.errors:
			_flag(m, err)
		_ref(m, "biomes", map.biome_id, "biome")
		if map.spawn_cells().size() < 4:
			_flag(m, "needs 4 spawn cells for a full party")
		for cell: Vector2i in map.spawn_cells():
			if not map.is_walkable(cell):
				_flag(m, "spawn cell %s is not walkable" % cell)
		for d: Dictionary in m.get("doors", []): # S63: a hackable gate names the Tech it takes
			if d.has("hack_tech") and (not (d["hack_tech"] is float or d["hack_tech"] is int) or int(d["hack_tech"]) < 1):
				_flag(m, "doors[%s].hack_tech must be a whole number of at least 1" % [d.get("cell", [])])
		var seen: Array[Vector2i] = []
		for p: Dictionary in m.get("enemies", []):
			_ref(m, "enemies", String(p.get("type", "")), "enemies")
			var cell := _cell(p)
			if not map.is_walkable(cell):
				_flag(m, "enemy %s placed on blocked %s" % [p.get("type", ""), cell])
			if seen.has(cell) or map.spawn_cells().has(cell):
				_flag(m, "enemy placement at %s overlaps another or a spawn" % cell)
			seen.append(cell)
		for p: Dictionary in m.get("npcs", []):
			var cell := _cell(p)
			if not map.is_walkable(cell):
				_flag(m, "npc placement at %s is not walkable" % cell)
			if p.has("merchant"):
				_ref(m, "merchants", String(p["merchant"]), "npcs.merchant")
			elif p.has("npc"):
				_ref(m, "npcs", String(p["npc"]), "npcs.npc")
			else:
				_ref(m, "companions", String(p.get("companion", "")), "npcs.companion")
			_check_requires(m, p.get("when", {}), "npc %s when" % cell)
		for p: Dictionary in m.get("pickups", []):
			_ref(m, "pickups", String(p.get("type", "")), "pickups")
		for err: String in ShardValidator.validate(m, _tiles):
			_flag(m, err)
		for t: Dictionary in m.get("transitions", []):
			_ref(m, "maps", String(t.get("to", "")), "transition")
			_check_requires(m, t.get("when", {}), "transition when")
		for t: Dictionary in m.get("triggers", []):
			var id := String(t.get("id", "?"))
			_check_requires(m, t.get("when", {}), "trigger %s when" % id)
			_check_effects(m, t.get("effects", {}), "trigger %s effects" % id)
		for b: Dictionary in m.get("buildings", []):
			_ref(m, "buildings", String(b.get("id", "")), "buildings")


func _cell(p: Dictionary) -> Vector2i:
	var raw: Array = p.get("cell", [])
	if raw.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(raw[0]), int(raw[1]))


func _shards() -> void:
	for t: Dictionary in _registry.get_all("shards"):
		_ref(t, "biomes", String(t.get("biome", "")), "biome")
		var tiles: Dictionary = t.get("tiles", {})
		for role: String in ["wall", "floor", "grate", "debris", "extraction"]:
			_ref(t, "tiles", String(tiles.get(role, "")), "tiles.%s" % role)
		var expanded := ShardGenerator.expand_remix(t, _registry)
		var pool: Array = Dictionary(expanded.get("enemies", {})).get("pool", [])
		if pool.is_empty():
			_flag(t, "enemies.pool is empty")
		for p: Dictionary in pool:
			_ref(t, "enemies", String(p.get("type", "")), "enemies.pool")
			if float(p.get("weight", 0)) <= 0.0:
				_flag(t, "enemies.pool weight must be positive")
		for p: Dictionary in Dictionary(t.get("pickups", {})).get("pool", []):
			_ref(t, "pickups", String(p.get("type", "")), "pickups.pool")
		var boss: Dictionary = Dictionary(expanded.get("enemies", {})).get("boss", {})
		if boss.has("type"):
			_ref(t, "enemies", String(boss["type"]), "enemies.boss")


func _pickups() -> void:
	for p: Dictionary in _registry.get_all("pickups"):
		if p.has("dialogue"):
			_ref(p, "dialogue", String(p["dialogue"]), "dialogue")
		elif Dictionary(p.get("grants", {})).is_empty():
			_flag(p, "needs grants or a dialogue")
		for key: String in p.get("grants", {}):
			if not GRANT_KEYS.has(key):
				_flag(p, "grant key '%s' unknown (known: %s)" % [key, ", ".join(GRANT_KEYS)])
		if not Color.html_is_valid(String(Dictionary(p.get("art", {})).get("color", ""))):
			_flag(p, "art.color must be an html colour")


func _buildings() -> void:
	for b: Dictionary in _registry.get_all("buildings"):
		var levels: Array = b.get("levels", [])
		if levels.size() < 2:
			_flag(b, "needs at least two levels (the free base and an upgrade)")
			continue
		if not Dictionary(Dictionary(levels[0]).get("cost", {})).is_empty():
			_flag(b, "level 0 must be free")
		for lv: Dictionary in levels:
			for key: String in lv.get("cost", {}):
				if not Ledger.RESOURCES.has(key):
					_flag(b, "cost key '%s' unknown" % key)
			_keys_known(b, lv.get("effects", {}), BUILDING_EFFECTS, "level effects")


func _factions() -> void:
	for f: Dictionary in _registry.get_all("factions"):
		if not Color.html_is_valid(String(f.get("color", ""))):
			_flag(f, "color must be an html colour")
		for r: Variant in f.get("rivals", []):
			_ref(f, "factions", String(r), "rivals")
		if f.has("envoy"):
			_ref(f, "npcs", String(f["envoy"]), "envoy")
		if f.has("vendor"):
			_ref(f, "merchants", String(f["vendor"]), "vendor")
		if f.has("area"):
			_ref(f, "maps", String(f["area"]), "area")
		for k: Variant in f.get("join_reputation", {}):
			_ref(f, "factions", String(k), "join_reputation")


func _npcs() -> void:
	for n: Dictionary in _registry.get_all("npcs"):
		_ref(n, "dialogue", String(n.get("dialogue", "")), "dialogue")
		var f := String(n.get("faction", ""))
		if not f.is_empty():
			_ref(n, "factions", f, "faction")


func _merchants() -> void:
	for m: Dictionary in _registry.get_all("merchants"):
		var stock: Variant = m.get("stock", [])
		if not stock is Array:
			_flag(m, "stock must be a list")
			continue
		for s: Variant in stock:
			if s is Dictionary and Dictionary(s).has("item"):
				_ref(m, "items", String(Dictionary(s)["item"]), "stock.item")
			if s is Dictionary and Dictionary(Dictionary(s).get("effect", {})).has("item"):
				_ref(m, "items", String(Dictionary(Dictionary(s)["effect"])["item"]), "stock.effect.item")


func _items() -> void:
	for i: Dictionary in _registry.get_all("items"):
		if String(i.get("slot", "")).is_empty():
			_flag(i, "slot is empty")
		if not Color.html_is_valid(String(Dictionary(i.get("art", {})).get("color", ""))):
			_flag(i, "art.color must be an html colour")
	for a: Dictionary in _registry.get_all("affixes"):
		if Array(a.get("slots", [])).is_empty():
			_flag(a, "slots is empty")


func _endings() -> void:
	for e: Dictionary in _registry.get_all("endings"):
		var when: Dictionary = e.get("when", {})
		_check_requires(e, when, "when")
		for m: Dictionary in e.get("modifiers", []):
			if String(m.get("text", "")).is_empty():
				_flag(e, "a modifier has no text")
			_check_requires(e, m.get("when", {}), "modifier when")
		var epilogue: Dictionary = e.get("epilogue", {})
		for id: String in epilogue:
			_ref(e, "companions", id, "epilogue")
			_keys_known(e, epilogue[id], EPILOGUE_KEYS, "epilogue %s" % id)


func _achievements() -> void:
	var seen: Dictionary = {}
	for a: Dictionary in _registry.get_all("achievements"):
		var sid := String(a.get("steam_id", ""))
		if not sid.begins_with("ACH_") or sid != sid.to_upper():
			_flag(a, "steam_id must look like ACH_UPPER_CASE")
		if seen.has(sid):
			_flag(a, "steam_id '%s' is also used by %s" % [sid, seen[sid]])
		seen[sid] = a["id"]
		_check_requires(a, a.get("when", {}), "when")


## A difficulty is a rules overlay (S50): every block names a rules entry and
## every key in it a field that entry already has, so a typo cannot silently
## do nothing. Exactly one base-game difficulty is the default.
func _difficulties() -> void:
	var defaults := 0
	for d: Dictionary in _registry.get_all("difficulties"):
		if bool(d.get("default", false)):
			defaults += 1
		var overlays: Variant = d.get("rules", {})
		if not overlays is Dictionary:
			_flag(d, "rules must be a dictionary of {rules entry id: {field: value}}")
			continue
		for rule_id: String in overlays:
			if not _has("rules", rule_id):
				_flag(d, "rules.%s overrides rules '%s', which does not exist" % [rule_id, rule_id])
				continue
			var base: Dictionary = _registry.get_entry("rules", rule_id)
			var block: Variant = overlays[rule_id]
			if not block is Dictionary:
				_flag(d, "rules.%s must be a dictionary of overrides" % rule_id)
				continue
			for key: String in block:
				if not base.has(key):
					_flag(d, "rules.%s overrides '%s', which rules/%s does not have" % [rule_id, key, rule_id])
	if defaults != 1 and _sources.is_empty() and not _registry.get_all("difficulties").is_empty():
		_flag(_registry.get_all("difficulties")[0], "exactly one difficulty must be the default (found %d)" % defaults)


## A race or enemy draws with a sheet that exists or says it is a placeholder (S56).
func _check_art(e: Dictionary) -> void:
	var art: Dictionary = e.get("art", {})
	var sheet := String(art.get("sheet", ""))
	if not sheet.is_empty():
		_ref(e, "sprites", sheet, "art.sheet")
	elif String(art.get("placeholder", "")) != "rig":
		_flag(e, "art needs a sheet or a documented placeholder (\"placeholder\": \"rig\")")


func _misc() -> void:
	for s: Dictionary in _registry.get_all("sprites"):
		var image := String(s.get("image", ""))
		if image.is_empty():
			continue
		var image_path := String(s.get("_path", "")).get_base_dir().path_join(image)
		var why := MediaLimits.check_image(image_path)
		if not why.is_empty():
			_flag(s, "image '%s' %s" % [image, why])
	for t: Dictionary in _registry.get_all("tiles"):
		var glow := String(Dictionary(t.get("art", {})).get("glow", ""))
		var t_art: Dictionary = t.get("art", {})
		if t_art.has("flicker") and not (t_art["flicker"] is bool):
			_flag(t, "art.flicker must be true or false")
		if bool(t_art.get("flicker", false)) and glow.is_empty():
			_flag(t, "art.flicker needs an art.glow to flicker")
		if glow.is_empty():
			continue
		for b: Dictionary in _registry.get_all("biomes"):
			if not Dictionary(b.get("palette", {})).has(glow):
				_flag(t, "art.glow role '%s' is not in the %s palette" % [glow, b["id"]])
	for b: Dictionary in _registry.get_all("biomes"):
		var raw_palette: Variant = b.get("palette", [])
		var palette: Array = raw_palette.values() if raw_palette is Dictionary else Array(raw_palette)
		if palette.size() != 16:
			_flag(b, "palette must have 16 colours")
		for c: Variant in palette:
			if not Color.html_is_valid(String(c)):
				_flag(b, "palette colour '%s' is not an html colour" % c)
	for br: Dictionary in _registry.get_all("branches"):
		if not Color.html_is_valid(String(br.get("color", ""))):
			_flag(br, "color must be an html colour")
	for t: Dictionary in _registry.get_all("tiles"):
		if not (t.get("walkable", null) is bool):
			_flag(t, "walkable must be true or false")
	for a: Dictionary in _registry.get_all("audio"):
		if not ["sfx", "music"].has(String(a.get("kind", ""))):
			_flag(a, "kind must be sfx or music")
		var file := String(a.get("file", ""))
		if not file.is_empty():
			var path := String(a.get("_path", "")).get_base_dir().path_join(file)
			if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
				_flag(a, "file '%s' is not beside the sidecar (the synth would play instead)" % file)
			elif not ["wav", "ogg", "mp3"].has(file.get_extension().to_lower()):
				_flag(a, "file '%s' must be .wav, .ogg or .mp3" % file)
			elif FileAccess.file_exists(path) and not MediaLimits.check_audio(path).is_empty():
				_flag(a, "file '%s' %s" % [file, MediaLimits.check_audio(path)])
		if a.has("loop") and not (a["loop"] is bool):
			_flag(a, "loop must be true or false")
	for o: Dictionary in _registry.get_all("origins"):
		if String(o.get("dialogue_tag", "")).is_empty():
			_flag(o, "dialogue_tag is empty")
	var defaults: Array[Dictionary] = []
	for l: Dictionary in _registry.get_all("loadouts"):
		for item_id: Variant in l.get("items", []):
			_ref(l, "items", String(item_id), "items")
		var res: Dictionary = l.get("resources", {})
		for key: String in res:
			if not Ledger.RESOURCES.has(key):
				_flag(l, "resources.%s is not a resource" % key)
		if l.has("unlock_flag") and String(l.get("unlock_flag", "")).is_empty():
			_flag(l, "unlock_flag is empty")
		if bool(l.get("default", false)):
			defaults.append(l)
	if defaults.size() > 1:
		for l: Dictionary in defaults:
			_flag(l, "%d loadouts say default; one may" % defaults.size())
	var look: Dictionary = _registry.get_entry("rules", "appearance")
	for part: String in ["tones", "accents"]:
		for o: Variant in look.get(part, []):
			if not (o is Dictionary):
				_flag(look, "%s entries must be objects" % part)
				continue
			var opt: Dictionary = o
			if String(opt.get("id", "")).is_empty() or String(opt.get("name", "")).is_empty():
				_flag(look, "%s entry needs an id and a name" % part)
			if not Color.html_is_valid(String(opt.get("color", ""))):
				_flag(look, "%s '%s' color is not an html colour" % [part, String(opt.get("id", ""))])
			if opt.has("unlock_flag") and String(opt.get("unlock_flag", "")).is_empty():
				_flag(look, "%s '%s' unlock_flag is empty" % [part, String(opt.get("id", ""))])
	for l: Dictionary in _registry.get_all("lore"):
		if int(l.get("order", 0)) < 1:
			_flag(l, "order must be at least 1")


## The command line: `--mods=<dir>` (a root holding mod folders, or one mod
## folder with a mod.json), `--all` to report base-game problems too.
## Returns {"lines": [...], "code": 0|1}.
static func run_cli(args: PackedStringArray) -> Dictionary:
	var lines: Array[String] = []
	var mods_root := ""
	var all := false
	for arg: String in args:
		if arg.begins_with("--mods="):
			mods_root = arg.get_slice("=", 1)
		elif arg == "--all":
			all = true
	if mods_root.is_empty():
		lines.append("usage: godot --headless --path . -s tools/validate_mods.gd -- --mods=<folder> [--all]")
		lines.append("  <folder> holds mod folders (each with mod.json and content/), or is one such mod folder.")
		return {"lines": lines, "code": 2}
	var root := mods_root
	if FileAccess.file_exists(mods_root.path_join(ContentRegistry.MOD_MANIFEST)):
		root = mods_root.get_base_dir() # one mod: scan its parent, report only it
	var registry := ContentRegistry.new()
	var roots: Array[String] = [root]
	registry.load_from(ContentRegistry.BASE_ROOT, roots)
	var sources: Array[String] = []
	for m: Dictionary in registry.loaded_mods:
		if root == mods_root or String(m["path"]).simplify_path() == mods_root.simplify_path():
			sources.append(String(m["id"]))
	for m: Dictionary in registry.loaded_mods:
		if sources.has(String(m["id"])):
			lines.append("loaded mod %s %s (priority %d) from %s" % [m["id"], m["version"], m["priority"], m["path"]])
	if sources.is_empty():
		lines.append("no mod found under %s (a mod is a folder with mod.json and content/)" % mods_root)
	var problems := 0
	for err: String in registry.load_errors:
		lines.append("load error: %s" % err)
		problems += 1
	for p: String in validate(registry, [] if all else sources):
		lines.append(p)
		problems += 1
	var counted := 0
	for kind: String in registry.kinds():
		for e: Dictionary in registry.get_all(kind):
			if sources.has(String(e.get("_source", ""))):
				counted += 1
	lines.append("%d mod entr%s checked, %d problem%s" % [counted, "y" if counted == 1 else "ies", problems, "" if problems == 1 else "s"])
	registry.free()
	return {"lines": lines, "code": 1 if problems > 0 else 0}
