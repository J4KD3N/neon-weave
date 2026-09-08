## Every GDScript under src/ and tests/ must compile. Catches parse and
## static-typing errors headlessly, without opening the editor.
extends TestCase

const ROOTS: Array[String] = ["res://src", "res://tests"]


func test_all_scripts_compile() -> void:
	var paths: Array[String] = []
	for root: String in ROOTS:
		_collect_scripts(root, paths)
	assert_true(paths.size() > 0, "no scripts found")
	for path: String in paths:
		var script: GDScript = load(path)
		assert_true(script != null, "failed to load " + path)
		if script != null:
			assert_true(script.can_instantiate(), "does not compile: " + path)


func test_base_content_loads_clean() -> void:
	var registry := ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [ContentRegistry.DEV_MODS_ROOT])
	assert_eq(registry.load_errors, [])
	assert_true(registry.kinds().size() > 0, "base content is empty")
	registry.free()


static func _collect_scripts(root: String, out: Array[String]) -> void:
	for file: String in DirAccess.get_files_at(root):
		if file.get_extension() == "gd":
			out.append(root.path_join(file))
	for dir: String in DirAccess.get_directories_at(root):
		if not dir.begins_with("."):
			_collect_scripts(root.path_join(dir), out)
