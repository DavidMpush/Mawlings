extends Node3D

# Moorbrut (Etappe 08, HORDE): kleine, geduckte, schnelle Kiefer-Kreaturen in
# Massen. Vertrag: stages/08_flood_difficulty.md (Horde-API). Kind von HuntWorld.
#
# - Reine Daten in gepackten Arrays (kein Knoten je Tier), gedeckelt auf MAX_BROOD.
# - Gezeichnet mit EINER MultiMesh (Mawling-Mesh, creature_anim.gdshader,
#   dunkel-schlammig umgefärbt, giftgelber Rand; Gang/Kiefer über INSTANCE_CUSTOM)
#   plus einer Schatten-MultiMesh und zwei fx_batch-MultiMeshes (Biss, Tod).
#   Alle Instanzdaten gehen pro Frame als ein Puffer an die MultiMesh.
# - Räumliche Gitter (verkettete Listen in PackedInt32Array) um den Schwarm:
#   Mawling-Punkte (Jagd, Biss, Nahkampf), Brut (Separation), Felsen (Kollision).
# - Alles läuft nur in step()/den Schadensaufrufen: Pause friert alles ein.
# - Tod: kleiner Effekt, take_kills() liefert räumlich gebündelte Beute.

const CREATURE_SHADER = preload("res://shaders/creature_anim.gdshader")
const MAWLING_SCENE = preload("res://assets/gameplay/characters/Mawling_game.glb")
const FX_BATCH = preload("res://scripts/fx_batch.gd")

const MAX_BROOD := 160
const DEFAULT_STATS := {"hp": 6.0, "speed": 4.8, "bite": 1.0, "bite_cooldown": 1.2, "biomass": 0.4, "dna": 1}

# Kontakt-Biss: Abstand Brut-Mittelpunkt zu Mawling-Punkt.
const BITE_RANGE := 0.55
# Unterhalb dieses Abstands klammert sich die Brut fest (kaum Vortrieb, Zuschnappen).
const CLING_RANGE := 0.42
const BODY_RADIUS := 0.28
# Wie tief die Brut in den Schwarm eindringen darf, bevor sie hinausgedrängt wird.
const RIM_DEPTH := 0.5
const RIM_PUSH := 1.4
const SEPARATION := 0.58
const SEPARATION_PUSH := 2.2
# Höchstens so viele Nachbarn je Separationsprüfung (Dichte-Deckel für die Leistung).
const SEPARATION_BUDGET := 16
const TURN_RESPONSE := 9.0
const STEER_RESPONSE := 7.0
const APPEAR_SECONDS := 0.35
const SNAP_SECONDS := 0.2
const FLASH_DECAY := 6.0
const KILL_BUNDLE_RADIUS := 2.2

# Gitter um den Schwarm (Weltmeter), ±16,8 m. Punkte: 0,6-m-Zellen, das 3x3-Umfeld
# deckt mindestens die Bissreichweite ab; weiter entfernte Brut läuft zur Mitte.
const GRID := 56
const CELL := 0.6
# Brut-Gitter für die Separation: Zelle ≈ Separationsabstand (3x3 genügt).
const BCELL := 0.6
const BGRID := 56
# Felsen: 2-m-Zellen, ±40 m (Flut-Ring bis ~30 m); wird erst neu gebaut, wenn der Anker 8 m weiter springt.
const OGRID := 40
const OCELL := 2.0
const OANCHOR_STEP := 8.0

# Aussehen: kleiner als Mawlings, flach und lang („geduckt“).
const MODEL_SCALE := 0.66
const MODEL_STRETCH := Vector3(1.12, 0.74, 1.05)
const BODY_TINT := Color(0.11, 0.12, 0.035, 0.97)
const RIM := Color("f4e23a")
const SNAP_COLOR := Color(1.0, 0.95, 0.45, 0.95)
const DEATH_COLOR := Color(0.86, 0.8, 0.26, 0.75)
const DEATH_SPARK := Color(1.0, 0.95, 0.35, 1.0)
const SHADOW_Y := 0.028
const GAIT_RATE := 15.0
# Gangphase läuft in [0, 8 TAU) (Vielfaches von TAU: kein Sprung im Shader).
const GAIT_WRAP := TAU * 8.0
const HOP := 0.07
const MAX_FX := 48
const SNAP_FX_SECONDS := 0.2
const DEATH_FX_SECONDS := 0.34

const STRIDE := 20   # 12 Transform + 4 Farbe + 4 Custom
const SHADOW_STRIDE := 12

var world: Node3D
var swarm: Node3D
var arena: Node3D

# Anzahl lebender Brut; Indizes 0..n-1 sind belegt (Entfernen = Tausch mit dem letzten).
var _n := 0
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _hp := PackedFloat32Array()
var _max_hp := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _bite := PackedFloat32Array()
var _bite_cd := PackedFloat32Array()
var _cd := PackedFloat32Array()
var _yaw := PackedFloat32Array()
var _gait := PackedFloat32Array()
var _walk := PackedFloat32Array()
var _snap := PackedFloat32Array()
var _flash := PackedFloat32Array()
var _appear := PackedFloat32Array()
var _biomass := PackedFloat32Array()
var _dna := PackedInt32Array()
# Leistung: die Logik läuft je Brut jeden zweiten Frame (siehe step()); der
# Separationsschub gilt zwischen seinen Berechnungen weiter.
var _push := PackedVector3Array()
# Quadratischer Abstand zum Zielpunkt aus dem letzten step() (für melee()).
var _near_d2 := PackedFloat32Array()
var _settled := PackedByteArray()
# 1 = Pufferplatz muss im nächsten _draw() sicher neu geschrieben werden (Tausch beim Tod).
var _dirty := PackedByteArray()
var _step_points := -1
var _step_tick := -1
# Größter Abstand eines Mawling-Punkts von der Schwarmmitte (Vorfilter).
var _extent := 0.0
var _indexed_tick := -1

