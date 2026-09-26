extends SceneTree

# Renders the start of a run for several strains through the real RunConfig path.
const PROFILE = preload("res://scripts/meta/profile.gd")
const SESSION = preload("res://scripts/meta/session.gd")
const STRAINS := ["glutmaw", "sporling", "flinkzahn", "knochenkiefer"]


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	var profile = PROFILE.load_or_create("user://mawlings_profile_capture.json")
	for strain in STRAINS:
		# Captures may show locked strains; build the config directly from data.
		if not profile.unlocked_strains.has(strain):
			profile.unlocked_strains.append(strain)
		if not profile.owned_strains.has(strain):
			profile.owned_strains.append(strain)
		SESSION.pending_config = profile.build_run_config(strain, "verdant_maw", 0)
		var scene: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(scene)
		var controls: Node = scene.get_node("HUD/Controls")
		for connection in controls.pause_requested.get_connections():
			controls.pause_requested.disconnect(connection.callable)
		Input.action_press("move_right")
		await create_timer(0.7).timeout
		Input.action_release("move_right")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://preview_strain_%s.png" % strain)
		scene.queue_free()
		await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://mawlings_profile_capture.json"))
	print("Saved strain previews")
	quit()
