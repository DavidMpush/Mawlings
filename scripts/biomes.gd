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
#
# Glutsumpf look (stage 09 prep, `ember` block below; Verdant has none, so its
# chunks are built exactly as before): a shader ground (peat tones, ash flecks,
# thin glowing cracks), trails become glow channels (dark crust with a narrow,
# broken ember core, one mesh with a vertex-colour profile), pools are pulsing
# lava, stones become basalt column clusters, root arches burn out to charcoal,
# fallen logs become three extinct stumps on the same collision knots, the
# meadow grows cold-glowing "Glutpilze" (flower mesh, cyan like gas flames, so
# nothing reads as an ember-red Mawling). Eruptions (scripts/eruptions.gd) rise
# from lava pools and glow channels with their own ring telegraph.

const DEFAULT := "verdant_maw"
# Biome circle of a run: every Migrationsschlund leads to the next entry and the
# last one back to the first (Glutsumpf -> Verdant Maw), so a run can loop forever;
# each visit brings its apex ("apex" in DATA) once, stronger on every loop (HuntWorld).
const ORDER := ["verdant_maw", "duerrschlund", "glutsumpf"]

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
		# Map edge (stage 18, arena_border.gd): forest floor under the wall, fog it
		# fades into (= the project clear colour), swamp water of the edge.
		"border": {"floor": Color("4a6a34"), "fog": Color(0.16, 0.23, 0.18), "water": Color("2b8a86"), "shore": Color("6f8a44")},
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
		"moss": [Color("6a5e62"), Color("4a3f45"), Color("76665f")],
		"sand": Color("5a4c4c"),
		"earth": Color("3e3337"),
		"plinth": Color("3e3438"),
		"pool": Color("ffc24a"),
		"pool_roughness": 0.6,
		"pool_emission": Color("ff9a2a"),
		"shore": Color("2a2124"),
		"flower_dark": Color("1f6a70"),
		"flower_light": Color("9fe6e0"),
		"prop_rim": Color("ffc07a"),
		"rock_tint": Color(0.42, 0.38, 0.42, 0.85),
		"leaf_tint": Color(0.34, 0.28, 0.24, 0.9),
		"wood_tint": Color(0.3, 0.24, 0.24, 0.85),
		"reed_tint": Color(0.5, 0.42, 0.34, 0.75),
		"moss_patches": 5,
		"sand_patches": 4,
		"pebbles": 6,
		"leaf_clumps_min": 2,
		"pond_one_in": 3,
		"flower_one_in": 4,
		"eruptions": true,
		"border": {"floor": Color("3a2e33"), "fog": Color("1d1417"), "water": Color("ffb040"), "shore": Color("2a2124"), "crust": Color("2e2327"), "crust_glow": Color("1a0802")},
		"light": {"color": Color(1.0, 0.86, 0.74), "energy": 1.2},
		# Shader look of arena.gd (only biomes with this block use it).
		"ember": {
			"ground_dark": Color("463a42"),
			"ground_light": Color("6c5a5c"),
			"ash": Color("8a8184"),
			"vein": Color("ff8a2c"),
			"vein_amount": 0.55,
			"crust": Color("33272a"),
			"crust_rim": Color("54433f"),
			"core": Color("ffb03c"),
			"core_hot": Color("fff0a0"),
			"lava_core": Color("ffe27a"),
			"lava_mid": Color("ff9a2e"),
			"lava_crust": Color("5a2014"),
			"basalt_tint": Color(0.24, 0.2, 0.22, 0.95),
			"char_rim": Color("ff9a4a"),
			"mushroom_dark": Color("0f4a58"),
			"mushroom_light": Color("8ff4ff"),
			"mushroom_rim": Color("b8fbff"),
		},
		# body_tint (alpha = amount) for creature_anim.gdshader, applied in stage 08.
		"enemy_tints": {
			"hunter": Color(0.36, 0.3, 0.34, 0.55),
			"skitter": Color(0.82, 0.62, 0.3, 0.45),
			"leaper": Color(0.3, 0.26, 0.3, 0.5),
			"bog_king": Color(0.34, 0.26, 0.26, 0.6),
			"prey": Color(0.55, 0.9, 0.88, 0.35),
		},
	},
	# Stage 19 (phase 1, data only): the desert "Dürrschlund" between Verdant Maw
	# and Glutsumpf. Not in ORDER yet – the map integration (arena, border, spawns,
	# migration order Verdant -> Dürrschlund -> Glutsumpf) is stage 19 phase 2.
	# Readability: the swarm is ember red, so the sand is pale ochre/beige with
	# cool (blue-grey) shadows instead of orange; paths are packed, greyer sand;
	# oases are turquoise with a green rim; cactus flowers pink (never orange).
	"duerrschlund": {
		"name": "Dürrschlund",
		"title": "DÜRRSCHLUND",
		"description": "Dünen, Knochenfelder und der Sandwurm.",
		"apex": "Sandwurm",
		# HuntWorld kind of the apex (scripts/apex_sandworm.gd).
		"apex_kind": "apex_sandworm",
		"ground": Color("dcc89e"),
		"path": Color("bcac8a"),
		"path_edge": Color("9f8f6e"),
		"path_emission": Color(0, 0, 0),
		"path_edge_emission": Color(0, 0, 0),
		"moss": [Color("d4bf92"), Color("c9b489"), Color("e3d1a8")],
		"sand": Color("e9d9b2"),
		"earth": Color("b5a07a"),
		"plinth": Color("a8936e"),
		"pool": Color("35c4bd"),
		"pool_roughness": 0.3,
		"pool_emission": Color(0, 0, 0),
		"shore": Color("86b25e"),
		"flower_dark": Color("b04c78"),
		"flower_light": Color("f3a8c6"),
		"prop_rim": Color("fff2d2"),
		"rock_tint": Color(0.9, 0.72, 0.52, 0.5),
		"leaf_tint": Color(0.62, 0.66, 0.42, 0.45),
		"wood_tint": Color(0.86, 0.8, 0.68, 0.65),
		"reed_tint": Color(0.84, 0.76, 0.54, 0.6),
		# Desert props (phase 2): walls a muted rust-brown so they stay darker than
		# the pale sand (rule "klare, dunkle Wände"), bones only slightly warmed.
		"wall_tint": Color(0.56, 0.42, 0.34, 0.68),
		"bone_tint": Color(1.0, 0.95, 0.85, 0.15),
		# Stage 19: no light ground patches (from above they read as pebbles);
		# the dune shader carries the variation.
		"moss_patches": 0,
		"sand_patches": 0,
		"pebbles": 4,
		"leaf_clumps_min": 1,
		"pond_one_in": 7,
		"flower_one_in": 5,
		"eruptions": false,
		# Phase-2 hazards (flags only, nothing reads them yet): quicksand patches
		# slow the swarm (walkable, announced by their look), sandstorms are short,
		# telegraphed waves that cut the view.
		"quicksand": true,
		"sandstorm": true,
		# Map edge (arena_border.gd): high dune ridges and sandstone, fading into a
		# dusty haze; "water" is the dune sea / quicksand ring of the edge.
		"border": {"floor": Color("bda77e"), "fog": Color(0.6, 0.55, 0.47), "water": Color("cfb07a"), "shore": Color("a78f66")},
		"light": {"color": Color(1.0, 0.96, 0.88), "energy": 1.15},
		# Shader look for the phase-2 ground (like the Glutsumpf "ember" block):
		# dune ripples, cool shadow side, bone-white flecks, turquoise oasis water.
		"desert": {
			"dune_light": Color("e6d4aa"),
			"dune_shadow": Color("b3a590"),
			"shadow_cool": Color("8e93a6"),
			"ripple": Color("cdb68a"),
			"ripple_amount": 0.4,
			"bone_fleck": Color("f4ecd8"),
			"quicksand": Color("b89a64"),
			"quicksand_swirl": Color("8f7446"),
			"oasis_core": Color("2fb8b8"),
			"oasis_shallow": Color("7fe0d0"),
			"oasis_rim": Color("6aa04a"),
		},
		# Props (assets/gameplay/props/*_game.glb) by role for the map generator.
		# wall: impassable, forms paths and choke points (cliff blocks, rib rows);
		# deco: small, walkable around; landmark: one per region at most;
		# portal: the desert Migrationsschlund (the worm's breakthrough maw).
		"props": {
			"wall": ["SandstoneCliff", "RibBones"],
			"deco": ["Cactus"],
			"landmark": ["GiantSkull", "RockArch"],
			"portal": "SandPortal",
			# Still missing (stages/ASSET_REQUESTS.md): oasis palm for the clearings.
			"missing": ["OasisPalm"],
		},
		"enemy_tints": {
			"hunter": Color(0.86, 0.72, 0.52, 0.4),
			"skitter": Color(0.92, 0.78, 0.5, 0.35),
			"leaper": Color(0.72, 0.58, 0.42, 0.4),
			"bog_king": Color(0.78, 0.64, 0.46, 0.45),
			"prey": Color(0.55, 0.9, 0.88, 0.3),
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
