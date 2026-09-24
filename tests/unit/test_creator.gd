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
	assert_eq(st.races.size(), 10, "all ten GDD races are playable (S30)")
	assert_eq(st.origins.size(), 4)
	assert_eq(st.classes.size(), 6)
	assert_eq(st.rows, ["name", "race", "origin", "class", "loadout", "tone", "accent", "body", "arcane", "tech"], "appearance rows since S51, the loadout since S62")
	assert_eq(st.current_row(), "race")
	var first := st.sheet.race_id
	assert_true(st.adjust(1))
	assert_ne(st.sheet.race_id, first)
	for _i: int in st.races.size() - 1:
		st.adjust(1)
	assert_eq(st.sheet.race_id, first, "wraps around")
	st.move_row(-2)
	assert_eq(st.current_row(), "tech", "wraps upward past the name row")
	st.move_row(-11)
	assert_eq(st.current_row(), "arcane")


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


func test_appearance_rows_cycle_validate_and_resolve() -> void:
	var st := CreatorState.new()
	st.setup(registry, rules)
	assert_eq(st.tones.size(), 7, "race default plus six tones")
	assert_eq(st.accents.size(), 7)
	assert_eq(st.appearance_name("tone"), "race default")
	assert_eq(st.appearance_colors(), {}, "the default look resolves to no colours")
	st.row = st.rows.find("tone")
	assert_true(st.adjust(1))
	assert_eq(st.sheet.appearance["tone"], "pale")
	assert_eq(st.appearance_name("tone"), "Pale")
	assert_true(st.adjust(-1))
	assert_true(st.adjust(-1))
	assert_eq(st.sheet.appearance["tone"], "verdigris", "wraps to the last tone")
	st.row = st.rows.find("accent")
	st.adjust(1)
	st.adjust(1)
	st.adjust(1)
	st.adjust(1)
	assert_eq(st.sheet.appearance["accent"], "neon_violet")
	var colors := st.appearance_colors()
	assert_eq(colors["tone"], Color.html("#7fb59a"))
	assert_eq(colors["accent"], Color.html("#b58cff"))
	assert_true(st.is_valid())
	assert_contains(st.render(), "Tone: Verdigris")
	assert_contains(st.render(), "▶ Accent: Neon violet")
	var round := CharacterSheet.from_dict(st.sheet.to_dict())
	assert_eq(round.appearance, {"tone": "verdigris", "accent": "neon_violet"}, "the appearance rides the sheet")
	round.appearance["tone"] = "octarine"
	assert_any_contains(round.validate(registry, attr_rules), "unknown tone 'octarine'")
	assert_eq(CharacterSheet.resolve_appearance(registry, round.appearance).keys(), ["accent"], "an unknown tone resolves to nothing")
	var old := CharacterSheet.from_dict(VEX)
	assert_eq(old.appearance, {"tone": "", "accent": ""}, "a sheet from before S51 has the default look")
	assert_eq(old.validate(registry, attr_rules), [])
	# The creator drops a look that no longer loads.
	var st2 := CreatorState.new()
	st2.setup(registry, rules, {"name": "Vex", "appearance": {"tone": "octarine", "accent": "ink"}})
	assert_eq(st2.sheet.appearance, {"tone": "", "accent": "ink"})


func test_next_point_preview_and_locked_origins() -> void:
	var st := CreatorState.new()
	st.setup(registry, rules, VEX)
	assert_eq(st.next_point_text("body"), "no points left")
	st.row = st.rows.find("tech")
	assert_true(st.adjust(-1))
	assert_eq(st.next_point_text("body"), "next point: HP 17 → 19")
	assert_eq(st.next_point_text("tech"), "next point: Evasion 19 → 21")
	assert_eq(st.next_point_text("arcane"), "next point: Initiative 5 → 6")
	assert_contains(st.render(), "Body: ●○○○  (+2 hp per point · next point: HP 17 → 19)")
	st.sheet.attributes["arcane"] = 4
	assert_eq(st.next_point_text("arcane"), "at the cap")
	# Origins still locked on the account are listed with their blurb, not offered.
	assert_false(st.origins.has("beacon_keeper"))
	assert_eq(st.locked_origins.size(), 1)
	assert_eq(st.locked_origins[0]["name"], "Beacon Keeper")
	assert_contains(st.render(), "locked: Beacon Keeper — Unlocked by reaching first contact")
	var st2 := CreatorState.new()
	st2.setup(registry, rules, {}, Account.offered(registry)) # every key, the kits and looks too (S62)
	assert_true(st2.origins.has("beacon_keeper"))
	assert_eq(st2.locked_origins, [])
	assert_false(st2.render().contains("locked:"))
	assert_contains(st.render(), "Esc cancel")
	st.for_new_game = true
	assert_contains(st.render(), "Esc back to the death-stakes")


