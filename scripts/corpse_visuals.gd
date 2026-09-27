extends Node3D

# Etappe 09 (Kadaver-Designs): every persistent corpse gets a look of its own,
# by animal and rank (normal enemy, mini-boss, main boss), like the loot piles in
# LoL Swarm. Display only: biomass, ids and harvesting stay in RunModel/HuntWorld.
#
#   corpse_visuals.add(id, kind, position, biomass)
#   corpse_visuals.set_fill(id, remaining / initial)   # 0..1, shrinks / dims
#   corpse_visuals.remove(id)                          # eaten completely
#   corpse_visuals.clear()                             # new run
#
# Biomass crystals (Hunyuan drops, assets/gameplay/props/*Drop_game.glb) hover,
# turn and pulse above the remains: small shards (1-3) on normal enemies, a
# medium crystal on mini-bosses, a big crystal on bosses and brood nests. They
# shrink with the fill; the motion runs in the vertex shader (no per-frame CPU).
#
# Performance: ONE MultiMesh per design (+ one for all amber pools, + one for
# all glow halos, + one per crystal size) with shared meshes/materials. Per
# corpse only instance data (transform + INSTANCE_CUSTOM: fill, glow, phase,
# pulse speed) is written; no node per corpse. 60 mixed corpses = at most 16
# draw calls.

const NIBBLER_SCENE = preload("res://assets/gameplay/characters/Nibbler_game.glb")
const REAPER_SCENE = preload("res://assets/gameplay/characters/MireReaper_game.glb")
# Asset pack V3: the real animal models, lying dead (baked into the design mesh).
const HUNTER_SCENE = preload("res://assets/gameplay/characters/HunterBeetle_game.glb")
const ELITE_CROWN_SCENE = preload("res://assets/gameplay/props/EliteCrown_game.glb")
const SKITTER_SCENE = preload("res://assets/gameplay/characters/Skitter_game.glb")
const MOORBRUT_SCENE = preload("res://assets/gameplay/characters/Moorbrut_game.glb")
const MOOSSCHLUND_SCENE = preload("res://assets/gameplay/characters/Moosschlund_game.glb")
const BOG_KING_SCENE = preload("res://assets/gameplay/characters/BogKingNew_game.glb")
# Triangle budget per remains model (the import LOD closest below it is baked;
# 0 = full mesh). Moorbrut corpses can number in the hundreds, so they are tiny.
const MODEL_TRIS := {"hunter": 1500, "elite": 1500, "skitter": 1300, "horde": 300, "boss": 4000, "apex": 4000}
const DROP_SCENES := {
	"drop_small": preload("res://assets/gameplay/props/SmallDrop_game.glb"),
	"drop_medium": preload("res://assets/gameplay/props/MediumDrop_game.glb"),
	"drop_big": preload("res://assets/gameplay/props/BigDrop_game.glb"),
}
# Model height (m) of each crystal mesh at instance scale 1 and its glow colour.
const DROP_HEIGHT := {"drop_small": 0.9, "drop_medium": 1.0, "drop_big": 1.2}
const DROP_GLOW := {"drop_small": Color("5ff2dc"), "drop_medium": Color("ffa53a"), "drop_big": Color("d9a8ff")}
# Up to 4 shards per corpse: layer keys are id * DROP_SLOTS + shard.
const DROP_SLOTS := 4

const BATCH_STEP := 32
const POOL_LAYER := "pool"
const HALO_LAYER := "halo"

# kind (as stored by HuntWorld) -> design. Unknown kinds fall back to FALLBACK_KIND.
const FALLBACK_KIND := "prey"
const KIND_DESIGN := {
	"prey": "prey", "hunter": "hunter", "skitter": "skitter", "horde": "horde",
	"elite": "elite", "leaper": "leaper",
	"boss": "boss", "apex": "apex", "apex_toad": "apex_toad",
	"mawling": "mawling", "nest": "nest",
}

# rank: normal / mini / boss / special. pool/halo: radius in m at full fill
# (0 = none). ref: biomass that gives scale 1 (pools grow a little with biomass).
# remains_min: remains scale at fill 0 (bones of bosses stay, flesh shrinks).
# pulse: angular speed of the glow (bosses slow and big, small ones subtle).
# drop: crystal layer ("" = none), drop_size: height in m at full fill,
# drop_count: max shards (normal enemies get 1-3 by biomass), drop_at: offset
# (corpse-local, before yaw) of the first crystal, drop_lift: hover height.
const DESIGNS := {
	"prey": {"rank": "normal", "pool": 0.8, "glow": 0.35, "halo": 0.0, "pulse": 2.6, "ref": 6.0, "remains_min": 0.55, "drop": "drop_small", "drop_size": 0.72, "drop_count": 3, "drop_at": Vector3(0.0, 0.0, 0.0), "drop_lift": 0.42},
	"hunter": {"rank": "normal", "pool": 0.9, "glow": 0.35, "halo": 0.0, "pulse": 2.6, "ref": 8.0, "remains_min": 0.55, "drop": "drop_small", "drop_size": 0.82, "drop_count": 3, "drop_at": Vector3(0.0, 0.0, -0.2), "drop_lift": 0.95},
	"skitter": {"rank": "normal", "pool": 0.85, "glow": 0.35, "halo": 0.0, "pulse": 2.6, "ref": 9.0, "remains_min": 0.55, "drop": "drop_small", "drop_size": 0.78, "drop_count": 3, "drop_at": Vector3(0.0, 0.0, 0.0), "drop_lift": 0.75},
	"horde": {"rank": "normal", "pool": 0.42, "glow": 0.3, "halo": 0.0, "pulse": 3.0, "ref": 1.5, "remains_min": 0.5, "drop": "drop_small", "drop_size": 0.48, "drop_count": 1, "drop_at": Vector3(0.0, 0.0, 0.0), "drop_lift": 0.2},
	"elite": {"rank": "mini", "pool": 1.45, "glow": 0.85, "halo": 4.4, "halo_color": Color(1.0, 0.72, 0.28), "halo_strength": 0.8, "pulse": 2.1, "ref": 26.0, "remains_min": 0.75, "drop": "drop_medium", "drop_size": 1.05, "drop_count": 1, "drop_at": Vector3(0.0, 0.0, -0.3), "drop_lift": 1.35},
	"leaper": {"rank": "mini", "pool": 1.35, "glow": 0.8, "halo": 4.2, "halo_color": Color(0.95, 0.8, 0.35), "halo_strength": 0.75, "pulse": 2.1, "ref": 10.0, "remains_min": 0.75, "drop": "drop_medium", "drop_size": 0.95, "drop_count": 1, "drop_at": Vector3(0.0, 0.0, 0.0), "drop_lift": 0.9},
	"boss": {"rank": "boss", "pool": 2.7, "glow": 1.0, "halo": 10.0, "halo_color": Color(1.0, 0.66, 0.24), "halo_strength": 0.9, "pulse": 1.3, "ref": 60.0, "remains_min": 0.93, "drop": "drop_big", "drop_size": 1.9, "drop_count": 1, "drop_at": Vector3(2.35, 0.0, 0.4), "drop_lift": 0.35},
	"apex": {"rank": "boss", "pool": 3.1, "glow": 1.0, "halo": 11.0, "halo_color": Color(0.95, 0.8, 0.32), "halo_strength": 0.9, "pulse": 1.1, "ref": 60.0, "remains_min": 0.93, "drop": "drop_big", "drop_size": 2.1, "drop_count": 1, "drop_at": Vector3(-3.3, 0.0, 0.9), "drop_lift": 0.35},
	# Aschenkröte (second apex, Glutsumpf): as big as the Moosschlund, orange halo.
	"apex_toad": {"rank": "boss", "pool": 3.3, "glow": 1.0, "halo": 11.5, "halo_color": Color(1.0, 0.56, 0.2), "halo_strength": 0.95, "pulse": 1.0, "ref": 60.0, "remains_min": 0.93, "drop": "drop_big", "drop_size": 2.1, "drop_count": 1, "drop_at": Vector3(2.6, 0.0, -0.8), "drop_lift": 0.35},
	"mawling": {"rank": "special", "pool": 0.0, "glow": 1.0, "halo": 1.6, "halo_color": Color(1.0, 0.5, 0.18), "halo_strength": 0.9, "pulse": 4.0, "ref": 1.0, "remains_min": 0.6, "drop": ""},
	"nest": {"rank": "special", "pool": 1.1, "glow": 0.6, "halo": 0.0, "pulse": 2.0, "ref": 18.0, "remains_min": 0.7, "drop": "drop_big", "drop_size": 0.95, "drop_count": 1, "drop_at": Vector3(0.0, 0.0, 0.0), "drop_lift": 0.3},
}

