// Glutsumpf eruption (scripts/eruptions.gd). One flat PlaneMesh per eruption.
// mode 0 = warning: rings contract towards the centre (faster with progress)
//          around a hot core that grows until the burst, inside the shared
//          dark-bright-dark contour of every telegraph (telegraph.gdshader).
//          The ring pattern exists nowhere else, so it reads without colour.
// mode 1 = burst: a splash of lava that cools to dark crust and fades (`age`).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/ember_noise.gdshaderinc"

uniform int mode = 0;
uniform vec4 fill_color : source_color = vec4(0.17, 0.05, 0.02, 1.0);
uniform vec4 pattern_color : source_color = vec4(1.0, 0.81, 0.29, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.95, 0.81, 1.0);
uniform vec4 dark_color : source_color = vec4(0.06, 0.04, 0.05, 1.0);
uniform vec4 lava_core : source_color = vec4(1.0, 0.89, 0.48, 1.0);
uniform vec4 lava_mid : source_color = vec4(1.0, 0.6, 0.18, 1.0);
uniform vec4 lava_crust : source_color = vec4(0.35, 0.13, 0.08, 1.0);
uniform float fill_alpha = 0.45;
uniform float progress = 0.0;
uniform float age = 0.0;
uniform float opacity = 1.0;
uniform float dark_width = 0.08;
uniform float edge_width = 0.2;
uniform float inner_dark_width = 0.06;

varying vec2 local_m;
varying vec2 half_m;
varying vec3 world_pos;

void vertex() {
	vec2 scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	local_m = VERTEX.xz * scale;
	half_m = abs(VERTEX.xz) * scale;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float aa_step(float edge, float value) {
	float w = max(fwidth(value), 1e-4);
	return smoothstep(edge - w, edge + w, value);
}

void fragment() {
	vec2 p = local_m;
	float radius = half_m.x;
	float r = length(p);
	float d = radius - r;
	if (d < 0.0) {
		discard;
	}
	if (mode == 1) {
		// Burst: reaches full size fast, then cools and fades.
		float reach = radius * min(1.0, 0.35 + age * 5.0);
		float inside = 1.0 - aa_step(reach, r);
		float blob = ember_noise(world_pos.xz * 1.3 + age * 2.0);
		float heat = clamp((1.0 - age * 1.3) * (1.1 - r / radius * 0.6) + (blob - 0.5) * 0.5, 0.0, 1.0);
		vec3 hot = mix(lava_mid.rgb, lava_core.rgb, heat);
		vec3 color = mix(lava_crust.rgb, hot, smoothstep(0.1, 0.55, heat));
		float ring = aa_step(reach - 0.25, r) * inside * (1.0 - age);
		color = mix(color, edge_color.rgb, ring);
		ALBEDO = color;
		ALPHA = clamp(inside * (1.0 - smoothstep(0.55, 1.0, age)) * (0.75 + 0.25 * blob) * opacity, 0.0, 1.0);
	} else {
		float t = TIME;
		float contour_in = dark_width + edge_width + inner_dark_width;
		vec3 color = fill_color.rgb;
		float alpha = fill_alpha * (0.7 + 0.3 * progress);
		// Contracting rings: spacing 0.62 m, speed rises towards the burst.
		float speed = mix(0.9, 3.2, progress * progress);
		float wave = fract(r / 0.62 + t * speed);
		float ring = (1.0 - aa_step(0.34, wave)) * aa_step(contour_in + 0.06, d);
		float ring_dark = aa_step(0.34, wave) * (1.0 - aa_step(0.5, wave)) * aa_step(contour_in, d);
		// Hot core grows with the wind-up: its rim shows how much time is left.
		float core_r = mix(0.35, radius * 0.72, progress);
		float core = 1.0 - aa_step(core_r, r);
		float core_rim = aa_step(core_r - 0.12, r) * core;
		color = mix(color, dark_color.rgb, ring_dark * 0.8);
		alpha = mix(alpha, 0.7, ring_dark * 0.6);
		color = mix(color, pattern_color.rgb, ring * (1.0 - core));
		alpha = mix(alpha, 0.95, ring * (1.0 - core));
		float boil = ember_noise(world_pos.xz * 2.2 + vec2(t * 0.8, -t * 0.6));
		// Stage 20: the core is lava (not a warning colour); rings and contour carry the danger hue.
		vec3 core_rgb = mix(lava_mid.rgb, lava_core.rgb, boil * 0.6);
		color = mix(color, core_rgb, core * 0.9);
		alpha = mix(alpha, 0.72 + 0.2 * boil, core);
		color = mix(color, dark_color.rgb, core_rim);
		alpha = mix(alpha, 0.95, core_rim);
		// Contour: dark hairline, bright band (pulses faster near the burst), dark hairline.
		float pulse = 0.5 + 0.5 * sin(t * mix(4.0, 18.0, progress * progress));
		float outer_dark = 1.0 - aa_step(dark_width, d);
		float bright = aa_step(dark_width, d) * (1.0 - aa_step(dark_width + edge_width, d));
		float inner_dark = aa_step(dark_width + edge_width, d) * (1.0 - aa_step(contour_in, d));
		color = mix(color, dark_color.rgb, max(outer_dark, inner_dark));
		color = mix(color, edge_color.rgb * mix(1.0, 0.75 + 0.25 * pulse, progress), bright);
		alpha = mix(alpha, 0.95, max(outer_dark, inner_dark));
		alpha = mix(alpha, 1.0, bright);
		ALBEDO = color;
		ALPHA = clamp(alpha * opacity, 0.0, 1.0);
	}
}
