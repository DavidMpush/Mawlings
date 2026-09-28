extends Node3D

# VFX package V1 (user art, assets/vfx/): pooled flat effect sprites in the world.
# One MultiMesh per texture = at most one draw call per effect kind; an instance
# is written only when it spawns, the animation (scale, spin, fade, pull, rise)
# runs in shaders/vfx_sprite.gdshaderinc from INSTANCE_CUSTOM and one `now` clock.
#
#   var vfx := VFX_SPRITES.create()      # add_child(vfx) somewhere in the world
#   vfx.spawn("bite", position)          # kind, world position, size factor, rotation
#   vfx.step(delta, swarm_position)      # advances the clock (only while the run steps)
#   vfx.clear()                          # reset: everything disappears at once
#
# Kinds (durations from the package README):
#   bite     contact bite of the Mawlings    0.12-0.20 s   pops, turns, snaps away
#   acid     acid spit / venom hit           0.25-0.40 s   70 % -> 110 %
#   spore    spore burst                     0.40-0.70 s   grows and fades
#   shock    heavy impact (dig, quake, boss) 0.25-0.45 s   radial push
#   harvest  biomass collected               0.45-0.60 s   pulled into the swarm centre
#   dna      DNA collected                   0.60-0.80 s   flashes, rises
# Every kind has a hard cap of live instances (the oldest is reused when full) and
# a minimum gap between spawns, so 250 Mawlings plus a flood cannot flood the screen.
# The quality tier's effect_density lowers the caps (never below a third).

const QUALITY = preload("res://scripts/quality.gd")
const SHADER = preload("res://shaders/vfx_sprite.gdshader")

# texture, mode (shader), cap, duration [min, max], size (m, quad edge at 1.0),
# tilt (deg towards the camera), lift (m above ground), gap (s between two
# spawns of this kind), spin (random start rotation, rad). All kinds draw over
# bodies (no depth test), so a short hit never vanishes inside the swarm.
# "shock" has size 1 m: callers pass the diameter (about 2.2 x the hit radius,
# the painted stone ring then sits on the radius).
const KINDS := {
	# Nutzer 28.09.: Bisse waren „zu viel und zu prominent“ -> kleiner, seltener, transparenter.
	"bite": {"texture": "res://assets/vfx/bite_hit.png", "mode": 0, "cap": 10, "duration": [0.1, 0.15],
		"size": 1.05, "tilt": 38.0, "lift": 0.5, "gap": 0.12, "spin": 0.5, "opacity": 0.6},
	"acid": {"texture": "res://assets/vfx/acid_splash.png", "mode": 1, "cap": 24, "duration": [0.25, 0.4],
		"size": 2.2, "tilt": 12.0, "lift": 0.2, "gap": 0.0, "spin": PI},
	"spore": {"texture": "res://assets/vfx/spore_cloud.png", "mode": 2, "cap": 12, "duration": [0.4, 0.7],
		"size": 3.4, "tilt": 16.0, "lift": 0.35, "gap": 0.05, "spin": PI},
	"shock": {"texture": "res://assets/vfx/slam_shockwave.png", "mode": 3, "cap": 12, "duration": [0.25, 0.45],
		"size": 1.0, "tilt": 0.0, "lift": 0.12, "gap": 0.0, "spin": 0.35, "opacity": 0.85},
	"harvest": {"texture": "res://assets/vfx/harvest_particles.png", "mode": 4, "cap": 16, "duration": [0.45, 0.6],
		"size": 1.9, "tilt": 25.0, "lift": 0.8, "gap": 0.1, "spin": PI},
	"dna": {"texture": "res://assets/vfx/dna_pickup.png", "mode": 5, "cap": 8, "duration": [0.6, 0.8],
		"size": 2.0, "tilt": 40.0, "lift": 1.0, "gap": 0.18, "spin": 0.2},
}
const ORDER := ["shock", "acid", "spore", "harvest", "bite", "dna"]

var _clock := 0.0
var _rng := RandomNumberGenerator.new()
# kind -> {batch, material, ends: PackedFloat32Array, used: int, cap, last}
var _pools := {}
var _pull_target := Vector3.ZERO
var spawned := 0
var rejected := 0
# Global switch (perf bench A/B: off=vfx). Off = spawn() does nothing.
static var enabled := true


static func create(node_name := "VFX sprites") -> Node3D:
	var node: Node3D = load("res://scripts/vfx_sprites.gd").new()
	node.name = node_name
	return node