var _kills: Array = []
var _bite_carry := 0.0
var _frame := 0
# Anzahl getroffener Brut beim letzten damage_circle()/damage_nearest() (Statistik der Formen).
var last_hit_count := 0
# Gesamtzahl der Tode und Bisse seit clear() (Tests/Statistik).
var total_kills := 0
var total_bites := 0

# Gitter
var _anchor := Vector3.ZERO
var _center := Vector3.ZERO
var _s_head := PackedInt32Array()
var _s_next := PackedInt32Array()
var _s_points := PackedVector3Array()
var _s_bitten := PackedByteArray()
var _b_head := PackedInt32Array()
var _b_next := PackedInt32Array()
var _o_anchor := Vector3(INF, 0.0, INF)
var _o_head := PackedInt32Array()
var _o_next := PackedInt32Array()
var _o_item := PackedInt32Array()
var _circles := PackedFloat32Array()   # x, z, r

# Darstellung
var _built := false
var _bodies: MultiMeshInstance3D
var _shadows: MultiMeshInstance3D
var _material: ShaderMaterial
var _buffer := PackedFloat32Array()
var _shadow_buffer := PackedFloat32Array()
var _k_x := Vector3.ZERO   # Spalten der Grundbasis (Skalierung * Mesh-Lage)
var _k_y := Vector3.ZERO
var _k_z := Vector3.ZERO
var _k_o := Vector3.ZERO
var _snap_batch: MultiMeshInstance3D
var _death_batch: MultiMeshInstance3D
var _spark_batch: MultiMeshInstance3D
var _fx: Array = []   # {kind 0=Biss 1=Tod, at, age}


func setup(world_node: Node3D, swarm_node: Node3D, arena_node: Node3D) -> void:
	world = world_node
	swarm = swarm_node
	arena = arena_node
	_allocate()
	_build()


func count() -> int:
	return _n


func spawn_ring(center: Vector3, amount: int, radius: float, stats: Dictionary) -> int:
	_allocate()
	_build()
	var room := mini(amount, MAX_BROOD - _n)
	if room <= 0:
		return 0
	var hp := maxf(0.1, float(stats.get("hp", DEFAULT_STATS.hp)))
	var speed := maxf(0.1, float(stats.get("speed", DEFAULT_STATS.speed)))
	var bite := maxf(0.0, float(stats.get("bite", DEFAULT_STATS.bite)))
	var cooldown := maxf(0.05, float(stats.get("bite_cooldown", DEFAULT_STATS.bite_cooldown)))
	var biomass := maxf(0.0, float(stats.get("biomass", DEFAULT_STATS.biomass)))
	var dna := maxi(0, int(stats.get("dna", DEFAULT_STATS.dna)))
	var spawned := 0
	var offset := fposmod(float(_frame) * 0.618034 + center.x * 0.13, 1.0) * TAU
	for k in room:
		var angle := offset + TAU * float(k) / float(room)
		var place := Vector3.INF
		# Bis zu drei Versuche (Radius/Winkel leicht versetzt), sonst ausgelassen.
		for attempt in 3:
			var a := angle + float(attempt) * 0.21
			var r := radius + float(attempt) * 1.3 + 0.6 * sin(float(k) * 2.3)
			var candidate := Vector3(center.x + cos(a) * r, 0.0, center.z + sin(a) * r)
			if _is_open(candidate):
				place = candidate
				break
		if place == Vector3.INF:
			continue
		var i := _n
		_n += 1
		_pos[i] = place
		_vel[i] = Vector3.ZERO
		_hp[i] = hp
		_max_hp[i] = hp
		_speed[i] = speed * (0.92 + 0.16 * fposmod(float(k) * 0.7548777, 1.0))
		_bite[i] = bite
		_bite_cd[i] = cooldown
		# Versetzte Anfangs-Abklingzeit: nicht alle beißen im selben Frame.
		_cd[i] = cooldown * 0.5 * fposmod(float(k) * 0.381966, 1.0)
		var inward := center - place
		_yaw[i] = atan2(inward.x, inward.z) + PI * 0.5
		_gait[i] = fposmod(float(k) * 1.3247, 1.0) * TAU
		_walk[i] = 0.0
		_snap[i] = 0.0
		_flash[i] = 0.0
		_appear[i] = 0.0
		_biomass[i] = biomass
		_dna[i] = dna
		_push[i] = Vector3.ZERO
		_near_d2[i] = INF
		_settled[i] = 0
		_dirty[i] = 1
		spawned += 1
	_draw()
	return spawned


