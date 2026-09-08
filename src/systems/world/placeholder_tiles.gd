## Generates placeholder isometric tile art at runtime from tile entries and a
## biome palette, and packs it into a [TileSet]. Real art replaces this at M1;
## the tile entry's `art` block is the contract either way.
##
## Every atlas region is 64×64. The floor diamond occupies the bottom half
## (centre 32,48; half extents 32,16) so blocks can rise above it. The
## region's texture origin is (0,16), which puts the diamond's centre on the
## cell centre.
class_name PlaceholderTiles
extends RefCounted

const TILE_SIZE := Vector2i(64, 32)
const REGION := Vector2i(64, 64)
const TEXTURE_ORIGIN := Vector2i(0, 16)
const SOURCE_ID := 0
const FLOOR_CENTER := Vector2i(32, 48)


## Returns {"tile_set": TileSet, "atlas_coords": {tile_id: Vector2i}, "image": Image}.
static func build(tiles: Array[Dictionary], palette: Dictionary) -> Dictionary:
	var count: int = maxi(tiles.size(), 1)
	var atlas := Image.create_empty(REGION.x * count, REGION.y, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	var coords: Dictionary = {}
	for i: int in tiles.size():
		var tile: Dictionary = tiles[i]
		var art: Dictionary = tile.get("art", {})
		var img := draw_tile(art, palette)
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, REGION), Vector2i(REGION.x * i, 0))
		coords[String(tile["id"])] = Vector2i(i, 0)

	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	tile_set.tile_size = TILE_SIZE
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(atlas)
	source.texture_region_size = REGION
	for tile_id: String in coords:
		var c: Vector2i = coords[tile_id]
		source.create_tile(c)
		var data: TileData = source.get_tile_data(c, 0)
		data.texture_origin = TEXTURE_ORIGIN
	tile_set.add_source(source, SOURCE_ID)
	return {"tile_set": tile_set, "atlas_coords": coords, "image": atlas}


## Draws one 64×64 region for an `art` block:
##   {"shape": "floor", "fill": <role>, "edge": <role>, "pattern": "grate"}
##   {"shape": "block", "height": 32, "top": <role>, "left": <role>, "right": <role>}
## Roles index the biome palette; unknown roles fall back to a loud magenta.
static func draw_tile(art: Dictionary, palette: Dictionary) -> Image:
	var img := Image.create_empty(REGION.x, REGION.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match String(art.get("shape", "floor")):
		"block":
			_draw_block(img, art, palette)
		_:
			_draw_floor(img, art, palette)
	return img


static func palette_color(palette: Dictionary, role: String, fallback: Color = Color.MAGENTA) -> Color:
	if role.is_empty() or not palette.has(role):
		return fallback
	return Color.html(String(palette[role]))


## Half-width of the diamond at vertical offset `dy` from its centre.
static func diamond_half_width(dy: int) -> int:
	return maxi(0, 2 * (16 - absi(dy)))


static func _draw_floor(img: Image, art: Dictionary, palette: Dictionary) -> void:
	var fill := palette_color(palette, String(art.get("fill", "floor")))
	var edge := palette_color(palette, String(art.get("edge", "")), fill.darkened(0.35))
	var pattern: String = String(art.get("pattern", ""))
	var line := palette_color(palette, String(art.get("pattern_color", "")), fill.lightened(0.18))
	for y: int in range(32, 64):
		var half := diamond_half_width(y - FLOOR_CENTER.y)
		var x0 := FLOOR_CENTER.x - half
		var x1 := mini(FLOOR_CENTER.x + half, REGION.x - 1)
		for x: int in range(x0, x1 + 1):
			var c := fill
			if x == x0 or x == x1 or y == 32 or y == 63:
				c = edge
			elif pattern == "grate" and (x + y) % 6 == 0:
				c = line
			elif pattern == "cracked" and (x * 7 + y * 13) % 29 == 0:
				c = edge
			elif pattern == "pad" and (absi(x - FLOOR_CENTER.x) == half / 2 or (half > 0 and half / 2 == 0)):
				c = line
			img.set_pixel(x, y, c)


## A raised block: the floor diamond lifted by `height`, with left/right faces.
static func _draw_block(img: Image, art: Dictionary, palette: Dictionary) -> void:
	var height: int = clampi(int(art.get("height", 32)), 1, 32)
	var top := palette_color(palette, String(art.get("top", "wall_top")))
	var left := palette_color(palette, String(art.get("left", "wall_left")))
	var right := palette_color(palette, String(art.get("right", "wall_right")))
	var edge := top.lightened(0.25)
	var top_center_y := FLOOR_CENTER.y - height
	for x: int in REGION.x:
		var dx := absi(x - FLOOR_CENTER.x)
		var e := 16 - dx / 2 # half-height of the diamond at this column
		if e < 0:
			continue
		var y_top := top_center_y - e
		var y_mid := top_center_y + e
		var y_bot := FLOOR_CENTER.y + e
		for y: int in range(maxi(y_top, 0), mini(y_bot, REGION.y - 1) + 1):
			var c: Color
			if y <= y_mid:
				c = edge if (y == y_top or y == y_mid) else top
			else:
				c = left if x < FLOOR_CENTER.x else right
				if x == FLOOR_CENTER.x or y == y_bot:
					c = c.darkened(0.3)
			img.set_pixel(x, y, c)
