// Ground warning areas (stage 05 readability). One flat PlaneMesh (subdivide 0)
// per telegraph; every enemy type has its own pattern so the areas stay apart
// without colour: 0 hunter = striped ring with inward teeth, 1 skitter = lane of
// moving chevrons, 2 leaper = dot field + crosshair, 3 boss = radial spokes.
// All share a dark-bright-dark outer contour and a progress fill.
// Pattern coordinates are world metres: node scale is honoured, so a lane that
// is scaled along its length keeps evenly spaced chevrons.
// Palettes come from scripts/telegraph_style.gd (normal and colour-blind).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform int pattern = 0;
uniform vec4 fill_color : source_color = vec4(1.0, 0.4, 0.3, 1.0);
uniform vec4 pattern_color : source_color = vec4(1.0, 0.55, 0.4, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.96, 0.88, 1.0);
uniform vec4 dark_color : source_color = vec4(0.06, 0.04, 0.05, 1.0);
uniform float fill_alpha = 0.2;
uniform float pattern_alpha = 0.75;
// 0..1 share of the wind-up that has passed; fills the area and speeds up the pulse.
uniform float progress = 0.0;
// 0 = calm preview (contour only, faint), 1 = armed warning.
uniform float armed = 1.0;
// Animation clock in seconds; negative = use the global TIME.
uniform float time = -1.0;
uniform float opacity = 1.0;
// Contour widths in metres, outermost first.
uniform float dark_width = 0.07;
uniform float edge_width = 0.17;
uniform float inner_dark_width = 0.05;

varying vec2 local_m;
varying vec2 half_m;

void vertex() {
	vec2 scale = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	local_m = VERTEX.xz * scale;
	// Corners of an unsubdivided plane: |VERTEX| is the half size everywhere.
	half_m = abs(VERTEX.xz) * scale;
}

float aa_step(float edge, float value) {
	float w = max(fwidth(value), 1e-4);
	return smoothstep(edge - w, edge + w, value);
}

