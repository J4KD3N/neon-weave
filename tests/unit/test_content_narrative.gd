## Cross-reference checks for companions, dialogue graphs, quests and map
## NPC placements. Every graph must be reachable and never dead-end.
extends TestCase

const KNOWN_TRIGGERS: Array[String] = ["enter_shard", "victory", "extract"]
const EFFECT_KEYS: Array[String] = ContentValidator.EFFECT_KEYS
const REQUIRES_KEYS: Array[String] = ContentValidator.REQUIRES_KEYS # one vocabulary (S45)

var registry: ContentRegistry


func before_each() -> void:
	registry = ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [])


func after_each() -> void:
	registry.free()


func test_companions_reference_existing_content() -> void:
	var companions := registry.get_all("companions")
	assert_true(companions.size() >= 1)
	for c: Dictionary in companions:
		assert_true(registry.has_entry("races", String(c.get("race", ""))), "companion %s race" % c["id"])
		assert_true(registry.has_entry("classes", String(c.get("class", ""))), "companion %s class" % c["id"])
		var d: Dictionary = c.get("dialogue", {})
		for key: String in ["recruit", "talk", "banter"]:
			assert_true(registry.has_entry("dialogue", String(d.get(key, ""))), "companion %s dialogue.%s" % [c["id"], key])
		assert_true(registry.has_entry("quests", String(c.get("quest", ""))), "companion %s quest" % c["id"])


func test_dialogue_graphs_are_well_formed() -> void:
	for d: Dictionary in registry.get_all("dialogue"):
		if String(d.get("kind", "")) == "banter":
			_check_banter(d)
			continue
		var nodes: Dictionary = d.get("nodes", {})
		assert_true(nodes.size() >= 1, "dialogue %s nodes" % d["id"])
		var starts: Array = []
		var start: Variant = d.get("start", "")
		if start is String:
			starts.append({"node": start})
		else:
			starts.assign(start)
		assert_true(starts.size() >= 1, "dialogue %s start" % d["id"])
		var last: Dictionary = starts[starts.size() - 1]
		assert_true(Dictionary(last.get("requires", {})).is_empty(), "dialogue %s last start entry must be unconditional" % d["id"])
		for s: Dictionary in starts:
			assert_true(nodes.has(String(s.get("node", ""))), "dialogue %s start node %s" % [d["id"], s.get("node")])
		for node_id: String in nodes:
			_check_node(d, node_id, nodes)


func _check_node(d: Dictionary, node_id: String, nodes: Dictionary) -> void:
	var node: Dictionary = nodes[node_id]
	assert_false(String(node.get("speaker", "")).is_empty(), "dialogue %s node %s speaker" % [d["id"], node_id])
	var choices: Array = node.get("choices", [])
	assert_true(choices.size() >= 1, "dialogue %s node %s has choices" % [d["id"], node_id])
	var unconditional := false
	for c: Dictionary in choices:
		if c.has("next"):
			assert_true(nodes.has(String(c["next"])), "dialogue %s node %s -> %s" % [d["id"], node_id, c["next"]])
		else:
			assert_true(bool(c.get("end", false)), "dialogue %s node %s choice needs next or end" % [d["id"], node_id])
		if Dictionary(c.get("requires", {})).is_empty():
			unconditional = true
		for k: String in c.get("requires", {}):
			assert_true(REQUIRES_KEYS.has(k), "dialogue %s requires.%s" % [d["id"], k])
		var fx: Dictionary = c.get("effects", {})
		for k: String in fx:
			assert_true(EFFECT_KEYS.has(k), "dialogue %s effects.%s" % [d["id"], k])
		if fx.has("recruit"):
			assert_true(registry.has_entry("companions", String(fx["recruit"])), "dialogue %s recruits unknown %s" % [d["id"], fx["recruit"]])
		if fx.has("quest"):
			var q: Dictionary = fx["quest"]
			var quest := registry.get_entry("quests", String(q.get("id", "")))
			assert_false(quest.is_empty(), "dialogue %s unknown quest" % d["id"])
			assert_true(Dictionary(quest.get("stages", {})).has(String(q.get("stage", ""))), "dialogue %s quest stage %s" % [d["id"], q.get("stage")])
	assert_true(unconditional, "dialogue %s node %s could dead-end for some players" % [d["id"], node_id])


