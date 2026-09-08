## Sprite sheet sidecars, facing resolution, frame building, palette swaps
## and the ActorSprite state machine (docs/art-pipeline.md).
extends TestCase

var registry: ContentRegistry


func before_each() -> void:
	registry = ContentRegistry.new()
	registry.load_from(ContentRegistry.BASE_ROOT, [])


func after_each() -> void:
	registry.free()


func _sheet(id: String) -> SpriteSheet:
	return SpriteSheet.load_entry(registry.get_entry("sprites", id))


func _fake(rows: int = 30, cols: int = 6) -> Dictionary:
	return {
		"id": "fake", "_path": "res://content/sprites/fake.json", "image": "fake.png",
		"frame": [48, 64], "origin": [24, 60],
		"directions": ["s", "sw", "w", "nw", "n"], "mirror": {"se": "sw", "e": "w", "ne": "nw"},
		"palette": {"fill": "#ff00ff", "outline": "#7f007f", "highlight": "#ff80ff"},
		"animations": {"idle": {"row": 0, "frames": 4, "fps": 6, "loop": true}, "walk": {"row": 5, "frames": cols, "fps": 10, "loop": true}, "death": {"row": rows - 5, "frames": 5, "fps": 8, "loop": false}},
	}


func _blank(w: int, h: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


func test_committed_sheets_load_and_match_their_sidecars() -> void:
	for id: String in ["trueborn", "scav"]:
		var s := _sheet(id)
		assert_eq(s.errors, [], id)
		assert_eq(s.id, id)
		assert_eq(s.image.get_size(), Vector2i(288, 1920), "%s sheet size" % id)
		assert_eq(s.directions.size(), 5)
		assert_eq(s.animations.size(), 6)
		for anim: String in ["idle", "walk", "attack", "cast", "hit", "death"]:
			assert_true(s.has_animation(anim), "%s has %s" % [id, anim])
		assert_eq(s.feet_offset(), Vector2(0, -28))


func test_sidecar_validation() -> void:
	var missing := SpriteSheet.load_entry(_fake())
	assert_any_contains(missing.errors, "cannot load image")
	var bad := _fake()
	bad["mirror"] = {"e": "x", "zz": "w"}
	bad["directions"] = ["s", "q"]
	var anims: Dictionary = bad["animations"]
	anims["idle"] = {"row": 0, "frames": 0}
	var s := SpriteSheet.from_entry(bad, _blank(48, 64))
	assert_any_contains(s.errors, "unknown direction 'q'")
	assert_any_contains(s.errors, "mirror 'e' points at undrawn row 'x'")
	assert_any_contains(s.errors, "unknown mirrored facing 'zz'")
	assert_any_contains(s.errors, "animation 'idle' has no frames")
	assert_any_contains(s.errors, "is smaller than")
	assert_false(s.is_valid())
	var ok := SpriteSheet.from_entry(_fake(), _blank(288, 1920))
	assert_eq(ok.errors, [])


func test_facing_resolution_mirrors_undrawn_rows() -> void:
	var s := SpriteSheet.from_entry(_fake(), _blank(288, 1920))
	assert_eq(s.facing_for(Vector2(0, 1)), {"row": "s", "flip": false})
	assert_eq(s.facing_for(Vector2(0, -1)), {"row": "n", "flip": false})
	assert_eq(s.facing_for(Vector2(-1, 0)), {"row": "w", "flip": false})
	assert_eq(s.facing_for(Vector2(1, 0)), {"row": "w", "flip": true}, "east is west mirrored")
	assert_eq(s.facing_for(Vector2(-1, 1)), {"row": "sw", "flip": false})
	assert_eq(s.facing_for(Vector2(1, 1)), {"row": "sw", "flip": true})
	assert_eq(s.facing_for(Vector2(-1, -1)), {"row": "nw", "flip": false})
	assert_eq(s.facing_for(Vector2(1, -1)), {"row": "nw", "flip": true})
	assert_eq(s.facing_for(Vector2.ZERO), {"row": "s", "flip": false}, "no direction faces the camera")
	assert_eq(s.facing_for(Vector2(0.3, 1)), {"row": "s", "flip": false}, "nearest facing wins")


func test_build_frames_names_counts_and_flags() -> void:
	var s := SpriteSheet.from_entry(_fake(), _blank(288, 1920))
	var frames := s.build_frames()
	assert_false(frames.has_animation("default"))
	assert_true(frames.has_animation("walk_s"))
	assert_true(frames.has_animation("death_nw"))
	assert_false(frames.has_animation("walk_e"), "mirrored facings are not separate animations")
	assert_eq(frames.get_frame_count("walk_s"), 6)
	assert_eq(frames.get_frame_count("idle_n"), 4)
	assert_eq(frames.get_frame_count("death_w"), 5)
	assert_true(frames.get_animation_loop("walk_s"))
	assert_false(frames.get_animation_loop("death_s"))
	assert_true(is_equal_approx(frames.get_animation_speed("walk_s"), 10.0))
	var tex := frames.get_frame_texture("walk_w", 2) as AtlasTexture
	assert_eq(tex.region, Rect2(96, (5 + 2) * 64, 48, 64), "column 2, walk block row for 'w'")


func test_recolor_swaps_only_listed_colours_and_keeps_alpha() -> void:
	var img := _blank(4, 1)
	img.set_pixel(0, 0, Color.html("#ff00ff"))
	img.set_pixel(1, 0, Color(1, 0, 1, 0.5))
	img.set_pixel(2, 0, Color.html("#123456"))
	var s := SpriteSheet.from_entry(_fake(), _blank(288, 1920))
	var swap := s.swap_for_tint(Color.html("#33e0d6"))
	assert_eq(swap.size(), 3)
	var out := SpriteSheet.recolor(img, swap)
	assert_eq(out.get_pixel(0, 0), Color.html("#33e0d6"))
	var edge := out.get_pixel(1, 0)
	assert_true(absf(edge.a - 0.5) < 0.01, "alpha preserved (8-bit)")
	assert_true(absf(edge.r - Color.html("#33e0d6").r) < 0.01, "semi-transparent fill pixels are recoloured too")
	assert_eq(out.get_pixel(2, 0), Color.html("#123456"), "unlisted colour untouched")
	assert_eq(out.get_pixel(3, 0).a, 0.0)
	assert_eq(img.get_pixel(0, 0), Color.html("#ff00ff"), "source untouched")
	assert_eq(s.swap_for_roles({"nope": Color.RED}).size(), 0)


func test_actor_sprite_state_machine() -> void:
	var s := _sheet("trueborn")
	var sprite := ActorSprite.new()
	sprite.setup(s, s.swap_for_tint(Color.RED))
	assert_eq(sprite.animation, &"idle_s")
	assert_eq(sprite.offset, Vector2(0, -28))
	sprite.set_facing(Vector2(1, 0))
	assert_eq(sprite.animation, &"idle_w")
	assert_true(sprite.flip_h)
	sprite.set_moving(true)
	assert_eq(sprite.animation, &"walk_w")
	sprite.play_action("attack", Vector2(0, -1))
	assert_eq(sprite.animation, &"attack_n")
	assert_false(sprite.flip_h)
	assert_eq(sprite.current_action, "attack")
	sprite._on_finished()
	assert_eq(sprite.animation, &"walk_n", "back to the movement state")
	sprite.set_moving(false)
	assert_eq(sprite.animation, &"idle_n")
	sprite.play_action("death")
	sprite._on_finished()
	assert_eq(sprite.current_action, "death", "death sticks")
	sprite.play_action("juggle")
	assert_eq(sprite.current_action, "death", "unknown actions are ignored")
	sprite.free()
