## Character sheet, creator model, party builder, stat derivation with
## attributes/origins, and race overlays on the shared paper-doll.
extends TestCase

const VEX: Dictionary = {"name": "Vex", "race_id": "chromed", "origin_id": "corp_asset", "class_id": "circuit_witch", "attributes": {"body": 1, "arcane": 3, "tech": 2}}

var registry: ContentRegistry
var rules: CombatRules
var attr_rules: Dictionary


func before_each() -> void:
	registry = ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [])
	rules = CombatRules.from_entry(registry.get_entry("rules", "combat"))
	attr_rules = registry.get_entry("rules", "attributes")


func after_each() -> void:
	registry.free()


func test_default_sheet_is_valid_and_round_trips() -> void:
	var s := CharacterSheet.new()
	assert_eq(s.validate(registry, attr_rules), [])
	var back := CharacterSheet.from_dict(s.to_dict())
	assert_eq(back.to_dict(), s.to_dict())
	assert_eq(CharacterSheet.from_dict(VEX).attribute("arcane"), 3)


func test_sheet_validation_errors() -> void:
	var s := CharacterSheet.from_dict(VEX)
	assert_eq(s.validate(registry, attr_rules), [])
	s.race_id = "elf"
	s.name = "   "
	s.attributes = {"body": 5, "arcane": 1, "tech": 0, "luck": 0}
	var errors := s.validate(registry, attr_rules)
	assert_any_contains(errors, "unknown race 'elf'")
	assert_any_contains(errors, "name is empty")
	assert_any_contains(errors, "unknown attribute 'luck'")
	assert_any_contains(errors, "body must be between 0 and 4")
	s.attributes = {"body": 1, "arcane": 1, "tech": 1}
	assert_any_contains(s.validate(registry, attr_rules), "spend 3 of 6 points")


func test_creator_state_lists_options_and_cycles() -> void:
	var st := CreatorState.new()
	st.setup(registry, rules)
	assert_eq(st.races.size(), 5, "M2 races: trueborn, chromed, aetherborn, synth, rootkin")
	assert_eq(st.origins.size(), 4)
	assert_eq(st.classes.size(), 4)
	assert_eq(st.rows, ["name", "race", "origin", "class", "body", "arcane", "tech"])
	assert_eq(st.current_row(), "race")
	var first := st.sheet.race_id
	assert_true(st.adjust(1))
	assert_ne(st.sheet.race_id, first)
	for _i: int in st.races.size() - 1:
		st.adjust(1)
	assert_eq(st.sheet.race_id, first, "wraps around")
	st.move_row(-2)
	assert_eq(st.current_row(), "tech", "wraps upward past the name row")
	st.move_row(-10)
	assert_eq(st.current_row(), "class")


func test_creator_points_budget() -> void:
	var st := CreatorState.new()
	st.setup(registry, rules)
	assert_eq(st.points_left(), 0)
	st.row = st.rows.find("body")
	assert_false(st.adjust(1), "no points left")
	assert_true(st.adjust(-1))
	assert_eq(st.points_left(), 1)
	assert_true(st.adjust(1))
	assert_eq(st.points_left(), 0)
	st.row = st.rows.find("tech")
	st.adjust(-1)
	st.adjust(-1)
	assert_false(st.adjust(-1), "floor at 0")
	assert_eq(st.sheet.attribute("tech"), 0)
	assert_false(st.is_valid(), "2 points unspent")
	st.row = st.rows.find("arcane")
	st.adjust(1)
	st.adjust(1)
	assert_eq(st.sheet.attribute("arcane"), 4)
	assert_false(st.adjust(1), "cap of 4")
	assert_true(st.is_valid())


