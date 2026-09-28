shader_type canvas_item;

// Map fog (minimap + big map). TEXTURE is the coarse exploration mask (one
// texel per fog cell, alpha 1 = unexplored). It is sampled with a smooth
// B-spline filter, then roughened with drifting cloud noise and cut with a
// soft threshold: organic cloud edges instead of stretched pixel blocks.

uniform vec4 fog_color : source_color = vec4(0.063, 0.043, 0.055, 1.0);
uniform vec4 mist_color : source_color = vec4(0.2, 0.25, 0.23, 1.0);
uniform vec4 rim_color : source_color = vec4(0.75, 0.85, 0.8, 1.0);
// Noise cells across the whole map (higher = finer clouds).
uniform float cloud_scale = 5.0;
uniform float edge_softness = 0.07;
uniform float drift = 0.012;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amp = 0.5;
	for (int octave = 0; octave < 4; octave++) {
		value += amp * noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		amp *= 0.5;
	}
	return value;
}

// Cubic B-spline sampling from 4 bilinear taps (smooth, no diamond artefacts).
vec4 cubic(float v) {
	vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
	vec4 s = n * n * n;
	float x = s.x;
	float y = s.y - 4.0 * s.x;
	float z = s.z - 4.0 * s.y + 6.0 * s.x;
	float w = 6.0 - x - y - z;
	return vec4(x, y, z, w) * (1.0 / 6.0);
}

void fragment() {
	// Inline B-spline sampling (TEXTURE cannot be passed to a function here).
	vec2 texel = TEXTURE_PIXEL_SIZE;
	vec2 coord = UV / texel - 0.5;
	vec2 f = fract(coord);
	coord -= f;
	vec4 xc = cubic(f.x);
	vec4 yc = cubic(f.y);
	vec4 c = coord.xxyy + vec2(-0.5, 1.5).xyxy;
	vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
	vec4 offset = (c + vec4(xc.yw, yc.yw) / s) * texel.xxyy;
	float m0 = texture(TEXTURE, offset.xz).a;
	float m1 = texture(TEXTURE, offset.yz).a;
	float m2 = texture(TEXTURE, offset.xw).a;
	float m3 = texture(TEXTURE, offset.yw).a;
	float sx = s.x / (s.x + s.y);
	float sy = s.z / (s.z + s.w);
	float mask = mix(mix(m3, m2, sx), mix(m1, m0, sx), sy);
	vec2 p = UV * cloud_scale * 4.0;
	float t = TIME * drift;
	float clouds = fbm(p + vec2(t, -t * 0.6));
	float detail = fbm(p * 2.7 - vec2(t * 1.7, t));
	// Wavy threshold: the explored edge breaks into soft cloud lobes.
	float edge = mask + (clouds - 0.5) * 0.42 + (detail - 0.5) * 0.12;
	float alpha = smoothstep(0.5 - edge_softness, 0.5 + edge_softness, edge);
	// Deeper inside the fog it gets darker; billows lighten it a little.
	float depth = smoothstep(0.55, 1.0, mask);
	vec3 col = mix(mist_color.rgb, fog_color.rgb, 0.45 + 0.55 * depth);
	// Visible billows: light cloud tops over darker hollows (fog, not a black hole).
	col = mix(col, mist_color.rgb * 1.45, smoothstep(0.42, 0.8, clouds) * 0.55);
	col *= 0.85 + 0.3 * detail;
	// A faint light rim where the fog lifts (reads as the edge of the known world).
	float rim = smoothstep(0.5 - edge_softness * 2.5, 0.5, edge) * (1.0 - smoothstep(0.5, 0.5 + edge_softness * 3.0, edge));
	col = mix(col, rim_color.rgb, rim * 0.5);
	COLOR = vec4(col, max(alpha, rim * 0.5) * COLOR.a);
}