# Palette (living colours, the shader darkens and desaturates the remains).
const BONE := Color("efe2c0")
const ASH_BONE := Color("c9c0b8")
const AMBER_EDGE := Color("c0650f")
const AMBER_MID := Color("f7a62a")
const AMBER_CORE := Color("ffe189")

# id -> {kind, design, position, yaw, phase, fill, scale, decay}
var corpses := {}
# Etappe 16: remains are empty decoration (the biomass lies in scripts/loot.gd
# crystals): no crystal shards, only a small dark stain instead of the amber pool,
# no halo; set_decay() lets them sink before HuntWorld removes them.
var empty := false
# layer name -> Layer
var layers := {}

# Shared by every CorpseVisuals node (one set per game run is enough).
static var _meshes := {}
static var _materials := {}


## Visual-only record for one corpse (id comes from RunModel.add_corpse).
func add(id: int, kind: String, location: Vector3, biomass: float) -> void:
	if corpses.has(id):
		remove(id)
	var design_name: String = KIND_DESIGN.get(kind, KIND_DESIGN[FALLBACK_KIND])
	var design: Dictionary = DESIGNS[design_name]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id * 7919 + 17)
	var size := clampf(sqrt(maxf(biomass, 0.01) / float(design.ref)), 0.85, 1.3)
	corpses[id] = {
		"kind": kind, "design": design_name, "position": location,
		"yaw": rng.randf() * TAU, "pool_yaw": rng.randf() * TAU, "phase": rng.randf(),
		"fill": 1.0, "scale": size, "drops": [] if empty else _drop_layout(design, size, rng),
		"decay": 0.0,
	}
	_apply(id)


## 0..1 of the biomass still there. The amber pool and glow shrink, normal
## remains shrink, boss bones stay; below ~10 % only scraps are left.
func set_fill(id: int, fraction: float) -> void:
	if not corpses.has(id):
		return
	var corpse: Dictionary = corpses[id]
	var fill := clampf(fraction, 0.0, 1.0)
	if is_equal_approx(fill, corpse.fill):
		return
	corpse.fill = fill
	_apply(id)


## Etappe 16: 0..1 of the sinking at the end of a remains' life (0 = lying,
## 1 = gone into the ground: lower, smaller, darker).
func set_decay(id: int, amount: float) -> void:
	if not corpses.has(id):
		return
	var corpse: Dictionary = corpses[id]
	var value := clampf(amount, 0.0, 1.0)
	if absf(value - float(corpse.decay)) < 0.02 and value < 1.0:
		return
	corpse.decay = value
	_apply(id)


func remove(id: int) -> void:
	if not corpses.has(id):
		return
	for layer_name: String in layers:
		var layer: Layer = layers[layer_name]
		if DROP_SCENES.has(layer_name):
			for shard in DROP_SLOTS:
				layer.erase(id * DROP_SLOTS + shard)
		else:
			layer.erase(id)
	corpses.erase(id)


func clear() -> void:
	for layer: Layer in layers.values():
		layer.clear()
	corpses.clear()


func count() -> int:
	return corpses.size()


func has(id: int) -> bool:
	return corpses.has(id)


func design_of(id: int) -> String:
	return corpses[id].design if corpses.has(id) else ""


static func rank_of(kind: String) -> String:
	return DESIGNS[KIND_DESIGN.get(kind, KIND_DESIGN[FALLBACK_KIND])].rank


## Crystal layer of a kind ("drop_small", "drop_medium", "drop_big" or "").
static func drop_of(kind: String) -> String:
	return DESIGNS[KIND_DESIGN.get(kind, KIND_DESIGN[FALLBACK_KIND])].drop


## Crystal shards of one corpse (0 = none).
func drops_of(id: int) -> int:
	return (corpses[id].drops as Array).size() if corpses.has(id) else 0


## Visible instances in one layer (design name, "pool", "halo" or "drop_*").
func instances(layer_name: String) -> int:
	return layers[layer_name].ids.size() if layers.has(layer_name) else 0


## MultiMeshes currently drawing something (= draw calls of all corpses).
func active_batches() -> int:
	var active := 0
	for layer: Layer in layers.values():
		if not layer.ids.is_empty():
			active += 1
	return active


# ---------------------------------------------------------------- instances

