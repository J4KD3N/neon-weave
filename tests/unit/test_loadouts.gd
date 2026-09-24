## Account unlocks beyond origins (S62, D-118; GDD §12): loadouts as a
## content kind chosen in the creator and worn from the first step,
## cosmetics (tones and accents) behind unlock flags, all earned on the
## account by the same path as origins.
extends TestCase

const LEDGER := "user://test_ledger_loadouts.json"
const SAVES := "user://test_saves_loadouts"
const ACCOUNT := "user://test_account_loadouts.json"

var registry: ContentRegistry
var rules: CombatRules


func before_each() -> void:
	_cleanup()
	registry = ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [])
	rules = CombatRules.from_entry(registry.get_entry("rules", "combat"))


func after_each() -> void:
	registry.free()
	_cleanup()


static func _cleanup() -> void:
	for f: String in [LEDGER, ACCOUNT]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var d := DirAccess.open(SAVES)
	if d != null:
		for f: String in d.get_files():
			d.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVES))


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _fresh() -> ExploreWorld:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var w := packed.instantiate() as ExploreWorld
	w.combat_seed = 1234
	w.ledger_path = LEDGER
	w.saves_dir = SAVES
	w.account_path = ACCOUNT
	w.settings_path = "user://test_settings_loadouts.json"
	w.input_path = "user://test_input_loadouts.json"
	_root().add_child(w)
	w.combat.animate = false
	return w


func _drop(w: ExploreWorld) -> void:
	_root().remove_child(w)
	w.free()


func test_loadouts_are_content_with_items_that_exist_and_one_default() -> void:
	var ids: Array[String] = []
	for l: Dictionary in registry.get_all("loadouts"):
		ids.append(String(l["id"]))
		for item_id: String in l.get("items", []):
			assert_true(registry.has_entry("items", item_id), "%s carries %s" % [l["id"], item_id])
	assert_eq(ids, ["corp_issue", "keepers_cache", "loom_walker", "scav_kit", "travelling_light"])
	assert_eq(CharacterSheet.default_loadout(registry), "travelling_light", "the default is the empty-handed one, so no test or balance number moves")
	assert_eq(Array(registry.get_entry("loadouts", "travelling_light")["items"]), [])
	assert_eq(String(registry.get_entry("loadouts", "keepers_cache")["unlock_flag"]), "choir_contact")
	assert_eq(String(registry.get_entry("loadouts", "loom_walker")["unlock_flag"]), "ending_seen")
	assert_true(Loc.TEXT_FIELDS.has("loadouts"), "translators see the kit names")
	assert_eq(ContentValidator.validate(registry, ["runtime"]).size(), 0, "the base content is clean")
	registry.put("loadouts", "zz_bad", {"name": "Bad", "items": ["laser_sword"], "resources": {"gold": 5}, "default": true, "unlock_flag": ""})
	var problems := ContentValidator.validate(registry, ["runtime"])
	assert_any_contains(problems, "loadouts/zz_bad (runtime): items points at items 'laser_sword', which does not exist")
	assert_any_contains(problems, "resources.gold is not a resource")
	assert_any_contains(problems, "unlock_flag is empty")
	assert_any_contains(problems, "2 loadouts say default; one may")
	registry._entries["loadouts"].erase("zz_bad")
	registry._fingerprint_cache = ""