void fragment() {
	float t = time >= 0.0 ? time : TIME;
	vec2 p = local_m;
	float radius = half_m.x;
	float r = length(p);
	float angle = atan(p.y, p.x);
	// Inward distance from the outline.
	float d;
	if (pattern == 1) {
		d = min(half_m.x - abs(p.x), half_m.y - abs(p.y));
	} else {
		d = radius - r;
	}
	if (d < 0.0) {
		discard;
	}
	float contour_in = dark_width + edge_width + inner_dark_width;
	// Progress fill: grows from the centre (circles) or from the lane start.
	float reached = pattern == 1
		? 1.0 - aa_step(-half_m.y + 2.0 * half_m.y * progress, p.y)
		: 1.0 - aa_step(radius * progress, r);
	vec3 color = fill_color.rgb;
	float alpha = fill_alpha * (0.35 + 0.65 * armed) + reached * 0.22 * armed;
	color = mix(color, mix(fill_color.rgb, edge_color.rgb, 0.25), reached * 0.5);

	float mark = 0.0;
	float mark_dark = 0.0;
	if (pattern == 0) {
		// Hunter: hazard-striped band inside the contour plus inward teeth.
		float band = 0.7;
		float in_band = aa_step(contour_in, d) * (1.0 - aa_step(contour_in + band, d));
		float count = max(8.0, floor(6.2832 * radius / 0.9));
		float stripe = fract(angle / 6.2832 * count + d / band * 0.6 + t * 0.12);
		float lit = aa_step(0.5, stripe);
		mark = in_band * lit;
		mark_dark = in_band * (1.0 - lit) * 0.8;
		float teeth = max(6.0, floor(6.2832 * radius / 1.3));
		float saw = abs(fract(angle / 6.2832 * teeth - t * 0.05) * 2.0 - 1.0);
		float tooth_d = contour_in + band + 0.6 * (1.0 - saw);
		mark = max(mark, aa_step(contour_in + band - 0.01, d) * (1.0 - aa_step(tooth_d, d)));
	} else if (pattern == 1) {
		// Skitter: chevrons pointing along +Z (dash direction), scrolling forward.
		float inner = aa_step(contour_in + 0.08, d);
		float v = (p.y + abs(p.x) * 0.9) / 1.1 - t * 1.6;
		float chevron = 1.0 - aa_step(0.42, fract(v));
		mark = inner * chevron;
		mark_dark = inner * aa_step(0.42, fract(v)) * (1.0 - aa_step(0.52, fract(v))) * 0.7;
	} else if (pattern == 2) {
		// Leaper: dot field (hex grid) with a crosshair on the landing point.
		vec2 cell = vec2(0.78, 0.675);
		vec2 q = p / cell;
		float row = floor(q.y + 0.5);
		q.x += mod(row, 2.0) * 0.5;
		vec2 f = (fract(q + 0.5) - 0.5) * cell;
		float dot_r = mix(0.15, 0.2, progress);
		float dots = (1.0 - aa_step(dot_r, length(f))) * aa_step(contour_in + 0.1, d);
		float arm = min(abs(p.x), abs(p.y));
		float crossbar = (1.0 - aa_step(0.07, arm)) * aa_step(0.62, r);
		float ring = aa_step(0.34, r) * (1.0 - aa_step(0.46, r));
		float hair = max(crossbar, ring);
		mark = max(dots * (1.0 - (1.0 - aa_step(0.2, arm)) * aa_step(0.5, r)), hair);
		mark_dark = (1.0 - aa_step(0.15, arm)) * (1.0 - hair) * aa_step(0.62, r) * aa_step(contour_in, d) * 0.8;
	} else {
		// Boss: radial spokes turning slowly around a solid hub.
		float spokes = 12.0;
		float s = fract(angle / 6.2832 * spokes + t * 0.04);
		float wedge = 1.0 - aa_step(0.34, s);
		float hub = 1.0 - aa_step(0.55, r);
		mark = max(wedge * aa_step(0.9, r) * aa_step(contour_in + 0.05, d), hub);
		mark_dark = aa_step(0.34, s) * (1.0 - aa_step(0.42, s)) * aa_step(0.9, r) * aa_step(contour_in, d) * 0.6;
	}
	float pulse_rate = mix(3.0, 16.0, progress * progress);
	float pulse = 0.5 + 0.5 * sin(t * pulse_rate);
	float mark_strength = pattern_alpha * armed * mix(0.8, 1.0, pulse * progress);
	color = mix(color, dark_color.rgb, mark_dark * armed);
	alpha = mix(alpha, 0.55, mark_dark * armed);
	color = mix(color, pattern_color.rgb, mark * armed);
	alpha = mix(alpha, 1.0, mark * mark_strength);

	// Contour: dark hairline outside, bright band, dark hairline inside.
	float outer_dark = 1.0 - aa_step(dark_width, d);
	float bright = aa_step(dark_width, d) * (1.0 - aa_step(dark_width + edge_width, d));
	float inner_dark = aa_step(dark_width + edge_width, d) * (1.0 - aa_step(contour_in, d));
	float edge_glow = mix(1.0, 0.7 + 0.3 * pulse, smoothstep(0.4, 1.0, progress));
	vec3 edge_rgb = mix(pattern_color.rgb, edge_color.rgb, armed) * edge_glow;
	color = mix(color, dark_color.rgb, max(outer_dark, inner_dark));
	color = mix(color, edge_rgb, bright);
	alpha = mix(alpha, 0.9 * (0.55 + 0.45 * armed), max(outer_dark, inner_dark));
	alpha = mix(alpha, 0.6 + 0.4 * armed, bright);

	ALBEDO = color;
	ALPHA = clamp(alpha * opacity, 0.0, 1.0);
}