func _apply(id: int) -> void:
	var corpse: Dictionary = corpses[id]
	var design: Dictionary = DESIGNS[corpse.design]
	var fill: float = corpse.fill
	var origin: Vector3 = corpse.position
	var decay: float = corpse.get("decay", 0.0)
	if decay > 0.0:
		origin.y -= decay * decay * 0.9 * float(corpse.scale)
	# Empty remains read as dead: darker and duller than any living animal.
	var custom := Color((0.15 if empty else fill) * (1.0 - 0.6 * decay), float(design.glow) * (0.35 if empty else 1.0), float(corpse.phase), float(design.pulse))
	# Remains: the animal's own leftovers.
	var remains_scale := lerpf(float(design.remains_min), 1.0, fill) * (1.0 - 0.35 * decay)
	var basis := Basis(Vector3.UP, corpse.yaw).scaled(Vector3.ONE * remains_scale)
	_layer(corpse.design).put(id, Transform3D(basis, origin), custom)
	# Amber biomass pool (flat, slightly domed); flattens and dims while eaten.
	# Empty remains: a small spent stain only.
	if float(design.pool) > 0.0:
		var pool_fill := 0.3 * (1.0 - decay) if empty else fill
		var radius := float(design.pool) * float(corpse.scale) * lerpf(0.28, 1.0, pool_fill)
		var height := pow(radius, 0.72) * lerpf(0.45, 1.0, pool_fill)
		var pool_basis := Basis(Vector3.UP, corpse.pool_yaw).scaled(Vector3(radius, height, radius))
		var pool_custom := custom
		if empty:
			pool_custom.r = 0.0
		_layer(POOL_LAYER).put(id, Transform3D(pool_basis, origin), pool_custom)
	# Soft light on the ground under mini-bosses, bosses and fallen Mawlings.
	if float(design.halo) > 0.0 and not empty:
		var halo_size := float(design.halo) * float(corpse.scale) * lerpf(0.45, 1.0, fill)
		var strength := float(design.halo_strength) * lerpf(0.25, 1.0, fill)
		var halo_custom := Color(fill, strength, float(corpse.phase), float(design.pulse))
		var halo_basis := Basis.from_scale(Vector3(halo_size, 1.0, halo_size))
		_layer(HALO_LAYER).put(id, Transform3D(halo_basis, origin + Vector3(0.0, 0.035, 0.0)), halo_custom, design.halo_color)
	# Biomass crystals: hover above the remains, shrink with the fill; extra
	# shards of normal enemies shrink faster, so the first one is eaten last.
	var drops: Array = corpse.drops
	if drops.is_empty():
		return
	var drop_layer := _layer(design.drop)
	var turn := Basis(Vector3.UP, corpse.yaw)
	var drop_custom := Color(fill, float(design.glow), float(corpse.phase), float(design.pulse))
	for shard in drops.size():
		var spec: Array = drops[shard]
		var shrink := lerpf(0.3, 1.0, pow(fill, 1.0 + 0.6 * float(shard)))
		var height: float = float(spec[2]) * shrink
		var drop_basis := Basis(Vector3.UP, float(spec[1])).scaled(Vector3.ONE * height / float(DROP_HEIGHT[design.drop]))
		var place: Vector3 = origin + turn * (spec[0] as Vector3)
		place.y += float(design.drop_lift) * lerpf(0.75, 1.0, fill)
		drop_custom.b = fmod(float(corpse.phase) + 0.37 * float(shard), 1.0)
		drop_layer.put(id * DROP_SLOTS + shard, Transform3D(drop_basis, place), drop_custom)


# Shard positions / turn / height (corpse-local), fixed per corpse.
static func _drop_layout(design: Dictionary, size: float, rng: RandomNumberGenerator) -> Array:
	if String(design.get("drop", "")) == "":
		return []
	var count := 1
	if int(design.drop_count) > 1:
		# 1-3 shards by biomass (size 0.85..1.3; the reference biomass gives 2).
		count = clampi(1 + int(size >= 0.97) + int(size >= 1.18), 1, int(design.drop_count))
	var result := []
	var first: Vector3 = design.drop_at
	var base_height := float(design.drop_size) * lerpf(0.9, 1.12, inverse_lerp(0.85, 1.3, size))
	for shard in count:
		var at := first
		var height := base_height
		if shard > 0:
			var angle := rng.randf() * TAU
			at += Vector3(cos(angle), 0.0, sin(angle)) * (0.32 + 0.1 * rng.randf())
			height *= 0.62 - 0.08 * float(shard - 1)
		result.append([at, rng.randf() * TAU, height])
	return result


func _layer(layer_name: String) -> Layer:
	if layers.has(layer_name):
		return layers[layer_name]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	# Compatibility multiplies COLOR by the instance colour (black without it).
	multimesh.use_colors = true
	multimesh.mesh = _mesh(layer_name)
	multimesh.instance_count = BATCH_STEP
	multimesh.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.name = "Corpses " + layer_name
	node.multimesh = multimesh
	node.material_override = _material(layer_name)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	add_child(node)
	node.top_level = true
	node.transform = Transform3D.IDENTITY
	var layer := Layer.new(node)
	layers[layer_name] = layer
	return layer


# One MultiMesh with swap-remove slots: id -> instance index.
class Layer:
	var node: MultiMeshInstance3D
	var ids: Array[int] = []
	var slot := {}
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var colors: Array[Color] = []

	func _init(batch: MultiMeshInstance3D) -> void:
		node = batch

	func put(id: int, xform: Transform3D, custom: Color, color := Color.WHITE) -> void:
		var multimesh := node.multimesh
		if slot.has(id):
			var index: int = slot[id]
			xforms[index] = xform
			customs[index] = custom
			colors[index] = color
			_write(index)
			return
		var index := ids.size()
		ids.append(id)
		xforms.append(xform)
		customs.append(custom)
		colors.append(color)
		slot[id] = index
		if index >= multimesh.instance_count:
			# Changing instance_count clears the buffer: rewrite every instance.
			multimesh.instance_count = (ids.size() / BATCH_STEP + 1) * BATCH_STEP
			for rewrite in ids.size():
				_write(rewrite)
		else:
			_write(index)
		multimesh.visible_instance_count = ids.size()
		node.visible = true

	func erase(id: int) -> void:
		if not slot.has(id):
			return
		var index: int = slot[id]
		var last := ids.size() - 1
		if index != last:
			var moved: int = ids[last]
			ids[index] = moved
			xforms[index] = xforms[last]
			customs[index] = customs[last]
			colors[index] = colors[last]
			slot[moved] = index
			_write(index)
		ids.remove_at(last)
		xforms.remove_at(last)
		customs.remove_at(last)
		colors.remove_at(last)
		slot.erase(id)
		node.multimesh.visible_instance_count = ids.size()
		node.visible = not ids.is_empty()

	func clear() -> void:
		ids.clear()
		slot.clear()
		xforms.clear()
		customs.clear()
		colors.clear()
		node.multimesh.visible_instance_count = 0
		node.visible = false

	func _write(index: int) -> void:
		var multimesh := node.multimesh
		multimesh.set_instance_transform(index, xforms[index])
		multimesh.set_instance_custom_data(index, customs[index])
		if multimesh.use_colors:
			multimesh.set_instance_color(index, colors[index])


