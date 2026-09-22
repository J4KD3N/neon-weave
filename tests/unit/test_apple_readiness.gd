## Apple (S59, D-114), as far as a checkout without a Mac or a Developer ID
## can go: the macOS preset is universal with a reverse-DNS bundle id and
## versions in step with the project, it names the entitlements file, the
## entitlements grant what Godot's renderer needs and nothing more, and the
## release workflow signs and notarizes with rcodesign when the five
## secrets exist and exports as before when they do not.
extends TestCase


func test_the_macos_preset_and_the_entitlements_are_ready() -> void:
	var result := AppleCheck.report()
	assert_eq(result["blockers"], PackedStringArray(), "no blockers in the checkout: %s" % ", ".join(result["blockers"]))
	assert_true(bool(result["ready"]))
	var preset: Dictionary = result["preset"]
	assert_eq(String(preset["binary_format/architecture"]), "universal")
	assert_eq(String(preset["application/bundle_identifier"]), "dev.neonweave.game")
	var version := String(ProjectSettings.get_setting("application/config/version", ""))
	assert_eq(String(preset["application/short_version"]), version, "the preset's version is the project's")
	assert_eq(String(preset["application/version"]), version)
	assert_eq(String(preset["codesign/entitlements/custom_file"]), "res://apple/entitlements.plist")
	assert_eq(String(preset["codesign/codesign"]), "0", "the committed preset signs ad-hoc so a fork exports as before")
	assert_eq(String(preset["notarization/notarization"]), "0")
	assert_any_contains(result["notes"], "notarization is off in the preset by design")
	var ents: Dictionary = result["entitlements"]
	assert_true(bool(ents["com.apple.security.cs.allow-unsigned-executable-memory"]), "Godot's renderer needs it under the hardened runtime")
	assert_false(bool(ents["com.apple.security.cs.allow-jit"]), "GDScript needs no JIT")
	assert_false(bool(ents["com.apple.security.cs.disable-library-validation"]))
	assert_false(bool(ents["com.apple.security.device.audio-input"]))
	assert_false(bool(ents.get("com.apple.security.app-sandbox", false)), "no sandbox: saves and mods live in the user directory")
	var text := "\n".join(result["lines"])
	assert_contains(text, "The checkout is ready")
	var doc := FileAccess.get_file_as_string("res://apple/READINESS.md")
	assert_false(doc.is_empty(), "apple/READINESS.md is committed")
	assert_contains(doc, "dev.neonweave.game")


func test_the_release_workflow_signs_when_the_secrets_exist_and_exports_as_before_when_not() -> void:
	var workflow := FileAccess.get_file_as_string("res://.github/workflows/release.yml")
	assert_contains(workflow, "Sign and notarize macOS")
	for s: String in AppleCheck.SECRETS:
		assert_contains(workflow, "secrets.%s" % s, "the step reads %s" % s)
	assert_contains(workflow, "rcodesign encode-app-store-connect-api-key")
	assert_contains(workflow, "export/macos/rcodesign")
	assert_contains(workflow, "codesign/codesign=2")
	assert_contains(workflow, "notarization/notarization=2")
	for v: String in ["GODOT_MACOS_CODESIGN_CERTIFICATE_FILE", "GODOT_MACOS_CODESIGN_CERTIFICATE_PASSWORD", "GODOT_MACOS_NOTARIZATION_API_UUID", "GODOT_MACOS_NOTARIZATION_API_KEY", "GODOT_MACOS_NOTARIZATION_API_KEY_ID"]:
		assert_contains(workflow, v, "the export gets %s" % v)
	assert_contains(workflow, "ad-hoc build (secrets not set", "without the secrets the step says so and exits 0")
	assert_true(workflow.find("Sign and notarize macOS") < workflow.find("Export all platforms"), "signing is set up before the export")
	assert_contains(workflow, "Verify the macOS signature")
	assert_contains(workflow, "rcodesign verify")


func test_the_parsers_read_the_preset_and_the_plist_and_refuse_absence() -> void:
	assert_eq(AppleCheck.macos_preset("res://nope.cfg"), {})
	assert_eq(AppleCheck.entitlements("res://nope.plist"), {})
	var preset := AppleCheck.macos_preset()
	assert_true(preset.size() >= 10, "the macOS options: %d" % preset.size())
	assert_false(preset.has("export_path"), "only the options block, not the preset header")
	assert_false(preset.has("binary_format/embed_pck"), "not the Windows preset's options")
	var ents := AppleCheck.entitlements()
	assert_eq(ents.size(), 6)
	assert_contains(FileAccess.get_file_as_string("res://apple/CHECKLIST.md"), "spctl -a -vv")
