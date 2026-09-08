## Narrative state, conditions, the dialogue runner and banter picking.
extends TestCase

const DIALOGUE: Dictionary = {
	"start": [
		{"node": "again", "requires": {"flags": {"met": true}}},
		{"node": "first"},
	],
	"nodes": {
		"first": {"speaker": "sera", "text": "First words.", "choices": [
			{"text": "Plain", "next": "second"},
			{"text": "[Vault] gated", "requires": {"origin_tag": "vault"}, "effects": {"approval": {"sera": 2}}, "next": "second"},
			{"text": "Leave", "end": true},
		]},
		"second": {"speaker": "player", "text": "Second.", "choices": [
			{"text": "Recruit", "effects": {"recruit": "sera", "flags": {"met": true}, "quest": {"id": "q", "stage": "start"}}, "end": true},
			{"text": "Dangling", "next": "nowhere"},
		]},
		"again": {"speaker": "sera", "text": "Again.", "choices": [
			{"text": "Bye", "end": true},
		]},
	},
}
const BANTER: Dictionary = {"kind": "banter", "lines": [
	{"trigger": "victory", "text": "once", "once": "b1"},
	{"trigger": "victory", "text": "gated", "requires": {"approval": {"sera": {"min": 3}}}, "effects": {"approval": {"sera": 1}}, "once": "b2"},
	{"trigger": "victory", "text": "always"},
	{"trigger": "extract", "text": "home"},
]}


func _ctx(n: NarrativeState = NarrativeState.new(), origin_tag: String = "") -> Dictionary:
	return {"narrative": n, "origin_tag": origin_tag, "race": "trueborn", "class": "scrap_knight"}


func test_narrative_state_round_trip() -> void:
	var n := NarrativeState.new()
	n.set_flag("met", true)
	n.add_approval("sera", 2)
	n.add_approval("sera", -1)
	n.set_stage("q", "start")
	n.recruit("sera")
	n.recruit("sera")
	assert_eq(n.recruited, ["sera"])
	var back := NarrativeState.from_dict(n.to_dict())
	assert_true(back.flag("met"))
	assert_false(back.flag("nope"))
	assert_eq(back.approval_of("sera"), 1)
	assert_eq(back.stage_of("q"), "start")
	assert_true(back.is_recruited("sera"))
	back.dismiss("sera")
	assert_false(back.is_recruited("sera"))
	var floaty := NarrativeState.from_dict({"approval": {"sera": 3.0}, "flags": {"x": 1}})
	assert_eq(floaty.approval_of("sera"), 3)
	assert_true(floaty.flag("x"))


func test_conditions_cover_every_key() -> void:
	var n := NarrativeState.new()
	n.set_flag("met", true)
	n.add_approval("sera", 2)
	n.set_stage("q", "start")
	n.recruit("sera")
	var ctx := _ctx(n, "vault")
	assert_true(Conditions.passes({}, ctx))
	assert_true(Conditions.passes({"flags": {"met": true, "other": false}}, ctx))
	assert_false(Conditions.passes({"flags": {"met": false}}, ctx))
	assert_true(Conditions.passes({"origin_tag": "vault"}, ctx))
	assert_false(Conditions.passes({"origin_tag": "undercity"}, ctx))
	assert_true(Conditions.passes({"race": "trueborn", "class": "scrap_knight"}, ctx))
	assert_false(Conditions.passes({"class": "aetherbinder"}, ctx))
	assert_true(Conditions.passes({"approval": {"sera": {"min": 2, "max": 2}}}, ctx))
	assert_false(Conditions.passes({"approval": {"sera": {"min": 3}}}, ctx))
	assert_false(Conditions.passes({"approval": {"sera": {"max": 1}}}, ctx))
	assert_true(Conditions.passes({"recruited": "sera"}, ctx))
	assert_false(Conditions.passes({"not_recruited": "sera"}, ctx))
	assert_true(Conditions.passes({"not_recruited": "kaj"}, ctx))
	assert_true(Conditions.passes({"quest": {"id": "q", "stage": "start"}}, ctx))
	assert_false(Conditions.passes({"quest": {"id": "q", "stage": "done"}}, ctx))
	assert_false(Conditions.passes({"recruited": "sera"}, {"origin_tag": ""}), "missing narrative means nothing is recruited")


