extends Node3D
## Continuous, unobstructed ocean; controller owns the encounter clock.
const Atmosphere = preload("res://scripts/atmosphere.gd")
var environment: Environment
var _water: ShaderMaterial
var _water_root: Node3D
var _atmosphere: Node3D
var _deck_light: OmniLight3D
var _boss_light: OmniLight3D
var _bow_lantern: OmniLight3D
var _sky_flash: DirectionalLight3D
var _deck_cone: SpotLight3D
var _rng := RandomNumberGenerator.new()
var _rock: ShaderMaterial
var _stone: StandardMaterial3D
var _wood: StandardMaterial3D

func _ready() -> void:
	_rng.seed = 730392
	_build_lighting()
	_build_storm_lights()
	_build_ocean()
	_build_grade()
	_build_landmarks()
	_atmosphere = Atmosphere.new()
	add_child(_atmosphere)
	animate(0.0, Vector3(0,0,85), 0.0, Vector3(0,-11,0), "idle", 0.0, 1, 0.0)

func _build_lighting() -> void:
	# Storm-night grade: a bright sky over a near-black hull, one warm kerosene
	# pool on the deck, one cold edge behind the beast.
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = preload("res://assets/environment/storm-panorama.png")
	sky_material.energy_multiplier = 1.35
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("6d8aa8")
	environment.ambient_light_energy = 0.30
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.18
	environment.tonemap_white = 6.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.06
	environment.glow_hdr_threshold = 0.90
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.ssao_enabled = true
	environment.ssao_radius = 2.1
	environment.ssao_intensity = 1.35
	environment.fog_enabled = true
	environment.fog_light_color = Color("22384c")
	environment.fog_light_energy = 0.55
	environment.fog_density = 0.0013
	environment.fog_sky_affect = 0.30
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.0013
	environment.volumetric_fog_albedo = Color("5d7f99")
	environment.volumetric_fog_length = 700.0
	environment.volumetric_fog_anisotropy = 0.45
	environment.volumetric_fog_sky_affect = 0.30
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.02
	environment.adjustment_contrast = 1.16
	environment.adjustment_saturation = 1.10
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-24,-52,0)
	moon.light_color = Color("bcd8f2")
	moon.light_energy = 1.55
	moon.shadow_enabled = true
	moon.shadow_blur = 1.6
	moon.directional_shadow_max_distance = 240.0
	add_child(moon)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-48,142,0)
	fill.light_color = Color("3f6b86")
	fill.light_energy = 0.20
	add_child(fill)
	# Cold edge from behind the boss: the silhouette has to cut out of the fog.
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-14,8,0)
	rim.light_color = Color("d7ecff")
	rim.light_energy = 0.65
	rim.shadow_enabled = false
	add_child(rim)
	_deck_light = OmniLight3D.new()
	_deck_light.omni_range = 34.0
	_deck_light.omni_attenuation = 1.4
	_deck_light.light_color = Color("ffb167")
	_deck_light.light_energy = 2.40
	_deck_light.light_cull_mask = 3
	add_child(_deck_light)
	_bow_lantern = OmniLight3D.new()
	_bow_lantern.omni_range = 16.0
	_bow_lantern.omni_attenuation = 1.8
	_bow_lantern.light_color = Color("ff9c4a")
	_bow_lantern.light_energy = 2.2
	_bow_lantern.light_cull_mask = 3
	add_child(_bow_lantern)
	_boss_light = OmniLight3D.new()
	_boss_light.omni_range = 130.0
	_boss_light.omni_attenuation = 1.1
	_boss_light.light_color = Color("7fe4ff")
	_boss_light.light_energy = 2.60
	_boss_light.light_cull_mask = 3
	add_child(_boss_light)


func _build_storm_lights() -> void:
	_sky_flash = DirectionalLight3D.new()
	_sky_flash.name = "LightningFlash"
	_sky_flash.light_color = Color("cfe0ff")
	_sky_flash.light_energy = 0.0
	_sky_flash.shadow_enabled = false
	_sky_flash.rotation_degrees = Vector3(-58.0, -34.0, 0.0)
	add_child(_sky_flash)
	_deck_cone = SpotLight3D.new()
	_deck_cone.name = "DeckLampCone"
	_deck_cone.light_color = Color("ffb167")
	_deck_cone.light_energy = 3.6
	_deck_cone.spot_range = 17.0
	_deck_cone.spot_angle = 35.0
	_deck_cone.spot_angle_attenuation = 1.7
	_deck_cone.spot_attenuation = 1.3
	_deck_cone.shadow_enabled = false
	add_child(_deck_cone)


