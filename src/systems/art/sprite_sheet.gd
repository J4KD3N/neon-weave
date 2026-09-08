## A sprite sheet + sidecar (`sprites` content kind) turned into Godot
## [SpriteFrames]. See docs/art-pipeline.md.
##
## Sidecar: {"image", "frame": [w,h], "origin": [x,y] (feet), "directions":
## [drawn rows], "mirror": {facing: drawn row}, "palette": {role: "#hex"},
## "animations": {name: {"row", "frames", "fps", "loop"}}}
## Rows: each animation is a block of `directions.size()` rows starting at
## `row`; columns are frames.
class_name SpriteSheet
extends RefCounted

## Screen-space angle (degrees, y down) of each facing name.
const FACING_ANGLES: Dictionary = {"e": 0.0, "se": 45.0, "s": 90.0, "sw": 135.0, "w": 180.0, "nw": 225.0, "n": 270.0, "ne": 315.0}

var id: String = ""
var image: Image
var frame := Vector2i(48, 64)
var origin := Vector2i(24, 60)
var directions: Array[String] = []
var mirror: Dictionary = {}
var palette: Dictionary = {}
var animations: Dictionary = {}
var errors: Array[String] = []


## Reads the sidecar entry and its image (relative to the entry's own
## path). The result may carry `errors`; check [method is_valid].
static func load_entry(entry: Dictionary) -> SpriteSheet:
	var dir := String(entry.get("_path", "")).get_base_dir()
	var image_path := dir.path_join(String(entry.get("image", "")))
	var img := Image.new()
	var err := ERR_FILE_NOT_FOUND
	if FileAccess.file_exists(image_path):
		err = img.load_png_from_buffer(FileAccess.get_file_as_bytes(image_path))
	var sheet := from_entry(entry, img if err == OK else null)
	if err != OK:
		sheet.errors.append("cannot load image %s: %s" % [image_path, error_string(err)])
	return sheet


static func from_entry(entry: Dictionary, img: Image) -> SpriteSheet:
	var s := SpriteSheet.new()
	s.id = String(entry.get("id", ""))
	s.image = img
	s.frame = _vec(entry.get("frame", [48, 64]), Vector2i(48, 64))
	s.origin = _vec(entry.get("origin", [24, 60]), Vector2i(24, 60))
	s.directions.assign(entry.get("directions", []))
	s.mirror = entry.get("mirror", {})
	s.palette = entry.get("palette", {})
	s.animations = entry.get("animations", {})
	s._validate()
	return s


func is_valid() -> bool:
	return errors.is_empty()


func _validate() -> void:
	if frame.x <= 0 or frame.y <= 0:
		errors.append("frame size must be positive")
	if directions.is_empty():
		errors.append("no directions")
	for d: String in directions:
		if not FACING_ANGLES.has(d):
			errors.append("unknown direction '%s'" % d)
	for facing: String in mirror:
		if not FACING_ANGLES.has(facing):
			errors.append("unknown mirrored facing '%s'" % facing)
		if not directions.has(String(mirror[facing])):
			errors.append("mirror '%s' points at undrawn row '%s'" % [facing, mirror[facing]])
	if animations.is_empty():
		errors.append("no animations")
	var rows_needed := 0
	var cols_needed := 0
	for name: String in animations:
		var a: Dictionary = animations[name]
		var frames := int(a.get("frames", 0))
		if frames <= 0:
			errors.append("animation '%s' has no frames" % name)
		rows_needed = maxi(rows_needed, int(a.get("row", 0)) + directions.size())
		cols_needed = maxi(cols_needed, frames)
	if image != null and not image.is_empty():
		if image.get_width() < cols_needed * frame.x or image.get_height() < rows_needed * frame.y:
			errors.append("image %dx%d is smaller than the %d×%d frames the sidecar needs" % [image.get_width(), image.get_height(), cols_needed, rows_needed])
	if origin.x < 0 or origin.y < 0 or origin.x > frame.x or origin.y > frame.y:
		errors.append("origin outside the frame")


