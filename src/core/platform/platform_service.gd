## `Platform` autoload: the single entry point for platform services.
## Picks a backend at startup. GodotSteam is wired in at M2; until then, and
## whenever Steam is absent, the null backend is used.
class_name PlatformService
extends Node

var backend: PlatformBackend


func _ready() -> void:
	backend = _pick_backend()


func _pick_backend() -> PlatformBackend:
	# M2: `if Engine.has_singleton("Steam"): return SteamPlatformBackend.new()`
	return NullPlatformBackend.new()


func is_available() -> bool:
	return backend.is_available()


func is_demo() -> bool:
	return backend.is_demo()


func cloud_saves_enabled() -> bool:
	return backend.cloud_saves_enabled()


func unlock_achievement(id: String) -> bool:
	return backend.unlock_achievement(id)


func set_stat(id: String, value: int) -> bool:
	return backend.set_stat(id, value)
