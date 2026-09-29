extends Control

# Etappe 37 (user request): damage numbers. Instead of hooking every damage
# path (melee, attack forms, abilities, relics, items, poison), this HUD layer
# polls the health of the living targets of HuntWorld (_living_targets) at
# POLL_HZ and turns every loss into a floating number. A swarm bites
# continuously, so losses are gathered per target over GATHER_SECONDS and shown
# as one number; big hits (share of the target's max HP) pop larger and gold,
# boss hits orange. At most MAX_POPUPS at once (the oldest make room).
# The horde (Moorbrut) is not shown (hundreds of tiny hits would flood the
# screen; their kills already burst into crystals).

const UiStyle := preload("res://scripts/ui/ui_style.gd")

const POLL_HZ := 20.0
const GATHER_SECONDS := 0.5
const LIFE := 0.8
const RISE := 56.0
const MAX_POPUPS := 30
const BIG_SHARE := 0.2        # >= 20 % of max HP in one number = big hit
const MIN_SHOWN := 0.5
const NORMAL := Color("fff6e8")
const BIG := Color("ffd23c")
const BOSS := Color("ff9a3c")

var enabled := true
var _world: Node
var _clock := 0.0
# instance id -> {"hp": last health, "acc": gathered loss, "age": gather clock,
# "node": weakref, "max": max health, "boss": bool}
var _tracked: Dictionary = {}
# {"text", "at" (screen), "age", "color", "size", "world" (Vector3)}
var _popups: Array[Dictionary] = []
var _jitter_step := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if _world == null or not is_instance_valid(_world):
		_world = _find_world()
		if _world == null:
			return
	var hud := get_parent()
	var paused: bool = hud != null and (bool(hud.get("paused")) or bool(hud.get("extinct")))
	if not enabled or paused:
		if not _popups.is_empty() and not enabled:
			_popups.clear()
			queue_redraw()
		return
	_clock += delta
	if _clock >= 1.0 / POLL_HZ:
		_poll(_clock)
		_clock = 0.0
	if _popups.is_empty():
		return
	for index in range(_popups.size() - 1, -1, -1):
		_popups[index].age += delta
		if float(_popups[index].age) >= LIFE:
			_popups.remove_at(index)
	queue_redraw()


func _find_world() -> Node:
	var node: Node = get_parent()
	while node != null:
		var found := node.get_node_or_null("HuntWorld")
		if found != null:
			return found
		node = node.get_parent()
	return null


# Health deltas of every living target since the last poll.
func _poll(step: float) -> void:
	if not _world.has_method("_living_targets"):
		return
	var seen := {}
	for target in _world._living_targets():
		if target == null or not is_instance_valid(target):
			continue
		var id: int = target.get_instance_id()
		seen[id] = true
		var hp: float = float(target.get("health"))
		if not _tracked.has(id):
			var top: Variant = target.get("max_health")
			_tracked[id] = {"hp": hp, "acc": 0.0, "age": 0.0, "node": weakref(target), "max": float(top) if top != null else maxf(hp, 1.0), "boss": top != null and float(top) >= 1000.0}
			continue
		var entry: Dictionary = _tracked[id]
		var lost: float = float(entry.hp) - hp
		entry.hp = hp
		if lost > 0.0:
			entry.acc = float(entry.acc) + lost
		entry.age = float(entry.age) + step
		if float(entry.acc) > 0.0 and (float(entry.age) >= GATHER_SECONDS or hp <= 0.0):
			_flush(entry, target)
	# Targets that died since the last poll: show what they lost in between.
	for id in _tracked.keys():
		if seen.has(id):
			continue
		var entry: Dictionary = _tracked[id]
		var node: Object = (entry.node as WeakRef).get_ref()
		if node != null and is_instance_valid(node):
			var lost: float = float(entry.hp) - maxf(0.0, float(node.get("health")))
			if lost > 0.0:
				entry.acc = float(entry.acc) + lost
			if float(entry.acc) > 0.0:
				_flush(entry, node)
		_tracked.erase(id)


func _flush(entry: Dictionary, target: Object) -> void:
	var amount: float = float(entry.acc)
	entry.acc = 0.0
	entry.age = 0.0
	if amount < MIN_SHOWN or not (target is Node3D):
		return
	var at3: Vector3 = (target as Node3D).global_position + Vector3(0.0, 1.6, 0.0)
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(at3):
		return
	var at: Vector2 = camera.unproject_position(at3)
	if not Rect2(Vector2.ZERO, size).grow(40.0).has_point(at):
		return
	var big: bool = amount >= float(entry.max) * BIG_SHARE and not bool(entry.boss)
	var tint: Color = BOSS if bool(entry.boss) else (BIG if big else NORMAL)
	var font_size: int = int(clampf(38.0 + 10.0 * log(maxf(1.0, amount)) / log(10.0), 38.0, 70.0)) + (8 if big else 0)
	if _popups.size() >= MAX_POPUPS:
		_popups.pop_front()
	# A little sideways jitter so gathered numbers of neighbours do not stack.
	# Sideways jitter per number (golden-ratio walk) so repeated numbers of one
	# target fan out instead of stacking.
	_jitter_step += 1
	var jitter := Vector2(fposmod(float(_jitter_step) * 0.618034, 1.0) * 70.0 - 35.0, fposmod(float(_jitter_step) * 0.381966, 1.0) * 20.0 - 10.0)
	_popups.append({"text": format_amount(amount), "at": at + jitter, "age": 0.0, "color": tint, "size": font_size})


## "7", "1.234", "12,3K", "1,2M" (German separators).
static func format_amount(value: float) -> String:
	if value >= 1_000_000.0:
		return ("%.1fM" % (value / 1_000_000.0)).replace(".", ",")
	if value >= 10_000.0:
		return ("%.1fK" % (value / 1000.0)).replace(".", ",")
	var whole := int(round(value))
	if whole >= 1000:
		return "%d.%03d" % [whole / 1000, whole % 1000]
	return str(maxi(1, whole))


func popup_count() -> int:
	return _popups.size()


func _draw() -> void:
	for popup in _popups:
		var t: float = float(popup.age) / LIFE
		# Pop in (0.12 s), rise with ease-out, fade over the last 40 %.
		var pop := clampf(float(popup.age) / 0.12, 0.0, 1.0)
		var grow := lerpf(1.35, 1.0, pop)
		var alpha := clampf((1.0 - t) / 0.4, 0.0, 1.0)
		var at: Vector2 = popup.at - Vector2(0.0, RISE * (1.0 - pow(1.0 - t, 2.0)))
		var tint: Color = popup.color
		UiStyle.text(self, String(popup.text), at, int(float(popup.size) * grow), Color(tint, alpha), true, 9)
