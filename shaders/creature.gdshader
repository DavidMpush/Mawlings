// Shared creature/prop look (see creature_look.gdshaderinc): vertex-colour albedo,
// soft fake key light, a coloured rim, optional prop recolour and a hit flash.
// The dark contour is off by default here (props, prey, enemies keep their look).
shader_type spatial;
render_mode unshaded, cull_disabled;

#define OUTLINE_DEFAULT 0.0
#include "res://shaders/creature_look.gdshaderinc"

void fragment() {
	ALBEDO = creature_look(COLOR.rgb, NORMAL, VIEW, FRONT_FACING);
}