func step(delta: float, swarm_points: PackedVector3Array) -> Dictionary:
	_allocate()
	_build()
	_frame += 1
	var bitten := PackedInt32Array()
	var losses := 0
	_index_points(swarm_points)
	_index_brood()
	_refresh_obstacles()
	var steer2 := 1.0 - exp(-STEER_RESPONSE * delta * 2.0)
	var turn := 1.0 - exp(-TURN_RESPONSE * delta * 2.0)
	var has_points := not swarm_points.is_empty()
	var point_count := swarm_points.size()
	var rocks := _o_anchor.x != INF and arena != null and is_instance_valid(arena)
	_step_points = point_count
	_step_tick = Engine.get_process_frames()
	# Leistung: Arrays und Felder als Lokale (GDScript-Memberzugriff ist ~2x teurer).
	# Beschriebene Arrays werden am Ende zurückgeschrieben (Copy-on-Write).
	var pos := _pos
	var vel := _vel
	var pushes := _push
	var near := _near_d2
	var yaws := _yaw
	var walks := _walk
	var gaits := _gait
	var appears := _appear
	var snaps := _snap
	var flashes := _flash
	var cds := _cd
	var bitten_mark := _s_bitten
	var speeds := _speed
	var bites := _bite
	var bite_cds := _bite_cd
	var points := _s_points
	var s_head := _s_head
	var s_next := _s_next
	var b_head := _b_head
	var b_next := _b_next
	var o_head := _o_head
	var ax := _anchor.x
	var az := _anchor.z
	var center_x := _center.x
	var center_z := _center.z
	var rim := _extent - RIM_DEPTH
	var oax := _o_anchor.x
	var oaz := _o_anchor.z
	var frame := _frame
	var carry := _bite_carry
	var sep2 := SEPARATION * SEPARATION
	var bite2 := BITE_RANGE * BITE_RANGE
	var settled := _settled
	for i in _n:
		# Logik (Ziel, Separation, Kollision, Biss) je Brut nur jeden zweiten Frame
		# (versetzte Hälften) mit doppeltem Zeitschritt. Dazwischen gleitet laufende
		# Brut nur mit ihrem Tempo weiter (flüssige 60-Hz-Darstellung); ruhende
		# Brut (festgebissen/eingekeilt) bleibt stehen.
		var resting := settled[i] == 1
		if ((i + frame) & 1) == 1:
			if not resting:
				var gv := vel[i]
				var gp := pos[i]
				var glide := Vector3(gp.x + gv.x * delta, 0.0, gp.z + gv.z * delta)
				if rocks:
					var gox := (glide.x - oax) / OCELL
					var goz := (glide.z - oaz) / OCELL
					if gox < 0.0 or goz < 0.0 or gox >= OGRID or goz >= OGRID or o_head[int(goz) * OGRID + int(gox)] >= 0:
						glide = _collide(i, glide)
				pos[i] = glide
			continue
		var dt := delta * 2.0
		var steer := steer2
		# Bewegungsanteil dieses Frames: laufende Brut ist im Zwischenframe schon geglitten.
		var move_dt := dt if resting else delta
		var p := pos[i]
		# Gitterzelle ohne floor()-Aufrufe: nur innerhalb (lx, lz >= 0) gültig.
		var lx := (p.x - ax) / CELL
		var lz := (p.z - az) / CELL
		var in_grid := lx >= 1.0 and lz >= 1.0 and lx < GRID - 1 and lz < GRID - 1
		var gx := int(lx)
		var gz := int(lz)
		# Nächster Mawling-Punkt im 3x3-Umfeld (mind. 0,6 m Suchradius).
		var best := -1
		var best_d2 := INF
		if in_grid and has_points:
			for cz in range(gz - 1, gz + 2):
				var row := cz * GRID
				for cx in range(gx - 1, gx + 2):
					var j := s_head[row + cx]
					while j >= 0:
						var q := points[j]
						var dx := q.x - p.x
						var dz := q.z - p.z
						var d2 := dx * dx + dz * dz
						if d2 < best_d2 and bitten_mark[j] == 0:
							best_d2 = d2
							best = j
						j = s_next[j]
		near[i] = best_d2
		var speed := speeds[i]
		var gx_goal := center_x
		var gz_goal := center_z
		if best >= 0:
			var goal := points[best]
			gx_goal = goal.x
			gz_goal = goal.z
		var tx := gx_goal - p.x
		var tz := gz_goal - p.z
		var distance := sqrt(tx * tx + tz * tz)
		var dvx := 0.0
		var dvz := 0.0
		if distance > 0.001 and (has_points or best >= 0):
			var pull := speed / distance
			# Festbeißen: kein Vortrieb mehr, zu nah wird leicht zurückgewichen.
			if best >= 0 and distance < CLING_RANGE:
				pull *= -0.6 if distance < CLING_RANGE * 0.6 else 0.0
			dvx = tx * pull
			dvz = tz * pull
		# Am Schwarmrand bleiben: wer tiefer als der Rand steckt, wird hinausgedrängt.
		if has_points:
			var rx := p.x - center_x
			var rz := p.z - center_z
			var from_center := sqrt(rx * rx + rz * rz)
			if from_center < rim and from_center > 0.01:
				var out := (rim - from_center) / from_center * RIM_PUSH * speed
				dvx += rx * out
				dvz += rz * out
		# Separation (jede zweite Logikrunde, ruhende Brut jede Runde; Nachbarn
		# gedeckelt); der Schub gilt dazwischen weiter.
		if not in_grid:
			pushes[i] = Vector3.ZERO
		elif resting or ((i + frame) >> 1) % 2 == 0:
			var px := 0.0
			var pz := 0.0
			var budget := SEPARATION_BUDGET
			# Innerhalb des Punktgitters (Rand >= 1 m) liegt auch das Brutgitter sicher innen.
			var hx := int((p.x - ax) / BCELL)
			var hz := int((p.z - az) / BCELL)
			for cz in range(hz - 1, hz + 2):
				var row := cz * BGRID
				for cx in range(hx - 1, hx + 2):
					var j := b_head[row + cx]
					while j >= 0 and budget > 0:
						if j != i:
							budget -= 1
							var q := pos[j]
							var dx := p.x - q.x
							var dz := p.z - q.z
							var d2 := dx * dx + dz * dz
							if d2 < sep2:
								if d2 > 0.000001:
									var d := sqrt(d2)
									var w := (SEPARATION - d) / (SEPARATION * d)
									px += dx * w
									pz += dz * w
								else:
									var a := float(i) * 2.39996
									px += cos(a)
									pz += sin(a)
						j = b_next[j]
			pushes[i] = Vector3(px, 0.0, pz)
		var push := pushes[i]
		var sep := speed * SEPARATION_PUSH
		dvx += push.x * sep
		dvz += push.z * sep
		var v := vel[i]
		v.x += (dvx - v.x) * steer
		v.z += (dvz - v.z) * steer
		vel[i] = v
		var next := Vector3(p.x + v.x * move_dt, 0.0, p.z + v.z * move_dt)
		# Schnellprüfung: leere Felsgitterzelle -> kein Funktionsaufruf.
		if rocks:
			var lox := (next.x - oax) / OCELL
			var loz := (next.z - oaz) / OCELL
			if lox < 0.0 or loz < 0.0 or lox >= OGRID or loz >= OGRID or o_head[int(loz) * OGRID + int(lox)] >= 0:
				next = _collide(i, next)
		pos[i] = next
		# Blickrichtung/Gang aus der tatsächlichen Bewegung; beim Festklammern zum Ziel.
		var mx := next.x - p.x
		var mz := next.z - p.z
		var real_speed := sqrt(mx * mx + mz * mz) / move_dt
		if real_speed > 0.3:
			yaws[i] = lerp_angle(yaws[i], atan2(mx, mz) + PI * 0.5, turn)
		elif best >= 0 and distance > 0.05:
			yaws[i] = lerp_angle(yaws[i], atan2(tx, tz) + PI * 0.5, turn)
		var share := real_speed / speed if speed > 0.1 else 0.0
		if share > 1.0:
			share = 1.0
		var walk := walks[i]
		walk += (share - walk) * steer
		walks[i] = walk
		var gait := gaits[i] + dt * GAIT_RATE * walk
		if gait > GAIT_WRAP:
			gait -= GAIT_WRAP
		gaits[i] = gait
		var shown := appears[i]
		if shown < 1.0:
			shown += dt / APPEAR_SECONDS
			if shown > 1.0:
				shown = 1.0
			appears[i] = shown
		var snap := snaps[i]
		if snap > 0.0:
			snap -= dt / SNAP_SECONDS
			snaps[i] = snap if snap > 0.0 else 0.0
		var flash := flashes[i]
		if flash > 0.0:
			flash -= FLASH_DECAY * dt
			flashes[i] = flash if flash > 0.0 else 0.0
		# Kontakt-Biss nach Abklingzeit, nur voll erschienen, je Punkt ein Biss pro Frame.
		var cd := cds[i] - dt
		if cd <= 0.0:
			cd = 0.0
			if best >= 0 and shown >= 1.0 and bitten_mark[best] == 0:
				var q := points[best]
				var bx := q.x - next.x
				var bz := q.z - next.z
				if bx * bx + bz * bz < bite2:
					bitten_mark[best] = 1
					total_bites += 1
					# Bruchteile (Biss < 1) sammeln sich; ein Index wird erst gemeldet,
					# wenn der Biss mindestens einen ganzen Verlust auslöst.
					carry += bites[i]
					var whole := int(floor(carry + 0.0001))
					carry -= float(whole)
					if whole > 0:
						bitten.append(best)
						losses += whole
					cd = bite_cds[i]
					snaps[i] = 1.0
					_add_fx(0, Vector3((q.x + next.x) * 0.5, 0.0, (q.z + next.z) * 0.5))
		cds[i] = cd
		# Ruhend = festgebissen oder im Gedränge eingekeilt (< 1 m/s).
		settled[i] = 1 if v.x * v.x + v.z * v.z < 1.0 and shown >= 1.0 else 0
	_settled = settled
	_pos = pos
	_vel = vel
	_push = pushes
	_near_d2 = near
	_yaw = yaws
	_walk = walks
	_gait = gaits
	_appear = appears
	_snap = snaps
	_flash = flashes
	_cd = cds
	_s_bitten = bitten_mark
	_bite_carry = carry
	_step_fx(delta)
	_draw()
	return {"bitten_indices": bitten, "losses": losses}


