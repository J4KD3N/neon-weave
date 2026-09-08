## Backend used when no platform client is present (open-source builds,
## CI, editor). Every call is a logged no-op.
class_name NullPlatformBackend
extends PlatformBackend

## Achievement ids unlocked this session, so tests and the debug overlay can
## see what would have fired.
var unlocked: Array[String] = []


func backend_name() -> String:
	return "null"


func unlock_achievement(id: String) -> bool:
	if not unlocked.has(id):
		unlocked.append(id)
	return true


func set_stat(_id: String, _value: int) -> bool:
	return true
