extends SceneTree
## Package only runtime sources and imported textures; no editor or user data.
func _initialize() -> void:
	var destination: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--pack="):
			destination = arg.trim_prefix("--pack=")
	if destination.is_empty():
		push_error("Pass -- --pack=<absolute output.pck>")
		quit(1)
		return
	var packer: PCKPacker = PCKPacker.new()
	var error: Error = packer.pck_start(destination)
	if error != OK:
		push_error("Cannot create package: %s" % error)
		quit(1)
		return
	var paths: Array[String] = ["res://project.godot"]
	for folder: String in ["scripts", "scenes", "shaders", "assets", ".godot/imported"]:
		_collect("res://" + folder, paths)
	for path: String in paths:
		error = packer.add_file(path, ProjectSettings.globalize_path(path))
		if error != OK:
			push_error("Packing failed: " + path)
			quit(1)
			return
	error = packer.flush()
	print("PACK_RESULT ", error, " FILES ", paths.size())
	quit(0 if error == OK else 1)


func _collect(folder: String, paths: Array[String]) -> void:
	var directory: DirAccess = DirAccess.open(folder)
	if directory == null:
		return
	for name: String in directory.get_files():
		if name.ends_with(".txt") or name.ends_with(".md"):
			continue
		paths.append(folder + "/" + name)
	for child: String in directory.get_directories():
		_collect(folder + "/" + child, paths)