func test_creator_render_and_preview() -> void:
	var st := CreatorState.new()
	st.setup(registry, rules, VEX)
	assert_eq(st.sheet.name, "Vex")
	var text := st.render()
	assert_contains(text, "NEW WEAVER")
	assert_contains(text, "▶ Race: Chromed")
	assert_contains(text, "Origin: Corp Asset")
	assert_contains(text, "Class: Circuit-Witch — Hexes")
	assert_contains(text, "Arcane: ●●●○")
	assert_contains(text, "Points left: 0")
	var s := st.preview_stats()
	assert_eq(s["hp"], 14 + 1 + 2, "witch 14, chromed +1, body 1 × 2")
	assert_eq(s["evasion"], 10 + 3 + 4 + 4, "witch 10, chromed +3, corp asset +4, tech 2 × 2")
	assert_eq(s["initiative"], 2 + 3, "witch 2, arcane 3 × 1")
	assert_contains(text, "Derived: HP 17")
	st.sheet.name = ""
	assert_contains(st.render(), "Cannot confirm: name is empty")


func test_party_builder_default_and_with_protagonist() -> void:
	var preset := registry.get_entry("parties", "prototype")
	var positions: Array[Vector2] = [Vector2(0, 0), Vector2(10, 0), Vector2(20, 0), Vector2(30, 0)]
	var plain := PartyBuilder.member_specs(registry, preset, {}, rules, positions)
	assert_eq(plain.size(), 3)
	assert_eq(Dictionary(plain[0]["data"])["id"], "weaver")
	assert_eq(Dictionary(plain[0]["overlay"])["kind"], "none")
	assert_eq(Dictionary(plain[2]["overlay"])["kind"], "plating", "synth rig overlay")
	var with := PartyBuilder.member_specs(registry, preset, VEX, rules, positions)
	assert_eq(with.size(), 3)
	var lead: Dictionary = with[0]
	assert_eq(Dictionary(lead["data"])["id"], PartyBuilder.PROTAGONIST_ID)
	assert_eq(Dictionary(lead["data"])["name"], "Vex")
	assert_eq(Dictionary(lead["data"])["origin"], "corp_asset")
	assert_eq(Dictionary(lead["data"])["resource_id"], "hexes")
	assert_eq(Dictionary(lead["stats"])["hp"], 17)
	assert_eq(Dictionary(lead["overlay"])["kind"], "chrome")
	assert_eq(lead["color"], Color.html("#b58cff"))
	assert_eq(lead["position"], Vector2(0, 0))
	assert_eq(Dictionary(with[1]["data"])["id"], "ash", "the rest of the preset is untouched")


func test_stat_block_extras() -> void:
	var s := StatBlock.for_member({"stats": {"hp": 10, "move": 5, "evasion": 0, "initiative": 0}}, {"stat_mods": {"hp": 1}}, rules, {
		"attributes": {"body": 2, "tech": 1},
		"attribute_effects": {"body": {"hp": 2}, "tech": {"evasion": 2}},
		"origin": {"stat_mods": {"move": 1}},
	})
	assert_eq(s, {"hp": 15, "move": 6, "evasion": 2, "initiative": 0})


func test_race_overlays_stamp_only_body_pixels() -> void:
	var base := PlaceholderActorArt.body_image(Color.RED)
	for kind: String in ["marks", "chrome", "bark", "plating"]:
		var img := PlaceholderActorArt.body_image(Color.RED, "capsule", {"kind": kind, "color": "#00ff00"})
		var stamped := 0
		for y: int in img.get_height():
			for x: int in img.get_width():
				var p := img.get_pixel(x, y)
				if p.g > 0.9 and p.r < 0.1:
					stamped += 1
					assert_true(base.get_pixel(x, y).a > 0.0, "%s painted outside the rig at %d,%d" % [kind, x, y])
				elif base.get_pixel(x, y).a == 0.0:
					assert_eq(p.a, 0.0, "%s changed the silhouette" % kind)
		assert_true(stamped > 4, "%s stamped %d pixels" % [kind, stamped])
	var none := PlaceholderActorArt.body_image(Color.RED, "capsule", {"kind": "none"})
	assert_eq(none.get_data(), base.get_data(), "none is the bare rig")