func _build_grade() -> void:
	# Screen-space finish above the 3D pass, below the HUD layer.
	var layer := CanvasLayer.new()
	layer.name = "GradeOverlay"
	layer.layer = 0
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/grade.gdshader")
	rect.material = material
	layer.add_child(rect)
	add_child(layer)

func _build_ocean() -> void:
	_water = ShaderMaterial.new()
	_water.shader = preload("res://shaders/ocean.gdshader")
	_water_root = Node3D.new()
	_water_root.name = "ContinuousOcean"
	add_child(_water_root)
	var plane := PlaneMesh.new()
	plane.size = Vector2(384,384)
	plane.subdivide_width = 127
	plane.subdivide_depth = 127
	_mesh(plane, _water, _water_root).name = "NearOcean3mGrid"
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var radii: Array[float] = [192.0,240.0,340.0,520.0,900.0,1600.0,3500.0]
	for side: int in range(4):
		for band: int in range(radii.size()-1):
			for segment: int in range(128):
				var start: int = vertices.size()
				for item: Vector2 in [Vector2(radii[band],float(segment)/128.0), Vector2(radii[band],float(segment+1)/128.0), Vector2(radii[band+1],float(segment)/128.0), Vector2(radii[band+1],float(segment+1)/128.0)]:
					var point := Vector3(lerpf(-item.x,item.x,item.y),0,-item.x).rotated(Vector3.UP, side*PI*0.5)
					vertices.append(point)
					normals.append(Vector3.UP)
				indices.append_array(PackedInt32Array([start,start+2,start+1,start+1,start+2,start+3]))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var horizon := ArrayMesh.new()
	horizon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_mesh(horizon,_water,_water_root).name = "JoinedOceanToHorizon"

func _mesh(mesh: Mesh, material: Material, parent: Node3D) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = mesh
	result.material_override = material
	parent.add_child(result)
	if parent == _water_root:
		result.layers = 2
		result.extra_cull_margin = 8.0
		result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return result

