// Stage 20: boss warning shapes that the SVG masks (telegraph_boss.gdshader:
// circle, cone) cannot draw, in the same style - so every boss attack reads
// alike: a bright danger ring EXACTLY on the hit edge (its outer border is the
// edge), a dark contour just outside, a translucent fill that darkens from the
// origin with the wind-up (`progress`) and pale marks inside. Colours come from
// scripts/telegraph_style.gd (palette "boss" / "hazard", colour-blind variants).
//
//   shape 0  disc            radius = `outer`
//   shape 1  lane            half width = `half_width`, length = `lane_length`; it
//                            starts at local z = -lane_length/2 and points along +Z
//                            (chevrons run outward, the wind-up grows from -Z)
//   shape 2  ring            `inner` .. `outer` (inside and outside are safe)
//   shape 3  disc + islands  up to 4 safe islands (xy = local centre, z = radius)
//   shape 4  hazard area     "liegt da": filled, calm rim, slow bubbles, no
//                            wind-up front and no pulse (Glutpfützen, Säure)
// The mesh (telegraph_style.shape_mesh) is the shape plus MARGIN on every side.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform int shape = 0;
// Kept for callers that tag a material with their own pattern id (tests).
uniform int pattern = 0;
uniform vec4 fill_color : source_color = vec4(0.95, 0.21, 0.56, 1.0);
uniform vec4 pattern_color : source_color = vec4(1.0, 0.9, 0.95, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.31, 0.63, 1.0);
uniform vec4 dark_color : source_color = vec4(0.23, 0.06, 0.14, 1.0);
uniform vec4 safe_color : source_color = vec4(0.5, 0.9, 1.0, 1.0);
uniform float fill_alpha = 0.2;
uniform float progress = 0.0;
uniform float armed = 1.0;
uniform float time = -1.0;
uniform float opacity = 1.0;
uniform float outer = 4.0;
uniform float inner = 0.0;
uniform float half_width = 1.5;
uniform float lane_length = 10.0;
uniform vec4 islands[4];
uniform int island_count = 0;

varying vec2 local_m;

void vertex() {
	vec2 s = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	local_m = VERTEX.xz * s;
}

float aa(float e, float v) {
	float w = max(fwidth(v), 1e-4);
	return smoothstep(e - w, e + w, v);
}