## Resolves a screen-space direction to a drawn row and whether to flip it.
func facing_for(dir: Vector2) -> Dictionary:
	if directions.is_empty():
		return {"row": "", "flip": false}
	if dir.length_squared() < 0.0001:
		dir = Vector2.DOWN
	var angle := fposmod(rad_to_deg(atan2(dir.y, dir.x)), 360.0)
	var best := ""
	var best_delta := 999.0
	var names: Array[String] = []
	names.assign(directions)
	for m: String in mirror:
		names.append(m)
	for name: String in names:
		var delta := absf(fposmod(angle - float(FACING_ANGLES[name]) + 180.0, 360.0) - 180.0)
		if delta < best_delta or (is_equal_approx(delta, best_delta) and directions.has(name) and not directions.has(best)):
			best = name
			best_delta = delta
	if mirror.has(best):
		return {"row": String(mirror[best]), "flip": true}
	return {"row": best, "flip": false}


## Colour swap by palette role: {role: Color}. Roles missing from the sheet
## palette are ignored.
func swap_for_roles(roles: Dictionary) -> Dictionary:
	var swap: Dictionary = {}
	for role: String in roles:
		if palette.has(role):
			swap[Color.html(String(palette[role]))] = roles[role]
	return swap


## The standard tint swap: fill = tint, outline darker, highlight lighter.
func swap_for_tint(tint: Color) -> Dictionary:
	return swap_for_roles({"fill": tint, "outline": tint.darkened(0.55), "highlight": tint.lightened(0.2)})


static func recolor(src: Image, swap: Dictionary) -> Image:
	var out := src.duplicate()
	if swap.is_empty():
		return out
	var keys: Array[Color] = []
	keys.assign(swap.keys())
	for y: int in out.get_height():
		for x: int in out.get_width():
			var p := out.get_pixel(x, y)
			if p.a == 0.0:
				continue
			for k: Color in keys:
				if p.is_equal_approx(k):
					var c: Color = swap[k]
					out.set_pixel(x, y, Color(c.r, c.g, c.b, p.a))
					break
	return out


## Built frames per (sheet id, image size, swap), shared by every actor that
## uses the same look; recolouring a full sheet per actor is too slow.
static var _frames_cache: Dictionary = {}


static func clear_cache() -> void:
	_frames_cache.clear()


## Builds frames named "<animation>_<row>" for every animation × drawn row.
func build_frames(swap: Dictionary = {}) -> SpriteFrames:
	if image == null or image.is_empty():
		var empty := SpriteFrames.new()
		empty.remove_animation("default")
		return empty
	var key := "%s|%s|%s" % [id, image.get_size(), swap]
	if _frames_cache.has(key):
		return _frames_cache[key]
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	_frames_cache[key] = frames
	var texture := ImageTexture.create_from_image(recolor(image, swap))
	for name: String in animations:
		var a: Dictionary = animations[name]
		var base_row := int(a.get("row", 0))
		var count := int(a.get("frames", 1))
		for di: int in directions.size():
			var anim := "%s_%s" % [name, directions[di]]
			frames.add_animation(anim)
			frames.set_animation_speed(anim, float(a.get("fps", 8)))
			frames.set_animation_loop(anim, bool(a.get("loop", false)))
			for f: int in count:
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = Rect2(f * frame.x, (base_row + di) * frame.y, frame.x, frame.y)
				frames.add_frame(anim, atlas)
	return frames


func has_animation(name: String) -> bool:
	return animations.has(name)


## Offset that puts the sheet's `origin` (feet) on the node position.
func feet_offset() -> Vector2:
	return Vector2(frame.x / 2.0 - origin.x, frame.y / 2.0 - origin.y)


static func _vec(v: Variant, fallback: Vector2i) -> Vector2i:
	if v is Array and (v as Array).size() == 2:
		return Vector2i(int(v[0]), int(v[1]))
	return fallback
