extends RefCounted

# Qualitätsstufen (Etappe 06, LEISTUNG). Daten- und Auswahl-API. Etappe 07:
# main.gd wählt die Stufe beim Start (Einstellung "quality" oder Heuristik) und
# wendet Viewport und Schwarm-Schatten an; fx.gd/attack_forms.gd lesen
# effect_density, hunt_world.gd corpse_segments; decor_density ist über
# main.quality_value() abfragbar (Arena liest es später). Nutzung (statisch):
#
#   const Quality := preload("res://scripts/quality.gd")
#   var tier: int = Quality.current_tier()        # Override oder Heuristik
#   var s: Dictionary = Quality.settings(tier)     # Kopie der Schalter
#   Quality.apply_viewport(get_viewport(), s)      # MSAA + 3D-Skalierung
#
# Alle Schalter sind rein visuell: sie dürfen weder Spielzustand, Kollision,
# Seed-Determinismus noch Trefferauflösung ändern (Kampf nutzt die sichtbaren
# Mawlings – deshalb bleibt visible_mawlings auch in NIEDRIG bei ≥ 80, siehe unten).

enum Tier { LOW, MEDIUM, HIGH }

const TIER_IDS := ["low", "medium", "high"]
const TIER_NAMES := ["NIEDRIG", "MITTEL", "HOCH"]

## Schalter je Stufe. Bedeutung und geplanter Leser:
## visible_mawlings   int   Obergrenze sichtbarer Mawling-Modelle (Swarm.VISUAL_LIMIT, heute 120).
##                          ACHTUNG: HuntWorld.melee_factor/_resolve_area_hit zählen sichtbare
##                          Tiere – vor einer Absenkung Trefferanteile vom Modell entkoppeln.
## unit_shadows       bool  Boden-Schatten-MultiMesh unter den Mawlings (Swarm.shadows).
## swarm_multimesh    bool  Mawlings als ein MultiMesh (INSTANCE_CUSTOM statt instance uniforms)
##                          statt 120 Einzel-MeshInstances; alle Stufen, sobald umgesetzt.
## anim_every_nth     int   Beinzyklus-Parameter nur jedes n-te Frame je Tier setzen (1 = immer).
## effect_density     float Anteil der Zier-Effektteile (Sporen-Partikel, Bogenpunkte,
##                          Spuckspuren, FX-Ringe); Telegraphen/Warnflächen sind NIE betroffen.
## decor_density      float Anteil rein dekorativer Chunk-Teile (Moos, Sandflecken, Kiesel,
##                          Blattbüschel, Blumen). Steine, Engstellen, Landmarken bleiben immer.
## corpse_segments    int   Radialsegmente der Kadaver-Kugel (SphereMesh-Standard: 64).
## hud_redraw_hz      int   Obergrenze der HUD-Neuzeichnung, wenn sich nichts animiert (0 = jedes Frame).
## popup_font_steps   int   Anzahl diskreter Schriftgrößen der Belohnungs-Popups (0 = stufenlos).
## menu_3d            bool  SubViewport-Rudel im Menü (menu_main.use_3d).
## menu_msaa          int   MSAA des Menü-SubViewports (Viewport.MSAA_*).
## msaa_3d            int   MSAA des Spiel-Viewports (Viewport.MSAA_*).
## scaling_3d_scale   float 3D-Renderskalierung des Spiel-Viewports (HUD bleibt scharf).
## max_fps            int   Bildraten-Obergrenze (0 = unbegrenzt/Vsync).
## Etappe 22:
## wall_detail        float Dichte der Wand-Requisiten tief im Inneren der Wände und am
##                          Kartenrand (1 = alle). Wandränder (Kollision = Optik) bleiben immer.
## minimap_bake_us    int   Backzeit der Minimap je Frame (µs).
## vfx_sprites        bool  Effekt-Sprites (vfx_sprites.gd); Warnflächen sind nie betroffen.
const PRESETS := {
	Tier.LOW: {
		"wall_detail": 0.55,
		"minimap_bake_us": 300,
		"vfx_sprites": true,
		"visible_mawlings": 80,
		"unit_shadows": false,
		"swarm_multimesh": true,
		"anim_every_nth": 2,
		"effect_density": 0.5,
		"decor_density": 0.5,
		"corpse_segments": 10,
		"hud_redraw_hz": 20,
		"popup_font_steps": 3,
		"menu_3d": false,
		"menu_msaa": Viewport.MSAA_DISABLED,
		"msaa_3d": Viewport.MSAA_DISABLED,
		"scaling_3d_scale": 0.7,
		"max_fps": 60,
	},
	Tier.MEDIUM: {
		"wall_detail": 0.8,
		"minimap_bake_us": 450,
		"vfx_sprites": true,
		"visible_mawlings": 100,
		"unit_shadows": true,
		"swarm_multimesh": true,
		"anim_every_nth": 1,
		"effect_density": 0.75,
		"decor_density": 0.8,
		"corpse_segments": 12,
		"hud_redraw_hz": 30,
		"popup_font_steps": 3,
		"menu_3d": true,
		"menu_msaa": Viewport.MSAA_2X,
		"msaa_3d": Viewport.MSAA_DISABLED,
		"scaling_3d_scale": 0.85,
		"max_fps": 60,
	},
	Tier.HIGH: {
		"wall_detail": 1.0,
		"minimap_bake_us": 600,
		"vfx_sprites": true,
		"visible_mawlings": 120,
		"unit_shadows": true,
		"swarm_multimesh": true,
		"anim_every_nth": 1,
		"effect_density": 1.0,
		"decor_density": 1.0,
		"corpse_segments": 16,
		"hud_redraw_hz": 0,
		"popup_font_steps": 4,
		"menu_3d": true,
		"menu_msaa": Viewport.MSAA_4X,
		"msaa_3d": Viewport.MSAA_2X,
		"scaling_3d_scale": 1.0,
		"max_fps": 60,
	},
}