func _check_banter(d: Dictionary) -> void:
	for line: Dictionary in d.get("lines", []):
		assert_true(KNOWN_TRIGGERS.has(String(line.get("trigger", ""))), "banter %s trigger" % d["id"])
		assert_false(String(line.get("text", "")).is_empty(), "banter %s text" % d["id"])
		for k: String in line.get("requires", {}):
			assert_true(REQUIRES_KEYS.has(k), "banter %s requires.%s" % [d["id"], k])
		for k: String in line.get("effects", {}):
			assert_true(EFFECT_KEYS.has(k), "banter %s effects.%s" % [d["id"], k])


func test_quests_and_sites() -> void:
	for q: Dictionary in registry.get_all("quests"):
		var stages: Dictionary = q.get("stages", {})
		assert_true(stages.has(String(q.get("start", ""))), "quest %s start stage" % q["id"])
		if bool(q.get("main", false)):
			assert_true(String(q.get("companion", "")).is_empty(), "main quest %s has no companion" % q["id"])
		else:
			assert_true(registry.has_entry("companions", String(q.get("companion", ""))), "quest %s companion" % q["id"])
		for stage_id: String in stages:
			for o: Dictionary in Dictionary(stages[stage_id]).get("objectives", []):
				assert_false(String(o.get("text", "")).is_empty(), "quest %s stage %s objective text" % [q["id"], stage_id])
				for k: String in o.get("done_when", {}):
					assert_true(REQUIRES_KEYS.has(k), "quest %s objective done_when.%s" % [q["id"], k])
		for stage_id: String in stages:
			var site: Dictionary = Dictionary(stages[stage_id]).get("shard_site", {})
			if not site.is_empty():
				var pickup := registry.get_entry("pickups", String(site.get("pickup", "")))
				assert_false(pickup.is_empty(), "quest %s stage %s site pickup" % [q["id"], stage_id])
				assert_true(registry.has_entry("dialogue", String(pickup.get("dialogue", ""))), "quest site pickup must open a dialogue")


func test_map_npcs_are_companions_on_walkable_cells() -> void:
	var tiles: Dictionary = {}
	for t: Dictionary in registry.get_all("tiles"):
		tiles[t["id"]] = t
	var found := 0
	for m: Dictionary in registry.get_all("maps"):
		var map := MapData.parse(m, tiles)
		for p: Dictionary in m.get("npcs", []):
			var raw: Array = p.get("cell", [])
			assert_true(map.is_walkable(Vector2i(int(raw[0]), int(raw[1]))), "map %s npc cell" % m["id"])
			if p.has("merchant"):
				assert_true(registry.has_entry("merchants", String(p["merchant"])), "map %s merchant" % m["id"])
				continue
			if p.has("npc"):
				var npc := registry.get_entry("npcs", String(p["npc"]))
				assert_false(npc.is_empty(), "map %s story npc %s" % [m["id"], p["npc"]])
				assert_true(registry.has_entry("dialogue", String(npc.get("dialogue", ""))), "npc %s dialogue" % p["npc"])
				assert_true(registry.has_entry("factions", String(npc.get("faction", ""))) or String(npc.get("faction", "")).is_empty(), "npc %s faction" % p["npc"])
				for k: String in p.get("when", {}):
					assert_true(REQUIRES_KEYS.has(k), "map %s npc when.%s" % [m["id"], k])
				continue
			found += 1
			assert_true(registry.has_entry("companions", String(p.get("companion", ""))), "map %s npc" % m["id"])
			for k: String in p.get("when", {}):
				assert_true(REQUIRES_KEYS.has(k), "map %s companion when.%s" % [m["id"], k])
	assert_true(found >= 1, "Sera stands somewhere")


