extends Node
## Offscreen frame capture for design review.
## Usage: godot --path <project> -- --shot=<file.png> [--shot-battle] [--shot-frames=N]
## Never runs without the flag, so normal play is untouched.

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var out := ""
	var battle := false
	var frames := 24
	var overlay := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			out = arg.substr(7)
		elif arg == "--shot-battle":
			battle = true
		elif arg.begins_with("--shot-frames="):
			frames = int(arg.substr(14))
		elif arg.begins_with("--shot-overlay="):
			overlay = arg.substr(15)
	if out.is_empty():
		return
	_capture(out, battle, frames, overlay)

func _capture(out: String, battle: bool, frames: int, overlay: String = "") -> void:
	for _i in 12:
		await get_tree().process_frame
	if battle:
		var scene := get_tree().current_scene
		if scene and scene.has_method("start_battle"):
			scene.start_battle()
	for _i in frames:
		await get_tree().process_frame
	if not overlay.is_empty():
		var scene: Node = get_tree().current_scene
		var hud: CanvasLayer = scene.get("hud") as CanvasLayer if scene != null else null
		if hud != null:
			if overlay in ["victory", "defeat"]:
				hud.call("set_result", {"time": 214.0, "hull": 47.0, "repairs": 2,
					"boss_hp": 0.0 if overlay == "victory" else 2680.0, "max_hp": 4200.0})
			hud.call("set_overlay", overlay)
			for _i in 10:
				await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(out)
	var data := image.get_data()
	var total := 0.0
	var steps := 0
	for index: int in range(0, data.size(), 4 * 97):
		total += (float(data[index]) * 0.299 + float(data[index + 1]) * 0.587 + float(data[index + 2]) * 0.114)
		steps += 1
	print("shot ", out, " err=", error, " size=", image.get_size(), " luma=", snappedf(total / maxf(1.0, float(steps)), 0.1))
	get_tree().quit()
