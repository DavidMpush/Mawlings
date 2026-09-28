extends SceneTree

# Stage 05 readability review (run WITHOUT --headless):
#   preview_readability_strains.png  – all 6 strains on moss (left) and sand (right),
#                                      a Nibbler next to every group, game camera scale
#   preview_readability_telegraph.png / _cb.png – the four warning patterns on moss
#                                      and sand, normal and colour-blind palette
#   *_grey.png                       – luminance-only copies of every page
# Prints the WCAG contrast of every strain tint and of the rendered swarm pixels.
const META = preload("res://scripts/meta/meta_data.gd")
const SWARM_SCRIPT = preload("res://scripts/swarm.gd")
const PREY_SCRIPT = preload("res://scripts/prey.gd")
const TELEGRAPH = preload("res://scripts/telegraph_style.gd")
const TUNING = preload("res://scripts/tuning.gd")
const MOSS := Color("80a04c")
const SAND := Color("d4b377")
const CAMERA_OFFSET := Vector3(0.0, 23.0, 15.0)
const SUN := Transform3D(Basis(Vector3(0.81915206, 0.0, 0.57357645), Vector3(0.46984634, 0.57357645, -0.6710101), Vector3(-0.32898995, 0.81915206, 0.46984634)), Vector3.ZERO)

var page: Node3D
var camera: Camera3D
var labels: CanvasLayer


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	_print_tint_contrast()
	await _strain_page()
	await _telegraph_page(false, "preview_readability_telegraph")
	await _telegraph_page(true, "preview_readability_telegraph_cb")
	print("Saved readability previews")
	quit()


# --- pages -------------------------------------------------------------------

func _strain_page() -> void:
	_new_page(Vector3(0.0, 0.0, 0.0), 1.0)
	_ground(MOSS, Vector3(-8.0, 0.0, 0.0), Vector2(16.0, 60.0))
	_ground(SAND, Vector3(8.0, 0.0, 0.0), Vector2(16.0, 60.0))
	var groups: Array = []
	for row in 3:
		for column in 2:
			var index := row * 2 + column
			var strain_id: String = META.STRAIN_ORDER[index]
			var strain: Dictionary = META.STRAINS[strain_id]
			var z := -11.0 + float(row) * 9.5
			# Each strain on both grounds: left half on moss, right half on sand.
			for side: float in [-1.0, 1.0]:
				var x := side * (2.4 + float(column) * 3.9)
				var swarm: Node3D = await _swarm(strain_id, Color(String(strain.tint)), Vector3(x, 0.0, z))
				groups.append({"id": strain_id, "node": swarm, "ground": MOSS if side < 0.0 else SAND})
				_prey(Vector3(x + side * 1.7, 0.0, z + 1.6))
			var label_x := -(2.4 + float(column) * 3.9)
			_label(String(strain.name), Vector3(label_x, 0.0, z - 2.6), index)
	await _settle()
	var image := await _save("preview_readability_strains")
	_measure(image, groups)
	_free_page()


func _telegraph_page(colorblind: bool, file_name: String) -> void:
	_new_page(Vector3(0.0, 0.0, 0.5), 1.3)
	_ground(MOSS, Vector3(-10.0, 0.0, 0.0), Vector2(20.0, 120.0))
	_ground(SAND, Vector3(10.0, 0.0, 0.0), Vector2(20.0, 120.0))
	var kinds := {"hunter": TUNING.HUNTER_ATTACK_RADIUS, "skitter": TUNING.SKITTER_WIDTH * 2.0,
		"leaper": TUNING.LEAPER_ZONE_RADIUS, "boss": TUNING.BOSS_ATTACK_RADIUS}
	var row := 0
	for kind: String in kinds:
		var z := -14.5 + float(row) * 9.0
		for side: float in [-1.0, 1.0]:
			var tele: MeshInstance3D = TELEGRAPH.build(kind, float(kinds[kind]), 1 if colorblind else 0)
			page.add_child(tele)
			tele.position = Vector3(side * 5.2, 0.1, z)
			if kind == "skitter":
				tele.rotation.y = PI * 0.5
				tele.scale = Vector3(1.0, 1.0, 8.0)
			TELEGRAPH.set_progress(tele, 0.55)
			(tele.material_override as ShaderMaterial).set_shader_parameter("time", 1.3)
			# A few Mawlings inside the area: patterns must not hide the swarm.
			await _swarm("glutmaw", Color(String(META.STRAINS["glutmaw"].tint)), tele.position + Vector3(side * 0.9, -0.1, 0.9), 5)
		_label(kind.to_upper(), Vector3(-0.9, 0.0, z - 3.0 if kind != "boss" else z - 4.2), row)
		row += 1
	# Calm (unarmed) hunter preview in the corner.
	var calm: MeshInstance3D = TELEGRAPH.build("hunter", TUNING.HUNTER_ATTACK_RADIUS, 1 if colorblind else 0)
	page.add_child(calm)
	calm.position = Vector3(0.0, 0.1, -21.0)
	calm.scale = Vector3.ONE * 0.45
	TELEGRAPH.set_armed(calm, false)
	await _settle()
	await _save(file_name)
	_free_page()


# --- building blocks ---------------------------------------------------------

