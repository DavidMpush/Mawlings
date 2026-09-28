extends RefCounted
## Lautstärke-Regler (Einstellungen): drei Busse Master, Music und SFX.
##
## Profil-Werte volume_master / volume_music / volume_sfx liegen linear bei
## 0,0–1,0 in 5-%-Schritten (Standard 1,0). Der Pegel folgt einer Hörkurve:
## dB = 20·log10(v²), also 50 % ≈ −12 dB, 25 % ≈ −24 dB; 0 schaltet den Bus stumm.
## Music- und SFX-Bus werden zur Laufzeit angelegt (es gibt kein
## default_bus_layout) und schicken auf Master; music.gd und sfx.gd hängen
## ihre Player an diese Busse.

const MASTER := "Master"
const MUSIC := "Music"
const SFX := "SFX"
const KEYS := {"volume_master": MASTER, "volume_music": MUSIC, "volume_sfx": SFX}
const STEP := 0.05
const DEFAULT := 1.0


## Legt Music und SFX an (einmal je Prozess), beide senden auf Master.
static func ensure_buses() -> void:
	for bus_name in [MUSIC, SFX]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, MASTER)


## Rastet auf 5-%-Schritte und begrenzt auf 0..1.
static func snap(value: float) -> float:
	return clampf(roundf(value / STEP) * STEP, 0.0, 1.0)


## Linearer Regler -> dB (Hörkurve), 0 -> -80 dB.
static func to_db(value: float) -> float:
	var v := clampf(value, 0.0, 1.0)
	if v <= 0.001:
		return -80.0
	return linear_to_db(v * v)


## Wert eines Reglers aus einem Einstellungs-Dictionary (Profil oder RunConfig).
## Alte Einträge ohne Regler: "sound": false = Gesamt 0.
static func volume(settings: Dictionary, key: String) -> float:
	var value: Variant = settings.get(key)
	if value is float or value is int:
		return snap(float(value))
	if key == "volume_master" and settings.get("sound") is bool and not bool(settings.sound):
		return 0.0
	return DEFAULT


## Setzt Pegel und Stummschaltung der drei Busse.
static func apply(settings: Dictionary) -> void:
	ensure_buses()
	for key in KEYS:
		var index := AudioServer.get_bus_index(KEYS[key])
		if index < 0:
			continue
		var v := volume(settings, key)
		AudioServer.set_bus_volume_db(index, to_db(v))
		AudioServer.set_bus_mute(index, v <= 0.001)


## Pegel (dB) eines Busses, für Tests.
static func bus_db(bus_name: String) -> float:
	var index := AudioServer.get_bus_index(bus_name)
	return AudioServer.get_bus_volume_db(index) if index >= 0 else 0.0


static func bus_muted(bus_name: String) -> bool:
	var index := AudioServer.get_bus_index(bus_name)
	return index >= 0 and AudioServer.is_bus_mute(index)
