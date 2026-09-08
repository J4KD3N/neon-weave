## Runtime-generated stand-in sprites for actors until the paper-doll rig
## lands (GDD §5). Shapes: "capsule" (torso + head) and "drone" (hovering
## orb). Race overlays (marks, chrome, bark, plating) are stamped over the
## body pixels in the race's overlay colour, one humanoid rig for all races.
class_name PlaceholderActorArt
extends RefCounted

const BODY_SIZE := Vector2i(32, 48)
const SHADOW_SIZE := Vector2i(36, 14)
const OVERLAY_KINDS: Array[String] = ["none", "marks", "chrome", "bark", "plating"]


static func body_texture(tint: Color, shape: String = "capsule", overlay: Dictionary = {}) -> ImageTexture:
	return ImageTexture.create_from_image(body_image(tint, shape, overlay))


static func body_image(tint: Color, shape: String = "capsule", overlay: Dictionary = {}) -> Image:
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
			_ellipse(img, Vector2(16, 10), Vector2(6.5, 7), tint.lightened(0.15), outline) # head
			_stamp_overlay(img, overlay)
	return img


static func shadow_texture() -> ImageTexture:
	var img := Image.create_empty(SHADOW_SIZE.x, SHADOW_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0, 0, 0, 0.45)
	_ellipse(img, Vector2(18, 7), Vector2(17, 6), c, c)
	return ImageTexture.create_from_image(img)


## Overlay pixels only ever replace existing body pixels, so the silhouette
## stays the shared rig's.
static func _stamp_overlay(img: Image, overlay: Dictionary) -> void:
	var kind := String(overlay.get("kind", "none"))
	if kind == "none" or kind.is_empty():
		return
	var color := Color.html(String(overlay.get("color", "#ffffff")))
	for y: int in img.get_height():
		for x: int in img.get_width():
			if img.get_pixel(x, y).a == 0.0:
				continue
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
			if hit:
				img.set_pixel(x, y, color)


static func _ellipse(img: Image, center: Vector2, radii: Vector2, fill: Color, outline: Color) -> void:
	for y: int in img.get_height():
		for x: int in img.get_width():
			var nx := (x + 0.5 - center.x) / radii.x
			var ny := (y + 0.5 - center.y) / radii.y
			var d := nx * nx + ny * ny
			if d <= 1.0:
				img.set_pixel(x, y, outline if d > 0.72 else fill)
