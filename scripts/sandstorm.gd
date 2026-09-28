extends Node

# Stage 19 (Dürrschlund): short sandstorm waves. Every SANDSTORM_INTERVAL
# seconds (first after SANDSTORM_FIRST_SECONDS in the desert) a storm is
# announced (hint), blows for SANDSTORM_SECONDS and fades out. While it blows a
# light dust veil drifts over the screen EDGES only (the centre with the swarm
# always stays clear) and every creature except the swarm is a little faster
# (arena.enemy_haste). Never damages, never covers the middle of the screen.
#
#   step(delta, active) -> String   hint for the HUD pill ("" = none)
#   state  0 calm, 1 warning, 2 storm, 3 fading;  strength 0..1 (veil)
#   waves  storms so far;  force(seconds_until) for tests and captures

const TUNING = preload("res://scripts/tuning.gd")

enum State { CALM, WARNING, STORM, FADING }
# The veil starts at this share of the half screen (the middle stays clear).
const VEIL_INNER := 0.7

const VEIL_CODE := """
shader_type canvas_item;
// Dust veil at the screen edges: clear rectangle in the middle (|c| < inner),
// drifting streaks outside. `strength` 0..1.
uniform float strength = 0.0;
uniform float inner = 0.7;
uniform vec4 dust : source_color = vec4(0.9, 0.8, 0.6, 1.0);
uniform vec2 wind = vec2(1.0, 0.3);
uniform float time = 0.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 c = (UV - 0.5) * 2.0;
	float d = max(abs(c.x), abs(c.y));
	float mask = smoothstep(inner, 1.0, d);
	float n = noise(UV * vec2(5.0, 11.0) - wind * time * 0.7) * 0.6 + noise(UV * vec2(16.0, 34.0) - wind * time * 1.8) * 0.4;
	float streak = smoothstep(0.4, 0.85, n);
	float a = strength * mask * (0.5 + 0.5 * streak);
	COLOR = vec4(dust.rgb, clamp(a, 0.0, 0.75));
}
"""

var state := State.CALM
var strength := 0.0
var waves := 0
var clock := 0.0
var arena: Node3D
var _layer: CanvasLayer
var _veil: ColorRect
var _material: ShaderMaterial
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _was_active := false


func setup(arena_node: Node3D, seed_value: int = 0) -> void:
	arena = arena_node
	_rng.seed = seed_value if seed_value != 0 else 19019
	clock = TUNING.SANDSTORM_FIRST_SECONDS


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "Sandstorm veil"
	_layer.layer = 0
	add_child(_layer)
	_veil = ColorRect.new()
	_veil.name = "Veil"
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = VEIL_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("inner", VEIL_INNER)
	_veil.material = _material
	_veil.visible = false
	_layer.add_child(_veil)


## Tests / captures: the next storm is announced in `seconds`.
func force(seconds := 0.0) -> void:
	state = State.CALM
	clock = seconds


func blowing() -> bool:
	return state == State.STORM


func step(delta: float, active: bool) -> String:
	if not active:
		# Outside the desert: calm at once, the next desert visit starts fresh.
		if _was_active:
			state = State.CALM
			clock = TUNING.SANDSTORM_FIRST_SECONDS
		_was_active = false
		strength = 0.0
		_apply()
		return ""
	_was_active = true
	_time += delta
	clock -= delta
	var hint := ""
	match state:
		State.CALM:
			strength = maxf(0.0, strength - delta)
			if clock <= 0.0:
				state = State.WARNING
				clock = TUNING.SANDSTORM_WARNING
		State.WARNING:
			hint = "SANDSTURM ZIEHT AUF · Gegner werden schneller"
			strength = minf(0.25, strength + delta * 0.1)
			if clock <= 0.0:
				state = State.STORM
				clock = TUNING.SANDSTORM_SECONDS
				waves += 1
		State.STORM:
			hint = "SANDSTURM · Gegner schneller, bleib in Bewegung"
			strength = minf(1.0, strength + delta / 1.5)
			if clock <= 0.0:
				state = State.FADING
				clock = TUNING.SANDSTORM_FADE
		State.FADING:
			strength = maxf(0.0, strength - delta / TUNING.SANDSTORM_FADE)
			if clock <= 0.0:
				state = State.CALM
				strength = 0.0
				clock = _rng.randf_range(TUNING.SANDSTORM_INTERVAL.x, TUNING.SANDSTORM_INTERVAL.y)
	_apply()
	return hint


func _apply() -> void:
	var haste := 1.0
	if state == State.STORM:
		haste = TUNING.SANDSTORM_ENEMY_HASTE
	elif state == State.FADING:
		haste = lerpf(1.0, TUNING.SANDSTORM_ENEMY_HASTE, strength)
	if arena != null and is_instance_valid(arena) and "enemy_haste" in arena:
		arena.set("enemy_haste", haste)
	if _veil == null:
		return
	_veil.visible = strength > 0.001
	_material.set_shader_parameter("strength", strength)
	_material.set_shader_parameter("time", _time)


func clear() -> void:
	state = State.CALM
	strength = 0.0
	clock = TUNING.SANDSTORM_FIRST_SECONDS
	_apply()


func _exit_tree() -> void:
	if arena != null and is_instance_valid(arena) and "enemy_haste" in arena:
		arena.set("enemy_haste", 1.0)