func test_apply_effects() -> void:
	var n := NarrativeState.new()
	var got := Conditions.apply({"approval": {"sera": 2}, "flags": {"met": true}, "recruit": "sera", "quest": {"id": "q", "stage": "start"}}, n)
	assert_eq(got, ["sera"])
	assert_eq(n.approval_of("sera"), 2)
	assert_true(n.flag("met"))
	assert_eq(n.stage_of("q"), "start")
	assert_eq(Conditions.apply({"recruit": "sera"}, n), [], "already recruited")
	assert_eq(Conditions.apply({}, n), [])


func test_runner_picks_start_filters_choices_and_applies_effects() -> void:
	var n := NarrativeState.new()
	var r := DialogueRunner.new()
	assert_true(r.start(DIALOGUE, _ctx(n)))
	assert_eq(r.node_id, "first")
	assert_eq(r.speaker(), "sera")
	assert_eq(r.text(), "First words.")
	var options := r.available_choices()
	assert_eq(options.size(), 2, "the vault line is hidden")
	assert_eq(options[1]["text"], "Leave")
	assert_eq(int(options[1]["index"]), 2, "original index kept")
	assert_eq(r.exit_choice(), 1)
	assert_true(r.choose(0))
	assert_eq(r.node_id, "second")
	assert_eq(r.speaker(), "player")
	assert_true(r.choose(0))
	assert_true(r.finished)
	assert_eq(r.recruited, ["sera"])
	assert_eq(r.applied.size(), 1)
	assert_true(n.flag("met"))
	assert_eq(n.stage_of("q"), "start")
	assert_false(r.choose(0), "finished runners refuse")
	# Second run: the start array now routes to "again".
	var r2 := DialogueRunner.new()
	assert_true(r2.start(DIALOGUE, _ctx(n)))
	assert_eq(r2.node_id, "again")
	assert_eq(r2.exit_choice(), 0)


func test_runner_gated_choice_and_dangling_next() -> void:
	var n := NarrativeState.new()
	var r := DialogueRunner.new()
	r.start(DIALOGUE, _ctx(n, "vault"))
	assert_eq(r.available_choices().size(), 3)
	assert_true(r.choose(1))
	assert_eq(n.approval_of("sera"), 2)
	assert_eq(r.node_id, "second")
	assert_true(r.choose(1), "dangling next ends the conversation instead of crashing")
	assert_true(r.finished)
	assert_false(r.choose(9))
	var empty := DialogueRunner.new()
	assert_false(empty.start({"start": "missing", "nodes": {}}, _ctx()))
	assert_true(empty.finished)


func test_banter_picks_first_matching_line_once() -> void:
	var n := NarrativeState.new()
	var ctx := _ctx(n)
	assert_eq(DialogueRunner.pick_banter(BANTER, "victory", ctx)["text"], "once")
	assert_true(n.flag("b1"))
	assert_eq(DialogueRunner.pick_banter(BANTER, "victory", ctx)["text"], "always", "once-line spent, gated line locked")
	n.add_approval("sera", 3)
	assert_eq(DialogueRunner.pick_banter(BANTER, "victory", ctx)["text"], "gated")
	assert_eq(n.approval_of("sera"), 4, "banter effects apply")
	assert_eq(DialogueRunner.pick_banter(BANTER, "victory", ctx)["text"], "always")
	assert_eq(DialogueRunner.pick_banter(BANTER, "extract", ctx)["text"], "home")
	assert_eq(DialogueRunner.pick_banter(BANTER, "nothing", ctx), {})
	assert_eq(DialogueRunner.pick_banter(BANTER, "victory", {}), {}, "no narrative, no banter")


func test_menu_render() -> void:
	var r := DialogueRunner.new()
	r.start(DIALOGUE, _ctx())
	var text := DialogueMenu.render(r, {"sera": "Sera"})
	assert_contains(text, "Sera: First words.")
	assert_contains(text, "[1] Plain")
	assert_contains(text, "[2] Leave")
	assert_contains(text, "Esc leaves")
	assert_false(text.contains("[Vault]"))
