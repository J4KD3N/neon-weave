## The marks a fight leaves (S61, D-117; GDD §5 "blood decals, corpse
## tiles", §9 "gore slider"): blood where an actor was hit, a pool where
## one went down, a body where one died. Marks are data ({x, y, kind, seed,
## fluid, color}) the world keeps per map, so they come back with a save;
## this node only draws them, on the floor between the ground and the
## walls, at the gore level the setting picks:
##   full  every mark;
##   low   bodies and pools, smaller and fainter, no splats;
##   off   nothing, and the fallen fade as they always did.
class_name DecalLayer
extends Node2D

const MODES: Array[String] = ["off", "low", "full"]
const KINDS: Array[String] = ["splat", "pool", "corpse"]
const FLUIDS: Array[String] = ["blood", "oil", "none"]
const DEFAULT_BLOOD := "#5a0f14"
const OIL := "#23282b"
## Marks kept per map; the oldest go first past this.
const MARKS_MAX := 200

static var level: String = "full"

var map_view: MapView
var marks: Array = []
var blood: Color = Color.html(DEFAULT_BLOOD)


static func cycle(name: String, direction: int) -> String:
	var i := MODES.find(name)
	return MODES[posmod(i + direction, MODES.size())]


## A mark as the world stores it. `color` is the body's tint for a corpse.
static func make(cell: Vector2i, kind: String, seed_value: int, fluid: String = "blood", color: String = "#888888") -> Dictionary:
	return {"x": cell.x, "y": cell.y, "kind": kind if KINDS.has(kind) else "splat", "seed": seed_value, "fluid": fluid if FLUIDS.has(fluid) else "blood", "color": color}


## Appends a mark to a list the world owns, dropping the oldest past the cap.
static func push(list: Array, mark: Dictionary) -> void:
	list.append(mark)
	while list.size() > MARKS_MAX:
		list.pop_front()


## Whether a mark shows at a gore level.
static func shows(mark: Dictionary, at_level: String) -> bool:
	match at_level:
		"off":
			return false
		"low":
			return String(mark.get("kind", "")) != "splat"
	return true


func set_palette(palette: Dictionary) -> void:
	blood = Color.html(String(palette.get("blood", DEFAULT_BLOOD)))
	queue_redraw()


func set_marks(list: Array) -> void:
	marks = list
	queue_redraw()


func add(mark: Dictionary) -> void:
	marks.append(mark)
	queue_redraw()


func clear() -> void:
	marks = []
	queue_redraw()


func set_level(name: String) -> void:
	level = name if MODES.has(name) else "full"
	queue_redraw()


## How many marks the current level draws.
func visible_count() -> int:
	var n := 0
	for m: Variant in marks:
		if shows(m, level):
			n += 1
	return n


func fluid_color(fluid: String) -> Color:
	return blood if fluid == "blood" else Color.html(OIL)


func _draw() -> void:
	if map_view == null or level == "off":
		return
	var rng := RandomNumberGenerator.new()
	for raw: Variant in marks:
		var m: Dictionary = raw
		if not shows(m, level):
			continue
		var c := to_local(map_view.cell_to_world(Vector2i(int(m["x"]), int(m["y"]))))
		rng.seed = int(m.get("seed", 0))
		var fluid := String(m.get("fluid", "blood"))
		var faint := level == "low"
		match String(m.get("kind", "splat")):
			"splat":
				if fluid == "none":
					continue
				var col := fluid_color(fluid)
				col.a = 0.75
				for i: int in rng.randi_range(3, 6):
					var at := c + Vector2(rng.randf_range(-16.0, 16.0), rng.randf_range(-7.0, 7.0))
					draw_circle(at, rng.randf_range(1.5, 4.0), col)
			"pool":
				if fluid == "none":
					continue
				var col := fluid_color(fluid)
				col.a = 0.5 if faint else 0.85
				var rx := rng.randf_range(14.0, 20.0) * (0.6 if faint else 1.0)
				draw_colored_polygon(_ellipse(c + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-2.0, 2.0)), rx, rx * 0.5, 0.0), col)
			"corpse":
				var angle := rng.randf_range(0.0, PI)
				if fluid != "none" and not faint:
					var under := fluid_color(fluid)
					under.a = 0.7
					draw_colored_polygon(_ellipse(c + Vector2(0, 2), 20.0, 9.0, 0.0), under)
				var body := Color.html(String(m.get("color", "#888888"))).darkened(0.45)
				body.a = 0.95
				draw_colored_polygon(_ellipse(c, 16.0, 5.5, angle), body)
				draw_circle(c + Vector2(cos(angle), sin(angle) * 0.5) * 17.0, 4.0, body.darkened(0.2))


static func _ellipse(centre: Vector2, rx: float, ry: float, angle: float, points: int = 14) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in points:
		var t := TAU * float(i) / float(points)
		var p := Vector2(cos(t) * rx, sin(t) * ry).rotated(angle)
		out.append(centre + Vector2(p.x, p.y * 0.5) if angle == 0.0 else centre + p)
	return out
