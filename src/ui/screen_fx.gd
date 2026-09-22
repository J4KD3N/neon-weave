## Screen effects (S56, D-111): one full-screen pass under the colour
## filter. "glow" adds a cheap bloom (bright pixels bleed into their
## neighbours) so neon reads as light; "crt" adds scanlines and a vignette
## on top; "off" draws nothing. A setting; `--fx=<mode>` for screenshots.
class_name ScreenFx
extends CanvasLayer

const MODES: Array[String] = ["off", "glow", "crt"]
const SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform int mode = 1;
uniform float glow_strength = 0.55;
uniform float threshold = 0.45;

void fragment() {
	vec4 c = texture(screen_tex, SCREEN_UV);
	vec3 rgb = c.rgb;
	if (mode >= 1) {
		vec2 px = SCREEN_PIXEL_SIZE * 3.0;
		vec3 sum = vec3(0.0);
		for (int i = -2; i <= 2; i++) {
			for (int j = -2; j <= 2; j++) {
				vec3 s = texture(screen_tex, SCREEN_UV + vec2(float(i), float(j)) * px).rgb;
				float l = max(max(s.r, s.g), s.b);
				sum += s * smoothstep(threshold, 1.0, l);
			}
		}
		rgb += sum / 25.0 * glow_strength;
	}
	if (mode >= 2) {
		float line = mod(FRAGCOORD.y, 3.0) < 1.0 ? 0.82 : 1.0;
		rgb *= line;
		vec2 d = SCREEN_UV - vec2(0.5);
		rgb *= 1.0 - dot(d, d) * 0.55;
	}
	COLOR = vec4(min(rgb, vec3(1.0)), c.a);
}
"""

var rect: ColorRect
var material_ref: ShaderMaterial
var mode: String = "glow"


func _ready() -> void:
	layer = 99
	rect = ColorRect.new()
	rect.name = "Fx"
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


func set_mode(name: String) -> void:
	mode = name if MODES.has(name) else "glow"
	var index := MODES.find(mode)
	if material_ref != null:
		material_ref.set_shader_parameter("mode", index)
	visible = index > 0


static func cycle(name: String, direction: int) -> String:
	var i := MODES.find(name)
	return MODES[posmod(i + direction, MODES.size())]
