## The lighting pass (S56, D-111): glow lives in the engine, not the
## sprites (GDD §5). A CanvasModulate dims the world to the biome's
## ambient, a PointLight2D sits on every tile whose art names a `glow`
## palette role (mana pools, conduits, pads, doors) up to a budget, and one
## light walks with the leader. Rebuilt with the map; off by a setting.
class_name LightingRig
extends Node2D

static var enabled: bool = true

const DEFAULT_AMBIENT := "#8c85a3"

var ambient_node: CanvasModulate
var party_light: PointLight2D
var lights: Array[PointLight2D] = []
var rules: Dictionary = {}
var ambient: Color = Color.WHITE
var _texture: GradientTexture2D


func _ready() -> void:
	name = "Lighting"
	_texture = GradientTexture2D.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	_texture.gradient = gradient
	_texture.fill = GradientTexture2D.FILL_RADIAL
	_texture.fill_from = Vector2(0.5, 0.5)
	_texture.fill_to = Vector2(0.5, 0.0)
	_texture.width = 256
	_texture.height = 256
	ambient_node = CanvasModulate.new()
	ambient_node.name = "Ambient"
	add_child(ambient_node)
	party_light = _make_light(Color.WHITE, 0.7, 140.0)
	party_light.name = "PartyLight"
	add_child(party_light)
	apply_enabled()


## Lays the lights for a map: one per glowing tile (a palette role in the
## tile's art `glow`), first come first served up to `max_lights`.
## Returns how many were placed.
func rebuild(map: MapData, palette: Dictionary, p_rules: Dictionary, cell_to_world: Callable) -> int:
	rules = p_rules
	for l: PointLight2D in lights:
		l.queue_free()
	lights.clear()
	ambient = Color.html(String(palette.get("ambient", rules.get("ambient", DEFAULT_AMBIENT))))
	var energy := float(rules.get("glow_energy", 0.9))
	var radius := float(rules.get("glow_radius", 96.0))
	var budget := int(rules.get("max_lights", 48))
	var party: Dictionary = rules.get("party_light", {})
	party_light.energy = float(party.get("energy", 0.7))
	party_light.texture_scale = float(party.get("radius", 140.0)) / 128.0
	for y: int in map.height:
		for x: int in map.width:
			if lights.size() >= budget:
				break
			var cell := Vector2i(x, y)
			var tile: Dictionary = map.tile_at(cell)
			var art: Dictionary = tile.get("art", {})
			var role := String(art.get("glow", ""))
			if role.is_empty() or map.is_enclosed(cell):
				continue
			var color := Color.html(String(palette.get(role, "#ffffff")))
			var light := _make_light(color, energy, radius)
			light.position = cell_to_world.call(cell)
			add_child(light)
			lights.append(light)
	apply_enabled()
	return lights.size()


## The leader's light walks with the leader.
func follow(world_position: Vector2) -> void:
	party_light.position = world_position


func set_enabled(on: bool) -> void:
	enabled = on
	apply_enabled()


## Off means the world at full brightness and no lights drawn.
func apply_enabled() -> void:
	ambient_node.color = ambient if enabled else Color.WHITE
	party_light.visible = enabled
	for l: PointLight2D in lights:
		l.visible = enabled


func _make_light(color: Color, energy: float, radius: float) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = _texture
	light.color = color
	light.energy = energy
	light.texture_scale = radius / 128.0
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.shadow_enabled = false
	return light