# ---------------------------------------------------------------- materials

const REMAINS_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
#define OUTLINE_DEFAULT 0.55
#include "res://shaders/creature_look.gdshaderinc"
// Corpse remains: the creature look, darker and desaturated (uniforms of the
// include); vertex alpha 0 marks glowing bits (amber, gems, sparks) that pulse.
uniform float eaten_dark = 0.4;
varying vec4 corpse;
void vertex() {
	corpse = INSTANCE_CUSTOM;
}
void fragment() {
	float pulse = 0.5 + 0.5 * sin(TIME * corpse.w + corpse.z * 6.2832);
	vec3 body = creature_look(COLOR.rgb, NORMAL, VIEW, FRONT_FACING);
	body *= mix(1.0 - eaten_dark, 1.0, corpse.x);
	vec3 lit = COLOR.rgb * (1.0 + corpse.y * (0.2 + 0.6 * pulse));
	ALBEDO = mix(body, lit, 1.0 - COLOR.a);
}
"""

const POOL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
// Amber biomass: vertex colour = amber ramp, vertex alpha = heat (core glows).
varying vec4 corpse;
void vertex() {
	corpse = INSTANCE_CUSTOM;
}
void fragment() {
	float pulse = 0.5 + 0.5 * sin(TIME * corpse.w + corpse.z * 6.2832);
	float facing = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
	vec3 col = COLOR.rgb * (0.72 + 0.28 * facing);
	col *= 0.9 + corpse.y * (0.12 + 0.4 * pulse) * COLOR.a;
	col += vec3(1.0, 0.95, 0.75) * pow(facing, 10.0) * 0.18 * COLOR.a;
	col = mix(col * vec3(0.6, 0.48, 0.4), col, corpse.x);
	ALBEDO = col;
}
"""

const HALO_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// Soft ground light (instance colour) with a slow pulse.
varying vec4 corpse;
varying vec4 tint;
void vertex() {
	corpse = INSTANCE_CUSTOM;
	tint = COLOR;
}
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float fall = pow(clamp(1.0 - d, 0.0, 1.0), 1.8);
	float pulse = 0.72 + 0.28 * sin(TIME * corpse.w + corpse.z * 6.2832);
	ALBEDO = tint.rgb;
	ALPHA = clamp(fall * corpse.y * pulse, 0.0, 1.0);
}
"""


const DROP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
// Biomass crystal: turns and bobs around its own axis (model space, before the
// instance transform), glows at the rim and pulses; dims when nearly eaten.
uniform vec3 glow_color : source_color = vec3(1.0, 0.8, 0.3);
uniform float bob = 0.06;
uniform float spin = 0.6;
uniform float tint_mix = 0.2;
uniform float brightness = 1.0;
uniform float saturation = 1.2;
varying vec4 corpse;
void vertex() {
	corpse = INSTANCE_CUSTOM;
	float phase = corpse.z * 6.2832;
	float a = TIME * spin + phase;
	mat2 turn = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	VERTEX.xz = turn * VERTEX.xz;
	NORMAL.xz = turn * NORMAL.xz;
	VERTEX.y += bob * (0.5 + 0.5 * sin(TIME * 1.6 + phase));
}
void fragment() {
	float pulse = 0.5 + 0.5 * sin(TIME * corpse.w + corpse.z * 6.2832);
	float facing = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
	vec3 base = mix(COLOR.rgb, glow_color * 0.8, tint_mix);
	// Saturate a little so the crystal reads as gem, not as rock.
	float grey = dot(base, vec3(0.3, 0.55, 0.15));
	base = mix(vec3(grey), base, saturation);
	vec3 col = base * (brightness + 0.4 * facing);
	col += glow_color * pow(1.0 - facing, 2.0) * (0.45 + 0.4 * pulse) * (0.4 + 0.6 * corpse.y);
	col += glow_color * 0.1 * pulse * corpse.y;
	col *= mix(0.62, 1.0, corpse.x);
	ALBEDO = col;
}
"""


static func _material(layer_name: String) -> ShaderMaterial:
	var key := "pool" if layer_name == POOL_LAYER else ("halo" if layer_name == HALO_LAYER else "remains")
	if DROP_SCENES.has(layer_name):
		key = layer_name
	if _materials.has(key):
		return _materials[key]
	var shader := Shader.new()
	var material := ShaderMaterial.new()
	match key:
		"pool":
			shader.code = POOL_SHADER
		"halo":
			shader.code = HALO_SHADER
		"drop_small", "drop_medium", "drop_big":
			shader.code = DROP_SHADER
			material.set_shader_parameter("glow_color", DROP_GLOW[key])
			material.set_shader_parameter("bob", 0.07 if key == "drop_small" else 0.05)
			material.set_shader_parameter("spin", 0.9 if key == "drop_small" else 0.45)
			material.set_shader_parameter("tint_mix", 0.16 if key == "drop_big" else 0.12)
			material.set_shader_parameter("brightness", 1.35 if key == "drop_big" else 1.05)
			material.set_shader_parameter("saturation", 1.5 if key == "drop_big" else 1.15)
		_:
			shader.code = REMAINS_SHADER
			material.set_shader_parameter("brightness", 0.82)
			material.set_shader_parameter("saturation", 0.62)
			material.set_shader_parameter("shape_light", 0.45)
			material.set_shader_parameter("rim_color", Color("ffc45e"))
			material.set_shader_parameter("rim_strength", 0.38)
			material.set_shader_parameter("rim_power", 2.4)
			material.set_shader_parameter("outline_strength", 0.6)
			material.set_shader_parameter("outline_color", Color(0.07, 0.04, 0.03))
	material.shader = shader
	_materials[key] = material
	return material


# ---------------------------------------------------------------- meshes