## Profil-/Einstellungswert, der die Heuristik übersteuert (-1 = automatisch).
static var override_tier := -1
static var _detected := -1


## Stufe, die das Spiel verwenden soll: Override, sonst (einmal ermittelte) Heuristik.
static func current_tier() -> int:
	if override_tier >= 0:
		return clampi(override_tier, Tier.LOW, Tier.HIGH)
	if _detected < 0:
		_detected = choose_tier(device_info())
	return _detected


## Kopie der Schalter einer Stufe (Aufrufer dürfen sie verändern).
static func settings(tier: int = -1) -> Dictionary:
	if tier < 0:
		tier = current_tier()
	return (PRESETS[clampi(tier, Tier.LOW, Tier.HIGH)] as Dictionary).duplicate()


## Einzelner Schalter der aktuellen Stufe mit Rückfallwert.
static func value(key: String, fallback: Variant = null) -> Variant:
	return settings().get(key, fallback)


static func set_override(tier: int) -> void:
	override_tier = tier if tier >= Tier.LOW and tier <= Tier.HIGH else -1


static func tier_id(tier: int) -> String:
	return TIER_IDS[clampi(tier, Tier.LOW, Tier.HIGH)]


static func tier_name(tier: int) -> String:
	return TIER_NAMES[clampi(tier, Tier.LOW, Tier.HIGH)]


## "low"/"medium"/"high" (oder deutsche Namen) -> Tier; unbekannt -> -1.
static func parse(text: String) -> int:
	var key := text.strip_edges().to_lower()
	for index in TIER_IDS.size():
		if key == TIER_IDS[index] or key == String(TIER_NAMES[index]).to_lower():
			return index
	return -1