func _init() -> void:
	top_level = true
	_rng.seed = 5171
	var density := clampf(float(QUALITY.value("effect_density", 1.0)), 0.34, 1.0)
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var priority := 1
	for kind in ORDER:
		var spec: Dictionary = KINDS[kind]
		var cap := maxi(2, int(round(float(spec.cap) * density)))
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("sprite", load(String(spec.texture)))
		material.set_shader_parameter("mode", int(spec.mode))
		material.set_shader_parameter("opacity", float(spec.get("opacity", 1.0)))
		material.render_priority = priority
		priority += 1
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = quad
		multimesh.instance_count = cap
		multimesh.visible_instance_count = 0
		var batch := MultiMeshInstance3D.new()
		batch.name = "VFX %s" % kind
		batch.multimesh = multimesh
		batch.material_override = material
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Instances move in the shader (pull, rise): never cull the batch.
		batch.custom_aabb = AABB(Vector3(-4000.0, -50.0, -4000.0), Vector3(8000.0, 100.0, 8000.0))
		batch.visible = false
		add_child(batch)
		var ends := PackedFloat32Array()
		ends.resize(cap)
		ends.fill(-1.0)
		_pools[kind] = {"batch": batch, "material": material, "ends": ends, "used": 0, "cap": cap, "last": -INF}


## Spawns one effect. `size` scales the kind's base size, `rotation` (rad) is
## random within the kind's range when NAN. Returns false when throttled.
func spawn(kind: String, at: Vector3, size := 1.0, rotation_rad := NAN) -> bool:
	var pool: Dictionary = _pools.get(kind, {})
	if not enabled or pool.is_empty() or size <= 0.0:
		return false
	var spec: Dictionary = KINDS[kind]
	if _clock - float(pool.last) < float(spec.gap):
		rejected += 1
		return false
	pool.last = _clock
	var ends: PackedFloat32Array = pool.ends
	var cap: int = pool.cap
	# First free slot, else the one that ends soonest (oldest effect is replaced).
	var slot := -1
	var soonest := 0
	for index in cap:
		if ends[index] <= _clock:
			slot = index
			break
		if ends[index] < ends[soonest]:
			soonest = index
	if slot < 0:
		slot = soonest
		rejected += 1
	var duration := _rng.randf_range(float(spec.duration[0]), float(spec.duration[1]))
	var angle := rotation_rad if not is_nan(rotation_rad) else _rng.randf_range(-float(spec.spin), float(spec.spin))
	var edge := float(spec.size) * size * _rng.randf_range(0.92, 1.08)
	var tilt := deg_to_rad(float(spec.tilt))
	var place := Vector3(at.x, float(spec.lift) + 0.5 * edge * sin(tilt), at.z)
	var multimesh: MultiMesh = (pool.batch as MultiMeshInstance3D).multimesh
	multimesh.set_instance_transform(slot, Transform3D(Basis(Vector3.RIGHT, tilt).scaled(Vector3.ONE * edge), place))
	multimesh.set_instance_custom_data(slot, Color(_clock, duration, angle, _rng.randf()))
	ends[slot] = _clock + duration
	pool.used = maxi(int(pool.used), slot + 1)
	multimesh.visible_instance_count = int(pool.used)
	(pool.material as ShaderMaterial).set_shader_parameter("now", _clock)
	(pool.batch as Node3D).visible = true
	spawned += 1
	return true


## Advances all effects. Call only while the run steps (pause = frozen effects).
func step(delta: float, pull_target: Vector3) -> void:
	_clock += maxf(0.0, delta)
	_pull_target = pull_target
	for kind in _pools:
		var pool: Dictionary = _pools[kind]
		if int(pool.used) <= 0:
			continue
		var ends: PackedFloat32Array = pool.ends
		var used := 0
		for index in int(pool.used):
			if ends[index] > _clock:
				used = index + 1
		pool.used = used
		var batch: MultiMeshInstance3D = pool.batch
		batch.multimesh.visible_instance_count = used
		batch.visible = used > 0
		if used > 0:
			var material: ShaderMaterial = pool.material
			material.set_shader_parameter("now", _clock)
			if kind == "harvest":
				material.set_shader_parameter("pull_target", Vector3(pull_target.x, 0.0, pull_target.z))


## Removes every effect at once (run reset, migration).
func clear() -> void:
	for kind in _pools:
		var pool: Dictionary = _pools[kind]
		(pool.ends as PackedFloat32Array).fill(-1.0)
		pool.used = 0
		pool.last = -INF
		var batch: MultiMeshInstance3D = pool.batch
		batch.multimesh.visible_instance_count = 0
		batch.visible = false


## Live effects of one kind ("" = all kinds).
func active_count(kind := "") -> int:
	var count := 0
	for key in _pools:
		if kind != "" and key != kind:
			continue
		var ends: PackedFloat32Array = _pools[key].ends
		for index in int(_pools[key].used):
			if ends[index] > _clock:
				count += 1
	return count


func capacity(kind: String) -> int:
	return int(_pools.get(kind, {}).get("cap", 0))


## Draw calls this manager currently adds (visible batches).
func visible_batches() -> int:
	var count := 0
	for kind in _pools:
		if (_pools[kind].batch as Node3D).visible:
			count += 1
	return count


func clock() -> float:
	return _clock