func test_placeholder_rig_paints_tone_and_accent_and_a_portrait() -> void:
	var base := PlaceholderActorArt.body_image(Color.RED)
	var tone := Color.html("#7fb59a")
	var accent := Color.html("#b58cff")
	var img := PlaceholderActorArt.body_image(Color.RED, "capsule", {"kind": "none"}, {"tone": tone, "accent": accent})
	var toned := 0
	var accented := 0
	for y: int in img.get_height():
		for x: int in img.get_width():
			var p := img.get_pixel(x, y)
			assert_eq(p.a == 0.0, base.get_pixel(x, y).a == 0.0, "the silhouette is the rig's at %d,%d" % [x, y])
			if p.is_equal_approx(tone):
				toned += 1
				assert_true(y < 18, "the tone is the head, not the torso (%d,%d)" % [x, y])
			elif p.is_equal_approx(accent):
				accented += 1
				assert_true(y < 10, "the accent is the hair cap (%d,%d)" % [x, y])
	assert_true(toned > 20, "toned %d pixels" % toned)
	assert_true(accented > 10, "accented %d pixels" % accented)
	var portrait := PlaceholderActorArt.portrait_image(Color.RED, {"kind": "chrome", "color": "#00ff00"}, {"tone": tone, "accent": accent})
	assert_eq(portrait.get_size(), PlaceholderActorArt.PORTRAIT_SIZE)
	var counts := {"tone": 0, "accent": 0, "overlay": 0, "eye": 0}
	for y: int in portrait.get_height():
		for x: int in portrait.get_width():
			var p := portrait.get_pixel(x, y)
			if p.is_equal_approx(tone):
				counts["tone"] += 1
			elif p.is_equal_approx(accent):
				counts["accent"] += 1
			elif p.g > 0.9 and p.r < 0.1:
				counts["overlay"] += 1
	assert_true(counts["tone"] > 300, "a face: %d" % counts["tone"])
	assert_true(counts["accent"] > 100, "hair: %d" % counts["accent"])
	assert_true(counts["overlay"] > 0, "the race overlay on the shoulders")
	assert_true(portrait.get_pixel(26, 32).r < 0.3, "an eye")
	assert_eq(portrait.get_pixel(0, 0).a, 0.0, "transparent corners")
	var plain := PlaceholderActorArt.portrait_image(Color.RED)
	assert_eq(plain.get_size(), PlaceholderActorArt.PORTRAIT_SIZE)
	var head := plain.get_pixel(32, 30)
	assert_true(head.r > 0.99 and absf(head.g - 0.15) < 0.01 and absf(head.b - 0.15) < 0.01, "the default head is the tint, lightened: %s" % head)


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
	assert_eq(lead["appearance"], {}, "no look chosen: the race default")
	var looked := VEX.duplicate(true)
	looked["appearance"] = {"tone": "umber", "accent": "ember"}
	var dressed := PartyBuilder.member_specs(registry, preset, looked, rules, positions)
	assert_eq(Dictionary(dressed[0]["appearance"])["tone"], Color.html("#8a5a3a"))
	assert_eq(Dictionary(dressed[0]["appearance"])["accent"], Color.html("#ff8a5b"))
	assert_eq(dressed[1]["appearance"], {}, "only the protagonist has a look")
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
