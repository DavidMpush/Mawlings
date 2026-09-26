// Creature look of creature.gdshader (shared creature_look.gdshaderinc) plus procedural limb
// animation in the vertex stage, for the rig-less Mawling and Bog King meshes.
//
// All region uniforms are in the RAW mesh space the vertex shader sees (the glb
// meshes are stored Z-up; their MeshInstance3D rotates them upright). The shader
// builds its own frame from `up_axis` and `forward_axis`:
//   f = forward coordinate, u = height above the soles, l = lateral (up x forward).
// Feet are given as (f, l) centres. Pair A (front + back) and pair B step in
// opposite phase, which gives the diagonal walk (front-left with back-right).
// Leg influence fades out with height, so feet move fully and the torso stays put.
shader_type spatial;
render_mode unshaded, cull_disabled;

// Mawlings (and the Bog King, the menu Mawling) get the dark contour by default.
#define OUTLINE_DEFAULT 0.85
#include "res://shaders/creature_look.gdshaderinc"

group_uniforms frame;
uniform vec3 up_axis = vec3(0.0, 0.0, -1.0);
uniform vec3 forward_axis = vec3(-1.0, 0.0, 0.0);
// dot(VERTEX, up_axis) at the lowest sole.
uniform float ground_offset = 0.0;

group_uniforms legs;
// Diagonal pair A and pair B, each (forward, lateral) in mesh units.
uniform vec2 foot_a_front = vec2(0.24, -0.29);
uniform vec2 foot_a_back = vec2(-0.29, 0.21);
uniform vec2 foot_b_front = vec2(0.06, 0.24);
uniform vec2 foot_b_back = vec2(-0.05, -0.19);
uniform float foot_radius = 0.12;
// Height above the soles where leg influence reaches zero.
uniform float leg_height = 0.2;
// Half the fore/aft foot travel and the peak foot lift, mesh units.
uniform float stride = 0.07;
uniform float lift = 0.06;
// 0..1: pulls a rest pose that is already mid-stride back to a centred cycle while walking.
uniform float stride_centering = 1.0;

group_uniforms drive;
// Effective walk = (walk_amount + instance_walk) * walk_scale, clamped to 0..1.
uniform float walk_amount = 0.0;
uniform float walk_scale = 1.0;
// Radians per second of the automatic cycle; 0 when the script drives the phase.
uniform float walk_speed = 0.0;
uniform float walk_phase = 0.0;
// Per-instance multipliers/offsets (set by script per MeshInstance3D).
instance uniform float instance_walk = 0.0;
instance uniform float instance_phase = 0.0;
instance uniform float instance_bite = 0.0;

group_uniforms jaw;
// Lower jaw: vertices in front of the hinge and between floor and hinge height.
uniform float jaw_hinge_forward = 0.14;
uniform float jaw_hinge_height = 0.36;
uniform float jaw_floor = 0.16;
uniform float jaw_angle = 0.45;
uniform float bite_amount = 0.0;

group_uniforms tail;
// Tail: everything behind `tail_start` (forward coordinate) and above `tail_floor`.
uniform float tail_start = -0.34;
uniform float tail_length = 0.26;
uniform float tail_floor = 0.1;
uniform float tail_swing = 0.06;
uniform float tail_rate = 3.0;
uniform float tail_phase = 0.0;
// Idle sway (tail) on/off, e.g. 0 while the game is paused.
uniform float idle_motion = 1.0;

group_uniforms stomp;
// Raises foot_a_front (and swings it forward) for a telegraphed stomp.
uniform float stomp_lift = 0.0;
uniform float stomp_height = 0.2;

// Flat-topped kernel: the foot moves rigidly, only its rim blends into the body.
float foot_weight(vec2 p, vec2 foot) {
	return 1.0 - smoothstep(foot_radius * 0.55, foot_radius, distance(p, foot));
}