void over(inout vec3 color, inout float alpha, vec3 layer, float layer_alpha) {
	float out_alpha = layer_alpha + alpha * (1.0 - layer_alpha);
	if (out_alpha > 1e-4) {
		color = (layer * layer_alpha + color * alpha * (1.0 - layer_alpha)) / out_alpha;
	}
	alpha = out_alpha;
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float t = time >= 0.0 ? time : TIME;
	vec2 p = local_m;
	float r = length(p);
	float ang = atan(p.y, p.x);
	// d: signed distance to the hit edge in metres (+ inside); u: wind-up
	// coordinate 0 at the origin .. 1 at the far edge; s: arc length along the
	// edge (dashes).
	float d = outer - r;
	float u = r / max(outer, 0.01);
	float s = ang * max(r, 0.5);
	if (shape == 1) {
		d = min(half_width - abs(p.x), lane_length * 0.5 - abs(p.y));
		u = (p.y + lane_length * 0.5) / max(lane_length, 0.01);
		s = abs(p.x) > half_width - 0.4 ? p.y : p.x;
	} else if (shape == 2) {
		d = min(outer - r, r - inner);
		u = (r - inner) / max(outer - inner, 0.01);
	}
	float safe_d = 1e6;
	if (shape == 3) {
		for (int i = 0; i < 4; i++) {
			if (i < island_count) {
				safe_d = min(safe_d, length(p - islands[i].xy) - islands[i].z);
			}
		}
	}
	vec3 color = fill_color.rgb;
	float alpha = 0.0;
	if (shape == 4) {
		// Hazard area: solid fill, soft dark rim, slow bubbles - it lies there.
		if (d < -0.2) {
			discard;
		}
		float inside = aa(0.0, d);
		float cell = hash(floor((p + vec2(t * 0.15, -t * 0.1)) / 0.9));
		vec2 f = fract((p + vec2(t * 0.15, -t * 0.1)) / 0.9) - 0.5;
		float bubble = (1.0 - aa(0.18 + 0.1 * cell, length(f))) * step(0.55, cell) * aa(0.5, d);
		alpha = inside * fill_alpha;
		over(color, alpha, pattern_color.rgb, bubble * 0.55);
		float rim = aa(-0.2, d) * (1.0 - aa(0.25, d));
		over(color, alpha, dark_color.rgb, rim * 0.75);
		float lip = aa(0.25, d) * (1.0 - aa(0.45, d));
		over(color, alpha, edge_color.rgb, lip * 0.8);
		ALBEDO = color;
		ALPHA = clamp(alpha * opacity, 0.0, 1.0);
	} else {
		if (d < -0.24) {
			discard;
		}
		float w = max(fwidth(u), 1e-4);
		float reached = 1.0 - smoothstep(progress - w, progress + w, u);
		float front = (1.0 - smoothstep(0.0, 2.5 * w, abs(u - progress))) * step(0.02, progress) * step(progress, 0.995);
		float pulse = 0.5 + 0.5 * sin(t * mix(3.0, 16.0, progress * progress));
		float ramp = smoothstep(0.3, 1.0, progress);
		float inside = aa(0.0, d);
		// Fill: faint while approaching, stronger when armed; the passed wind-up
		// share darkens so the swarm inside stays readable.
		alpha = inside * fill_alpha * (0.35 + 0.65 * armed);
		over(color, alpha, mix(fill_color.rgb, dark_color.rgb, 0.55), inside * reached * 0.26 * armed);
		over(color, alpha, pattern_color.rgb, inside * front * 0.55 * armed);
		// Pale marks: a dashed inner ring 0.55 m inside every edge, chevrons on lanes.
		float dash = step(0.5, fract(s / 1.1 - t * 0.35));
		float inner_line = aa(0.5, d) * (1.0 - aa(0.66, d)) * dash;
		float marks = inner_line;
		if (shape == 1) {
			float along = fract((p.y + lane_length * 0.5) / 1.6 - t * mix(0.4, 1.4, progress));
			float chevron = abs(along - 0.5 - abs(p.x) / max(half_width, 0.01) * 0.28);
			marks = max(marks, (1.0 - aa(0.07, chevron)) * aa(0.75, d));
		}
		over(color, alpha, pattern_color.rgb, marks * (0.35 + 0.55 * armed) * mix(1.0, 0.75 + 0.25 * pulse, ramp));
		// Contour: dark just outside the edge, bright danger band inside it (its
		// outer border is the hit edge).
		float outside_dark = (1.0 - aa(0.0, d)) * aa(-0.22, d);
		over(color, alpha, dark_color.rgb, outside_dark * 0.88 * (0.55 + 0.45 * armed));
		float band = aa(0.0, d) * (1.0 - aa(0.22, d));
		vec3 ring = mix(pattern_color.rgb, edge_color.rgb, armed) * mix(1.0, 0.8 + 0.45 * pulse, ramp);
		over(color, alpha, ring, band * (0.6 + 0.4 * armed));
		float inner_dark = aa(0.22, d) * (1.0 - aa(0.32, d));
		over(color, alpha, dark_color.rgb, inner_dark * 0.5 * armed);
		// Safe islands: clear ground with a friendly outline (never danger colours).
		if (safe_d < 0.0) {
			float line = max(1.0 - aa(0.22, -safe_d), aa(0.45, -safe_d) * (1.0 - aa(0.55, -safe_d)));
			color = mix(safe_color.rgb, vec3(1.0), line);
			alpha = mix(0.3 + 0.1 * pulse, 1.0, line);
		} else if (safe_d < 0.2) {
			color = mix(color, dark_color.rgb, 0.85);
			alpha = max(alpha, 0.85);
		}
		if (alpha < 0.003) {
			discard;
		}
		ALBEDO = color;
		ALPHA = clamp(alpha * opacity, 0.0, 1.0);
	}
}