func _new_page(target: Vector3, zoom: float) -> void:
	page = Node3D.new()
	root.add_child(page)
	var sun := DirectionalLight3D.new()
	sun.transform = SUN
	sun.light_energy = 1.15
	page.add_child(sun)
	camera = Camera3D.new()
	camera.fov = 58.0
	page.add_child(camera)
	camera.position = target + CAMERA_OFFSET * zoom
	camera.look_at(target, Vector3.UP)
	camera.current = true
	labels = CanvasLayer.new()
	page.add_child(labels)


func _free_page() -> void:
	page.queue_free()
	page = null


func _ground(color: Color, center: Vector3, size: Vector2) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = center + Vector3(0.0, -0.02, 0.0)
	page.add_child(part)


# Real swarm node with the real RunConfig tint path, frozen for a still frame.
func _swarm(strain_id: String, tint: Color, location: Vector3, count := 9) -> Node3D:
	var swarm := Node3D.new()
	swarm.set_script(SWARM_SCRIPT)
	page.add_child(swarm)
	swarm.position = location
	swarm.apply_config({"strain_id": strain_id, "tint": tint, "mods": {}})
	swarm.set_population(count, false)
	swarm.set_process(false)
	# Let the surplus units free their shader-instance slots before the next group.
	await process_frame
	return swarm


func _prey(location: Vector3) -> void:
	var prey := Node3D.new()
	prey.set_script(PREY_SCRIPT)
	page.add_child(prey)
	prey.position = location
	prey.set_process(false)


func _label(text: String, world: Vector3, _index: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	labels.add_child(label)
	label.position = camera.unproject_position(world) - Vector2(40.0, 10.0)


func _settle() -> void:
	for frame in 4:
		await process_frame


func _save(file_name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://previews/%s.png" % file_name)
	var grey := image.duplicate() as Image
	grey.convert(Image.FORMAT_L8)
	grey.save_png("res://previews/%s_grey.png" % file_name)
	return image


# --- numbers -----------------------------------------------------------------

static func luminance(color: Color) -> float:
	var channels := [color.r, color.g, color.b]
	var linear: Array[float] = []
	for value: float in channels:
		linear.append(value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4))
	return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _print_tint_contrast() -> void:
	for strain_id: String in META.STRAIN_ORDER:
		var tint := Color(String(META.STRAINS[strain_id].tint))
		print("tint %-14s %s  moss %.2f  sand %.2f  hue %3d" % [strain_id, tint.to_html(false),
			contrast(tint, MOSS), contrast(tint, SAND), int(tint.h * 360.0)])
	var outline := Color(0.06, 0.04, 0.05)
	print("outline contour     moss %.2f  sand %.2f" % [contrast(outline, MOSS), contrast(outline, SAND)])


# Rendered body colour: mean of the pixels around each group that clearly differ
# from the ground there, plus the share of dark contour pixels.
func _measure(image: Image, groups: Array) -> void:
	var results := {}
	for group: Dictionary in groups:
		var node: Node3D = group.node
		# unproject_position works in the 900 x 1600 canvas; the image is the window size.
		var center := camera.unproject_position(node.global_position) * float(image.get_width()) / root.get_visible_rect().size.x
		var ground_px := _local_ground(image, center)
		var pixels: Array = []
		for y in range(int(center.y) - 30, int(center.y) + 30):
			for x in range(int(center.x) - 34, int(center.x) + 34):
				if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
					continue
				var pixel := image.get_pixel(x, y)
				var delta := Vector3(pixel.r - ground_px.r, pixel.g - ground_px.g, pixel.b - ground_px.b).length()
				if delta >= 0.18:
					pixels.append(pixel)
		if pixels.size() < 20:
			continue
		# Bodies are bimodal (lit fill + dark contour): report both halves.
		pixels.sort_custom(func(a: Color, b: Color) -> bool: return luminance(a) < luminance(b))
		var fill := _mean(pixels.slice(pixels.size() / 2))
		var edge := _mean(pixels.slice(0, maxi(1, pixels.size() / 5)))
		var key := "%s %s" % [group.id, "moss" if group.ground == MOSS else "sand"]
		if not results.has(key):
			results[key] = true
			var hue_gap := absf(fill.h - ground_px.h) * 360.0
			hue_gap = minf(hue_gap, 360.0 - hue_gap)
			print("render %-20s fill %s  L-contrast %.2f  hue gap %3d  |  contour %s  L-contrast %.2f" % [key,
				fill.to_html(false), contrast(fill, ground_px), int(hue_gap), edge.to_html(false), contrast(edge, ground_px)])


static func _mean(colors: Array) -> Color:
	var sum := Vector3.ZERO
	for color: Color in colors:
		sum += Vector3(color.r, color.g, color.b)
	sum /= float(maxi(1, colors.size()))
	return Color(sum.x, sum.y, sum.z)


# Ground right next to a group: median-luminance pixel of a ring of samples.
func _local_ground(image: Image, center: Vector2) -> Color:
	var samples: Array = []
	for step in 24:
		var angle := TAU * float(step) / 24.0
		var at := center + Vector2(cos(angle) * 62.0, sin(angle) * 44.0)
		if at.x >= 0.0 and at.y >= 0.0 and at.x < 540.0 and at.y < 960.0:
			samples.append(image.get_pixelv(Vector2i(at)))
	samples.sort_custom(func(a: Color, b: Color) -> bool: return luminance(a) < luminance(b))
	return samples[samples.size() / 2]
