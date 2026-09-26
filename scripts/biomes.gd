extends RefCounted

# Biome data (stage 07, APEX preparation). Pure data: arena.gd reads ground,
# trail, decoration and pool colours plus a few decoration counts from here;
# hunt_world / enemies may read `enemy_tints` and `light` in stage 08.
#
# verdant_maw reproduces the classic arena exactly (every value below was the
# former constant in arena.gd), so the default biome never changes the image,
# the layout or any test.
#
# Glutsumpf decision (lava pools): the pools are WALKABLE decoration, not a
# damage area. Reasons: (1) every loss in MAWLINGS is announced by a telegraph
# first – a permanent damage floor has no wind-up and would punish players who
# simply did not see it at phone size; (2) the arena must stay open, and a floor
# you may not cross is an obstacle in disguise; (3) the Verdant pools are
# walkable too, so the rule "flat ground decoration never hurts" stays true in
# every biome. Danger in the Glutsumpf comes from telegraphed events instead:
# `eruptions` below is the hook for stage 08 (a pool swells, shows the apex
# "spore ring" style warning, then erupts once).
#
# Readability: the Glutmaw swarm is ember red and the hunter telegraph is
# red/orange, so the Glutsumpf avoids large saturated orange areas. Ground is
# smoky violet-brown peat (dark, but lighter than the black creature outline),
# the glow channels are a narrow amber core on dark crust, and the pools are
# pale yellow-orange with a dark crust rim – brighter and yellower than any
# strain. Flowers are recoloured to cold teal so no deco competes with the swarm.

const DEFAULT := "verdant_maw"
const ORDER := ["verdant_maw", "glutsumpf"]

const DATA := {
	"verdant_maw": {
		"name": "Verdant Maw",
		"title": "VERDANT MAW",
		"description": "Offene, grüne Jagdgründe.",
		"apex": "Moosschlund",
		"ground": Color("80a04c"),
		"path": Color("d4b377"),
		"path_edge": Color("aeaa62"),
		# Glow of trail and edge (0 = plain, matte ground like the classic map).
		"path_emission": Color(0, 0, 0),
		"path_edge_emission": Color(0, 0, 0),
		"moss": [Color("88a852"), Color("718f40"), Color("7a9844")],
		"sand": Color("c8ab6e"),
		"earth": Color("b39862"),
		"plinth": Color("62883a"),
		"pool": Color("3fc0c4"),
		"pool_roughness": 0.35,
		"pool_emission": Color(0, 0, 0),
		"shore": Color("dcd296"),
		"flower_dark": Color("6a5a8e"),
		"flower_light": Color("c3b3de"),
		"prop_rim": Color("f2f0c8"),
		# body_tint of the prop shader per prop group (alpha = amount, 0 = original colours).
		"rock_tint": Color(1, 1, 1, 0),
		"leaf_tint": Color(1, 1, 1, 0),
		"wood_tint": Color(1, 1, 1, 0),
		"reed_tint": Color(1, 1, 1, 0),
		# Decoration counts per chunk (classic layout).
		"moss_patches": 6,
		"sand_patches": 3,
		"pebbles": 5,
		"leaf_clumps_min": 3,
		"pond_one_in": 5,
		"flower_one_in": 3,
		"eruptions": false,
		"light": {"color": Color(1, 1, 1), "energy": 1.15},
		"enemy_tints": {},
	},
	"glutsumpf": {
		"name": "Glutsumpf",
		"title": "GLUTSUMPF",
		"description": "Glühender Sumpf voller Gase.",
		"apex": "Aschenkröte",
		"ground": Color("5e4f55"),
		"path": Color("3c2c2c"),
		"path_edge": Color("b8622c"),
		"path_emission": Color(0, 0, 0),
		"path_edge_emission": Color("5a2408"),
		"moss": [Color("75686c"), Color("4e4146"), Color("806a5e")],
		"sand": Color("7a6658"),
		"earth": Color("463a3c"),
		"plinth": Color("3e3438"),
		"pool": Color("ffc24a"),
		"pool_roughness": 0.6,
		"pool_emission": Color("ff9a2a"),
		"shore": Color("2a2124"),
		"flower_dark": Color("1f6a70"),
		"flower_light": Color("9fe6e0"),
		"prop_rim": Color("ffc07a"),
		"rock_tint": Color(0.42, 0.38, 0.42, 0.85),
		"leaf_tint": Color(0.46, 0.44, 0.3, 0.8),
		"wood_tint": Color(0.3, 0.24, 0.24, 0.85),
		"reed_tint": Color(0.5, 0.42, 0.34, 0.75),
		"moss_patches": 5,
		"sand_patches": 4,
		"pebbles": 6,
		"leaf_clumps_min": 2,
		"pond_one_in": 3,
		"flower_one_in": 4,
		"eruptions": true,
		"light": {"color": Color(1.0, 0.86, 0.74), "energy": 1.2},
		# body_tint (alpha = amount) for creature_anim.gdshader, applied in stage 08.
		"enemy_tints": {
			"hunter": Color(0.36, 0.3, 0.34, 0.55),
			"skitter": Color(0.82, 0.62, 0.3, 0.45),
			"leaper": Color(0.3, 0.26, 0.3, 0.5),
			"bog_king": Color(0.34, 0.26, 0.26, 0.6),
			"prey": Color(0.55, 0.9, 0.88, 0.35),
		},
	},
}


static func has(id: String) -> bool:
	return DATA.has(id)


# Full data set; unknown ids fall back to the default biome.
static func get_data(id: String) -> Dictionary:
	return DATA.get(id, DATA[DEFAULT])


static func display_name(id: String) -> String:
	return String(get_data(id).name)


static func enemy_tint(id: String, kind: String) -> Color:
	return get_data(id).enemy_tints.get(kind, Color(1, 1, 1, 0))


# Biome after `id` in the migration order (wraps around, the run stays endless).
static func next_biome(id: String) -> String:
	var index := ORDER.find(id)
	return ORDER[(index + 1) % ORDER.size()]
