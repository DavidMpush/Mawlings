extends SceneTree

# Guard against double-encoded UTF-8 (a file read as cp1252 and written back as
# UTF-8 turns "Ä" into A-tilde + quote, "×" into A-tilde + dash, "·" into
# A-circumflex + "·"). The patterns are written as code points only.
# Scans every scripts/**/*.gd and tests/**/*.gd and fails on a hit.
#   godot --headless --path . --script res://tests/encoding.gd

# Built from code points so this file never contains the patterns itself.
var patterns := [
	String.chr(0xC3),                                  # A-tilde: start of a broken Ä/Ö/Ü/ä/ö/ü/ß/×
	String.chr(0xE2) + String.chr(0x20AC),             # a-circumflex + euro: broken – — “ ” … •
	String.chr(0xC2) + String.chr(0xB7),               # A-circumflex + middle dot: broken ·
	String.chr(0xC2) + String.chr(0xA0),               # A-circumflex + no-break space
]
var hits: Array[String] = []
var scanned := 0


func _initialize() -> void:
	for root in ["res://scripts", "res://tests"]:
		_scan(root)
	if not hits.is_empty():
		for hit in hits:
			push_error("Double-encoded text: " + hit)
		quit(1)
		return
	print("PASS encoding: %d .gd files free of double-encoded UTF-8" % scanned)
	quit(0)


func _scan(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan(path.path_join(sub))
	for file in dir.get_files():
		if file.get_extension() != "gd":
			continue
		var full := path.path_join(file)
		var text := FileAccess.get_file_as_string(full)
		scanned += 1
		var lines := text.split("\n")
		for index in lines.size():
			for pattern: String in patterns:
				if lines[index].contains(pattern):
					hits.append("%s:%d" % [full, index + 1])
					break
