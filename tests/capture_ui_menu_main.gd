extends SceneTree
## Stage 04 / MENU_MAIN: renders the Brutstätte main view with the new component
## (legacy blocks off) for three strain states, plus a side-by-side sheet with the
## HUD concept. Run WITHOUT --headless (frame_post_draw needs a window).
## Uses a scratch profile; the real player profile is never touched.

const TEST_PROFILE := "user://capture_ui_menu_main_profile.json"
const COMPONENT := "res://scripts/ui/menu/menu_main.gd"
const CONCEPT := "C:/Users/vrxby/Documents/Codex/Swarm/Design/MAWLINGS_ACTIVE_HUD_CONCEPT_PORTRAIT.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(540, 960)
	var session: Variant = load("res://scripts/meta/session.gd")
	if FileAccess.file_exists(TEST_PROFILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	var profile: Variant = load("res://scripts/meta/profile.gd").load_or_create(TEST_PROFILE)
	profile.essence = 1240
	profile.crowns = 4
	profile.upgrades["brood_size"] = 3
	profile.upgrades["rending"] = 2
	profile.instinct_level = 3
	profile.completed_quests.append_array(["survive_1", "survive_3", "peak_50", "kills_100"])
	profile.records.best_seconds = 262.0
	profile.records.best_peak = 88
	profile.records.total_kills = 340
	profile.records.total_leapers = 6
	profile.records.total_bosses = 0
	profile.save()
	session.last_result = {}
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	menu.profile_path = TEST_PROFILE
	menu.change_scene_on_play = false
	var component: Control = load(COMPONENT).new()
	for key in component.REPLACES:
		menu.legacy[key] = false
	menu.add_child(component)
	root.add_child(menu)
	await _settle(20)
	await _shot("res://preview_ui_menu_main_free.png")
	menu.strain_index = menu.strain_ids.find("knochenkiefer")
	await _settle(6)
	await _shot("res://preview_ui_menu_main_locked.png")
	menu.profile.unlocked_strains.append("knochenkiefer")
	await _settle(6)
	await _shot("res://preview_ui_menu_main_buy.png")
	_compare("res://preview_ui_menu_main_free.png", "res://preview_ui_menu_main_compare.png")
	menu.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROFILE))
	print("Saved MENU_MAIN review frames")
	quit()


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


## Preview next to the concept at the same height for the design review.
func _compare(preview_path: String, out_path: String) -> void:
	var preview := Image.load_from_file(ProjectSettings.globalize_path(preview_path))
	if preview == null or not FileAccess.file_exists(CONCEPT):
		return
	var concept := Image.load_from_file(CONCEPT)
	if concept == null:
		return
	concept.convert(preview.get_format())
	concept.resize(int(concept.get_width() * float(preview.get_height()) / concept.get_height()), preview.get_height(), Image.INTERPOLATE_BILINEAR)
	var sheet := Image.create(preview.get_width() + concept.get_width() + 12, preview.get_height(), false, preview.get_format())
	sheet.fill(Color.BLACK)
	sheet.blit_rect(preview, Rect2i(Vector2i.ZERO, preview.get_size()), Vector2i.ZERO)
	sheet.blit_rect(concept, Rect2i(Vector2i.ZERO, concept.get_size()), Vector2i(preview.get_width() + 12, 0))
	sheet.save_png(ProjectSettings.globalize_path(out_path))