func damage_circle(center: Vector3, radius: float, amount: float) -> int:
	last_hit_count = 0
	if _n == 0 or amount <= 0.0 or radius <= 0.0:
		return 0
	var r2 := radius * radius
	var killed := 0
	var i := _n - 1
	while i >= 0:
		var p := _pos[i]
		var dx := p.x - center.x
		var dz := p.z - center.z
		if dx * dx + dz * dz <= r2:
			last_hit_count += 1
			if _hurt(i, amount):
				killed += 1
		i -= 1
	return killed


func damage_nearest(point: Vector3, max_range: float, amount: float) -> Vector3:
	last_hit_count = 0
	var i := _nearest_index(point, max_range)
	if i < 0:
		return Vector3.INF
	var hit := _pos[i]
	last_hit_count = 1
	if amount > 0.0:
		_hurt(i, amount)
	return hit


func melee(swarm_points: PackedVector3Array, reach: float, dps: float, delta: float) -> int:
	if _n == 0 or swarm_points.is_empty() or dps <= 0.0 or delta <= 0.0 or reach <= 0.0:
		return 0
	# Innerhalb eines Frames nach step() (oder direkt davor, mit den Abständen des
	# letzten Frames) und gleicher Punktzahl: Zielabstände aus step() wiederverwenden;
	# nur Brut ohne bekannten Kontakt sucht selbst im Gitter.
	var cached := _step_tick >= 0 and Engine.get_process_frames() - _step_tick <= 1 and _step_points == swarm_points.size()
	_index_points(swarm_points)
	var amount := dps * delta
	var r2 := reach * reach
	var span := int(ceil(reach / CELL))
	var outer := _extent + reach + 0.1
	var killed := 0
	var i := _n - 1
	while i >= 0:
		var p := _pos[i]
		if cached and _near_d2[i] <= r2:
			if _hurt(i, amount):
				killed += 1
			i -= 1
			continue
		if (p.x - _center.x) * (p.x - _center.x) + (p.z - _center.z) * (p.z - _center.z) > outer * outer:
			i -= 1
			continue
		var gx := int(floor((p.x - _anchor.x) / CELL))
		var gz := int(floor((p.z - _anchor.z) / CELL))
		var touched := false
		if gx >= -span and gz >= -span and gx < GRID + span and gz < GRID + span:
			for cz in range(maxi(0, gz - span), mini(GRID, gz + span + 1)):
				if touched:
					break
				var row := cz * GRID
				for cx in range(maxi(0, gx - span), mini(GRID, gx + span + 1)):
					var j := _s_head[row + cx]
					while j >= 0:
						var q := _s_points[j]
						var dx := q.x - p.x
						var dz := q.z - p.z
						if dx * dx + dz * dz <= r2:
							touched = true
							break
						j = _s_next[j]
					if touched:
						break
		if touched and _hurt(i, amount):
			killed += 1
		i -= 1
	return killed


