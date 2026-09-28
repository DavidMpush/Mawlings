// Shared body of the pooled VFX sprites (scripts/vfx_sprites.gd). One MultiMesh
// per effect texture; every instance is a flat quad (PlaneMesh 1 x 1, faces +Y)
// whose transform holds position, tilt towards the camera and base size.
// The whole animation runs here, so the CPU touches an instance only at spawn:
//   INSTANCE_CUSTOM.x = start time (manager clock), .y = duration (s),
//   .z = start rotation (rad), .w = variation 0..1 (spin direction, drift)
// `now` is the manager clock: it only advances while the world steps, so pause
// freezes every effect and reset simply hides them.
// Drawn over bodies and the swarm (no depth test): a 0.15-0.7 s effect must never
// vanish inside a creature or under the dense swarm; caps keep the screen calm.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D sprite : source_color, filter_linear_mipmap, repeat_disable;
// 0 bite, 1 acid, 2 spore, 3 shockwave, 4 harvest (pulled to `pull_target`), 5 dna (rises)
uniform int mode = 0;
uniform float now = 0.0;
uniform vec3 pull_target = vec3(0.0);
uniform float opacity = 1.0;
// Own strain abilities (scripts/vfx_sprites.gd ABILITY_POOL): 1 = the sprite's
// light and shade mapped onto the swarm's ember ramp (deep red -> orange ->
// warm white) instead of the painted poison violet/green.
uniform float ember = 0.0;

varying float v_alpha;
varying float v_flash;

float ease_out(float t) {
	return 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
}

// Small overshoot: 0 -> ~1.1 -> 1.
float ease_back(float t) {
	float c = 1.7;
	float u = t - 1.0;
	return 1.0 + (c + 1.0) * u * u * u + c * u * u;
}

void vertex() {
	float duration = max(INSTANCE_CUSTOM.y, 0.001);
	float age = (now - INSTANCE_CUSTOM.x) / duration;
	float spin_dir = INSTANCE_CUSTOM.w < 0.5 ? -1.0 : 1.0;
	float grow = 1.0;
	float spin = 0.0;
	float alpha = 1.0;
	float flash = 0.0;
	vec3 world_offset = vec3(0.0);
	if (mode == 0) {
		// Bite: pops open, turns a little, snaps away.
		grow = mix(0.55, 1.0, ease_back(clamp(age / 0.45, 0.0, 1.0)));
		spin = spin_dir * 0.35 * age;
		alpha = 1.0 - smoothstep(0.5, 1.0, age);
		flash = 1.0 - smoothstep(0.0, 0.35, age);
	} else if (mode == 1) {
		// Acid: splashes from 70 to 110 %.
		grow = mix(0.7, 1.1, ease_out(age));
		spin = spin_dir * 0.12 * age;
		alpha = 1.0 - smoothstep(0.45, 1.0, age);
	} else if (mode == 2) {
		// Spores: puff grows and fades, slow turn.
		grow = mix(0.6, 1.15, ease_out(age));
		spin = spin_dir * 0.4 * age;
		alpha = smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.4, 1.0, age));
	} else if (mode == 3) {
		// Shockwave: fast radial push, fades while it widens.
		grow = mix(0.3, 1.0, ease_out(age));
		alpha = 1.0 - smoothstep(0.35, 1.0, age);
		flash = 1.0 - smoothstep(0.0, 0.25, age);
	} else if (mode == 4) {
		// Harvest: short pop, then pulled into the swarm centre and absorbed.
		float pull = smoothstep(0.15, 1.0, age);
		world_offset = (pull_target - MODEL_MATRIX[3].xyz) * pull * pull;
		world_offset.y = 0.0;
		grow = mix(0.7, 1.0, ease_out(clamp(age / 0.2, 0.0, 1.0))) * mix(1.0, 0.45, pull);
		spin = spin_dir * 1.2 * age;
		alpha = smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.7, 1.0, age));
	} else {
		// DNA: flashes up and drifts upwards (towards screen-top).
		grow = mix(0.5, 1.0, ease_back(clamp(age / 0.35, 0.0, 1.0)));
		world_offset = vec3(0.0, 1.4, -0.9) * ease_out(age);
		alpha = 1.0 - smoothstep(0.55, 1.0, age);
		flash = 1.0 - smoothstep(0.0, 0.4, age);
	}
	float angle = INSTANCE_CUSTOM.z + spin;
	vec2 corner = VERTEX.xz * grow;
	float c = cos(angle);
	float s = sin(angle);
	VERTEX.xz = vec2(c * corner.x - s * corner.y, s * corner.x + c * corner.y);
	// World offset into model space (the basis holds tilt and size).
	VERTEX += inverse(mat3(MODEL_MATRIX)) * world_offset;
	bool live = age >= 0.0 && age < 1.0;
	// Finished or not yet started: collapse the quad (no fragments at all).
	VERTEX = live ? VERTEX : vec3(0.0);
	v_alpha = live ? alpha : 0.0;
	v_flash = flash;
}

void fragment() {
	vec4 tex = texture(sprite, UV);
	vec3 col = tex.rgb;
	if (ember > 0.0) {
		float lum = max(max(col.r, col.g), col.b) * 0.6 + dot(col, vec3(0.299, 0.587, 0.114)) * 0.4;
		vec3 ramp = mix(vec3(0.55, 0.09, 0.03), vec3(1.0, 0.47, 0.1), smoothstep(0.15, 0.6, lum));
		ramp = mix(ramp, vec3(1.0, 0.85, 0.52), smoothstep(0.7, 0.98, lum));
		col = mix(col, ramp, ember);
	}
	ALBEDO = col * (1.0 + 0.6 * v_flash);
	ALPHA = tex.a * v_alpha * opacity;
}
