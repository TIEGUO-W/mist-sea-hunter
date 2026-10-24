extends Node3D
## Restrained rain, sea spray and foam. Driven by the encounter's clock, not _process.

const RAIN_COUNT: int = 1100
const FOAM_COUNT: int = 320
const SPRAY_COUNT: int = 240
const MIST_COUNT: int = 44
const SURGE_COUNT: int = 220

var _rain: MultiMeshInstance3D
var _foam: MultiMeshInstance3D
var _spray: MultiMeshInstance3D
var _mist: MultiMeshInstance3D
var _surge: MultiMeshInstance3D
var _surge_seeds: Array[Vector4] = []
var _wake: Node3D
var _foam_material: ShaderMaterial
var _mist_material: ShaderMaterial
var _wake_material: ShaderMaterial
var _rain_seeds: Array[Vector4] = []
var _foam_seeds: Array[Vector4] = []
var _spray_seeds: Array[Vector4] = []
var _mist_seeds: Array[Vector4] = []


func _ready() -> void:
	_build_rain()
	_build_sea_air()
	_build_wake()
	# Landmarks are owned by arena.gd, outside the navigation radius.
	animate(0.0, Vector3(0, 0, 15), Vector3(0, -8, -17), "idle", 0.0)


func _seed(index: int, salt: float) -> float:
	return fposmod(sin(float(index) * 127.1 + salt * 311.7) * 43758.5453, 1.0)


func _seeds(count: int, salt: float) -> Array[Vector4]:
	var values: Array[Vector4] = []
	for index: int in range(count):
		values.append(Vector4(_seed(index, salt), _seed(index, salt + 1.0), _seed(index, salt + 2.0), _seed(index, salt + 3.0)))
	return values