static func _mesh(layer_name: String) -> Mesh:
	if _meshes.has(layer_name):
		return _meshes[layer_name]
	var mesh: Mesh
	if layer_name == HALO_LAYER:
		var quad := PlaneMesh.new()
		quad.size = Vector2.ONE
		mesh = quad
	else:
		var b := Builder.new()
		if DROP_SCENES.has(layer_name):
			# Upright crystal, centred on its axis, base at y = 0.
			b.glb(DROP_SCENES[layer_name], 1.0, Basis.IDENTITY, Vector3.ZERO, Color.WHITE, true, DROP_HEIGHT[layer_name])
		match layer_name:
			POOL_LAYER: _build_pool(b)
			"prey": _build_prey(b)
			"hunter": _build_hunter(b)
			"elite": _build_elite(b)
			"skitter": _build_skitter(b)
			"horde": _build_horde(b)
			"leaper": _build_leaper(b)
			"boss": _build_boss(b)
			"apex": _build_apex(b)
			"apex_toad": _build_apex_toad(b)
			"mawling": _build_mawling(b)
			"nest": _build_nest(b)
		mesh = b.commit()
	_meshes[layer_name] = mesh
	return mesh


# Amber pool of radius 1 (instance scale = design radius): an irregular flat
# puddle, a domed core and two droplets. Alpha = heat for the pool shader.
static func _build_pool(b: Builder) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var sides := 32
	var rim := PackedFloat32Array()
	for index in sides:
		rim.append(0.86 + rng.randf() * 0.1 + 0.07 * sin(float(index) * 0.9) + 0.04 * sin(float(index) * 2.3))
	var center := b.vertex(Vector3(0.0, 0.07, 0.0), Vector3.UP, Color(AMBER_MID, 0.6))
	var ring_in := []
	var ring_out := []
	for index in sides:
		var angle := TAU * float(index) / float(sides)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		ring_in.append(b.vertex(dir * rim[index] * 0.62 + Vector3(0.0, 0.055, 0.0), Vector3.UP, Color(AMBER_MID.lerp(AMBER_EDGE, 0.2), 0.45)))
		ring_out.append(b.vertex(dir * rim[index] + Vector3(0.0, 0.012, 0.0), (Vector3.UP + dir * 0.8).normalized(), Color(AMBER_EDGE, 0.15)))
	for index in sides:
		var next := (index + 1) % sides
		b.tri(center, ring_in[next], ring_in[index])
		b.tri(ring_in[index], ring_in[next], ring_out[next])
		b.tri(ring_in[index], ring_out[next], ring_out[index])
	b.blob(Vector3(0.0, 0.05, 0.0), Vector3(0.62, 0.42, 0.56), Color(AMBER_CORE, 1.0), Basis.IDENTITY, false, true)
	b.blob(Vector3(0.52, 0.03, 0.28), Vector3(0.2, 0.14, 0.18), Color(AMBER_CORE.lerp(AMBER_MID, 0.4), 0.8), Basis.IDENTITY, false, true)
	b.blob(Vector3(-0.4, 0.03, -0.44), Vector3(0.15, 0.1, 0.14), Color(AMBER_CORE.lerp(AMBER_MID, 0.4), 0.8), Basis.IDENTITY, false, true)


# Nibbler (teal prey) lying on its side, a bit smaller than alive.
static func _build_prey(b: Builder) -> void:
	b.glb(NIBBLER_SCENE, 1.3, Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.0, -0.06, 0.0), Color(1.15, 1.15, 1.15))
	b.bone_splinter(Vector3(0.55, 0.0, -0.4), Vector3(0.75, 0.35, -0.55), 0.05, BONE)


# Hunter beetle on its back, legs in the air, tipped a little onto one flank.
static func _build_hunter(b: Builder, crown := false) -> void:
	var lying := Basis(Vector3(0, 0, 1), PI - 0.35)
	b.glb(HUNTER_SCENE, 1.9, lying, Vector3(0.0, -0.04, 0.0), Color(1.25, 1.2, 1.3), true, 0.0, false, int(MODEL_TRIS.hunter))
	if not crown:
		return
	# Golden crown fallen off beside the head (glowing bit: stays gold, pulses).
	var tipped := Basis(Vector3(0, 0, 1), 1.25).rotated(Vector3.UP, 0.6)
	b.glb(ELITE_CROWN_SCENE, 1.0, tipped, Vector3(1.0, 0.0, 0.9), Color(1.75, 1.35, 0.55), true, 0.0, true, 400)
	b.bone_splinter(Vector3(-0.95, 0.0, -0.5), Vector3(-1.2, 0.55, -0.75), 0.06, BONE)
	b.bone_splinter(Vector3(0.2, 0.0, -1.05), Vector3(0.25, 0.45, -1.4), 0.05, BONE)


# Elite: the hunter beetle at elite size plus its golden crown fallen beside it.
static func _build_elite(b: Builder) -> void:
	b.frame = Transform3D(Basis.from_scale(Vector3.ONE * 1.4), Vector3.ZERO)
	_build_hunter(b, true)
	b.frame = Transform3D.IDENTITY


# Skitter on its back, blade legs splayed up.
static func _build_skitter(b: Builder) -> void:
	var lying := Basis(Vector3(0, 0, 1), PI + 0.3)
	b.glb(SKITTER_SCENE, 1.75, lying, Vector3(0.0, -0.04, 0.0), Color(1.2, 1.2, 1.25), true, 0.0, false, int(MODEL_TRIS.skitter))


# Horde (Moorbrut): a small body on its side, low-poly LOD (they come in hordes).
static func _build_horde(b: Builder) -> void:
	var lying := Basis(Vector3(0, 0, 1), PI * 0.5)
	b.glb(MOORBRUT_SCENE, 0.72, lying, Vector3(0.0, -0.03, 0.0), Color(1.5, 1.45, 1.4), true, 0.0, false, int(MODEL_TRIS.horde))


# Mire Reaper on its side, bone splinters around it.
static func _build_leaper(b: Builder) -> void:
	b.glb(REAPER_SCENE, 2.05, Basis(Vector3(0, 0, 1), PI * 0.5), Vector3(0.0, -0.08, 0.0), Color(1.9, 1.75, 1.9))
	b.bone_splinter(Vector3(1.1, 0.0, 0.3), Vector3(1.45, 0.7, 0.45), 0.09, BONE)
	b.bone_splinter(Vector3(-1.05, 0.0, -0.4), Vector3(-1.4, 0.6, -0.65), 0.08, BONE)
	b.bone_splinter(Vector3(0.3, 0.0, -1.2), Vector3(0.45, 0.65, -1.6), 0.08, BONE)
	b.bone_splinter(Vector3(-0.4, 0.0, 1.15), Vector3(-0.55, 0.5, 1.5), 0.07, BONE)