func take_kills() -> Array:
	if _kills.is_empty():
		return []
	# Nahe Tode zu einem Eintrag bündeln (weniger Kadaver, Ressourcen bleiben erhalten).
	var bundles: Array = []
	for kill in _kills:
		var merged := false
		for bundle in bundles:
			var at: Vector3 = bundle.position
			if Vector2(at.x - kill.position.x, at.z - kill.position.z).length() <= KILL_BUNDLE_RADIUS:
				var weight: float = float(bundle.count)
				bundle.position = (at * weight + kill.position) / (weight + 1.0)
				bundle.biomass += kill.biomass
				bundle.dna += kill.dna
				bundle.count += 1
				merged = true
				break
		if not merged:
			bundles.append({"position": kill.position, "biomass": kill.biomass, "dna": kill.dna, "count": 1})
	_kills.clear()
	return bundles


func nearest(point: Vector3) -> Vector3:
	var i := _nearest_index(point, INF)
	return _pos[i] if i >= 0 else Vector3.INF


func positions() -> PackedVector3Array:
	return _pos.slice(0, _n)


func clear() -> void:
	_n = 0
	_step_tick = -1
	_indexed_tick = -1
	_kills.clear()
	_bite_carry = 0.0
	last_hit_count = 0
	total_kills = 0
	total_bites = 0
	for entry in _fx:
		entry.age = INF
	_fx.clear()
	if _built:
		_draw()
		_draw_fx()


# ---------------------------------------------------------------- Kern

func _hurt(i: int, amount: float) -> bool:
	var hp := _hp[i] - amount
	_hp[i] = hp
	# Kleine Dauerschäden (Aura) nur zart aufleuchten lassen, Treffer deutlich.
	var strength := 1.0 if amount >= _max_hp[i] * 0.25 else 0.35
	_flash[i] = maxf(_flash[i], strength)
	if hp > 0.0:
		return false
	_kill(i)
	return true


func _kill(i: int) -> void:
	var at := _pos[i]
	_kills.append({"position": at, "biomass": _biomass[i], "dna": _dna[i]})
	total_kills += 1
	_add_fx(1, at)
	var last := _n - 1
	if i != last:
		_pos[i] = _pos[last]
		_vel[i] = _vel[last]
		_hp[i] = _hp[last]
		_max_hp[i] = _max_hp[last]
		_speed[i] = _speed[last]
		_bite[i] = _bite[last]
		_bite_cd[i] = _bite_cd[last]
		_cd[i] = _cd[last]
		_yaw[i] = _yaw[last]
		_gait[i] = _gait[last]
		_walk[i] = _walk[last]
		_snap[i] = _snap[last]
		_flash[i] = _flash[last]
		_appear[i] = _appear[last]
		_biomass[i] = _biomass[last]
		_dna[i] = _dna[last]
		_push[i] = _push[last]
		_near_d2[i] = _near_d2[last]
		_settled[i] = _settled[last]
		_dirty[i] = 1
	_n = last


func _nearest_index(point: Vector3, max_range: float) -> int:
	var best := -1
	var best_d2 := max_range * max_range if max_range < INF else INF
	for i in _n:
		var p := _pos[i]
		var dx := p.x - point.x
		var dz := p.z - point.z
		var d2 := dx * dx + dz * dz
		if d2 <= best_d2:
			best_d2 = d2
			best = i
	return best


func _allocate() -> void:
	if _pos.size() == MAX_BROOD:
		return
	_pos.resize(MAX_BROOD)
	_vel.resize(MAX_BROOD)
	_hp.resize(MAX_BROOD)
	_max_hp.resize(MAX_BROOD)
	_speed.resize(MAX_BROOD)
	_bite.resize(MAX_BROOD)
	_bite_cd.resize(MAX_BROOD)
	_cd.resize(MAX_BROOD)
	_yaw.resize(MAX_BROOD)
	_gait.resize(MAX_BROOD)
	_walk.resize(MAX_BROOD)
	_snap.resize(MAX_BROOD)
	_flash.resize(MAX_BROOD)
	_appear.resize(MAX_BROOD)
	_biomass.resize(MAX_BROOD)
	_dna.resize(MAX_BROOD)
	_push.resize(MAX_BROOD)
	_near_d2.resize(MAX_BROOD)
	_settled.resize(MAX_BROOD)
	_dirty.resize(MAX_BROOD)
	_s_head.resize(GRID * GRID)
	_b_head.resize(BGRID * BGRID)
	_b_next.resize(MAX_BROOD)
	_o_head.resize(OGRID * OGRID)
	_o_head.fill(-1)


# Mawling-Punkte ins Gitter (Anker = Schwarmmitte, bei jedem Aufruf neu).
func _index_points(points: PackedVector3Array) -> void:
	var count := points.size()
	# Im selben Frame schon mit denselben Punkten indiziert (melee() vor step()): überspringen.
	var tick := Engine.get_process_frames()
	if tick == _indexed_tick and count == _s_points.size() and count > 0 			and points[0] == _s_points[0] and points[count - 1] == _s_points[count - 1]:
		_s_bitten.fill(0)
		return
	_indexed_tick = tick
	if count > 0:
		var sum := Vector3.ZERO
		for point in points:
			sum += point
		_center = Vector3(sum.x / float(count), 0.0, sum.z / float(count))
		var widest := 0.0
		for point in points:
			widest = maxf(widest, (point.x - _center.x) * (point.x - _center.x) + (point.z - _center.z) * (point.z - _center.z))
		_extent = sqrt(widest)
	else:
		_extent = 0.0
	if count == 0 and swarm != null and is_instance_valid(swarm) and swarm.is_inside_tree():
		_center = Vector3(swarm.global_position.x, 0.0, swarm.global_position.z)
	var half := float(GRID) * CELL * 0.5
	_anchor = Vector3(floor(_center.x / CELL) * CELL - half, 0.0, floor(_center.z / CELL) * CELL - half)
	_s_points = points
	_s_head.fill(-1)
	_s_next.resize(count)
	_s_bitten.resize(count)
	_s_bitten.fill(0)
	for j in count:
		var q := points[j]
		var gx := int(floor((q.x - _anchor.x) / CELL))
		var gz := int(floor((q.z - _anchor.z) / CELL))
		if gx < 0 or gz < 0 or gx >= GRID or gz >= GRID:
			_s_next[j] = -1
			continue
		var cell := gz * GRID + gx
		_s_next[j] = _s_head[cell]
		_s_head[cell] = j


