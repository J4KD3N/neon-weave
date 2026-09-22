## Runtime-generated stand-in sprites for actors until the paper-doll rig
## lands (GDD §5). Shapes: "capsule" (torso + head) and "drone" (hovering
## orb). Race overlays (marks, chrome, bark, plating) are stamped over the
## body pixels in the race's overlay colour, one humanoid rig for all races.
## Appearance (S51): a `tone` colours the head and an `accent` the hair cap;
## `portrait_image` is the same rig as a head-and-shoulders placeholder.
class_name PlaceholderActorArt
extends RefCounted

const BODY_SIZE := Vector2i(32, 48)
const SHADOW_SIZE := Vector2i(36, 14)
const OVERLAY_KINDS: Array[String] = ["none", "marks", "chrome", "bark", "plating", "echo", "pelt", "sky", "swarm"]
const PORTRAIT_SIZE := Vector2i(64, 64)


static func body_texture(tint: Color, shape: String = "capsule", overlay: Dictionary = {}, appearance: Dictionary = {}) -> ImageTexture:
	return ImageTexture.create_from_image(body_image(tint, shape, overlay, appearance))


static func body_image(tint: Color, shape: String = "capsule", overlay: Dictionary = {}, appearance: Dictionary = {}) -> Image:
	var img := Image.create_empty(BODY_SIZE.x, BODY_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var outline := tint.darkened(0.55)
	match shape:
		"drone":
			_ellipse(img, Vector2(16, 20), Vector2(11, 9), tint, outline)
			_ellipse(img, Vector2(16, 20), Vector2(4, 3), tint.lightened(0.5), tint.lightened(0.5))
			_ellipse(img, Vector2(16, 34), Vector2(3, 2), outline, outline)
		_:
			_ellipse(img, Vector2(16, 30), Vector2(8, 15), tint, outline) # torso
			_ellipse(img, Vector2(16, 10), Vector2(6.5, 7), appearance.get("tone", tint.lightened(0.15)), outline) # head
			_stamp_overlay(img, overlay)
			if appearance.has("accent"): # the hair cap: the top of the head, above the brow
				_cap(img, Vector2(16, 10), Vector2(6.5, 7), 4.5, appearance["accent"])
	return img


## A head-and-shoulders portrait on the same rig: shoulders in the tint,
## the head in the tone, the overlay stamped, the accent as a hair cap and
## two eyes. A placeholder until portraits are drawn (S51).
static func portrait_texture(tint: Color, overlay: Dictionary = {}, appearance: Dictionary = {}) -> ImageTexture:
	return ImageTexture.create_from_image(portrait_image(tint, overlay, appearance))


static func portrait_image(tint: Color, overlay: Dictionary = {}, appearance: Dictionary = {}) -> Image:
	var img := Image.create_empty(PORTRAIT_SIZE.x, PORTRAIT_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var outline := tint.darkened(0.55)
	_ellipse(img, Vector2(32, 66), Vector2(30, 22), tint, outline) # shoulders, cut by the frame
	_stamp_overlay(img, overlay, 28) # the rig's torso rows, shifted down onto the shoulders
	var tone: Color = appearance.get("tone", tint.lightened(0.15))
	_ellipse(img, Vector2(32, 30), Vector2(15, 18), tone, outline) # head
	if appearance.has("accent"):
		_cap(img, Vector2(32, 30), Vector2(15, 18), 10.0, appearance["accent"])
	var eye := Color(0.08, 0.06, 0.1)
	for p: Vector2i in [Vector2i(26, 32), Vector2i(27, 32), Vector2i(37, 32), Vector2i(38, 32), Vector2i(26, 33), Vector2i(27, 33), Vector2i(37, 33), Vector2i(38, 33)]:
		img.set_pixel(p.x, p.y, eye)
	return img


static func shadow_texture() -> ImageTexture:
	var img := Image.create_empty(SHADOW_SIZE.x, SHADOW_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0, 0, 0, 0.45)
	_ellipse(img, Vector2(18, 7), Vector2(17, 6), c, c)
	return ImageTexture.create_from_image(img)


## Overlay pixels only ever replace existing body pixels, so the silhouette
## stays the shared rig's. `y_shift` reads the pattern that many rows up (the
## portrait puts the rig's torso rows on its shoulders).
static func _stamp_overlay(img: Image, overlay: Dictionary, y_shift: int = 0) -> void:
	var kind := String(overlay.get("kind", "none"))
	if kind == "none" or kind.is_empty():
		return
	var color := Color.html(String(overlay.get("color", "#ffffff")))
	for py: int in img.get_height():
		for x: int in img.get_width():
			if img.get_pixel(x, py).a == 0.0:
				continue
			var y := py - y_shift
			var hit := false
			match kind:
				"marks":
					hit = y > 16 and (x + y) % 7 == 0
				"chrome":
					hit = (y >= 26 and y <= 28) or (x >= 8 and x <= 11 and y >= 24 and y <= 34)
				"bark":
					hit = (x * 3 + y * 5) % 6 == 0
				"plating":
					hit = y == 8 or y == 20 or y == 21 or y == 34 or y == 35
				"echo": # a faint static every other row: a body the light passes through
					hit = y % 2 == 0 and (x + y / 2) % 3 == 0
				"pelt": # dense fur flecks below the face
					hit = y > 12 and (x * 7 + y * 3) % 4 == 0
				"sky": # a single pale line down the spine and long limbs
					hit = x == img.get_width() / 2 or (y > 30 and x % 5 == 0)
				"swarm": # shifting grain: no two rows agree
					hit = (x * x + y * 11) % 5 == 0
			if hit:
				img.set_pixel(x, py, color)


## Paints the part of an ellipse above `top_rows` from its top edge (a hair cap).
static func _cap(img: Image, center: Vector2, radii: Vector2, top_rows: float, color: Color) -> void:
	var limit := center.y - radii.y + top_rows
	for y: int in img.get_height():
		if y + 0.5 >= limit:
			continue
		for x: int in img.get_width():
			var nx := (x + 0.5 - center.x) / radii.x
			var ny := (y + 0.5 - center.y) / radii.y
			if nx * nx + ny * ny <= 0.72:
				img.set_pixel(x, y, color)


static func _ellipse(img: Image, center: Vector2, radii: Vector2, fill: Color, outline: Color) -> void:
	for y: int in img.get_height():
		for x: int in img.get_width():
			var nx := (x + 0.5 - center.x) / radii.x
			var ny := (y + 0.5 - center.y) / radii.y
			var d := nx * nx + ny * ny
			if d <= 1.0:
				img.set_pixel(x, y, outline if d > 0.72 else fill)
