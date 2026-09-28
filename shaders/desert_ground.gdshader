// Dürrschlund ground (stage 19): pale ochre dunes with cool blue-grey troughs,
// thin bent wind ripples and a few bone-white flecks. World-space, so chunks
// tile seamlessly; lit like the Verdant ground (roughness 0.95, no specular).
// Never orange: the ember-red swarm must stay the strongest colour on the sand.
// use_vertex_tint: seeded maps pass the soft region tint as vertex colour (sRGB).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/ember_noise.gdshaderinc"

uniform vec4 dune_light : source_color = vec4(0.9, 0.83, 0.67, 1.0);
uniform vec4 dune_shadow : source_color = vec4(0.7, 0.65, 0.56, 1.0);
uniform vec4 shadow_cool : source_color = vec4(0.56, 0.58, 0.65, 1.0);
uniform vec4 ripple : source_color = vec4(0.8, 0.71, 0.54, 1.0);
uniform float ripple_amount = 0.4;
uniform vec4 bone_fleck : source_color = vec4(0.96, 0.93, 0.85, 1.0);
uniform bool use_vertex_tint = false;
uniform vec4 reference_color : source_color = vec4(0.86, 0.78, 0.62, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 w = world_pos.xz;
	// Broad dunes: light crests, cool troughs (subtle, the swarm stays on top).
	float dune = ember_noise(w * 0.035) * 0.65 + ember_noise(w * 0.09 + 3.1) * 0.35;
	vec3 base = mix(dune_shadow.rgb, dune_light.rgb, smoothstep(0.22, 0.78, dune));
	base = mix(base, shadow_cool.rgb, (1.0 - smoothstep(0.12, 0.42, dune)) * 0.3);
	if (use_vertex_tint) {
		vec3 tint = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
		base *= clamp(tint / max(reference_color.rgb, vec3(0.02)), vec3(0.85), vec3(1.15));
	}
	// Wind ripples: thin bent stripes, fading on the dune troughs.
	float bend = ember_noise(w * 0.05) * 6.0;
	float stripe = sin(w.x * 2.2 + w.y * 0.75 + bend);
	float ripple_mask = smoothstep(0.86, 0.99, stripe) * smoothstep(0.2, 0.55, dune);
	base = mix(base, ripple.rgb, ripple_mask * ripple_amount * 0.55);
	// Soft shadow line on the lee side of every ripple (reads as relief).
	float lee = smoothstep(0.55, 0.8, stripe) * (1.0 - smoothstep(0.86, 0.95, stripe));
	base = mix(base, shadow_cool.rgb, lee * ripple_amount * 0.12 * smoothstep(0.2, 0.55, dune));
	// Bone-white flecks: rare small spots.
	float fleck = smoothstep(0.9, 0.95, ember_noise(w * 2.7 + 41.0)) * smoothstep(0.55, 0.75, ember_noise(w * 0.12 + 9.0));
	base = mix(base, bone_fleck.rgb, fleck * 0.35);
	ALBEDO = base;
	ROUGHNESS = 0.95;
}
