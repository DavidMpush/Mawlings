// Glutsumpf glow channel (replaces the sand trail). One mesh per chunk carries a
// vertex-colour profile across the channel: COLOR.a = glow (1 on the centre
// line), COLOR.r = rim share (1 on the outer edge). The core breaks into slowly
// drifting ember segments; the crust stays dark so warnings and the swarm read.
shader_type spatial;
render_mode unshaded, cull_disabled;

#include "res://shaders/ember_noise.gdshaderinc"

uniform vec4 crust_color : source_color = vec4(0.17, 0.13, 0.14, 1.0);
uniform vec4 rim_color : source_color = vec4(0.29, 0.23, 0.23, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.69, 0.24, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.94, 0.63, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = world_pos.xz;
	float glow = COLOR.a;
	float drift = ember_noise(w * 0.5 + vec2(TIME * 0.18, TIME * -0.11));
	float grain = ember_noise(w * 1.9 + 3.0);
	// Broken core: the threshold wanders, so the line splits into segments.
	float core = smoothstep(0.52 + 0.4 * drift, 0.72 + 0.3 * drift, glow);
	// Hairline side cracks branching off the core.
	float side = ember_line(ember_noise(w * 0.8 + 21.0), 0.02) * smoothstep(0.15, 0.45, glow) * (1.0 - core);
	float pulse = 0.82 + 0.18 * sin(TIME * 1.7 + w.x * 0.21 + w.y * 0.17);
	vec3 crust = mix(crust_color.rgb, rim_color.rgb, COLOR.r) * (0.82 + 0.3 * grain);
	vec3 hot = mix(core_color.rgb, hot_color.rgb, core * core * drift) * pulse;
	float heat = clamp(core + side * 0.7, 0.0, 1.0);
	// A faint warm halo around the core so the channel reads as hot from afar.
	crust = mix(crust, core_color.rgb * 0.45, smoothstep(0.35, 0.8, glow) * 0.35);
	ALBEDO = mix(crust, hot, heat);
}