func _multimesh(node_name: String, count: int, mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = MultiMesh.new()
	instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	instance.multimesh.instance_count = count
	instance.multimesh.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.extra_cull_margin = 100.0
	add_child(instance)
	return instance


func _surface(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _build_rain() -> void:
	_rain_seeds = _seeds(RAIN_COUNT, 1.0)
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.009, 0.36, 0.009)
	var material: StandardMaterial3D = _surface(Color(0.23, 0.38, 0.45, 0.27))
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain = _multimesh("FineWindRain", RAIN_COUNT, mesh, material)


func _foam_shader(tint: Color, opacity: float, mist: bool = false) -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color;
uniform float opacity = 0.3;
uniform float clock = 0.0;
uniform bool mist = false;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() {
 if(!mist){vec2 p=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;VERTEX.y+=sin(dot(p,vec2(.075,.125))+clock*.76)*.78+sin(dot(p,vec2(-.16,.065))+clock*1.05)*.34+sin(dot(p,vec2(.31,.19))+clock*1.51)*.13;}
}
void fragment() {
	vec2 p = UV*2.0-1.0;
	float edge = 1.0-smoothstep(0.28,1.0,length(p));
	float n = noise(UV*7.0+vec2(clock*0.17,-clock*0.12));
	float fine = noise(UV*23.0+vec2(clock*0.12));
	float pattern = mist ? mix(0.25,0.8,n) : smoothstep(0.33,0.72,n*0.6+fine*0.4);
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.94;
	ALPHA = edge*pattern*opacity;
}
"""
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("mist", mist)
	return material


func _build_sea_air() -> void:
	_foam_seeds = _seeds(FOAM_COUNT, 11.0)
	_spray_seeds = _seeds(SPRAY_COUNT, 21.0)
	_mist_seeds = _seeds(MIST_COUNT, 31.0)
	var foam_mesh: PlaneMesh = PlaneMesh.new()
	foam_mesh.size = Vector2(6.4, 7.6)
	_foam_material = _foam_shader(Color(0.42, 0.56, 0.60), 0.62)
	_foam = _multimesh("BrokenFoamRing", FOAM_COUNT, foam_mesh, _foam_material)
	var spray_mesh: BoxMesh = BoxMesh.new()
	spray_mesh.size = Vector3(0.10, 0.42, 0.10)
	_spray = _multimesh("SaltSpray", SPRAY_COUNT, spray_mesh, _surface(Color(0.33, 0.48, 0.49, 0.49)))
	var mist_mesh: QuadMesh = QuadMesh.new()
	mist_mesh.size = Vector2(17.0, 6.0)
	_mist_material = _foam_shader(Color(0.24, 0.36, 0.39), 0.22, true)
	_mist = _multimesh("LowSeaVapour", MIST_COUNT, mist_mesh, _mist_material)
	# 巨兽吃水线的一圈持续白沫：证明它"泡在水里"，而不是浮在画面上
	_surge_seeds = _seeds(SURGE_COUNT, 41.0)
	var surge_mesh: PlaneMesh = PlaneMesh.new()
	surge_mesh.size = Vector2(5.6, 5.6)
	var surge_material: ShaderMaterial = _foam_shader(Color(0.66, 0.78, 0.83), 0.55)
	_surge = _multimesh("BossWaterlineSurge", SURGE_COUNT, surge_mesh, surge_material)


func _ribbon_mesh(side: float) -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	const SEGMENTS: int = 24
	for index: int in range(SEGMENTS + 1):
		var progress: float = float(index) / float(SEGMENTS)
		var center_x: float = side * (2.3 + 4.3 * progress)
		var center_z: float = -6.7 + 30.0 * progress
		var width: float = 0.12 + 0.62 * sin(progress * PI * 0.8)
		var alpha: float = sin(progress * PI) * 0.5
		vertices.append(Vector3(center_x - width, 0.0, center_z))
		vertices.append(Vector3(center_x + width, 0.0, center_z))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.0, progress))
		uvs.append(Vector2(1.0, progress))
		colors.append(Color(1, 1, 1, alpha))
		colors.append(Color(1, 1, 1, alpha))
		if index < SEGMENTS:
			var start: int = index * 2
			indices.append_array(PackedInt32Array([start, start + 1, start + 2, start + 1, start + 3, start + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_wake() -> void:
	_wake = Node3D.new()
	_wake.name = "BowFoamRibbons"
	add_child(_wake)
	var shader: Shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float clock = 0.0;
uniform float speed_alpha = 0.0;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
	float edge = smoothstep(0.0,0.25,UV.x)*(1.0-smoothstep(0.65,1.0,UV.x));
	float n = noise(vec2(UV.x*6.0,UV.y*33.0-clock*1.2));
	float broken = smoothstep(0.2,0.72,n);
	ALBEDO = vec3(0.39,0.54,0.59);
	ROUGHNESS = 1.0;
	ALPHA = COLOR.a*edge*broken*speed_alpha;
}
"""
	_wake_material = ShaderMaterial.new()
	_wake_material.shader = shader
	for side: float in [-1.0, 1.0]:
		var ribbon: MeshInstance3D = MeshInstance3D.new()
		ribbon.mesh = _ribbon_mesh(side)
		ribbon.material_override = _wake_material
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_wake.add_child(ribbon)


func animate(time: float, ship_pos: Vector3, boss_pos: Vector3, attack: String, windup: float, ship_heading: float = 0.0, speed: float = 0.0) -> void:
	if not is_instance_valid(_rain):
		return
	var pressure: float = clampf((windup - 0.72) / 0.28, 0.0, 1.0) if attack != "idle" else 0.0
	_rain.position = Vector3(ship_pos.x, 0.0, ship_pos.z)
	for index: int in range(RAIN_COUNT):
		var seed: Vector4 = _rain_seeds[index]
		var position_value: Vector3 = Vector3((seed.x - 0.5) * 85.0, fposmod(seed.y * 23.0 - time * (14.0 + seed.w * 5.0), 23.0), (seed.z - 0.5) * 95.0)
		position_value.x += position_value.y * 0.1
		var basis: Basis = Basis(Vector3.FORWARD, -0.13).scaled(Vector3(1.0, 0.7 + seed.w * 0.8, 1.0))
		_rain.multimesh.set_instance_transform(index, Transform3D(basis, position_value))
	_surge.position = Vector3(boss_pos.x, 1.45, boss_pos.z)
	for index: int in range(SURGE_COUNT):
		var surge_seed: Vector4 = _surge_seeds[index]
		var wave: float = fposmod(time * (0.15 + surge_seed.w * 0.10) + surge_seed.y, 1.0)
		var surge_angle: float = surge_seed.x * TAU
		var surge_radius: float = 20.0 + wave * 8.5 + pressure * 3.0
		var surge_basis: Basis = Basis(Vector3.UP, surge_angle).scaled(Vector3(
			(0.45 + surge_seed.z * 0.95) * sin(wave * PI),
			1.0,
			(0.45 + surge_seed.z * 0.95) * sin(wave * PI)))
		_surge.multimesh.set_instance_transform(index, Transform3D(surge_basis,
			Vector3(cos(surge_angle) * surge_radius, sin(surge_angle * 3.0) * 0.05, sin(surge_angle) * surge_radius)))
	_surge.material_override.set_shader_parameter("clock", time)
	_foam.position = Vector3(boss_pos.x, 1.30, boss_pos.z)
	_spray.position = Vector3(boss_pos.x, 1.15, boss_pos.z)
	_mist.position = Vector3(boss_pos.x, 0.3, boss_pos.z)
	for index: int in range(FOAM_COUNT):
		var seed: Vector4 = _foam_seeds[index]
		var angle: float = seed.x * TAU + time * (0.018 + seed.z * 0.025)
		# Broad, broken tidal patches, rather than a perfect white ring.
		var sector: float = sin(angle*3.0+0.8)*0.5+0.5
		var radius: float = 20.0 + seed.y * 12.0 + sin(angle*5.0)*1.6 + sin(time * 0.8 + seed.w * TAU) * 0.2
		var position_value: Vector3 = Vector3(cos(angle) * radius, sin(time * 1.5 + angle * 4.0) * 0.07, sin(angle) * radius)
		var size_value: float = (0.40 + seed.z * 1.05 + pressure * 0.55)*(0.45+sector*.65)
		var basis: Basis = Basis(Vector3.UP, angle).scaled(Vector3(size_value, 1.0, size_value))
		_foam.multimesh.set_instance_transform(index, Transform3D(basis, position_value))
	for index: int in range(SPRAY_COUNT):
		var seed: Vector4 = _spray_seeds[index]
		var life: float = fposmod(time * (0.38 + seed.w * 0.22) + seed.y, 1.0)
		var angle: float = seed.x * TAU
		var radius: float = 23.0 + seed.z * 5.5 + life * (0.9 + pressure * 1.8)
		var height: float = sin(life * PI) * (0.6 + seed.z * 1.7 + pressure * 3.5)
		var position_value: Vector3 = Vector3(cos(angle) * radius, height, sin(angle) * radius)
		var scale_value: float = maxf(0.06, sin(life * PI))
		var basis: Basis = Basis(Vector3.FORWARD, -0.4 + seed.w * 0.8).scaled(Vector3.ONE * scale_value)
		_spray.multimesh.set_instance_transform(index, Transform3D(basis, position_value))
	for index: int in range(MIST_COUNT):
		var seed: Vector4 = _mist_seeds[index]
		var angle: float = seed.x * TAU + time * 0.012
		var radius: float = 23.0 + seed.y * 7.0
		var position_value: Vector3 = Vector3(cos(angle) * radius, 0.3 + seed.z * 0.7, sin(angle) * radius)
		var basis: Basis = Basis(Vector3.UP, -angle + PI * 0.5).scaled(Vector3(0.6 + seed.w, 0.8, 1.0))
		_mist.multimesh.set_instance_transform(index, Transform3D(basis, position_value))
	_wake.position = Vector3(ship_pos.x, ship_pos.y + 0.1, ship_pos.z)
	_wake.rotation.y = ship_heading
	_wake_material.set_shader_parameter("speed_alpha", clampf(absf(speed)/18.0,0.0,1.0))
	_foam_material.set_shader_parameter("clock", time)
	_mist_material.set_shader_parameter("clock", time)
	_wake_material.set_shader_parameter("clock", time)


