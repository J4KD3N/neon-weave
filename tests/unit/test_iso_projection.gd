## Placeholder tile art layout and the TileMapLayer projection it relies on.
extends TestCase

const PALETTE: Dictionary = {
	"floor": "#26232b", "floor_edge": "#17151b",
	"wall_top": "#4a4550", "wall_left": "#2b2730", "wall_right": "#36313c",
}


static func _tiles() -> Array[Dictionary]:
	return [
		{"id": "floor", "art": {"shape": "floor"}},
		{"id": "wall", "art": {"shape": "block", "height": 32}},
	]


func test_atlas_has_one_region_per_tile() -> void:
	var built: Dictionary = PlaceholderTiles.build(_tiles(), PALETTE)
	var image: Image = built["image"]
	assert_eq(image.get_size(), Vector2i(128, 64))
	assert_eq(built["atlas_coords"], {"floor": Vector2i(0, 0), "wall": Vector2i(1, 0)})
	var tile_set: TileSet = built["tile_set"]
	assert_eq(tile_set.tile_size, Vector2i(64, 32))
	assert_eq(tile_set.tile_shape, TileSet.TILE_SHAPE_ISOMETRIC)
	var source: TileSetAtlasSource = tile_set.get_source(PlaceholderTiles.SOURCE_ID)
	assert_true(source.has_tile(Vector2i(1, 0)))
	assert_eq(source.get_tile_data(Vector2i(0, 0), 0).texture_origin, PlaceholderTiles.TEXTURE_ORIGIN)


func test_floor_art_fills_the_bottom_diamond() -> void:
	var img := PlaceholderTiles.draw_tile({"shape": "floor"}, PALETTE)
	assert_eq(img.get_pixel(32, 48).a, 1.0, "diamond centre is opaque")
	assert_eq(img.get_pixel(32, 33).a, 1.0, "just below top vertex")
	assert_eq(img.get_pixel(2, 48).a, 1.0, "left tip")
	assert_eq(img.get_pixel(0, 0).a, 0.0, "corner is transparent")
	assert_eq(img.get_pixel(32, 20).a, 0.0, "above the diamond is transparent")
	assert_eq(img.get_pixel(2, 34).a, 0.0, "outside the diamond edge is transparent")
	assert_eq(img.get_pixel(32, 48), Color.html("#26232b"))


func test_block_art_rises_above_the_floor() -> void:
	var img := PlaceholderTiles.draw_tile({"shape": "block", "height": 32}, PALETTE)
	assert_eq(img.get_pixel(32, 16), Color.html("#4a4550"), "top face centre")
	assert_eq(img.get_pixel(20, 45), Color.html("#2b2730"), "left face")
	assert_eq(img.get_pixel(44, 45), Color.html("#36313c"), "right face")
	assert_eq(img.get_pixel(0, 16).a, 1.0, "left silhouette edge")
	assert_eq(img.get_pixel(0, 15).a, 0.0)
	assert_eq(img.get_pixel(0, 0).a, 0.0)
	var low := PlaceholderTiles.draw_tile({"shape": "block", "height": 10}, PALETTE)
	assert_eq(low.get_pixel(32, 16).a, 0.0, "a low block leaves the upper region empty")
	assert_eq(low.get_pixel(32, 38).a, 1.0)


func test_unknown_palette_role_is_loud() -> void:
	assert_eq(PlaceholderTiles.palette_color({}, "nope"), Color.MAGENTA)
	assert_eq(PlaceholderTiles.palette_color(PALETTE, "", Color.RED), Color.RED)


func test_tilemap_round_trips_cells() -> void:
	var built: Dictionary = PlaceholderTiles.build(_tiles(), PALETTE)
	var layer := TileMapLayer.new()
	layer.tile_set = built["tile_set"]
	for y: int in 10:
		for x: int in 10:
			var cell := Vector2i(x, y)
			assert_eq(layer.local_to_map(layer.map_to_local(cell)), cell)
	layer.free()


func test_diamond_down_axes() -> void:
	var built: Dictionary = PlaceholderTiles.build(_tiles(), PALETTE)
	var layer := TileMapLayer.new()
	layer.tile_set = built["tile_set"]
	var origin := layer.map_to_local(Vector2i(0, 0))
	var dx := layer.map_to_local(Vector2i(1, 0)) - origin
	var dy := layer.map_to_local(Vector2i(0, 1)) - origin
	assert_true(is_equal_approx(dx.y, 16.0), "x axis descends half a tile: %s" % dx)
	assert_true(is_equal_approx(dy.y, 16.0), "y axis descends half a tile: %s" % dy)
	assert_true(is_equal_approx(absf(dx.x), 32.0), "x axis moves half a tile width: %s" % dx)
	assert_true(is_equal_approx(dx.x, -dy.x), "axes mirror horizontally")
	layer.free()
