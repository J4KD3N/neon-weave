## Runtime-generated stand-in sprites for actors until the paper-doll rig
## lands (GDD §5). Shapes: "capsule" (torso + head) and "drone" (hovering orb).
class_name PlaceholderActorArt
extends RefCounted

const BODY_SIZE := Vector2i(32, 48)
const SHADOW_SIZE := Vector2i(36, 14)


static func body_texture(tint: Color, shape: String = "capsule") -> ImageTexture:
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
	return ImageTexture.create_from_image(img)


static func shadow_texture() -> ImageTexture:
	var img := Image.create_empty(SHADOW_SIZE.x, SHADOW_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0, 0, 0, 0.45)
	_ellipse(img, Vector2(18, 7), Vector2(17, 6), c, c)
	return ImageTexture.create_from_image(img)


static func _ellipse(img: Image, center: Vector2, radii: Vector2, fill: Color, outline: Color) -> void:
	for y: int in img.get_height():
		for x: int in img.get_width():
			var nx := (x + 0.5 - center.x) / radii.x
			var ny := (y + 0.5 - center.y) / radii.y
			var d := nx * nx + ny * ny
			if d <= 1.0:
				img.set_pixel(x, y, outline if d > 0.72 else fill)
