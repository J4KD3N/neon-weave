## Crash reporting without a service (gap analysis 2026-09-24, D-116).
## The engine writes its log to user://logs/ (project.godot enables file
## logging). This marks a session as begun and, on a clean quit, as ended;
## a marker still saying "begun" at the next start means the last run
## died, so the last log is copied to user://crash_<stamp>.txt and the
## title screen says where it is. A player sends that file with the
## playtest log; nothing leaves the machine by itself.
class_name CrashReport
extends RefCounted

const MARKER := "user://session_marker.json"
const LOG_DIR := "user://logs"

static var last_report: String = "" # the report the last begin() wrote, "" when the last run ended cleanly


## Call once at start. Returns true when the previous run did not end
## cleanly; the report path is then in `last_report`.
static func begin(marker: String = MARKER, log_dir: String = LOG_DIR) -> bool:
	last_report = ""
	var crashed := false
	var previous := _read(marker)
	if not previous.is_empty() and not bool(previous.get("ended", true)):
		crashed = true
		last_report = write_report(previous, log_dir, marker.get_base_dir())
	_write(marker, {"started": Time.get_datetime_string_from_system(true, true), "ended": false, "version": String(ProjectSettings.get_setting("application/config/version", "0.0.0")), "pid": OS.get_process_id()})
	return crashed


## Call on every clean way out (the title's Quit, the window's close).
static func end(marker: String = MARKER) -> void:
	var m := _read(marker)
	if m.is_empty():
		return
	m["ended"] = true
	m["ended_at"] = Time.get_datetime_string_from_system(true, true)
	_write(marker, m)


## The newest log in the log dir (Godot names them godot.log, godot_<stamp>.log).
static func latest_log(log_dir: String = LOG_DIR) -> String:
	var dir := DirAccess.open(log_dir)
	if dir == null:
		return ""
	var newest := ""
	var newest_time := 0
	for f: String in dir.get_files():
		if not f.ends_with(".log"):
			continue
		var path := log_dir.path_join(f)
		var t := FileAccess.get_modified_time(path)
		if t >= newest_time:
			newest_time = t
			newest = path
	return newest


## Writes user://crash_<stamp>.txt: what the marker knew and the tail of
## the newest log. Returns the path, "" when nothing could be written.
static func write_report(previous: Dictionary, log_dir: String = LOG_DIR, out_dir: String = "user://") -> String:
	var stamp := Time.get_datetime_string_from_system(true, true).replace(":", "-")
	var path := out_dir.path_join("crash_%s.txt" % stamp)
	var lines: PackedStringArray = []
	lines.append("Neon Weave crash report")
	lines.append("The run that started at %s (version %s) did not end cleanly." % [previous.get("started", "?"), previous.get("version", "?")])
	lines.append("OS: %s. Engine: %s." % [OS.get_name(), Engine.get_version_info().get("string", "?")])
	lines.append("Send this file with your playtest log (docs/playtest.md).")
	lines.append("")
	var log_path := latest_log(log_dir)
	if log_path.is_empty():
		lines.append("(no engine log found under %s)" % log_dir)
	else:
		lines.append("Last log: %s" % log_path)
		lines.append("")
		var text := FileAccess.get_file_as_string(log_path)
		var all := text.split("\n")
		var start := maxi(all.size() - 200, 0)
		for i: int in range(start, all.size()):
			lines.append(all[i])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string("\n".join(lines))
	return path


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _write(path: String, data: Dictionary) -> void:
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))