# Big carcass: spine arching over broken rib hoops, a horned skull, pelvis and
# tail. Scale 1 ~ 7 m long. The amber pool core glows between the ribs.
static func _skeleton(b: Builder, bone: Color) -> void:
	var spine := [Vector3(0.0, 0.12, -3.4), Vector3(0.0, 0.55, -2.6), Vector3(0.0, 1.2, -1.8), Vector3(0.0, 1.5, -0.4), Vector3(0.0, 1.5, 1.0), Vector3(0.0, 1.25, 2.0), Vector3(0.0, 0.85, 2.5)]
	b.tube(spine, 0.2, 0.2, bone, 7)
	for index in range(1, 11):
		var t := float(index) / 11.0
		var point := _along(spine, t)
		b.blob(point + Vector3(0.0, 0.13, 0.0), Vector3(0.28, 0.34, 0.22), bone.darkened(0.06))
	# Ribs: hoops from the spine down to the ground on both sides, some broken.
	var rib_z := [-1.3, -0.7, -0.1, 0.5, 1.1, 1.6]
	var rib_r := [1.15, 1.42, 1.55, 1.55, 1.42, 1.15]
	for index in rib_z.size():
		for side in [-1.0, 1.0]:
			var end := 1.0
			if (index == 1 and side > 0.0) or (index == 4 and side < 0.0):
				end = 0.55
			var points := []
			for step in 8:
				var angle := lerpf(PI * 0.5, PI * 0.5 - 1.45 * end, float(step) / 7.0)
				var radius: float = rib_r[index]
				points.append(Vector3(side * cos(angle) * radius * 1.05, sin(angle) * 1.45, float(rib_z[index]) - 0.4 * (1.0 - sin(angle))))
			b.tube(points, 0.11, 0.065, bone, 6)
	# Pelvis.
	b.blob(Vector3(0.0, 0.6, -2.3), Vector3(1.4, 0.45, 0.7), bone)
	# Skull: cranium, snout, dark eye sockets, tusks, dropped jaw.
	b.blob(Vector3(0.0, 0.72, 3.0), Vector3(1.55, 1.15, 1.4), bone)
	b.blob(Vector3(0.0, 0.45, 3.75), Vector3(1.05, 0.62, 1.05), bone)
	for side in [-1.0, 1.0]:
		b.blob(Vector3(side * 0.42, 0.95, 3.5), Vector3(0.4, 0.38, 0.34), Color("1c1216"))
		b.tube([Vector3(side * 0.4, 0.35, 4.1), Vector3(side * 0.72, 0.6, 4.5), Vector3(side * 0.78, 1.1, 4.62)], 0.16, 0.02, bone.lightened(0.1), 7)
	b.blob(Vector3(0.0, 0.3, 4.2), Vector3(0.26, 0.14, 0.12), Color("1c1216"))
	b.tube([Vector3(-0.55, 0.08, 3.4), Vector3(-0.1, 0.1, 4.6), Vector3(0.6, 0.08, 4.35)], 0.13, 0.1, bone.darkened(0.08))


static func _along(points: Array, t: float) -> Vector3:
	var span := t * float(points.size() - 1)
	var index := mini(int(span), points.size() - 2)
	return (points[index] as Vector3).lerp(points[index + 1], span - float(index))


# Bog King fallen on its side (squashed flat), a few bone splinters around it.
static func _build_boss(b: Builder) -> void:
	var lying := Basis(Vector3(0, 0, 1), PI * 0.5)
	b.glb(BOG_KING_SCENE, 6.4, lying, Vector3(0.0, -0.1, 0.0), Color(1.3, 1.2, 1.3), true, 0.0, false, int(MODEL_TRIS.boss), 2.4)
	b.bone_splinter(Vector3(1.9, 0.0, -2.2), Vector3(2.4, 1.0, -2.7), 0.12, BONE)
	b.bone_splinter(Vector3(-2.0, 0.0, 1.2), Vector3(-2.6, 0.8, 1.5), 0.11, BONE)
	b.bone_splinter(Vector3(-1.4, 0.0, -2.6), Vector3(-1.8, 0.9, -3.1), 0.1, BONE)


# Moosschlund (apex) collapsed on its back, feet up, squashed flat.
static func _build_apex(b: Builder) -> void:
	var lying := Basis(Vector3(0, 0, 1), PI - 0.3)
	b.glb(MOOSSCHLUND_SCENE, 7.2, lying, Vector3(0.0, -0.1, 0.0), Color(1.2, 1.15, 1.15), true, 0.0, false, int(MODEL_TRIS.apex), 2.6)


# Aschenkröte (apex_toad): a squat, wide skeleton of ash-grey bones, charred
# hide scraps, burnt-out ember bubbles on the back (dark crust, only a few
# embers still glowing) and a cracked lava tongue.
static func _build_apex_toad(b: Builder) -> void:
	b.frame = Transform3D(Basis.from_scale(Vector3(1.3, 0.72, 1.02)), Vector3.ZERO)
	_skeleton(b, ASH_BONE)
	b.frame = Transform3D.IDENTITY
	var hide := Color("3a3032")
	for spec in [[Vector3(1.5, 0.08, -0.8), 0.95], [Vector3(-1.6, 0.08, 0.5), 0.9], [Vector3(0.6, 0.07, 2.1), 0.75], [Vector3(-0.5, 0.08, -2.4), 0.85], [Vector3(2.0, 0.06, 1.3), 0.6]]:
		var size: float = spec[1]
		b.blob(spec[0], Vector3(size * 1.1, 0.24, size * 0.8), hide, Basis(Vector3.UP, size * 5.0))
	# Burnt-out ember bubbles along the back: dark crust, cracked grey caps.
	var crust := Color("2a2224")
	var cap := Color("6a6060")
	var bubbles := [Vector3(0.0, 1.22, -1.3), Vector3(0.7, 1.1, -0.2), Vector3(-0.75, 1.12, 0.3), Vector3(0.0, 1.25, 0.9), Vector3(0.9, 0.95, 1.5), Vector3(-0.95, 0.9, -1.2), Vector3(0.45, 1.0, -2.1)]
	for index in bubbles.size():
		var size := 0.32 + 0.1 * float(index % 3)
		b.blob(bubbles[index], Vector3(size, size * 0.8, size), crust, Basis(Vector3.UP, float(index)))
		b.blob(bubbles[index] + Vector3(0.0, size * 0.55, 0.0), Vector3(size * 0.72, size * 0.28, size * 0.72), cap, Basis(Vector3.UP, float(index) * 1.7))
	# A few embers still glowing in the cracks.
	for spot in [Vector3(0.7, 1.32, -0.2), Vector3(0.0, 1.5, 0.9), Vector3(-0.95, 1.05, -1.2)]:
		b.blob(spot, Vector3.ONE * 0.16, Color("ff8a1e"), Basis.IDENTITY, true)
	# Cracked lava tongue lolling from the skull.
	b.tube([Vector3(0.0, 0.2, 3.6), Vector3(0.35, 0.08, 4.6), Vector3(0.1, 0.05, 5.5), Vector3(-0.4, 0.04, 6.0)], 0.28, 0.14, Color("7a2a30"), 7)
	b.blob(Vector3(-0.42, 0.06, 6.05), Vector3(0.24, 0.08, 0.2), Color("ff9a3a"), Basis.IDENTITY, true)