func test_the_account_earns_kits_and_looks_from_the_same_flags_as_origins() -> void:
	var a := Account.new()
	a.path = ACCOUNT
	var n := NarrativeState.new()
	assert_eq(a.grant_from(n, registry), [], "nothing earned yet")
	assert_eq(Account.offered(registry), ["origin:beacon_keeper", "loadout:keepers_cache", "loadout:loom_walker", "tone:loom_lit", "accent:choir_silver"])
	n.set_flag("choir_contact", true)
	assert_eq(a.grant_from(n, registry), ["origin:beacon_keeper", "loadout:keepers_cache", "accent:choir_silver"], "first contact earns an origin, a kit and a look")
	assert_eq(a.grant_from(n, registry), [], "once")
	n.set_flag("ending_seen", true)
	assert_eq(a.grant_from(n, registry), ["loadout:loom_walker", "tone:loom_lit"], "an ending earns the rest")
	assert_eq(Account.key_name(registry, "loadout:keepers_cache"), "Keeper's cache")
	assert_eq(Account.key_name(registry, "accent:choir_silver"), "Choir silver")
	assert_eq(Account.key_name(registry, "tone:loom_lit"), "Loom-lit")
	assert_eq(Account.key_name(registry, "origin:beacon_keeper"), "Beacon Keeper")
	assert_eq(Account.key_name(registry, "iron_weave:drift"), "iron_weave:drift", "a key with no entry names itself")
	a.begin_playthrough()
	a.begin_playthrough()
	var back := Account.load_or_new(ACCOUNT)
	assert_eq(back.unlocked.size(), 5, "saved with the keys")
	assert_eq(back.playthroughs, 2, "and the count")


func test_the_creator_offers_what_the_account_earned_and_lists_the_locked() -> void:
	var st := CreatorState.new()
	st.setup(registry, rules)
	assert_eq(st.loadouts, ["corp_issue", "scav_kit", "travelling_light"], "the free kits")
	assert_eq(st.sheet.loadout_id, "travelling_light", "the default kit unless chosen")
	assert_eq(st.locked_loadouts.size(), 2)
	assert_eq(st.locked_loadouts[0]["name"], "Keeper's cache")
	assert_false(st.tones.has("loom_lit"), "a locked tone is not offered")
	assert_false(st.accents.has("choir_silver"))
	assert_eq(st.locked_looks.size(), 2)
	assert_eq(st.offered_count, 5)
	assert_eq(st.unlocked_count, 0)
	var text := st.render()
	assert_contains(text, "Account: 0 playthroughs · 0 of 5 unlocks earned")
	assert_contains(text, "Loadout: Travelling light — What you walked in with")
	assert_contains(text, "kit: nothing")
	assert_contains(text, "locked: Keeper's cache — Unlocked by reaching first contact")
	assert_contains(text, "locked: Loom-walker's kit — Unlocked by reaching any ending")
	assert_contains(text, "locked: Loom-lit — Unlocked by reaching any ending")
	assert_contains(text, "locked: Choir silver — Unlocked by reaching first contact")
	st.row = st.rows.find("loadout")
	assert_true(st.adjust(1))
	assert_eq(st.sheet.loadout_id, "corp_issue", "cycles round the offered kits")
	assert_contains(st.render(), "kit: Bolt pistol, Mesh weave")
	assert_true(st.adjust(1))
	assert_eq(st.sheet.loadout_id, "scav_kit")
	assert_eq(st.sheet.validate(registry, registry.get_entry("rules", "attributes")), [])
	# With everything earned.
	var st2 := CreatorState.new()
	st2.setup(registry, rules, {}, Account.offered(registry))
	st2.playthroughs = 3
	assert_eq(st2.loadouts, ["corp_issue", "keepers_cache", "loom_walker", "scav_kit", "travelling_light"])
	assert_eq(st2.locked_loadouts, [])
	assert_eq(st2.locked_looks, [])
	assert_true(st2.tones.has("loom_lit"))
	assert_true(st2.accents.has("choir_silver"))
	assert_eq(st2.unlocked_count, 5)
	st2.sheet.loadout_id = "keepers_cache"
	st2.sheet.appearance["accent"] = "choir_silver"
	var t2 := st2.render()
	assert_contains(t2, "Account: 3 playthroughs · 5 of 5 unlocks earned")
	assert_contains(t2, "kit: Weft charm, Lucky bolt, +10 salvage")
	assert_contains(t2, "Accent: Choir silver")
	assert_false(t2.contains("locked:"))
	assert_true(st2.appearance_colors().has("accent"), "the rig paints the earned accent")
	# A sheet that names a kit the account lost (a different account) falls back.
	var st3 := CreatorState.new()
	st3.setup(registry, rules, {"name": "Kest", "loadout_id": "keepers_cache"})
	assert_eq(st3.sheet.loadout_id, "travelling_light", "a locked kit on the sheet falls back to the default")
	# The sheet carries the kit through its dictionary and refuses an unknown one.
	var s := CharacterSheet.from_dict({"loadout_id": "scav_kit"})
	assert_eq(String(s.to_dict()["loadout_id"]), "scav_kit")
	assert_eq(CharacterSheet.from_dict(s.to_dict()).loadout_id, "scav_kit")
	s.loadout_id = "nope"
	assert_any_contains(s.validate(registry, registry.get_entry("rules", "attributes")), "unknown loadout 'nope'")