## Gerätedaten für die Heuristik; getrennt, damit choose_tier() testbar bleibt.
static func device_info() -> Dictionary:
	var screen := DisplayServer.screen_get_size() if DisplayServer.get_name() != "headless" else Vector2i(1080, 2340)
	var memory := OS.get_memory_info()
	return {
		"os": OS.get_name(),
		"cores": OS.get_processor_count(),
		"cpu": OS.get_processor_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"screen": screen,
		"memory_mb": int(memory.get("physical", 0)) / 1048576,
	}


## Heuristik (bewusst konservativ, per Geräteprofil nachzuschärfen):
## - Desktop/Editor: HOCH.
## - Mobil: Punkte für GPU-Familie, Kernzahl und Arbeitsspeicher;
##   Adreno 7xx/8xx, Mali-G7xx/Immortalis und ≥ 8 GB → HOCH (z. B. Galaxy S25),
##   Adreno 6xx, Mali-G6x/G5x-MC mit ≥ 6 GB → MITTEL, sonst NIEDRIG.
## - Sehr viele Bildpunkte (> 3,2 MP) bei nicht-HOCH senken zusätzlich eine Stufe.
static func choose_tier(info: Dictionary) -> int:
	var os_name := String(info.get("os", ""))
	if os_name in ["Windows", "macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]:
		return Tier.HIGH
	var score := 0
	var adapter := String(info.get("adapter", "")).to_lower()
	var gpu := _gpu_class(adapter)
	score += gpu
	var cores := int(info.get("cores", 4))
	if cores >= 8:
		score += 1
	var memory_mb := int(info.get("memory_mb", 0))
	if memory_mb >= 7500:
		score += 2
	elif memory_mb >= 5500:
		score += 1
	var tier := Tier.LOW
	if score >= 5:
		tier = Tier.HIGH
	elif score >= 3:
		tier = Tier.MEDIUM
	var screen: Vector2i = info.get("screen", Vector2i(1080, 2340))
	if tier != Tier.HIGH and screen.x * screen.y > 3_200_000:
		tier = maxi(Tier.LOW, tier - 1)
	return tier


## 0 = unbekannt/schwach, 1 = Mittelklasse, 2 = aktuelle Oberklasse.
static func _gpu_class(adapter: String) -> int:
	var digits := _first_number(adapter)
	if adapter.contains("adreno"):
		if digits >= 730:
			return 2
		if digits >= 610:
			return 1
		return 0
	if adapter.contains("immortalis"):
		return 2
	if adapter.contains("mali-g"):
		# Mali-G710/G715/G720 und neuer = 2; G57/G68/G77/G78/G610 = 1.
		if digits >= 710:
			return 2
		if digits >= 57:
			return 1
		return 0
	if adapter.contains("xclipse") or adapter.contains("apple"):
		return 2
	if adapter.contains("powervr"):
		return 0
	return 1 if adapter != "" else 0


static func _first_number(text: String) -> int:
	var digits := ""
	for character in text:
		if character >= "0" and character <= "9":
			digits += character
		elif digits != "":
			break
	return int(digits) if digits != "" else 0


## Wendet die Viewport-Schalter an (MSAA, 3D-Skalierung, FPS-Grenze). Die
## Kompatibilitäts-Renderpipeline unterstützt nur bilineare 3D-Skalierung.
static func apply_viewport(viewport: Viewport, values: Dictionary) -> void:
	if viewport == null:
		return
	viewport.msaa_3d = int(values.get("msaa_3d", Viewport.MSAA_DISABLED))
	var scale := clampf(float(values.get("scaling_3d_scale", 1.0)), 0.5, 1.0)
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = scale
	Engine.max_fps = int(values.get("max_fps", 0))


## Anzahl dekorativer Teile nach Dichte (deterministisch: nimmt die ersten n,
## damit derselbe Seed bei derselben Stufe dieselbe Karte ergibt).
static func scaled_count(full: int, density: float) -> int:
	return clampi(int(round(float(full) * clampf(density, 0.0, 1.0))), 0, full)
