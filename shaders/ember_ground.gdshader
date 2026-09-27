// Glutsumpf ground (stage 09 prep): smoky peat in two tones, pale ash flecks and
// thin glowing cracks that pulse slowly. World-space, so chunks tile seamlessly.
// Lit like the Verdant StandardMaterial ground (roughness 0.95, no specular).
// use_vertex_tint: seeded maps pass the soft region tint as vertex colour (sRGB).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/ember_noise.gdshaderinc"

uniform vec4 dark_color : source_color = vec4(0.27, 0.23, 0.26, 1.0);
uniform vec4 light_color : source_color = vec4(0.42, 0.35, 0.36, 1.0);
uniform vec4 ash_color : source_color = vec4(0.54, 0.5, 0.52, 1.0);
uniform vec4 vein_color : source_color = vec4(1.0, 0.54, 0.17, 1.0);
uniform float vein_amount = 0.55;
uniform bool use_vertex_tint = false;
uniform vec4 reference_color : source_color = vec4(0.37, 0.31, 0.33, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = world_pos.xz;
	float broad = ember_noise(w * 0.085);
	float fine = ember_noise(w * 0.42 + 11.0);
	vec3 base = mix(dark_color.rgb, light_color.rgb, smoothstep(0.2, 0.85, broad * 0.72 + fine * 0.28));
	if (use_vertex_tint) {
		// Region tint relative to the biome ground colour (vertex colour is sRGB).
		vec3 tint = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
		base *= clamp(tint / max(reference_color.rgb, vec3(0.02)), vec3(0.8), vec3(1.25));
	}
	// Ash flecks: small pale spots, mostly on the lighter peat.
	float ash = smoothstep(0.82, 0.9, ember_noise(w * 3.1 + 37.0)) * smoothstep(0.45, 0.8, broad);
	base = mix(base, ash_color.rgb, ash * 0.25);
	// Glowing cracks: thin noise contour lines, only in some zones of the map.
	float zone = smoothstep(0.5, 0.68, ember_noise(w * 0.05 + 5.0));
	float crack = ember_line(ember_noise(w * 0.21 + fine * 0.6), 0.014) * zone;
	// Burnt scars: large, soft darker areas around the crack zones.
	base *= 1.0 - 0.22 * smoothstep(0.35, 0.8, zone + (fine - 0.5) * 0.4);
	float pulse = 0.72 + 0.28 * sin(TIME * 1.25 + broad * 9.0);
	ALBEDO = mix(base, vein_color.rgb * 0.45, crack * 0.75);
	EMISSION = vein_color.rgb * crack * vein_amount * pulse;
	ROUGHNESS = 0.95;
}