func test_a_new_game_wears_the_kit_banks_its_tin_and_counts_the_playthrough() -> void:
	var w := _fresh()
	var sheet := {"name": "Kest", "race_id": "trueborn", "origin_id": "scav_runner", "class_id": "scrap_knight", "attributes": {"body": 2, "arcane": 2, "tech": 2}, "loadout_id": "scav_kit"}
	assert_true(w.new_game(false, "balanced", false, sheet))
	assert_eq(w.account.playthroughs, 1, "counted on the account")
	assert_eq(Account.load_or_new(ACCOUNT).playthroughs, 1, "and saved")
	var equipment: Dictionary = Dictionary(w.ledger.builds.get("protagonist", {})).get("equipment", {})
	assert_eq(String(Dictionary(equipment.get("weapon", {})).get("item", "")), "strut_blade", "the blade is in hand")
	assert_eq(String(Dictionary(equipment.get("armour", {})).get("item", "")), "scrap_plating", "the plating is worn")
	assert_eq(w.ledger.items.size(), 0, "nothing left in the pack")
	var leader := w.party.leader()
	assert_eq(leader.member_id, "protagonist")
	assert_eq(int(ItemSystem.equipment_mods(w.registry, equipment)["stats"]["hp"]), 3)
	assert_eq(leader.damage_bonus, 1, "the strut blade's edge from the first step")
	# A locked kit is refused until the account earns it; then its tin is banked.
	sheet["loadout_id"] = "keepers_cache"
	assert_true(w.new_game(false, "balanced", false, sheet))
	assert_eq(w.ledger.items.size(), 0)
	assert_eq(Dictionary(w.ledger.builds.get("protagonist", {})).get("equipment", {}).size(), 0, "not earned: nothing worn")
	assert_eq(w.ledger.total("salvage"), 0)
	w.account.unlock("loadout:keepers_cache")
	assert_true(w.new_game(false, "balanced", false, sheet))
	equipment = Dictionary(w.ledger.builds.get("protagonist", {})).get("equipment", {})
	assert_eq(String(Dictionary(equipment.get("trinket_1", {})).get("item", "")), "weft_charm")
	assert_eq(String(Dictionary(equipment.get("trinket_2", {})).get("item", "")), "lucky_bolt")
	assert_eq(w.ledger.total("salvage"), 10, "the tin is banked")
	assert_eq(w.account.playthroughs, 3)
	# A kit with cyberware for a race with no slot goes to the pack instead.
	w.registry.put("loadouts", "zz_cyber", {"name": "Cyber", "items": ["optic_suite", "strut_blade"]})
	sheet["loadout_id"] = "zz_cyber"
	assert_true(w.new_game(false, "balanced", false, sheet))
	assert_eq(w.ledger.items.size(), 1, "the optic suite waits in the pack for a Chromed")
	assert_eq(String(Dictionary(w.ledger.items[0]).get("item", "")), "optic_suite")
	w.registry._entries["loadouts"].erase("zz_cyber")
	w.registry._fingerprint_cache = ""
	# No sheet at all: the default kit, empty-handed, as every test before S62.
	assert_true(w.new_game(false))
	assert_eq(w.ledger.items.size(), 0)
	assert_false(w.ledger.builds.has("protagonist"))
	# The unlock toast names a kit and a look, not just an origin.
	w.narrative.set_flag("choir_contact", true)
	assert_eq(w.grant_account_unlocks(), ["origin:beacon_keeper", "accent:choir_silver"], "the kit was already unlocked above")
	_drop(w)
