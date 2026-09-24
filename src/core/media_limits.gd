## Caps on media a mod can bring (gap analysis 2026-09-24, D-116): a mod is
## JSON, but its sprite sheets and sound files are read from disk, so the
## validator and the loaders refuse anything past these before decoding
## it. One place for the numbers; the same check in both.
class_name MediaLimits
extends RefCounted

const MAX_IMAGE_BYTES := 8 * 1024 * 1024
const MAX_IMAGE_SIDE := 4096
const MAX_AUDIO_BYTES := 32 * 1024 * 1024
const PNG_SIGNATURE_BYTES: Array[int] = [137, 80, 78, 71, 13, 10, 26, 10]
const AUDIO_EXTENSIONS: Array[String] = ["wav", "ogg", "mp3"]


## "" when the file may be loaded as a sprite sheet, else why not.
static func check_image(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "missing"
	if path.get_extension().to_lower() != "png":
		return "not a .png"
	var size := _size(path)
	if size > MAX_IMAGE_BYTES:
		return "too large: %d bytes over the %d limit" % [size, MAX_IMAGE_BYTES]
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "unreadable"
	var head := f.get_buffer(8)
	f.close()
	if head != png_signature():
		return "not a PNG (bad signature)"
	return ""


## Dimensions past the cap, checked after a decode; "" when fine.
static func check_image_size(img: Image) -> String:
	if img == null:
		return "no image"
	if img.get_width() > MAX_IMAGE_SIDE or img.get_height() > MAX_IMAGE_SIDE:
		return "too big: %dx%d over the %d-pixel side limit" % [img.get_width(), img.get_height(), MAX_IMAGE_SIDE]
	return ""


## "" when the file may be loaded as audio, else why not.
static func check_audio(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "missing"
	if not AUDIO_EXTENSIONS.has(path.get_extension().to_lower()):
		return "not .wav, .ogg or .mp3"
	var size := _size(path)
	if size > MAX_AUDIO_BYTES:
		return "too large: %d bytes over the %d limit" % [size, MAX_AUDIO_BYTES]
	return ""


## The eight bytes every PNG starts with.
static func png_signature() -> PackedByteArray:
	return PackedByteArray(PNG_SIGNATURE_BYTES)


static func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n
