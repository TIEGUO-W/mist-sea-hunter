extends Node3D
## Close-up look-dev stage for the sea monster sculpt.
## godot --path <project> res://tools/model_stage.tscn -- --shot=<png> [--angle=hero|front|side|top] [--frames=30]

const Monster = preload("res://scripts/sea_monster.gd")

var _camera: Camera3D
var _out := ""
var _angle := "hero"
var _frames := 30

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_out = arg.substr(7)
		elif arg.begins_with("--angle="):
			_angle = arg.substr(8)
		elif arg.begins_with("--frames="):
			_frames = int(arg.substr(9))
	_build_stage()
	if _out.is_empty():
		return
	_capture()

func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0a1017")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("5d7d99")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.05
	environment.glow_enabled = true
	environment.glow_intensity = 0.4
	environment.glow_bloom = 0.05
	environment.fog_enabled = true
	environment.fog_light_color = Color("22384c")
	environment.fog_density = 0.002
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-32,-46,0)
	key.light_color = Color("c6dcf2")
	key.light_energy = 1.5
	key.shadow_enabled = true
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-8,150,0)
	rim.light_color = Color("8fd8ff")
	rim.light_energy = 1.1
	add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0,2,12)
	fill.omni_range = 40.0
	fill.light_color = Color("ffb167")
	fill.light_energy = 1.6
	add_child(fill)
	var monster := Monster.new()
	monster.position = Vector3.ZERO
	add_child(monster)
	_camera = Camera3D.new()
	_camera.fov = 42.0
	_camera.far = 400.0
	add_child(_camera)
	var target := Vector3(0,5.2,1.0)
	match _angle:
		"front":
			_camera.position = Vector3(0,7.0,30.0)
		"side":
			_camera.position = Vector3(31.0,7.5,4.0)
		"top":
			_camera.position = Vector3(6.0,30.0,18.0)
		"low":
			_camera.position = Vector3(9.0,-1.5,17.0)
		_:
			_camera.position = Vector3(15.5,10.5,23.0)
	_camera.look_at(target)
	_camera.current = true

func _capture() -> void:
	for _i in _frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out)
	print("model shot ", _out, " angle=", _angle, " size=", image.get_size())
	get_tree().quit()