func _index_brood() -> void:
	_b_head.fill(-1)
	for i in _n:
		var p := _pos[i]
		var gx := int(floor((p.x - _anchor.x) / BCELL))
		var gz := int(floor((p.z - _anchor.z) / BCELL))
		if gx < 0 or gz < 0 or gx >= BGRID or gz >= BGRID:
			_b_next[i] = -1
			continue
		var cell := gz * BGRID + gx
		_b_next[i] = _b_head[cell]
		_b_head[cell] = i


# Felskreise der Arena in ein grobes Gitter um den Schwarm (nur bei Ankersprung).
func _refresh_obstacles() -> void:
	if arena == null or not is_instance_valid(arena) or not arena.has_method("obstacles"):
		return
	var half := float(OGRID) * OCELL * 0.5
	var anchor := Vector3(floor(_center.x / OANCHOR_STEP) * OANCHOR_STEP - half, 0.0, floor(_center.z / OANCHOR_STEP) * OANCHOR_STEP - half)
	if anchor == _o_anchor:
		return
	_o_anchor = anchor
	_o_head.fill(-1)
	_o_next.resize(0)
	_o_item.resize(0)
	_circles.resize(0)
	var arena_cell: float = float(arena.get("CELL")) if arena.get("CELL") != null else 28.0
	var span := float(OGRID) * OCELL
	var from := Vector2i(floori((anchor.x - 4.0) / arena_cell), floori((anchor.z - 4.0) / arena_cell))
	var to := Vector2i(floori((anchor.x + span + 4.0) / arena_cell), floori((anchor.z + span + 4.0) / arena_cell))
	for x in range(from.x, to.x + 1):
		for z in range(from.y, to.y + 1):
			for circle in arena.obstacles(Vector2i(x, z)):
				var reach: float = circle.w + BODY_RADIUS
				var min_x := int(floor((circle.x - reach - anchor.x) / OCELL))
				var max_x := int(floor((circle.x + reach - anchor.x) / OCELL))
				var min_z := int(floor((circle.z - reach - anchor.z) / OCELL))
				var max_z := int(floor((circle.z + reach - anchor.z) / OCELL))
				if max_x < 0 or max_z < 0 or min_x >= OGRID or min_z >= OGRID:
					continue
				var index := _circles.size() / 3
				_circles.append(circle.x)
				_circles.append(circle.z)
				_circles.append(circle.w)
				for cz in range(maxi(0, min_z), mini(OGRID, max_z + 1)):
					for cx in range(maxi(0, min_x), mini(OGRID, max_x + 1)):
						var cell := cz * OGRID + cx
						_o_item.append(index)
						_o_next.append(_o_head[cell])
						_o_head[cell] = _o_item.size() - 1


# Schiebt eine Brut aus Felsen heraus. Im Felsgitter pro Frame (billig: meist 0-1
# Kreise je Zelle); weit draußen alle 4 Frames über arena.resolve_motion.
func _collide(i: int, next: Vector3) -> Vector3:
	if arena == null or not is_instance_valid(arena):
		return next
	var gx := int(floor((next.x - _o_anchor.x) / OCELL))
	var gz := int(floor((next.z - _o_anchor.z) / OCELL))
	if gx < 0 or gz < 0 or gx >= OGRID or gz >= OGRID:
		if (i + _frame) % 4 == 0 and arena.has_method("resolve_motion"):
			return arena.resolve_motion(next, Vector3.ZERO, BODY_RADIUS)
		return next
	for attempt in 2:
		var moved := false
		var e := _o_head[gz * OGRID + gx]
		while e >= 0:
			var c := _o_item[e] * 3
			var dx := next.x - _circles[c]
			var dz := next.z - _circles[c + 1]
			var minimum := _circles[c + 2] + BODY_RADIUS
			var d2 := dx * dx + dz * dz
			if d2 < minimum * minimum:
				var d := sqrt(d2)
				if d > 0.0001:
					next.x = _circles[c] + dx / d * minimum
					next.z = _circles[c + 1] + dz / d * minimum
				else:
					next.x = _circles[c] + minimum
				moved = true
			e = _o_next[e]
		if not moved:
			break
		gx = int(floor((next.x - _o_anchor.x) / OCELL))
		gz = int(floor((next.z - _o_anchor.z) / OCELL))
		if gx < 0 or gz < 0 or gx >= OGRID or gz >= OGRID:
			break
	return next


func _is_open(location: Vector3) -> bool:
	if arena == null or not is_instance_valid(arena) or not arena.has_method("is_open"):
		return true
	return arena.is_open(location, BODY_RADIUS + 0.1)


# ---------------------------------------------------------------- Darstellung

