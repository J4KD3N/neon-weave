## Interface for platform services (achievements, stats, cloud saves, demo
## detection). The game only ever talks to this; GodotSteam lives behind a
## concrete backend so the open repo runs Steam-free (GDD §4). Both
## backends pass the same contract tests (tests/unit/test_platform.gd).
class_name PlatformBackend
extends RefCounted


func backend_name() -> String:
	return "abstract"


## True when the backend is connected to a live platform client.
func is_available() -> bool:
	return false


func is_demo() -> bool:
	return false


func user_name() -> String:
	return ""


func app_id() -> int:
	return 0


# --- achievements -----------------------------------------------------------

## Unlocks by achievement id (the content id; backends map it to their own).
## True when the platform accepted it, also when it was already unlocked.
func unlock_achievement(_id: String) -> bool:
	return false


func is_achievement_unlocked(_id: String) -> bool:
	return false


func unlocked_achievements() -> Array[String]:
	return []


func set_stat(_id: String, _value: int) -> bool:
	return false


# --- cloud saves --------------------------------------------------------------

func cloud_saves_enabled() -> bool:
	return false


## Writes a file into the cloud store by bare file name.
func cloud_write(_file_name: String, _bytes: PackedByteArray) -> bool:
	return false


## Reads a cloud file; empty when missing.
func cloud_read(_file_name: String) -> PackedByteArray:
	return PackedByteArray()


func cloud_exists(_file_name: String) -> bool:
	return false


func cloud_list() -> Array[String]:
	return []


func cloud_delete(_file_name: String) -> bool:
	return false
