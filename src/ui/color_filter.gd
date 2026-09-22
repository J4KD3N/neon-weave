## Colour-blind palettes (S54, D-109): a full-screen pass over everything
## drawn, on the top layer, that daltonizes the frame for protanopia,
## deuteranopia or tritanopia (Machado 2009 simulation, the lost signal
## pushed into the channels that remain). One node, no colour in the game
## touched; hidden entirely when the palette is "normal".
class_name ColorFilter
extends CanvasLayer

const MODES: Array[String] = ["normal", "protanopia", "deuteranopia", "tritanopia"]
const SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform int mode = 0;

void fragment() {
	vec4 c = texture(screen_tex, SCREEN_UV);
	vec3 rgb = c.rgb;
	vec3 sim = rgb;
	if (mode == 1) {
		sim = mat3(vec3(0.567, 0.558, 0.0), vec3(0.433, 0.442, 0.242), vec3(0.0, 0.0, 0.758)) * rgb;
	} else if (mode == 2) {
		sim = mat3(vec3(0.625, 0.7, 0.0), vec3(0.375, 0.3, 0.3), vec3(0.0, 0.0, 0.7)) * rgb;
	} else if (mode == 3) {
		sim = mat3(vec3(0.95, 0.0, 0.0), vec3(0.05, 0.433, 0.475), vec3(0.0, 0.567, 0.525)) * rgb;
	}
	vec3 err = rgb - sim;
	vec3 shift = vec3(0.0, 0.7 * err.r + err.g, 0.7 * err.r + err.b);
	COLOR = vec4(clamp(rgb + shift, 0.0, 1.0), c.a);
}
"""

var rect: ColorRect
var material_ref: ShaderMaterial
var mode: String = "normal"


func _ready() -> void:
	layer = 100
	rect = ColorRect.new()
	rect.name = "Filter"
	rect.color = Color.WHITE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = SHADER_CODE
	material_ref = ShaderMaterial.new()
	material_ref.shader = shader
	rect.material = material_ref
	add_child(rect)
	set_mode(mode)


## Picks a palette by name; unknown names mean normal. Normal hides the
## layer so nothing is drawn twice.
func set_mode(name: String) -> void:
	mode = name if MODES.has(name) else "normal"
	var index := MODES.find(mode)
	if material_ref != null:
		material_ref.set_shader_parameter("mode", index)
	visible = index > 0


static func cycle(name: String, direction: int) -> String:
	var i := MODES.find(name)
	return MODES[posmod(i + direction, MODES.size())]