func _build() -> void:
	if _built:
		return
	_built = true
	var sample: Node3D = MAWLING_SCENE.instantiate()
	var piece: MeshInstance3D = sample.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh := piece.mesh
	var mesh_local := Transform3D.IDENTITY
	var node: Node = piece
	while node != sample:
		mesh_local = (node as Node3D).transform * mesh_local
		node = node.get_parent()
	sample.free()
	var base := Transform3D(Basis.from_scale(MODEL_STRETCH * MODEL_SCALE), Vector3.ZERO) * mesh_local
	_k_x = base.basis.x
	_k_y = base.basis.y
	_k_z = base.basis.z
	_k_o = base.origin
	_material = _creature_material()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = MAX_BROOD
	multimesh.visible_instance_count = 0
	_bodies = MultiMeshInstance3D.new()
	_bodies.name = "Moorbrut"
	_bodies.multimesh = multimesh
	_bodies.material_override = _material
	_bodies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bodies)
	_bodies.top_level = true
	_bodies.global_transform = Transform3D.IDENTITY
	_buffer.resize(MAX_BROOD * STRIDE)
	_buffer.fill(0.0)
	# Konstante Einträge einmalig: Farb-Alpha und Custom.w.
	for i in MAX_BROOD:
		_buffer[i * STRIDE + 15] = 1.0

	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var shadow_multimesh := MultiMesh.new()
	shadow_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	shadow_multimesh.mesh = plane
	shadow_multimesh.instance_count = MAX_BROOD
	shadow_multimesh.visible_instance_count = 0
	_shadows = MultiMeshInstance3D.new()
	_shadows.name = "Moorbrut shadows"
	_shadows.multimesh = shadow_multimesh
	_shadows.material_override = _shadow_material()
	_shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadows)
	_shadows.top_level = true
	_shadows.global_transform = Transform3D.IDENTITY
	_shadow_buffer.resize(MAX_BROOD * SHADOW_STRIDE)
	_shadow_buffer.fill(0.0)
	# Schatten liegen flach: nur Größe (0, 10) und Lage (3, 11) ändern sich.
	for i in MAX_BROOD:
		_shadow_buffer[i * SHADOW_STRIDE + 5] = 1.0
		_shadow_buffer[i * SHADOW_STRIDE + 7] = SHADOW_Y

	var torus := TorusMesh.new()
	torus.inner_radius = 0.72
	torus.outer_radius = 1.0
	torus.rings = 20
	torus.ring_segments = 4
	_snap_batch = _fx_batch(torus, MAX_FX, "Moorbrut bites")
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 0.6
	puff.radial_segments = 8
	puff.rings = 4
	_death_batch = _fx_batch(puff, MAX_FX, "Moorbrut deaths")
	var spark := SphereMesh.new()
	spark.radius = 0.12
	spark.height = 0.24
	spark.radial_segments = 6
	spark.rings = 3
	_spark_batch = _fx_batch(spark, MAX_FX * 4, "Moorbrut death sparks")


func _fx_batch(mesh: Mesh, capacity: int, node_name: String) -> MultiMeshInstance3D:
	var batch := FX_BATCH.create(mesh, capacity, true, true, node_name)
	add_child(batch)
	batch.top_level = true
	batch.global_transform = Transform3D.IDENTITY
	return batch


func _draw() -> void:
	if not _built:
		return
	var buffer := _buffer
	var shadow := _shadow_buffer
	var pos := _pos
	var yaws := _yaw
	var appears := _appear
	var walks := _walk
	var gaits := _gait
	var snaps := _snap
	var flashes := _flash
	var kxx := _k_x.x
	var kxy := _k_x.y
	var kxz := _k_x.z
	var kyx := _k_y.x
	var kyy := _k_y.y
	var kyz := _k_y.z
	var kzx := _k_z.x
	var kzy := _k_z.y
	var kzz := _k_z.z
	var kox := _k_o.x
	var koy := _k_o.y
	var koz := _k_o.z
	var settled := _settled
	var dirty := _dirty
	var frame := _frame
	for i in _n:
		# Ruhende Brut bewegt sich nur in ihren Logikframes: dazwischen bleibt ihr
		# Pufferplatz stehen (Kiefer/Aufblitzen laufen dann mit 30 Hz).
		if settled[i] == 1 and dirty[i] == 0 and ((i + frame) & 1) == 1:
			continue
		dirty[i] = 0
		var p := pos[i]
		var yaw := yaws[i]
		var c := cos(yaw)
		var s := sin(yaw)
		var grow := appears[i]
		if grow < 1.0:
			var g := grow - 1.0
			grow = 1.0 + 2.70158 * g * g * g + 1.70158 * g * g
		var walk := walks[i]
		var gait := gaits[i]
		var snap := snaps[i]
		var hop := absf(sin(gait)) * HOP * walk
		# Zuschnappen: kurzer Vorstoß des Kopfes (Kopf zeigt lokal nach -X).
		var lunge := sin(snap * PI) * 0.14
		# Spalten B = R(yaw) * K * grow
		var cg := c * grow
		var sg := s * grow
		var k := i * STRIDE
		buffer[k] = cg * kxx + sg * kxz
		buffer[k + 1] = cg * kyx + sg * kyz
		buffer[k + 2] = cg * kzx + sg * kzz
		buffer[k + 3] = p.x + cg * kox + sg * koz - c * lunge
		buffer[k + 4] = kxy * grow
		buffer[k + 5] = kyy * grow
		buffer[k + 6] = kzy * grow
		buffer[k + 7] = koy * grow + hop
		buffer[k + 8] = cg * kxz - sg * kxx
		buffer[k + 9] = cg * kyz - sg * kyx
		buffer[k + 10] = cg * kzz - sg * kzx
		buffer[k + 11] = p.z + cg * koz - sg * kox + s * lunge
		var flash := flashes[i]
		var glow := 1.0 + flash * 1.4
		buffer[k + 12] = glow
		buffer[k + 13] = glow
		buffer[k + 14] = glow * (1.0 - 0.25 * flash)
		buffer[k + 16] = walk
		buffer[k + 17] = gait + PI * 0.5
		var jaw := 0.18 * walk
		buffer[k + 18] = snap if snap > jaw else jaw
		var size := 0.62 * grow * (1.0 - hop * 2.0)
		var m := i * SHADOW_STRIDE
		shadow[m] = size
		shadow[m + 3] = p.x
		shadow[m + 10] = size * 1.15
		shadow[m + 11] = p.z
	_buffer = buffer
	_shadow_buffer = shadow
	_dirty = dirty
	_bodies.multimesh.buffer = buffer
	_bodies.multimesh.visible_instance_count = _n
	_shadows.multimesh.buffer = shadow
	_shadows.multimesh.visible_instance_count = _n
	_bodies.visible = _n > 0
	_shadows.visible = _n > 0


