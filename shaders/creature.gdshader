// Shared creature look: vertex-colour albedo, soft fake key light for shape,
// a coloured rim that separates silhouettes from the green ground, and a hit flash.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float brightness = 1.0;
uniform float saturation = 1.0;
uniform float shape_light = 0.35;
uniform vec4 rim_color : source_color = vec4(1.0, 0.85, 0.7, 1.0);
uniform float rim_strength = 0.0;
uniform float rim_power = 2.5;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash = 0.0;

void fragment() {
	vec3 base = COLOR.rgb * brightness;
	float grey = dot(base, vec3(0.299, 0.587, 0.114));
	base = mix(vec3(grey), base, saturation);
	vec3 normal = normalize(NORMAL);
	if (!FRONT_FACING) {
		normal = -normal;
	}
	// View-space key light from upper left, facing the camera.
	float key = clamp(dot(normal, normalize(vec3(-0.35, 0.75, 0.55))) * 0.5 + 0.5, 0.0, 1.0);
	base *= mix(1.0 - shape_light, 1.0 + shape_light * 0.45, key);
	float rim = pow(1.0 - clamp(abs(dot(normal, VIEW)), 0.0, 1.0), rim_power) * rim_strength;
	base = mix(base, rim_color.rgb, clamp(rim, 0.0, 1.0));
	base = mix(base, flash_color.rgb, clamp(flash, 0.0, 1.0));
	ALBEDO = base;
}