func _surface(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _build_landmarks() -> void:
	_stone = _surface(Color("283c45"),0.89)
	_wood = _surface(Color("242f32"),0.85)
	_rock = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
varying vec3 p;
float hash(vec3 q){return fract(sin(dot(q,vec3(12.71,311.7,74.7)))*43758.54);}
void vertex(){p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){float n=hash(floor(p*1.7));float strata=sin(p.y*.31+sin(p.x*.36)*2.0+sin(p.z*.27))*0.5+0.5;float wet=1.0-smoothstep(0.0,9.0,p.y);ALBEDO=mix(vec3(.05,.075,.084),vec3(.12,.16,.17),strata*.5+n*.25)*(1.0-wet*.28);ROUGHNESS=mix(.9,.44,wet);SPECULAR=.36;}
"""
	_rock.shader = shader
	for group: int in range(22):
		var angle: float = float(group)*TAU/22.0 + _rng.randf_range(-0.07,0.07)
		var radius: float = _rng.randf_range(500,635)
		var root := Node3D.new()
		root.position = Vector3(sin(angle)*radius,0,cos(angle)*radius)
		root.rotation.y = angle
		add_child(root)
		# Uneven horizon masses: a few tall navigation landmarks, quieter broken reefs.
		# The closest mesh still remains beyond the 420m playable sea.
		var height: float = _rng.randf_range(18,42)
		if group % 7 == 1:
			height = _rng.randf_range(68,88)
		elif group % 5 == 2:
			height = _rng.randf_range(44,57)
		for cluster: int in range(5):
			var rock := _mesh(_crag_mesh(),_rock,root)
			rock.position = Vector3(_rng.randf_range(-19,19),-2,_rng.randf_range(-14,14))
			rock.scale = Vector3(_rng.randf_range(9,18), height*_rng.randf_range(.35,1.12),_rng.randf_range(8,15))
			rock.rotation.y = _rng.randf()*TAU
		if group%4 == 0:
			_build_ruin(root,height*.65)
		elif group%3 == 0:
			_build_mast(root)

func _crag_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for ring: int in range(9):
		var points := PackedVector3Array()
		var y: float = float(ring)/8.0
		for sector: int in range(10):
			var angle: float = float(sector)*TAU/10.0
			var radius: float = (1.0-y*y)*_rng.randf_range(.48,1.15)+.025
			points.append(Vector3(sin(angle)*radius + y*.4,y+_rng.randf_range(-.07,.07),cos(angle)*radius+y*y*.27))
		rings.append(points)
	for ring: int in range(8):
		for sector: int in range(10):
			var next: int = (sector+1)%10
			for p: Vector3 in [rings[ring][sector],rings[ring+1][sector],rings[ring][next],rings[ring][next],rings[ring+1][sector],rings[ring+1][next]]:
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()

func _build_ruin(parent: Node3D, height: float) -> void:
	for level: int in range(7):
		for block: int in range(12):
			if level>4 and _rng.randf()<.35:
				continue
			var angle: float = (float(block)+.5*float(level%2))*TAU/12.0
			var brick := BoxMesh.new()
			brick.size = Vector3(2.15,1.8,1.7)
			var instance := _mesh(brick,_stone,parent)
			instance.position = Vector3(sin(angle)*4.3,height+level*1.85,cos(angle)*4.3)
			instance.rotation = Vector3(_rng.randf_range(-.03,.03),angle,_rng.randf_range(-.03,.03))
	_build_beacon(parent,Vector3(0,height+9,0))

func _build_mast(parent: Node3D) -> void:
	var mast := CylinderMesh.new()
	mast.height = 22
	mast.top_radius = .15
	mast.bottom_radius = .4
	var instance := _mesh(mast,_wood,parent)
	instance.position = Vector3(14,8,12)
	instance.rotation.z = .2
	var beam := BoxMesh.new()
	beam.size = Vector3(12,.4,.4)
	_mesh(beam,_wood,parent).position = Vector3(11,15,12)
	_build_beacon(parent,Vector3(9,14,12))

func _build_beacon(parent: Node3D, point: Vector3) -> void:
	var lantern := SphereMesh.new()
	lantern.radius = .48
	lantern.height = .96
	var glow := _surface(Color("edb66d"),.3)
	glow.emission_enabled = true
	glow.emission = Color("d8903e")
	glow.emission_energy_multiplier = 3.0
	_mesh(lantern,glow,parent).position = point
	var light := OmniLight3D.new()
	light.position = point
	light.light_color = Color("e8b56b")
	light.light_energy = 5
	light.omni_range = 25
	parent.add_child(light)

func animate(time: float, ship_pos: Vector3, ship_heading: float, boss_pos: Vector3, attack: String, windup: float, phase: int, speed: float) -> void:
	if not is_instance_valid(_water_root):
		return
	_water_root.position = Vector3(roundf(ship_pos.x/12.0)*12.0,0,roundf(ship_pos.z/12.0)*12.0)
	_water.set_shader_parameter("clock",time)
	_water.set_shader_parameter("ship_position",ship_pos)
	_water.set_shader_parameter("ship_heading",ship_heading)
	_water.set_shader_parameter("ship_speed",speed)
	_water.set_shader_parameter("boss_position",boss_pos)
	_deck_light.position = ship_pos + Vector3(0,7,0)
	_bow_lantern.position = ship_pos + Vector3(0,3.2,-9.5)
	_boss_light.position = boss_pos + Vector3(-22,49,15)
	_boss_light.light_energy = 3.50 + float(phase-1)*.20
	# 雷击：整片海域被冷光打亮一瞬，巨兽与船同时被"照出轮廓"
	var strike: float = 0.0
	if attack in ["lightning", "thunder"]:
		strike = clampf(windup, 0.0, 1.0) * (0.30 + 0.70 * absf(sin(time * 29.0)))
	if is_instance_valid(_sky_flash):
		_sky_flash.light_energy = strike * 7.5
		environment.ambient_light_energy = 0.30 + strike * 0.40
	if is_instance_valid(_deck_cone):
		_deck_cone.position = ship_pos + Vector3(0.0, 5.4, -3.2)
		_deck_cone.look_at(Vector3(ship_pos.x, 0.0, ship_pos.z) + Vector3(sin(ship_heading), 0.0, cos(ship_heading)) * 5.0)
	_atmosphere.animate(time,ship_pos,boss_pos,attack,windup,ship_heading,speed)

func sample_wave(world_xz: Vector2, time: float) -> float:
	return sin(world_xz.dot(Vector2(.075,.125))+time*.76)*.78 + sin(world_xz.dot(Vector2(-.16,.065))+time*1.05)*.34 + sin(world_xz.dot(Vector2(.31,.19))+time*1.51)*.13