# Fallen Mawling: a small dark stain, a scrap and hovering orange sparks.
static func _build_mawling(b: Builder) -> void:
	b.disc(Vector3(0.0, 0.015, 0.0), 0.5, Color("24181b"))
	b.blob(Vector3(0.05, 0.06, 0.0), Vector3(0.36, 0.15, 0.28), Color("4a2a26"))
	for index in 8:
		var angle := TAU * float(index) / 8.0 + 0.4
		var reach := 0.18 + 0.12 * float(index % 3)
		b.blob(Vector3(cos(angle) * reach, 0.16 + 0.1 * float(index % 4), sin(angle) * reach), Vector3.ONE * (0.11 + 0.04 * float(index % 2)), Color("ffb347"), Basis.IDENTITY, true)


# Destroyed brood nest: broken twig ring, cracked eggshells, shell shards.
static func _build_nest(b: Builder) -> void:
	var twig := Color("6b4a2f")
	var egg := Color("bff5ec")
	for arc in [[0.2, 1.9], [2.3, 3.6], [4.0, 5.9]]:
		var points := []
		for step in 7:
			var angle := lerpf(arc[0], arc[1], float(step) / 6.0)
			points.append(Vector3(cos(angle) * 1.0, 0.1 + 0.04 * sin(angle * 3.0), sin(angle) * 1.0))
		b.tube(points, 0.09, 0.07, twig, 5)
	# Cups: open side up (rotated), one lying on its side, one upside down.
	b.shell(Vector3(0.35, 0.02, 0.2), 0.34, egg, Basis(Vector3.RIGHT, PI))
	b.shell(Vector3(-0.4, 0.2, 0.35), 0.3, egg, Basis(Vector3(0, 0, 1), PI * 0.55))
	b.shell(Vector3(-0.1, 0.02, -0.45), 0.32, egg, Basis(Vector3.RIGHT, PI * 0.85))
	b.shell(Vector3(0.6, 0.0, -0.4), 0.26, egg, Basis.IDENTITY)
	for spec in [Vector3(0.05, 0.03, 0.62), Vector3(-0.7, 0.03, -0.2), Vector3(0.8, 0.03, 0.35), Vector3(-0.25, 0.03, 0.05)]:
		b.box(spec, Vector3(0.14, 0.03, 0.1), egg.darkened(0.08), Basis(Vector3.UP, spec.x * 5.0))


# ---------------------------------------------------------------- builder