func _add_fx(kind: int, at: Vector3) -> void:
	if _fx.size() >= MAX_FX:
		var oldest := 0
		for index in _fx.size():
			if _fx[index].age > _fx[oldest].age:
				oldest = index
		_fx.remove_at(oldest)
	_fx.append({"kind": kind, "at": at, "age": 0.0, "seed": float(total_kills + _frame) * 0.618034})


func _step_fx(delta: float) -> void:
	var index := _fx.size() - 1
	while index >= 0:
		var entry: Dictionary = _fx[index]
		entry.age += delta
		var life := SNAP_FX_SECONDS if entry.kind == 0 else DEATH_FX_SECONDS
		if entry.age >= life:
			_fx.remove_at(index)
		index -= 1
	_draw_fx()


func _draw_fx() -> void:
	if not _built:
		return
	_snap_batch.begin()
	_death_batch.begin()
	_spark_batch.begin()
	for entry in _fx:
		var at: Vector3 = entry.at
		if entry.kind == 0:
			var t: float = entry.age / SNAP_FX_SECONDS
			var r := lerpf(0.18, 0.5, 1.0 - pow(1.0 - t, 2.0))
			_snap_batch.add(Transform3D(Basis.from_scale(Vector3(r, 0.5, r)), Vector3(at.x, 0.3, at.z)),
				Color(SNAP_COLOR.r, SNAP_COLOR.g, SNAP_COLOR.b, SNAP_COLOR.a * (1.0 - t)))
		else:
			var t: float = entry.age / DEATH_FX_SECONDS
			var puff := lerpf(0.35, 0.95, 1.0 - pow(1.0 - t, 3.0))
			_death_batch.add(Transform3D(Basis.from_scale(Vector3(puff, puff * 0.55, puff)), Vector3(at.x, 0.18, at.z)),
				Color(DEATH_COLOR.r, DEATH_COLOR.g, DEATH_COLOR.b, DEATH_COLOR.a * (1.0 - t) * (1.0 - t)))
			var spark_seed: float = entry.seed
			for k in 4:
				var a := spark_seed * TAU + float(k) * TAU * 0.25
				var reach := 0.2 + t * 0.75
				var lift := 0.2 + sin(t * PI) * 0.45
				var size := 1.0 - t * 0.7
				_spark_batch.add(Transform3D(Basis.from_scale(Vector3.ONE * size), Vector3(at.x + cos(a) * reach, lift, at.z + sin(a) * reach)),
					Color(DEATH_SPARK.r, DEATH_SPARK.g, DEATH_SPARK.b, DEATH_SPARK.a * (1.0 - t)))
	_snap_batch.finish()
	_death_batch.finish()
	_spark_batch.finish()


func _creature_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CREATURE_SHADER
	material.set_shader_parameter("use_instance_custom", true)
	material.set_shader_parameter("brightness", 1.0)
	material.set_shader_parameter("saturation", 1.0)
	material.set_shader_parameter("shape_light", 0.4)
	material.set_shader_parameter("body_tint", BODY_TINT)
	material.set_shader_parameter("rim_color", RIM)
	material.set_shader_parameter("rim_strength", 1.0)
	material.set_shader_parameter("rim_power", 3.2)
	material.set_shader_parameter("outline_strength", 0.95)
	material.set_shader_parameter("flash_color", Color("fff3b0"))
	material.set_shader_parameter("flash", 0.0)
	# Gleicher Glieder-/Kiefer-Rahmen wie swarm.gd (Mawling_game.glb, Z-up-Rohdaten).
	material.set_shader_parameter("up_axis", Vector3(0.0, 0.0, -1.0))
	material.set_shader_parameter("forward_axis", Vector3(-1.0, 0.0, 0.0))
	material.set_shader_parameter("ground_offset", -0.0008)
	material.set_shader_parameter("foot_a_front", Vector2(0.239, -0.287))
	material.set_shader_parameter("foot_a_back", Vector2(-0.286, 0.205))
	material.set_shader_parameter("foot_b_front", Vector2(0.063, 0.239))
	material.set_shader_parameter("foot_b_back", Vector2(-0.052, -0.191))
	material.set_shader_parameter("foot_radius", 0.15)
	material.set_shader_parameter("leg_height", 0.22)
	material.set_shader_parameter("stride", 0.1)
	material.set_shader_parameter("lift", 0.08)
	material.set_shader_parameter("stride_centering", 0.5)
	material.set_shader_parameter("walk_speed", 0.0)
	material.set_shader_parameter("walk_amount", 0.0)
	material.set_shader_parameter("walk_scale", 1.0)
	material.set_shader_parameter("jaw_hinge_forward", 0.12)
	material.set_shader_parameter("jaw_hinge_height", 0.47)
	material.set_shader_parameter("jaw_floor", 0.22)
	material.set_shader_parameter("jaw_angle", 0.75)
	material.set_shader_parameter("bite_amount", 0.0)
	material.set_shader_parameter("tail_start", -0.34)
	material.set_shader_parameter("tail_length", 0.26)
	material.set_shader_parameter("tail_floor", 0.1)
	material.set_shader_parameter("tail_swing", 0.09)
	material.set_shader_parameter("tail_rate", 7.0)
	return material


func _shadow_material() -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 1), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 32
	texture.height = 32
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(0, 0, 0, 0.42)
	material.albedo_texture = texture
	material.render_priority = 1
	return material
