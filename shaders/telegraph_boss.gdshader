// Boss warning areas from the user's VFX package V1 (boss_telegraph_circle.svg /
// boss_telegraph_cone.svg). tools/build_vfx.gd rasterises each SVG into a
// channel mask: R = translucent fill, G = dark contour, B = coral ring/edge,
// A = pale marks (dashed inner ring, corner arrows, chevrons, origin diamond).
// Colours come from scripts/telegraph_style.gd ("boss" palette, normal and
// colour-blind), so the shapes stay and only the hues change.
// Same uniforms as telegraph.gdshader: progress (wind-up share, grows a darker
// fill from the centre / cone origin and speeds up the ring pulse), armed, time,
// opacity. The mesh maps the SVG's hit edge exactly onto the attack radius.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D mask : filter_linear_mipmap, repeat_disable;
// 0 = circle (centre 256/256, hit radius 210 px), 1 = cone (origin 75/256, reach ~412 px).
uniform int shape = 0;
// Free tag for callers (e.g. the toad's shape id); not used for drawing.
uniform int pattern = 0;
uniform vec4 fill_color : source_color = vec4(1.0, 0.431, 0.345, 1.0);
uniform vec4 pattern_color : source_color = vec4(1.0, 0.894, 0.733, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.443, 0.373, 1.0);
uniform vec4 dark_color : source_color = vec4(0.22, 0.094, 0.141, 1.0);
uniform float fill_alpha = 0.13;
uniform float progress = 0.0;
uniform float armed = 1.0;
uniform float time = -1.0;
uniform float opacity = 1.0;

void over(inout vec3 color, inout float alpha, vec3 layer, float layer_alpha) {
	float out_alpha = layer_alpha + alpha * (1.0 - layer_alpha);
	if (out_alpha > 1e-4) {
		color = (layer * layer_alpha + color * alpha * (1.0 - layer_alpha)) / out_alpha;
	}
	alpha = out_alpha;
}

void fragment() {
	float t = time >= 0.0 ? time : TIME;
	vec4 m = texture(mask, UV);
	vec2 px = UV * 512.0;
	// Share of the hit radius / reach at this pixel (0 at centre or cone origin).
	float r = shape == 1 ? length(px - vec2(75.0, 256.0)) / 412.0 : length(px - vec2(256.0)) / 210.0;
	float w = max(fwidth(r), 1e-4);
	float reached = 1.0 - smoothstep(progress - w, progress + w, r);
	float front = (1.0 - smoothstep(0.0, 2.5 * w, abs(r - progress))) * step(0.02, progress) * step(progress, 0.995);

	float pulse_rate = mix(3.0, 16.0, progress * progress);
	float pulse = 0.5 + 0.5 * sin(t * pulse_rate);
	float ramp = smoothstep(0.3, 1.0, progress);

	// Fill: faint while approaching, stronger when armed; the passed wind-up share
	// darkens towards the contour colour so the coral swarm stays readable inside.
	vec3 color = fill_color.rgb;
	float alpha = m.r * fill_alpha * (0.35 + 0.65 * armed);
	over(color, alpha, mix(fill_color.rgb, dark_color.rgb, 0.55), m.r * reached * 0.26 * armed);
	over(color, alpha, pattern_color.rgb, m.r * front * 0.55 * armed);
	// Pale marks, dark contour, coral ring on top (SVG order).
	over(color, alpha, pattern_color.rgb, m.a * (0.35 + 0.55 * armed) * mix(1.0, 0.75 + 0.25 * pulse, ramp));
	over(color, alpha, dark_color.rgb, m.g * 0.88 * (0.55 + 0.45 * armed));
	vec3 ring = mix(pattern_color.rgb, edge_color.rgb, armed) * mix(1.0, 0.8 + 0.45 * pulse, ramp);
	over(color, alpha, ring, m.b * (0.6 + 0.4 * armed));
	if (alpha < 0.003) {
		discard;
	}
	ALBEDO = color;
	ALPHA = clamp(alpha * opacity, 0.0, 1.0);
}
