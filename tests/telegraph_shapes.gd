extends SceneTree

# Stage 20: every boss telegraph draws its hit edge exactly where the attack
# hits. For each attack the test rebuilds the shader's signed edge distance
# (telegraph_boss_shapes.gdshader: d >= 0 inside, the bright band's outer border
# is d = 0; SVG circle / cone: hit ring at 210 px / reach at 412 px) from the
# live node transform, mesh and uniforms, and compares it with the boss's own
# contains() on a dense grid. Also: shared danger palette (S1), colour-blind
# palette, the Fläche style for the Glutpfützen, safe islands in friendly cyan,
# normal enemies in danger colours (never ember orange).

const TG = preload("res://scripts/telegraph_style.gd")
const UI_STYLE = preload("res://scripts/ui/ui_style.gd")
const APEX = preload("res://scripts/apex_boss.gd")
const TOAD = preload("res://scripts/apex_toad.gd")
const WORM = preload("res://scripts/apex_sandworm.gd")
const BOG_KING = preload("res://scripts/bog_king.gd")
const TUNING = preload("res://scripts/tuning.gd")
# Tolerance at the edge (m): the grid may land on a sampling seam.
const EDGE := 0.08

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_palette()
	_check_moss()
	_check_toad()
	_check_worm()
	_check_hazard()
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("PASS telegraph_shapes: hit edge = drawn edge for Moosschlund (lanes, ring, islands), Aschenkröte (circles, lane, puddles), Sandwurm (circle, cone); danger palette, colour-blind, hazard area, friendly islands")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _world(boss: Node3D) -> Node3D:
	var main := Node3D.new()
	main.name = "Main"
	root.add_child(main)
	var world := Node3D.new()
	world.name = "World"
	main.add_child(world)
	world.add_child(boss)
	return main


# Signed edge distance of one telegraph part at a world point (+ inside).
func _drawn(part: MeshInstance3D, point: Vector3) -> float:
	var local := part.global_transform.affine_inverse() * point
	var material := part.material_override as ShaderMaterial
	var p := Vector2(local.x, local.z)
	if material.shader == TG.BOSS_SHADER:
		var edge_m: float = (part.mesh as Mesh).get_aabb().size.x
		if int(material.get_shader_parameter("shape")) == 0:
			return edge_m * TG.CIRCLE_HIT_PX / 512.0 - p.length()
		# Cone: rebuild the quad's mapping (u along +Z from the origin).
		var aabb := (part.mesh as Mesh).get_aabb()
		var along := aabb.size.z / 512.0
		var across := aabb.size.x / 512.0
		var px := Vector2(p.y / along + TG.CONE_ORIGIN_PX.x, p.x / across + TG.CONE_ORIGIN_PX.y)
		var rel := px - TG.CONE_ORIGIN_PX
		var reach := TG.CONE_REACH_PX - rel.length()
		var side := (TG.CONE_TAN * rel.x - absf(rel.y)) / sqrt(1.0 + TG.CONE_TAN * TG.CONE_TAN)
		return minf(reach, side) * along
	var shape := int(material.get_shader_parameter("shape"))
	var outer := _param(material, "outer")
	match shape:
		TG.Shape.LANE:
			var hw := _param(material, "half_width")
			var hl := _param(material, "lane_length") * 0.5
			return minf(hw - absf(p.x), hl - absf(p.y))
		TG.Shape.RING:
			return minf(outer - p.length(), p.length() - _param(material, "inner"))
		TG.Shape.ISLANDS:
			var d := outer - p.length()
			var islands: PackedVector4Array = material.get_shader_parameter("islands")
			for index in int(_param(material, "island_count")):
				var island := islands[index]
				d = minf(d, (p - Vector2(island.x, island.y)).length() - island.z)
			return d
	return outer - p.length()


# Uniform value or the shader default (unset uniforms read back as null).
func _param(material: ShaderMaterial, key: String) -> float:
	var value: Variant = material.get_shader_parameter(key)
	if value == null:
		value = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), key)
	return float(value) if value != null else 0.0


# Compares drawn edge and hit test over a grid around `center`.
func _compare(label: String, parts: Array, hit: Callable, center: Vector3, span: float) -> void:
	var wrong := 0
	var inside := 0
	var steps := 70
	for iz in steps:
		for ix in steps:
			var point := center + Vector3(-span + 2.0 * span * (float(ix) + 0.5) / steps, 0.0, -span + 2.0 * span * (float(iz) + 0.5) / steps)
			var d := -INF
			for part in parts:
				d = maxf(d, _drawn(part, point))
			if absf(d) < EDGE:
				continue
			var hits: bool = hit.call(point)
			if hits:
				inside += 1
			if hits != (d > 0.0):
				wrong += 1
				print("  mismatch %s at %s (d %.3f, hit %s)" % [label, point - center, d, hits])
	_check(inside > 20 and wrong == 0, "%s: drawn edge = hit edge (%d mismatches, %d inside)" % [label, wrong, inside])