## Quarters scenes (S35, S37): every scene opens a real dialogue, its gates
## use the condition vocabulary, romance scenes belong to romanceable
## companions only, and every romanceable companion has a spark, a
## commitment, a night and a scene for their death (D-092).
func test_quarters_scenes_are_well_formed_and_every_romance_is_complete() -> void:
	var romanceable := 0
	for c: Dictionary in registry.get_all("companions"):
		var ids: Array[String] = []
		var romance_scenes := 0
		var dead_scenes := 0
		var commits := 0
		for s: Dictionary in c.get("scenes", []):
			var sid := String(s.get("id", ""))
			assert_false(sid.is_empty() or ids.has(sid), "companion %s scene id %s" % [c["id"], sid])
			ids.append(sid)
			var d := registry.get_entry("dialogue", String(s.get("dialogue", "")))
			assert_false(d.is_empty(), "companion %s scene %s dialogue" % [c["id"], sid])
			for k: String in s.get("requires", {}):
				assert_true(REQUIRES_KEYS.has(k), "companion %s scene %s requires.%s" % [c["id"], sid, k])
			assert_true(int(s.get("quarters", 1)) >= 1, "scene %s needs the Quarters" % sid)
			if bool(s.get("romance", false)):
				assert_true(bool(c.get("romanceable", false)), "companion %s is not romanceable but scene %s is a romance" % [c["id"], sid])
				romance_scenes += 1
				for node_id: String in d.get("nodes", {}):
					for ch: Dictionary in Dictionary(d["nodes"][node_id]).get("choices", []):
						var r: Dictionary = Dictionary(ch.get("effects", {})).get("romance", {})
						if r.has("commit"):
							assert_eq(String(r["commit"]), String(c["id"]), "scene %s commits to its own companion" % sid)
							commits += 1
			if bool(s.get("dead", false)):
				dead_scenes += 1
				assert_true(Dictionary(Dictionary(s.get("requires", {})).get("flags", {})).has("romance_%s_lost" % c["id"]) or not bool(c.get("romanceable", false)), "a romanceable companion's death scene reads romance_<id>_lost")
		if bool(c.get("romanceable", false)):
			romanceable += 1
			assert_true(romance_scenes >= 3, "companion %s: spark, commitment and a night" % c["id"])
			assert_eq(commits, 1, "companion %s: exactly one commitment" % c["id"])
			assert_true(dead_scenes >= 1, "companion %s: a dead partner is a scene, not a crash" % c["id"])
		else:
			assert_eq(romance_scenes, 0, "companion %s has no romance" % c["id"])
	assert_eq(romanceable, 4, "Sera, Kaj-7, Whisper and Yev")


## Borrowed voices (S40): a node's `voice` is a companion or "player"; quests
## with `start_when` use the condition vocabulary and have a start stage.
func test_borrowed_voices_and_start_when_are_well_formed() -> void:
	var voices := 0
	for d: Dictionary in registry.get_all("dialogue"):
		for node_id: String in d.get("nodes", {}):
			var v := String(Dictionary(d["nodes"][node_id]).get("voice", ""))
			if v.is_empty():
				continue
			voices += 1
			assert_true(v == "player" or registry.has_entry("companions", v), "dialogue %s node %s borrows an unknown voice %s" % [d["id"], node_id, v])
	assert_true(voices >= 21, "the Choir borrows every companion's voice three times")
	var started := 0
	for q: Dictionary in registry.get_all("quests"):
		if not q.has("start_when"):
			continue
		started += 1
		for k: String in q["start_when"]:
			assert_true(REQUIRES_KEYS.has(k), "quest %s start_when.%s" % [q["id"], k])
		assert_true(Dictionary(q.get("stages", {})).has(String(q.get("start", ""))), "quest %s start stage" % q["id"])
	assert_true(started >= 1, "Stolen Voices starts itself")


## Key delves (S41): a site bound to a template names a real Shard template,
## and the catastrophe's conditional steps use the condition vocabulary.
func test_bound_sites_and_sequence_steps_are_well_formed() -> void:
	var bound := 0
	for q: Dictionary in registry.get_all("quests"):
		for stage_id: String in q.get("stages", {}):
			var site: Dictionary = Dictionary(Dictionary(q["stages"])[stage_id]).get("shard_site", {})
			if site.has("template"):
				bound += 1
				assert_true(registry.has_entry("shards", String(site["template"])), "quest %s stage %s site template" % [q["id"], stage_id])
	assert_eq(bound, 4, "three Keys, one biome each, and the Loom's door")
	var conditional := 0
	for m: Dictionary in registry.get_all("maps"):
		for t: Dictionary in m.get("triggers", []):
			for step: Dictionary in Dictionary(t.get("effects", {})).get("sequence", []):
				for k: String in step.get("when", {}):
					conditional += 1
					assert_true(REQUIRES_KEYS.has(k), "map %s trigger %s step when.%s" % [m["id"], t.get("id"), k])
				if step.has("dismiss"):
					assert_true(registry.has_entry("companions", String(step["dismiss"])), "map %s dismisses a stranger" % m["id"])
	assert_true(conditional >= 10, "the catastrophe branches on prior choices")


