extends SceneTree
## Helper for assets/ui/v4/build_icons_v4.py: rasterises painted SVG icons of
## res://assets/ui/icons/ to plain PNGs (Python has no SVG renderer here).
## Usage: godot --headless --path <project> --script res://assets/ui/v4/rasterize_svg.gd -- <out_dir> <scale> <id> [<id> ...]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: -- <out_dir> <scale> <id> ...")
		quit(1)
		return
	var out_dir: String = args[0]
	var scale := float(args[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	var failed := 0
	for i in range(2, args.size()):
		var id: String = args[i]
		var bytes := FileAccess.get_file_as_bytes("res://assets/ui/icons/%s.svg" % id)
		var image := Image.new()
		if bytes.is_empty() or image.load_svg_from_buffer(bytes, scale) != OK:
			push_error("cannot rasterise %s" % id)
			failed += 1
			continue
		image.save_png(out_dir.path_join(id + ".png"))
	print("rasterised %d svg icons" % (args.size() - 2 - failed))
	quit(1 if failed else 0)
