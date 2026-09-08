## Interface for platform services (achievements, stats, cloud saves, demo
## detection). The game only ever talks to this; GodotSteam lives behind a
## concrete backend so the open repo runs Steam-free (GDD §4).
class_name PlatformBackend
extends RefCounted


func backend_name() -> String:
	return "abstract"


## True when the backend is connected to a live platform client.
func is_available() -> bool:
	return false


func is_demo() -> bool:
	return false


func cloud_saves_enabled() -> bool:
	return false


func unlock_achievement(_id: String) -> bool:
	return false


func set_stat(_id: String, _value: int) -> bool:
	return false