func _check_palette() -> void:
	var danger := UI_STYLE.BRAWL_DANGER_FACE
	for kind in ["hunter", "boss", "boss_cone"]:
		_check(TG.PALETTE[kind].fill == danger, "%s warning in danger magenta" % kind)
	var ember: Color = UI_STYLE.BRAWL_TONES.ember.face
	for kind in ["hunter", "skitter", "leaper", "boss", "boss_cone", "hazard"]:
		var fill: Color = TG.PALETTE[kind].fill
		var hue_gap := absf(fill.h - ember.h)
		hue_gap = minf(hue_gap, 1.0 - hue_gap)
		_check(hue_gap > 0.12, "%s is not ember orange (hue gap %.2f)" % [kind, hue_gap])
		_check(TG.PALETTE_COLORBLIND.has(kind), "%s has a colour-blind palette" % kind)
	var blind := TG.shape_material(TG.Shape.RING, "boss", true)
	_check(blind.get_shader_parameter("fill_color") == TG.PALETTE_COLORBLIND.boss.fill and blind.get_shader_parameter("safe_color") == TG.SAFE_COLORBLIND, "Procedural shapes take the colour-blind palette")
	var safe := TG.SAFE
	var safe_gap := minf(absf(safe.h - danger.h), 1.0 - absf(safe.h - danger.h))
	_check(safe_gap > 0.3, "Safe islands far from the danger hue")


func _check_moss() -> void:
	var boss: Variant = APEX.new()
	var main := _world(boss)
	boss.state = APEX.State.CHASE
	boss.cooldown = 99.0
	for pattern in [APEX.Pattern.ROOTS, APEX.Pattern.SPORES, APEX.Pattern.QUAKE]:
		boss.phase = 2 if pattern == APEX.Pattern.QUAKE else 1
		boss.begin_attack(pattern, Vector3(7, 0, 3), 1.0)
		for part in boss.telegraphs:
			_check((part.material_override as ShaderMaterial).get_shader_parameter("pattern") == pattern, "Moosschlund part tagged with its pattern")
		_compare("Moosschlund %s" % APEX.pattern_name(pattern), boss.telegraphs, boss.contains, boss.attack_center, 26.0)
		boss._clear_telegraphs()
	main.free()


func _check_toad() -> void:
	var toad: Variant = TOAD.new()
	var main := _world(toad)
	toad.state = TOAD.State.CHASE
	toad.cooldown = 99.0
	for pattern in [TOAD.Pattern.LEAP, TOAD.Pattern.SPIT, TOAD.Pattern.TONGUE]:
		toad.begin_attack(pattern, Vector3(8, 0, 2), 1.0)
		_compare("Aschenkröte %s" % TOAD.pattern_name(pattern), toad.telegraphs, toad.contains, toad.attack_center, 22.0)
		toad._clear_telegraphs()
	main.free()


func _check_worm() -> void:
	var worm: Variant = WORM.new()
	var main := _world(worm)
	worm.state = WORM.State.CHASE
	worm.cooldown = 99.0
	for pattern in [WORM.Pattern.BREACH, WORM.Pattern.SWEEP]:
		worm.begin_attack(pattern, Vector3(3, 0, 5), 1.0)
		var zone: Dictionary = worm.zones[0]
		_compare("Sandwurm %s" % WORM.pattern_name(pattern), worm.telegraphs, worm.contains, zone.center, 20.0)
		worm._clear_telegraphs()
	main.free()
	# Bog King: the same SVG circle on BOSS_ATTACK_RADIUS.
	var zone := TG.build("boss", TUNING.BOSS_ATTACK_RADIUS)
	root.add_child(zone)
	_compare("Bog King stomp", [zone], func(p: Vector3) -> bool: return p.length() <= TUNING.BOSS_ATTACK_RADIUS, Vector3.ZERO, 8.0)
	zone.free()


# Glutpfützen = Fläche: hazard style, filled, the hit disc = drawn disc.
func _check_hazard() -> void:
	var material := TOAD.telegraph_material(TOAD.SHAPE_PUDDLE, false)
	_check(material.shader == TG.SHAPES_SHADER and int(material.get_shader_parameter("shape")) == TG.Shape.HAZARD, "Puddle uses the hazard area style")
	_check(material.get_shader_parameter("fill_color") == TG.PALETTE.hazard.fill, "Puddle in the hazard palette")
	var toad: Variant = TOAD.new()
	var main := _world(toad)
	toad.puddles.add(Vector3(4, 0, -2), 2.5, 5.0, material)
	var node: MeshInstance3D = toad.puddles.spots[0].node
	_compare("Glutpfütze", [node], toad.puddles.contains, Vector3(4, 0, -2), 5.0)
	main.free()