void vertex() {
	vec3 up = normalize(up_axis);
	vec3 fwd = normalize(forward_axis);
	vec3 lat = cross(up, fwd);
	float f = dot(VERTEX, fwd);
	float u = dot(VERTEX, up) - ground_offset;
	float l = dot(VERTEX, lat);
	vec2 p = vec2(f, l);

	float walk = clamp((walk_amount + instance_walk) * walk_scale, 0.0, 1.0);
	float phase = TIME * walk_speed + walk_phase + instance_phase;

	// Leg deformation, fading out with height (squared: feet travel, hips barely).
	float leg = 1.0 - smoothstep(0.0, leg_height, u);
	leg *= leg;
	float wa_f = foot_weight(p, foot_a_front);
	float wa_b = foot_weight(p, foot_a_back);
	float wb_f = foot_weight(p, foot_b_front);
	float wb_b = foot_weight(p, foot_b_back);
	float total = wa_f + wa_b + wb_f + wb_b;
	float norm = leg / max(1.0, total);
	// Rest-pose bias per foot: offset from the mean of its front/back row.
	float front_mid = 0.5 * (foot_a_front.x + foot_b_front.x);
	float back_mid = 0.5 * (foot_a_back.x + foot_b_back.x);
	float centering = stride_centering * walk;
	float sa = sin(phase);
	float ca = cos(phase);
	// Stride moves forward while lifted (cos > 0), backward on the ground.
	float step_a = walk * stride * sa;
	float step_b = -step_a;
	float up_a = walk * lift * max(0.0, ca);
	float up_b = walk * lift * max(0.0, -ca);
	float d_f = wa_f * (step_a - centering * (foot_a_front.x - front_mid))
		+ wa_b * (step_a - centering * (foot_a_back.x - back_mid))
		+ wb_f * (step_b - centering * (foot_b_front.x - front_mid))
		+ wb_b * (step_b - centering * (foot_b_back.x - back_mid));
	float d_u = (wa_f + wa_b) * up_a + (wb_f + wb_b) * up_b;
	f += d_f * norm;
	u += d_u * norm;
	// Stomp: the whole forearm of foot_a_front rises (wider radius, linear height
	// falloff) so the limb lifts as one piece instead of stretching the claws.
	float stomp = (1.0 - smoothstep(foot_radius * 0.9, foot_radius * 1.6, distance(p, foot_a_front)))
		* (1.0 - smoothstep(0.0, leg_height * 1.8, u));
	u += stomp * stomp_lift * stomp_height;
	f += stomp * stomp_lift * stomp_height * 0.3;

	// Lower jaw drops around a lateral hinge.
	float bite = clamp(bite_amount + instance_bite, 0.0, 1.0);
	float jaw = smoothstep(jaw_hinge_forward, jaw_hinge_forward + 0.06, f)
		* (1.0 - smoothstep(jaw_hinge_height - 0.03, jaw_hinge_height + 0.01, u))
		* smoothstep(jaw_floor, jaw_floor + 0.04, u);
	float angle = bite * jaw_angle * jaw;
	float rf = f - jaw_hinge_forward;
	float ru = u - jaw_hinge_height;
	float cj = cos(angle);
	float sj = sin(angle);
	f = jaw_hinge_forward + rf * cj + ru * sj;
	u = jaw_hinge_height - rf * sj + ru * cj;

	// Tail pendulum, stronger towards the tip and while walking.
	float tail = smoothstep(tail_start, tail_start - tail_length, f) * smoothstep(tail_floor, tail_floor + 0.05, u);
	float swing = sin(TIME * tail_rate + tail_phase + instance_phase * 0.5);
	l += tail * tail * tail_swing * swing * (0.35 * idle_motion + 0.65 * walk);

	VERTEX = fwd * f + up * (u + ground_offset) + lat * l;
}

void fragment() {
	ALBEDO = creature_look(COLOR.rgb, NORMAL, VIEW, FRONT_FACING);
}