# Collects vertex-coloured geometry into ONE surface. Colour alpha: remains =
# glow mask (0 = glowing bit), pool = heat. `frame` transforms everything added.
class Builder:
	var frame := Transform3D.IDENTITY
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	static var _sphere: SphereMesh
	static var _cube: BoxMesh
	static var _hemi: SphereMesh
	static var _cylinder: CylinderMesh

	func vertex(point: Vector3, normal: Vector3, color: Color) -> int:
		verts.append(frame * point)
		normals.append((frame.basis.inverse().transposed() * normal).normalized())
		colors.append(color)
		return verts.size() - 1

	func tri(a: int, b: int, c: int) -> void:
		indices.append(a)
		indices.append(b)
		indices.append(c)

	func add_mesh(mesh: Mesh, xform: Transform3D, color: Color, keep_colors := false, glow := false, alpha := -1.0, lod_indices := PackedInt32Array()) -> void:
		var arrays := mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var mesh_normals = arrays[Mesh.ARRAY_NORMAL]
		var mesh_colors = arrays[Mesh.ARRAY_COLOR]
		var mesh_indices = lod_indices if not lod_indices.is_empty() else arrays[Mesh.ARRAY_INDEX]
		var full := frame * xform
		var normal_basis := full.basis.inverse().transposed()
		var has_normals: bool = mesh_normals != null and mesh_normals.size() == points.size()
		var has_colors: bool = keep_colors and mesh_colors != null and mesh_colors.size() == points.size()
		var base := verts.size()
		var a := alpha if alpha >= 0.0 else (0.0 if glow else 1.0)
		for index in points.size():
			verts.append(full * points[index])
			normals.append((normal_basis * mesh_normals[index]).normalized() if has_normals else Vector3.UP)
			var c := color
			if has_colors:
				c = Color(mesh_colors[index].r * color.r, mesh_colors[index].g * color.g, mesh_colors[index].b * color.b)
			colors.append(Color(c, a))
		if mesh_indices != null and mesh_indices.size() > 0:
			for index in mesh_indices:
				indices.append(base + index)
		else:
			for index in points.size():
				indices.append(base + index)

	# Low-poly ellipsoid: `size` = full extents.
	func blob(center: Vector3, size: Vector3, color: Color, rotation := Basis.IDENTITY, glow := false, pool := false) -> void:
		if _sphere == null:
			_sphere = SphereMesh.new()
			_sphere.radius = 0.5
			_sphere.height = 1.0
			_sphere.radial_segments = 10
			_sphere.rings = 6
		add_mesh(_sphere, Transform3D(rotation * Basis.from_scale(size), center), color, false, glow, color.a if pool else -1.0)

	func box(center: Vector3, size: Vector3, color: Color, rotation := Basis.IDENTITY) -> void:
		if _cube == null:
			_cube = BoxMesh.new()
		add_mesh(_cube, Transform3D(rotation * Basis.from_scale(size), center), color)

	func disc(center: Vector3, radius: float, color: Color) -> void:
		if _cylinder == null:
			_cylinder = CylinderMesh.new()
			_cylinder.top_radius = 1.0
			_cylinder.bottom_radius = 1.0
			_cylinder.height = 1.0
			_cylinder.radial_segments = 14
			_cylinder.rings = 1
		add_mesh(_cylinder, Transform3D(Basis.from_scale(Vector3(radius, 0.02, radius)), center), color)

	# Open half egg shell (dome up; rotate to turn the cup open side up).
	func shell(center: Vector3, radius: float, color: Color, rotation: Basis) -> void:
		if _hemi == null:
			_hemi = SphereMesh.new()
			_hemi.radius = 0.5
			_hemi.height = 0.5
			_hemi.is_hemisphere = true
			_hemi.radial_segments = 10
			_hemi.rings = 4
		add_mesh(_hemi, Transform3D(rotation * Basis.from_scale(Vector3(radius * 2.0, radius * 2.6, radius * 2.0)), center + Vector3(0.0, radius * 0.6, 0.0)), color)

	func bone_splinter(foot: Vector3, tip: Vector3, radius: float, color: Color) -> void:
		tube([foot, foot.lerp(tip, 0.55) + Vector3(0.03, 0.0, 0.0), tip], radius, radius * 0.15, color, 5)

	# Tube along a polyline, radius r0 -> r1, closed ends.
	func tube(points: Array, r0: float, r1: float, color: Color, sides := 6, glow := false) -> void:
		var c := Color(color, 0.0 if glow else 1.0)
		var count := points.size()
		var rings := []
		for index in count:
			var here: Vector3 = points[index]
			var tangent: Vector3 = (points[mini(index + 1, count - 1)] as Vector3) - (points[maxi(index - 1, 0)] as Vector3)
			tangent = tangent.normalized()
			var reference := Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
			var side_a := reference.cross(tangent).normalized()
			var side_b := tangent.cross(side_a)
			var radius := lerpf(r0, r1, float(index) / float(count - 1))
			var ring := []
			for step in sides:
				var angle := TAU * float(step) / float(sides)
				var dir := side_a * cos(angle) + side_b * sin(angle)
				ring.append(vertex(here + dir * radius, dir, c))
			rings.append(ring)
		for index in count - 1:
			for step in sides:
				var next := (step + 1) % sides
				tri(rings[index][step], rings[index + 1][step], rings[index][next])
				tri(rings[index][next], rings[index + 1][step], rings[index + 1][next])
		var start_dir: Vector3 = ((points[0] as Vector3) - (points[1] as Vector3)).normalized()
		var end_dir: Vector3 = ((points[count - 1] as Vector3) - (points[count - 2] as Vector3)).normalized()
		var start := vertex(points[0], start_dir, c)
		var end := vertex(points[count - 1], end_dir, c)
		for step in sides:
			var next := (step + 1) % sides
			tri(start, rings[0][next], rings[0][step])
			tri(end, rings[count - 1][step], rings[count - 1][next])

	# A GLB model (first mesh, its node transform baked), scaled to `length`
	# along its longest ground axis, rotated, centred, resting on the ground.
	# height > 0 scales to that height instead (upright props like crystals).
	# glow: the whole model counts as glowing bit; max_tris > 0 bakes the
	# import LOD closest below that triangle count instead of the full mesh.
	# max_height > 0 squashes a taller result flat (collapsed boss carcasses).
	func glb(scene: PackedScene, length: float, rotation: Basis, offset: Vector3, tint: Color, rest_on_ground := true, height := 0.0, glow := false, max_tris := 0, max_height := 0.0) -> void:
		var source: Array = CorpseVisualsMeshes.extract(scene)
		var mesh: Mesh = source[0]
		var base: Transform3D = source[1]
		var shaped := Transform3D(rotation, Vector3.ZERO) * base
		var bounds: AABB = shaped * mesh.get_aabb()
		var scale := length / maxf(maxf(bounds.size.x, bounds.size.z), 0.01)
		if height > 0.0:
			scale = height / maxf(bounds.size.y, 0.01)
		shaped = Transform3D(Basis.from_scale(Vector3.ONE * scale), Vector3.ZERO) * shaped
		bounds = shaped * mesh.get_aabb()
		if max_height > 0.0 and bounds.size.y > max_height:
			shaped = Transform3D(Basis.from_scale(Vector3(1.0, max_height / bounds.size.y, 1.0)), Vector3.ZERO) * shaped
			bounds = shaped * mesh.get_aabb()
		var center := bounds.get_center()
		var lift := -bounds.position.y if rest_on_ground else -center.y
		shaped.origin += Vector3(-center.x, lift, -center.z) + offset
		var lod := CorpseVisualsMeshes.lod_indices(mesh, max_tris) if max_tris > 0 else PackedInt32Array()
		add_mesh(mesh, shaped, tint, true, glow, -1.0, lod)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh


# GLB mesh extraction (like arena.gd), cached per scene.
class CorpseVisualsMeshes:
	static var cache := {}

	static func extract(scene: PackedScene) -> Array:
		if cache.has(scene.resource_path):
			return cache[scene.resource_path]
		var root := scene.instantiate()
		var model: MeshInstance3D = root.find_children("*", "MeshInstance3D", true, false)[0]
		var base := Transform3D.IDENTITY
		var node: Node = model
		while node != root and node is Node3D:
			base = (node as Node3D).transform * base
			node = node.get_parent()
		var result := [model.mesh, base]
		root.free()
		cache[scene.resource_path] = result
		return result

	# Index list of the finest import LOD (meshes/generate_lods) with at most
	# `max_tris` triangles; empty = use the full mesh (no LODs, e.g. dummy renderer).
	static func lod_indices(mesh: Mesh, max_tris: int) -> PackedInt32Array:
		var result := PackedInt32Array()
		var surface: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
		var index_count := int(surface.get("index_count", 0))
		if index_count <= max_tris * 3 or not surface.has("lods"):
			return result
		var full: PackedByteArray = surface.get("index_data", PackedByteArray())
		var width := 2 if int(surface.get("vertex_count", 0)) <= 65535 else 4
		if full.size() > 0:
			width = full.size() / index_count
		for lod: Dictionary in surface.lods:
			var data: PackedByteArray = lod.get("index_data", PackedByteArray())
			if data.size() / width <= max_tris * 3:
				result.resize(data.size() / width)
				for index in result.size():
					result[index] = data.decode_u16(index * 2) if width == 2 else data.decode_u32(index * 4)
				return result
		return result
