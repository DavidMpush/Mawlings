extends Node3D

# Stage 19: hands the attack forms two broods at once - the Moorbrut horde
# (scripts/horde.gd) and the desert sand grubs (scripts/sandgrub.gd). Same
# calls as a single horde (attack_forms.set_horde): count, positions, nearest,
# damage_circle, damage_nearest and last_hit_count; either side may be null.

var first: Node3D
var second: Node3D
var last_hit_count := 0


func setup(a: Node3D, b: Node3D) -> void:
	first = a
	second = b


func _parts() -> Array:
	var result := []
	for part in [first, second]:
		if part != null and is_instance_valid(part):
			result.append(part)
	return result


func count() -> int:
	var total := 0
	for part in _parts():
		total += int(part.call("count"))
	return total


func positions() -> PackedVector3Array:
	var result := PackedVector3Array()
	for part in _parts():
		if int(part.call("count")) > 0:
			result.append_array(part.call("positions"))
	return result


func nearest(point: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_distance := INF
	for part in _parts():
		if int(part.call("count")) <= 0:
			continue
		var candidate: Vector3 = part.call("nearest", point)
		if candidate == Vector3.INF:
			continue
		var distance := Vector2(candidate.x - point.x, candidate.z - point.z).length()
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


func damage_circle(center: Vector3, radius: float, amount: float) -> int:
	var hits := 0
	for part in _parts():
		if int(part.call("count")) > 0:
			hits += int(part.call("damage_circle", center, radius, amount))
	last_hit_count = hits
	return hits


func damage_nearest(point: Vector3, max_range: float, amount: float) -> Vector3:
	var target := nearest(point)
	last_hit_count = 0
	if target == Vector3.INF or Vector2(target.x - point.x, target.z - point.z).length() > max_range:
		return Vector3.INF
	for part in _parts():
		if int(part.call("count")) <= 0:
			continue
		var candidate: Vector3 = part.call("nearest", point)
		if candidate == target:
			var struck: Vector3 = part.call("damage_nearest", point, max_range, amount)
			last_hit_count = int(part.get("last_hit_count")) if "last_hit_count" in part else (1 if struck != Vector3.INF else 0)
			return struck
	return Vector3.INF