## Endings (S43): modifiers use the condition vocabulary, epilogue keys are
## the known ladder, every companion has alive, dead and taken lines in
## every ending, and romanced/lost lines only belong to romanceable ones.
func test_endings_write_every_companion() -> void:
	var keys: Array[String] = ["alive", "dead", "absent", "taken", "loyal", "romanced", "lost"]
	for e: Dictionary in registry.get_all("endings"):
		for k: String in e.get("when", {}):
			assert_true(REQUIRES_KEYS.has(k) or k == "party_approval_min", "ending %s when.%s" % [e["id"], k])
		for m: Dictionary in e.get("modifiers", []):
			assert_false(String(m.get("text", "")).is_empty(), "ending %s modifier text" % e["id"])
			for k: String in m.get("when", {}):
				assert_true(REQUIRES_KEYS.has(k), "ending %s modifier when.%s" % [e["id"], k])
		var epilogue: Dictionary = e.get("epilogue", {})
		for c: Dictionary in registry.get_all("companions"):
			var id := String(c["id"])
			assert_true(epilogue.has(id), "ending %s writes %s" % [e["id"], id])
			var lines: Dictionary = epilogue.get(id, {})
			for k: String in lines:
				assert_true(keys.has(k), "ending %s %s epilogue key %s" % [e["id"], id, k])
				if k == "romanced" or k == "lost":
					assert_true(bool(c.get("romanceable", false)), "ending %s writes a %s line for %s, who has no romance" % [e["id"], k, id])
			for need: String in ["alive", "dead", "taken"]:
				assert_false(String(lines.get(need, "")).is_empty(), "ending %s: %s has no %s line" % [e["id"], id, need])


## The reactivity budget (S44, D-099): every playable race has a gated
## line in every act (by its id or one of its tags), every origin tag is
## used more than once, the NPCs react to a Hollow in the party and to a
## Swarmborn whose disguise slips, and a skill check exists in every act.
func test_every_race_has_gated_lines_in_every_act() -> void:
	var per_race: Dictionary = {}
	var per_origin: Dictionary = {}
	var party_reactions := 0
	var disguise_lines := 0
	var skill_checks: Dictionary = {1: 0, 2: 0, 3: 0}
	var tags_of: Dictionary = {}
	for r: Dictionary in registry.get_all("races"):
		tags_of[r["id"]] = Dictionary(r.get("traits", {})).get("tags", [])
		per_race[r["id"]] = {1: 0, 2: 0, 3: 0}
	for d: Dictionary in registry.get_all("dialogue"):
		if String(d.get("kind", "")) == "banter":
			continue
		var act := int(d.get("act", 0))
		assert_true(act >= 1 and act <= 3, "dialogue %s carries its act" % d["id"])
		var gates: Array = []
		for s: Dictionary in d.get("start", []) if d.get("start", "") is Array else []:
			gates.append(s.get("requires", {}))
		for node_id: String in d.get("nodes", {}):
			for c: Dictionary in Dictionary(d["nodes"][node_id]).get("choices", []):
				gates.append(c.get("requires", {}))
		for g: Dictionary in gates:
			if g.has("party_race") or g.has("party_race_tag"):
				party_reactions += 1
			if g.has("disguised"):
				disguise_lines += 1
			if g.has("attribute"):
				skill_checks[act] += 1
			if g.has("origin_tag"):
				per_origin[g["origin_tag"]] = int(per_origin.get(g["origin_tag"], 0)) + 1
			for race_id: String in per_race:
				if String(g.get("race", "")) == race_id or (g.has("race_tag") and Array(tags_of[race_id]).has(String(g["race_tag"]))):
					per_race[race_id][act] = int(per_race[race_id][act]) + 1
	for race_id: String in per_race:
		var counts: Dictionary = per_race[race_id]
		print("  reactivity %-10s act 1: %d  act 2: %d  act 3: %d" % [race_id, counts[1], counts[2], counts[3]])
		for act: int in [1, 2, 3]:
			assert_true(int(counts[act]) >= 1, "%s has no gated line in act %d" % [race_id, act])
	for o: Dictionary in registry.get_all("origins"):
		var tag := String(o.get("dialogue_tag", ""))
		assert_true(int(per_origin.get(tag, 0)) >= 2, "origin tag %s is used %d times" % [tag, int(per_origin.get(tag, 0))])
	assert_true(party_reactions >= 2, "NPCs react to who walks behind you")
	assert_true(disguise_lines >= 3, "the Swarmborn disguise is checked")
	for act: int in [1, 2, 3]:
		assert_true(int(skill_checks[act]) >= 1, "a skill check in act %d" % act)
