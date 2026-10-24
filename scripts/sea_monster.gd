extends Node3D
## 渊鲸·角渊 —— 连续曲面重建版。
## 躯体、颅骨、下颌、触肢、鳍膜全部由连续网格（而非椭球/管的拼装）构成，
## 因此存在真实的 UV、法线与掠射过渡。对外接口与旧版完全一致。
## 外部遭遇控制器掌握时间；本文件不做自动 _process。

const SKIN_SHADER: String = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec4 skin_color : source_color = vec4(0.055, 0.10, 0.13, 1.0);
uniform vec4 sheen_color : source_color = vec4(0.16, 0.52, 0.55, 1.0);
uniform vec4 sss_color : source_color = vec4(0.42, 0.10, 0.14, 1.0);
uniform float surface_kind = 0.0;
uniform float sss_amount = 1.0;
uniform float cell_scale = 3.0;
uniform float relief_strength = 1.0;
uniform float glow_amount = 1.0;
uniform float pore_threshold = 0.945;
uniform float veiny = 0.0;
uniform float wound_glow = 0.0;
uniform vec3 wound_position = vec3(0.0);
uniform float time = 0.0;
uniform mat4 monster_world_inverse;

// 静态细节会被按材质并进同一个 MeshInstance；每实例记录它在静止姿态下的
// 位置/法线基，因此程序化鳞纹不会随肢体摆动而滑动。
instance uniform vec4 rest_position_x = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform vec4 rest_position_y = vec4(0.0, 1.0, 0.0, 0.0);
instance uniform vec4 rest_position_z = vec4(0.0, 0.0, 1.0, 0.0);
instance uniform vec4 rest_normal_x = vec4(1.0, 0.0, 0.0, 0.0);
instance uniform vec4 rest_normal_y = vec4(0.0, 1.0, 0.0, 0.0);
instance uniform vec4 rest_normal_z = vec4(0.0, 0.0, 1.0, 0.0);
// 次级运动：沿"肢体静止轴"传播的行波。sway_axis.xyz = 轴，.w = 长度；
// sway_motion = (相位, 振幅, 频率, 备用)。振幅 0 的部件（躯干、头）完全不受影响。
instance uniform vec4 sway_axis = vec4(0.0, 1.0, 0.0, 1.0);
instance uniform vec4 sway_motion = vec4(0.0, 0.0, 1.0, 0.0);
uniform float sway_time = 0.0;

varying vec3 rp;
varying vec3 cur;

vec3 hash33(vec3 p3) {
	p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// 最近格点距离 + 细胞边界宽度：一次得到鳞片穹顶与鳞缝。
float cell_field(vec3 x, out vec3 cid, out float edge) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	float f1 = 8.0;
	float f2 = 8.0;
	vec3 best = vec3(0.0);
	for (int k = -1; k <= 1; k++) {
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec3 g = vec3(float(i), float(j), float(k));
				vec3 o = hash33(p + g);
				vec3 r = g + o - f;
				float d = dot(r, r);
				if (d < f1) {
					f2 = f1;
					f1 = d;
					best = p + g;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}
	cid = best;
	edge = sqrt(f2) - sqrt(f1);
	return sqrt(f1);
}

float vnoise(vec3 a) {
	vec3 i = floor(a);
	vec3 f = fract(a);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash33(i).x, hash33(i + vec3(1, 0, 0)).x, f.x),
	               mix(hash33(i + vec3(0, 1, 0)).x, hash33(i + vec3(1, 1, 0)).x, f.x), f.y),
	           mix(mix(hash33(i + vec3(0, 0, 1)).x, hash33(i + vec3(1, 0, 1)).x, f.x),
	               mix(hash33(i + vec3(0, 1, 1)).x, hash33(i + vec3(1, 1, 1)).x, f.x), f.y), f.z);
}

float fbm3(vec3 a) {
	return vnoise(a) * 0.55 + vnoise(a * 2.07 + 11.3) * 0.28 + vnoise(a * 4.11 + 27.7) * 0.17;
}

void vertex() {
	vec4 lp = vec4(VERTEX, 1.0);
	if (sway_motion.y > 0.0001) {
		float along = clamp((dot(VERTEX, sway_axis.xyz) - sway_motion.w) / max(sway_axis.w, 0.001), 0.0, 1.0);
		vec3 bend_dir = cross(sway_axis.xyz, vec3(0.0, 1.0, 0.0));
		if (length(bend_dir) < 0.05) { bend_dir = cross(sway_axis.xyz, vec3(1.0, 0.0, 0.0)); }
		bend_dir = normalize(bend_dir);
		vec3 lift_dir = normalize(cross(bend_dir, sway_axis.xyz));
		float w = pow(along, 1.7) * sway_motion.y;
		float phase = sway_time * sway_motion.z + sway_motion.x - along * 3.1;
		VERTEX += bend_dir * sin(phase) * w + lift_dir * sin(phase * 0.63 + 1.3) * w * 0.45;
	}
	rp = vec3(dot(rest_position_x, lp), dot(rest_position_y, lp), dot(rest_position_z, lp));
	// 伤口锚点活在“当前”怪物坐标里，与静止纹理空间无关。
	cur = (monster_world_inverse * MODEL_MATRIX * lp).xyz;
}

void fragment() {
	vec3 lattice = rp * cell_scale;
	vec3 cid;
	float edge;
	float d1 = cell_field(lattice, cid, edge);

	// dome: 鳞片外缘为 0、中心为 1；crevice: 鳞缝
	float dome = smoothstep(0.0, 0.55, edge);
	float crest = pow(clamp(1.0 - dome, 0.0, 1.0), 0.62);
	float crevice = smoothstep(0.30, 0.0, edge);

	// 第二层细鳞与皮纹，避免整幅只有一种尺度
	vec3 cid2;
	float edge2;
	cell_field(rp * cell_scale * 2.9 + 4.7, cid2, edge2);
	float fine = smoothstep(0.0, 0.42, edge2);

	float grain = fbm3(rp * 7.0);
	float pores_n = fbm3(rp * 19.0);
	float wrinkles = sin(rp.y * 7.5 + fbm3(rp * 1.7) * 7.0) * 0.5 + 0.5;

	float plate_mask = clamp(surface_kind, 0.0, 1.0);
	float membrane_mask = clamp(surface_kind - 1.0, 0.0, 1.0);
	float bone_mask = clamp(surface_kind - 2.0, 0.0, 1.0);

	float value = 0.30 + crest * 0.58 + fine * 0.08 + grain * 0.13 - crevice * 0.34;
	value = mix(value, value * 1.15 + 0.10, plate_mask);
	value = mix(value, value * 1.05, membrane_mask);
	value = mix(value, 0.95 + grain * 0.22, bone_mask);

	vec3 base = skin_color.rgb;
	ALBEDO = base * value;
	// 鳞脊上的一层冷色薄膜感（珍珠质），只在掠射角度明显
	float grazing = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.1);
	ALBEDO += sheen_color.rgb * crest * 0.030 * (1.0 - bone_mask);
	ALBEDO = mix(ALBEDO, vec3(0.02, 0.05, 0.06), veiny * (1.0 - crest) * 0.4);

	// 湿润：鳞顶积水成镜面，鳞缝凹处吸水变哑
	ROUGHNESS = mix(0.46, 0.19, crest) + crevice * 0.26 + plate_mask * 0.05 - membrane_mask * 0.06;
	ROUGHNESS = clamp(ROUGHNESS, 0.08, 0.95);
	METALLIC = 0.02 + plate_mask * 0.06;
	SPECULAR = mix(0.62, 0.38, plate_mask) + membrane_mask * 0.10;

	// 皮下散射：薄处（鳃、鳍、下颌）逆光透出血色。这是“活体”最关键的一笔。
	BACKLIGHT = sss_color.rgb * (0.14 + crest * 0.28 + membrane_mask * 0.75) * sss_amount;

	// 生物光：鳞缝里渗出的青色，以及稀疏的发光孔
	float pore = smoothstep(0.17, 0.0, d1) * step(pore_threshold, hash33(cid + 3.1).x);
	float pulse = 0.72 + 0.28 * sin(time * 1.35 + hash33(cid).y * 12.0);
	EMISSION += sheen_color.rgb * crevice * crevice * (0.020 + pore * 0.9) * glow_amount * pulse * (1.0 - bone_mask);
	EMISSION += sheen_color.rgb * grazing * 0.045 * (1.0 - bone_mask);

	// 表面梯度凹凸：不需要切线/UV，规避细长形变的爆点（与原实现同样加保护）
	float height = (crest * 0.55 + fine * 0.18 + grain * 0.20 + wrinkles * 0.07 + pores_n * 0.05) * 0.042 * relief_strength;
	vec3 px = dFdx(VERTEX);
	vec3 py = dFdy(VERTEX);
	float hx = dFdx(height);
	float hy = dFdy(height);
	vec3 view_n = normalize(NORMAL);
	vec3 rx = cross(py, view_n);
	vec3 ry = cross(view_n, px);
	float signed_area = dot(px, rx);
	if (abs(signed_area) > 1e-10 && dot(px, px) < 1e12 && dot(py, py) < 1e12) {
		vec3 slope = (hx * rx + hy * ry) / signed_area;
		float slope_sq = dot(slope, slope);
		if (slope_sq >= 0.0 && slope_sq < 100000.0) {
			slope *= min(1.0, 0.11 * inversesqrt(max(slope_sq, 1e-10)));
			NORMAL = normalize(view_n - slope);
		}
	}

	float wound = 1.0 - smoothstep(0.35, 2.4, distance(cur, wound_position));
	EMISSION += vec3(0.55, 0.20, 0.10) * wound * wound_glow * 1.4;
	ALBEDO += vec3(0.30, 0.16, 0.10) * wound * min(wound_glow, 1.0) * 0.5;
}
"""

const EYE_SHADER: String = """
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform vec4 iris_color : source_color = vec4(0.52, 0.16, 0.72, 1.0);
uniform vec4 iris_core : source_color = vec4(0.95, 0.62, 1.0, 1.0);
uniform float eye_radius = 0.42;
uniform float glow = 1.0;
uniform float time = 0.0;
varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 q = lp.xy / eye_radius;
	float r = length(q);
	float angle = atan(q.y, q.x);
	// 竖瞳占中心，虹膜是一圈细纤维，角膜反光在最外缘
	vec2 slit_q = vec2(q.x / 0.19, q.y / 0.86);
	float slit = length(slit_q);
	float pupil = smoothstep(1.02, 0.70, slit);
	float disc = smoothstep(0.86, 0.40, r);
	float iris = disc * (1.0 - pupil);
	float fibre = 0.55 + 0.45 * sin(angle * 37.0 + sin(angle * 9.0) * 2.4 + r * 11.0);
	float crypt = 0.5 + 0.5 * sin(angle * 73.0 - r * 19.0);
	vec3 iris_col = mix(vec3(0.045, 0.012, 0.085), iris_color.rgb, 0.30 + fibre * 0.40 + crypt * 0.22);
	float rim = smoothstep(0.14, 0.0, abs(r - 0.86)) * disc;
	// 眼球本体近乎全黑，只有虹膜与瞳孔边缘发光
	ALBEDO = vec3(0.006, 0.005, 0.011);
	ALBEDO = mix(ALBEDO, iris_col * 0.55, iris);
	ALBEDO = mix(ALBEDO, vec3(0.30, 0.42, 0.44), rim * 0.25);
	EMISSION = iris_col * iris * (0.55 + 0.18 * sin(time * 1.7)) * glow;
	EMISSION += iris_core.rgb * rim * 0.16 * glow;
	ROUGHNESS = 0.09;
	SPECULAR = 0.95;
	METALLIC = 0.0;
}
"""

const SEG_U: int = 64
const SEG_HEAD: int = 60

var _root: Node3D
var _head: Node3D
var _jaw: Node3D
var _tail: Node3D
var _arms: Array[Node3D] = []
var _whiskers: Array[Node3D] = []
var _lures: Array[Node3D] = []
var _tentacles: Array[Node3D] = []
var _tentacle_lights: Array[StandardMaterial3D] = []
var _torso_sections: Array[Vector4] = []
var _skull_def: Array[Vector4] = []
var _back_cores: Array[Node3D] = []
var _core_materials: Array[StandardMaterial3D] = []
var _mouth_material: StandardMaterial3D
var _crown_material: StandardMaterial3D
var _electric_material: StandardMaterial3D
var _sensory_material: StandardMaterial3D
var _eye_material: ShaderMaterial
var _eye_minor: ShaderMaterial
var _electric_forks: Node3D
var _previous_state: String = "chase"
var _previous_attack: String = ""
var _phase_time: float = 0.0
var _recovery_pose: Dictionary = {}
var _glow_materials: Array[StandardMaterial3D] = []
var _glow_base: Array[float] = []
var _skin_materials: Array[ShaderMaterial] = []
var _flash: float = 0.0
var _last_time: float = 0.0
var _hit_segments: Array[Dictionary] = []
var _wound_pivot: Node3D
var _wound_local_point: Vector3 = Vector3.ZERO
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _sway_bindings: Array[Dictionary] = []
var _jaw_rest: float = 0.38

var _mat_hide: ShaderMaterial
var _mat_face: ShaderMaterial
var _mat_plate: ShaderMaterial
var _mat_dark_plate: ShaderMaterial
var _mat_belly: ShaderMaterial
var _mat_fin: ShaderMaterial
var _mat_bone: ShaderMaterial
var _mat_horn: ShaderMaterial
var _mat_gum: StandardMaterial3D
var _mat_inner: StandardMaterial3D
var _mat_tooth: StandardMaterial3D
var _mat_tooth_old: StandardMaterial3D
var _mat_cavity: StandardMaterial3D


func _ready() -> void:
	_rng.seed = 20261023
	_root = _pivot(self, "Root", Vector3.ZERO)
	_mat_hide = _skin(Color("08131b"), 0.0, 1.0, 3.1)
	_mat_face = _skin(Color("0c1d25"), 0.0, 0.85, 3.9)
	_mat_plate = _skin(Color("1c2c36"), 1.0, 0.30, 5.2)
	_mat_dark_plate = _skin(Color("0e171d"), 1.0, 0.30, 5.2)
	_mat_belly = _skin(Color("13242b"), 0.0, 0.55, 4.4)
	_mat_fin = _skin(Color("131f27"), 2.0, 0.80, 4.0)
	_mat_bone = _skin(Color("6f6a5c"), 3.0, 0.0, 7.0)
	_mat_horn = _skin(Color("26252c"), 3.0, 0.0, 6.0)
	_mat_gum = _mat(Color("1e0a14"), 0.0, 0.40)
	_mat_inner = _mat(Color("0b0409"), 0.0, 0.26)
	_mat_tooth = _mat(Color("a9a189"), 0.02, 0.32)
	_mat_tooth_old = _mat(Color("5c5344"), 0.02, 0.46)
	_mat_cavity = _mat(Color("020306"), 0.0, 0.55)
	_mouth_material = _glow(Color("6a2a8c"), 0.10)
	_crown_material = _glow(Color("5d3fa0"), 0.10)
	_electric_material = _glow(Color("477cc3"), 0.22)
	_sensory_material = _glow(Color("1d3a52"), 0.20)
	_eye_material = _eye_surface(0.42, 0.55)
	_eye_minor = _eye_surface(0.10, 0.35)

	_build_torso()
	_build_head()
	_build_limbs()
	_build_cores()
	_build_attack_conduits()
	_merge_static_meshes(_root)
	_bind_limb_sway()
	_bind_material_rest_coordinates(_root)
	_sync_material_coordinates()
	_apply_light_layers(_root)
	_add_silhouette_lights()


# ---------------------------------------------------------------- 网格基元

func _grid_mesh(parent: Node3D, label: String, points: PackedVector3Array, cols: int, rows: int,
		material: Material, closed_u: bool, centers: PackedVector3Array) -> MeshInstance3D:
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	normals.resize(points.size())
	uvs.resize(points.size())
	for r: int in range(rows):
		for c: int in range(cols):
			var cu: int = (c + 1) % cols if closed_u else mini(c + 1, cols - 1)
			var cl: int = posmod(c - 1, cols) if closed_u else maxi(c - 1, 0)
			var du: Vector3 = points[r * cols + cu] - points[r * cols + cl]
			var dv: Vector3 = points[mini(r + 1, rows - 1) * cols + c] - points[maxi(r - 1, 0) * cols + c]
			var n: Vector3 = du.cross(dv)
			if n.length_squared() < 1e-12:
				n = Vector3.UP
			n = n.normalized()
			if not centers.is_empty():
				var outward: Vector3 = points[r * cols + c] - centers[r]
				if outward.length_squared() > 1e-9 and n.dot(outward) < 0.0:
					n = -n
			normals[r * cols + c] = n
			uvs[r * cols + c] = Vector2(float(c) / float(cols), float(r) / float(maxi(rows - 1, 1)))
	for r: int in range(rows - 1):
		var span: int = cols if closed_u else cols - 1
		for c: int in range(span):
			var c2: int = (c + 1) % cols
			var a: int = r * cols + c
			var b: int = r * cols + c2
			var d: int = (r + 1) * cols + c
			var e: int = (r + 1) * cols + c2
			indices.append_array(PackedInt32Array([a, b, d, b, e, d]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _superellipse(angle: float, rx: float, ry: float, exponent: float) -> Vector2:
	var s: float = sin(angle)
	var c: float = cos(angle)
	var d: float = pow(pow(absf(s), exponent) + pow(absf(c), exponent), -1.0 / exponent)
	return Vector2(s * rx, c * ry) * d


func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------- 躯干

func _build_torso() -> void:
	# 弓背：背线在 y≈5 处向后隆起，颈部再向前折回 —— 捕食者的潜行姿态。
	var sections: Array[Vector4] = [
		Vector4(0.26, -3.60, 0.24, -0.62),
		Vector4(1.30, -2.20, 1.06, -0.78),
		Vector4(2.34, -0.60, 1.82, -0.98),
		Vector4(2.86, 1.30, 2.24, -1.12),
		Vector4(2.96, 2.95, 2.32, -1.20),
		Vector4(2.72, 4.45, 2.20, -1.18),
		Vector4(2.28, 5.80, 1.94, -0.92),
		Vector4(1.86, 6.80, 1.62, -0.38),
		Vector4(1.62, 7.40, 1.36, 0.02),
	]
	_torso_sections = sections
	var rows: int = (sections.size() - 1) * 6 + 1
	var cols: int = SEG_U
	var points: PackedVector3Array = PackedVector3Array()
	var centers: PackedVector3Array = PackedVector3Array()
	for r: int in range(rows):
		var p: float = float(r) / 6.0
		var span: int = mini(int(p), sections.size() - 2)
		var t: float = _smooth(p - float(span))
		var sec: Vector4 = (sections[span] as Vector4).lerp(sections[span + 1] as Vector4, t)
		var center: Vector3 = Vector3(0.0, sec.y, sec.w)
		centers.append(center)
		for c: int in range(cols):
			var angle: float = float(c) * TAU / float(cols)
			var seg: Vector2 = _superellipse(angle, sec.x, sec.z, 2.35)
			var x: float = seg.x
			var z: float = seg.y
			# 背脊：向后拉出一道连续龙骨
			var ridge: float = pow(maxf(0.0, -cos(angle)), 5.0)
			z -= ridge * sec.x * 0.20
			# 腹侧压平并收进
			var belly: float = pow(maxf(0.0, cos(angle)), 3.0)
			z -= belly * sec.z * 0.10
			# 肩胛与鳃裂的肌肉起伏
			var muscle: float = 0.035 * sin(angle * 3.0 + sec.y * 1.6) + 0.02 * sin(angle * 7.0)
			points.append(Vector3(x * (1.0 + muscle), sec.y + ridge * 0.12, center.z + z + sec.w * 0.0))
	_grid_mesh(_root, "ArmoredTorso", points, cols, rows, _mat_hide, true, centers)
	# 腹部纵向褶层：真正的解剖，不是贴花
	for i: int in range(6):
		var y: float = -0.9 + float(i) * 0.78
		var w: float = 1.85 - absf(y - 2.0) * 0.10
		var z: float = 1.92 - absf(y - 2.0) * 0.02
		_tube(_root, "VentralFold", [
			Vector3(-w, y, z - 0.62), Vector3(-w * 0.55, y - 0.14, z - 0.12),
			Vector3(0.0, y - 0.20, z + 0.04), Vector3(w * 0.55, y - 0.14, z - 0.12),
			Vector3(w, y, z - 0.62)], [0.030, 0.042, 0.050, 0.042, 0.018], _mat_dark_plate, 8, 3)
	# 背部骨板：沿背脊交错堆叠，给剪影加齿
	for i: int in range(9):
		var t: float = float(i) / 8.0
		var y: float = 1.6 + t * 5.9
		var z: float = -2.30 - sin(t * PI) * 0.42
		var scale: float = 0.72 + sin(t * PI) * 0.55
		_spike(_root, Vector3(0.0, y, z), Vector3(0.0, 0.55, -0.84), 1.05 * scale, 0.30 * scale, _mat_bone)
	# 侧向肋骨凸起，撑出胸廓
	for side: float in [-1.0, 1.0]:
		for i: int in range(5):
			var y: float = 1.0 + float(i) * 0.78
			var x: float = side * (2.55 + 0.18 * sin(float(i) * 1.9))
			var z: float = -0.55 - float(i) * 0.18
			_tube(_root, "CostalRidge", [Vector3(x * 0.55, y - 0.30, z + 0.95), Vector3(x, y, z + 0.12), Vector3(x * 0.72, y + 0.24, z - 0.72)],
				[0.10, 0.19, 0.07], _mat_plate, 10, 5)
	_add_shoulder_mantle()


# ---------------------------------------------------------------- 头骨

func _skull_section(sections: Array[Vector4], z: float, angle: float, flatten: float, keel: float) -> Vector3:
	var lo: int = 0
	var hi: int = sections.size() - 1
	for i: int in range(sections.size() - 1):
		if z >= sections[i].w and z <= sections[i + 1].w:
			lo = i
			hi = i + 1
			break
	var span: float = maxf(0.0001, sections[hi].w - sections[lo].w)
	var t: float = clampf((z - sections[lo].w) / span, 0.0, 1.0)
	var sec: Vector4 = (sections[lo] as Vector4).lerp(sections[hi] as Vector4, t)
	var seg: Vector2 = _superellipse(angle, sec.x, sec.y, 2.25)
	var py: float = seg.y
	if py < 0.0:
		py *= flatten
	py += keel * sec.y * pow(maxf(0.0, cos(angle)), 9.0)
	return Vector3(seg.x, sec.z + py, z)


func _build_head() -> void:
	_head = _pivot(_root, "Head", Vector3(0, 7.0, 0))
	_head.scale = Vector3(1.26, 1.16, 1.20)
	var skull: Array[Vector4] = [
		Vector4(0.55, 0.46, 0.10, -2.30),
		Vector4(1.62, 1.12, 0.14, -1.86),
		Vector4(2.36, 1.52, 0.16, -1.12),
		Vector4(2.66, 1.62, 0.16, -0.34),
		Vector4(2.48, 1.50, 0.10, 0.52),
		Vector4(1.98, 1.14, -0.02, 1.34),
		Vector4(1.48, 0.80, -0.16, 2.06),
		Vector4(1.00, 0.52, -0.26, 2.66),
		Vector4(0.42, 0.24, -0.34, 3.08),
	]
	_skull_def = skull
	var rows: int = (skull.size() - 1) * 5 + 1
	var cols: int = SEG_HEAD
	var points: PackedVector3Array = PackedVector3Array()
	var centers: PackedVector3Array = PackedVector3Array()
	for r: int in range(rows):
		var p: float = float(r) / 5.0
		var span: int = mini(int(p), skull.size() - 2)
		var t: float = _smooth(p - float(span))
		var z: float = lerpf(skull[span].w, skull[span + 1].w, t)
		var yc: float = lerpf(skull[span].z, skull[span + 1].z, t)
		centers.append(Vector3(0.0, yc, z))
		for c: int in range(cols):
			var angle: float = float(c) * TAU / float(cols)
			points.append(_skull_section(skull, z, angle, 0.62, 0.20))
	_grid_mesh(_head, "AbyssalSkull", points, cols, rows, _mat_face, true, centers)

	# 上颚与咽腔：给口腔深度，而不是两块平板
	_ellipsoid(_head, "Palate", Vector3(0.0, -0.86, 1.90), Vector3(1.30, 0.16, 1.18), _mat_gum, 0.05)
	_ellipsoid(_head, "PharyngealVoid", Vector3(0.0, -0.92, 1.10), Vector3(0.94, 0.50, 0.70), _mat_inner, 0.06)
	_ellipsoid(_head, "GulletGlow", Vector3(0.0, -0.78, 1.86), Vector3(0.30, 0.16, 0.26), _mouth_material, 0.12)

	# 下颌：铰接枢轴，张口时真实下坠
	_jaw = _pivot(_head, "LowerJaw", Vector3(0.0, -1.17, 0.80))
	var mandible: Array[Vector4] = [
		Vector4(0.42, 0.26, 0.02, -1.05),
		Vector4(1.50, 0.44, -0.02, -0.60),
		Vector4(1.62, 0.50, -0.12, 0.28),
		Vector4(1.42, 0.46, -0.30, 1.16),
		Vector4(1.04, 0.34, -0.46, 1.92),
		Vector4(0.58, 0.20, -0.56, 2.24),
	]
	var jrows: int = (mandible.size() - 1) * 5 + 1
	var jpoints: PackedVector3Array = PackedVector3Array()
	var jcenters: PackedVector3Array = PackedVector3Array()
	for r: int in range(jrows):
		var p: float = float(r) / 5.0
		var span: int = mini(int(p), mandible.size() - 2)
		var t: float = _smooth(p - float(span))
		var z: float = lerpf(mandible[span].w, mandible[span + 1].w, t)
		var yc: float = lerpf(mandible[span].z, mandible[span + 1].z, t)
		jcenters.append(Vector3(0.0, yc, z))
		for c: int in range(48):
			var angle: float = float(c) * TAU / 48.0
			jpoints.append(_skull_section(mandible, z, angle, 0.85, 0.0))
	_grid_mesh(_jaw, "HookedMandible", jpoints, 48, jrows, _mat_face, true, jcenters)
	_ellipsoid(_jaw, "Tongue", Vector3(0.0, 0.26, 1.10), Vector3(1.24, 0.16, 0.92), _mat_gum, 0.10)
	_ellipsoid(_jaw, "LowerGumRim", Vector3(0.0, 0.10, 1.55), Vector3(1.34, 0.12, 1.02), _mat_gum, 0.06)

	_add_skull_plates()
	_build_mouth()
	_build_eyes()
	_build_brow_and_fins()
	_build_crown()
	_build_lures()


func _build_mouth() -> void:
	# 内外两排交错獠牙：破掉“拉链”感，也给出真实咬合深度
	for layer: int in range(2):
		var count: int = 17 if layer == 0 else 12
		for i: int in range(count):
			var u: float = -1.0 + 2.0 * (float(i) + 0.5) / float(count)
			var wobble: float = _rng.randf_range(-0.05, 0.05)
			var x: float = u * (1.46 if layer == 0 else 1.16) + wobble
			var z: float = (2.96 if layer == 0 else 2.70) - 1.44 * u * u - float(layer) * 0.30
			var y: float = -0.70 - 0.34 * (1.0 - u * u) + float(layer) * 0.10
			var length: float = _rng.randf_range(0.30, 0.66) * (1.0 + 0.35 * (1.0 - absf(u)))
			var radius: float = 0.042 + length * 0.095
			# 深海捕食者的獠牙：少数几颗越出下颌线，交错咬合
			if absf(absf(u) - 0.47) < 0.06 and layer == 0:
				length = 1.72
				radius = 0.150
			elif absf(absf(u) - 0.86) < 0.055 and layer == 0:
				length = 1.28
				radius = 0.126
			elif absf(absf(u) - 0.17) < 0.045 and layer == 0:
				length = 1.48
				radius = 0.136
			var lean: float = 0.12 * signf(u) if absf(u) > 0.2 else 0.0
			var tip: Vector3 = Vector3(x + lean * 2.2, y - length, z + 0.10 + length * 0.05)
			_tube(_head, "UpperFang", [Vector3(x, y, z), Vector3(x + lean * 0.4, y - length * 0.55, z + 0.06), tip],
				[radius, radius * 0.56, 0.004], _mat_tooth if _rng.randf() > 0.22 else _mat_tooth_old, 8, 3)
	for layer: int in range(2):
		var count: int = 14 if layer == 0 else 10
		for i: int in range(count):
			var u: float = -1.0 + 2.0 * (float(i) + 0.5) / float(count)
			var x: float = u * (1.34 if layer == 0 else 1.06)
			var z: float = (2.16 if layer == 0 else 1.92) - 1.18 * u * u
			var y: float = 0.14 - float(layer) * 0.05
			var length: float = _rng.randf_range(0.24, 0.52) * (1.0 + 0.25 * (1.0 - absf(u)))
			var radius: float = 0.038 + length * 0.088
			if absf(absf(u) - 0.42) < 0.05 and layer == 0:
				length = 0.78
				radius = 0.115
			_tube(_jaw, "LowerFang", [Vector3(x, y, z), Vector3(x, y + length * 0.58, z + 0.03),
				Vector3(x * 0.97, y + length, z + 0.01)], [radius, radius * 0.6, 0.004],
				_mat_tooth if _rng.randf() > 0.3 else _mat_tooth_old, 8, 3)
	# 嘴角筋膜与下垂的唇，把獠牙根部收进肉里
	for side: float in [-1.0, 1.0]:
		_tube(_head, "MaxillaryGumLine", [Vector3(side * 1.62, -0.62, 1.34), Vector3(side * 1.30, -0.80, 2.10),
			Vector3(side * 0.70, -0.92, 2.80), Vector3(0.0, -0.96, 3.02)], [0.13, 0.12, 0.09, 0.055], _mat_gum, 10, 6)
		_tube(_jaw, "MandibularGumLine", [Vector3(side * 1.50, 0.20, 1.16), Vector3(side * 1.16, 0.22, 1.96),
			Vector3(side * 0.58, 0.20, 2.26), Vector3(0.0, 0.18, 2.34)], [0.12, 0.10, 0.075, 0.05], _mat_gum, 10, 6)
		_tube(_head, "JawCornerCrease", [Vector3(side * 1.72, -0.42, 1.16), Vector3(side * 1.76, -0.70, 1.46),
			Vector3(side * 1.60, -0.94, 1.74)], [0.10, 0.13, 0.055], _mat_dark_plate, 10, 5)


func _build_eyes() -> void:
	for side: float in [-1.0, 1.0]:
		var at: Vector3 = Vector3(side * 1.78, 0.40, 1.92)
		# 眼窝：向内凹的碗，制造深洞阴影
		_eye_bowl(_head, at + Vector3(-side * 0.20, 0.0, -0.34), Vector2(0.60, 0.40), 0.26, side * 0.30, _mat_cavity)
		var globe: MeshInstance3D = _sphere(_head, "AbyssalGlobe", Vector3.ZERO, 0.42, _eye_material)
		globe.position = at
		globe.rotation.y = side * 0.52
		globe.set_meta("no_merge", true)
		# 眼睑：上眼睑沉重下垂，下眼睑是湿的肉环
		_tube(_head, "HoodedUpperLid", [Vector3(side * 1.22, 0.62, 1.96), Vector3(side * 1.62, 0.94, 1.92),
			Vector3(side * 2.06, 0.90, 1.62), Vector3(side * 2.34, 0.62, 1.20)], [0.10, 0.24, 0.26, 0.11], _mat_dark_plate, 12, 6)
		_tube(_head, "WetLowerLid", [Vector3(side * 1.32, 0.02, 1.86), Vector3(side * 1.72, -0.10, 1.78),
			Vector3(side * 2.08, 0.02, 1.50), Vector3(side * 2.26, 0.26, 1.18)], [0.08, 0.13, 0.14, 0.07], _mat_gum, 12, 5)
		# 眉脊：上挑的外缘给“怒”的表情
		_tube(_head, "BrowRidge", [Vector3(side * 0.66, 1.00, 1.98), Vector3(side * 1.34, 1.24, 1.96),
			Vector3(side * 2.02, 1.18, 1.58), Vector3(side * 2.42, 0.80, 1.10)], [0.18, 0.28, 0.28, 0.14], _mat_plate, 12, 6)
		# 眼眶外缘的骨环：把发光眼球框住
		_tube(_head, "OrbitalBoneRing", [Vector3(side * 1.52, 0.86, 1.74), Vector3(side * 2.14, 0.74, 1.62),
			Vector3(side * 2.28, 0.22, 1.44), Vector3(side * 2.10, -0.16, 1.30)], [0.09, 0.13, 0.13, 0.07], _mat_bone, 10, 6)
		# 次级小眼：三枚沿颧骨排列，读起来"不像地球生物"
		for k: int in range(3):
			var sp: Vector3 = Vector3(side * (1.44 + float(k) * 0.20), 0.04 - float(k) * 0.20, 2.18 - float(k) * 0.30)
			var small: MeshInstance3D = _sphere(_head, "SecondaryEye", Vector3.ZERO, 0.075 + 0.03 * float(k), _eye_minor)
			small.position = sp
			small.rotation.y = side * 0.7
			small.set_meta("no_merge", true)
			_ellipsoid(_head, "SecondarySocket", sp + Vector3(side * 0.02, 0.0, -0.03), Vector3(0.13, 0.11, 0.07), _mat_cavity, 0.0)
		# 眼周甲片
		for i: int in range(3):
			_shield(_head, "OrbitalScute", Vector3(side * (1.12 + float(i) * 0.42), 0.66 + float(i) * 0.10, 1.72 - float(i) * 0.20),
				Vector3(0.40, 0.30, 0.12), Vector3(-0.35, side * (0.2 + float(i) * 0.18), side * 0.4), _mat_plate if i % 2 == 0 else _mat_dark_plate)


func _build_brow_and_fins() -> void:
	for side: float in [-1.0, 1.0]:
		# 鳃裂：三道向后倾斜的裂口，露出内部血色
		for i: int in range(3):
			var y: float = -0.10 - float(i) * 0.36
			_tube(_head, "GillSlit", [Vector3(side * 2.24, y, -0.20), Vector3(side * 2.10, y - 0.10, 0.46),
				Vector3(side * 1.86, y - 0.14, 1.02)], [0.05, 0.09, 0.04], _mat_inner, 8, 4)
		# 面鳍：撕裂的膜 + 硬棘支撑
		for fin: int in range(2):
			var top: float = 1.34 - float(fin) * 0.78
			var far: float = 4.55 - float(fin) * 0.45
			_membrane(_head, Vector3(side * 2.02, top - 0.30, -0.55), Vector3(side * far, top + 1.05, -1.62),
				Vector3(side * 2.42, top + 0.86, -0.62), _mat_fin)
			_tube(_head, "FinSpine", [Vector3(side * 2.02, top - 0.30, -0.55), Vector3(side * 3.10, top + 0.30, -1.02),
				Vector3(side * far, top + 1.05, -1.62)], [0.075, 0.05, 0.008], _mat_horn, 8, 5)
		# 颊部甲板
		for row: int in range(3):
			for column: int in range(4):
				var p: Vector3 = Vector3(side * (1.28 + float(column) * 0.30), -0.72 + float(row) * 0.26, 1.28 - float(column) * 0.26)
				_shield(_head, "CheekScute", p, Vector3(0.27, 0.34, 0.13), Vector3(0.1, side * 0.45, side * -0.32),
					_mat_plate if (row + column) % 3 else _mat_dark_plate)
		# 鼻角：鼻骨上的短刺
		_tube(_head, "NasalHorn", [Vector3(side * 0.62, 0.72, 2.10), Vector3(side * 0.72, 1.05, 2.16), Vector3(side * 0.78, 1.28, 2.08)],
			[0.11, 0.06, 0.004], _mat_horn, 8, 4)


func _build_crown() -> void:
	# 不对称鹿角：右舷完整，左舷折断 —— 自带一段战史
	for side: float in [-1.0, 1.0]:
		var base: Vector3 = Vector3(side * 1.42, 1.16, -0.62)
		var broken: bool = side < 0.0
		var top: float = 3.05 if broken else 4.35
		var trunk: Array[Vector3] = []
		trunk.append(base)
		if broken:
			trunk.append(base + Vector3(side * 0.66, 0.72, -0.14))
			trunk.append(base + Vector3(side * 0.94, 1.52, -0.18))
			trunk.append(base + Vector3(side * 1.02, 1.92, -0.26))
		else:
			trunk.append(base + Vector3(side * 0.62, 0.78, -0.16))
			trunk.append(base + Vector3(side * 0.92, 1.72, -0.20))
			trunk.append(base + Vector3(side * 0.78, top, -0.10))
		var radii: Array[float] = [0.52, 0.40, 0.26, 0.03 if not broken else 0.16]
		_tube(_head, "AntlerTrunk", trunk, radii, _mat_horn, 14, 9)
		if broken:
			# 断口：参差的骨茬
			for i: int in range(5):
				var a: float = float(i) * TAU / 5.0
				var at: Vector3 = trunk[3] + Vector3(cos(a) * 0.10, 0.0, sin(a) * 0.10)
				_tube(_head, "BrokenBoneShard", [at, at + Vector3(cos(a) * 0.06, 0.20 + float(i % 3) * 0.10, sin(a) * 0.06)],
					[0.075, 0.004], _mat_bone, 6, 3)
		else:
			for i: int in range(3):
				var start: Vector3 = trunk[i + 1]
				var dir: float = -1.0 if i == 1 else 1.0
				_tube(_head, "AntlerTine", [start, start + Vector3(side * dir * 0.46, 0.10, 0.10),
					start + Vector3(side * dir * 0.78, 0.52, 0.14), start + Vector3(side * dir * 0.72, 1.06, 0.16)],
					[0.30 - float(i) * 0.04, 0.22 - float(i) * 0.03, 0.12, 0.004], _mat_horn, 10, 7)
		# 角上寄生的藤壶与发光导流缝
		for i: int in range(5):
			var p: Vector3 = trunk[1] + Vector3(side * sin(float(i) * 1.8) * 0.16, float(i) * 0.20, 0.20 + cos(float(i)) * 0.06)
			_tube(_head, "AntlerBarnacle", [p, p + Vector3(0.0, 0.0, 0.09)], [0.085 + float(i % 3) * 0.02, 0.05], _mat_bone, 7, 2)
	# 颅内脊：沿颅顶中线的骨刺列
	for i: int in range(7):
		var z: float = 0.70 - float(i) * 0.44
		var h: float = 0.55 + sin(float(i) * 0.8) * 0.18
		_spike(_head, Vector3(0.0, 1.62, z), Vector3(0.0, 0.86, -0.5), h, 0.20, _mat_horn)


func _build_lures() -> void:
	# 颌角垂下的两枚诱光饵：从下缘垂落，不进入额头弱点的视线
	var bulb_material: StandardMaterial3D = _glow(Color("63d6c6"), 1.35)
	var pore_material: StandardMaterial3D = _glow(Color("3fd6c2"), 1.9)
	for side: float in [-1.0, 1.0]:
		var lure: Node3D = _pivot(_head, "AnglerLure", Vector3(side * 1.60, -1.05, 1.20))
		lure.set_meta("no_merge", true)
		_lures.append(lure)
		var stalk: Array[Vector3] = [Vector3.ZERO, Vector3(side * 0.34, -0.44, 0.24),
			Vector3(side * 0.76, -1.04, 0.58), Vector3(side * 0.92, -1.70, 0.82), Vector3(side * 0.86, -2.20, 0.94)]
		_tube(lure, "LureStalk", stalk, [0.125, 0.092, 0.062, 0.040, 0.028], _mat_bone, 8, 8)
		_ellipsoid(lure, "LureBulb", stalk[4], Vector3(0.17, 0.21, 0.17), bulb_material, 0.12)
		var light: OmniLight3D = OmniLight3D.new()
		light.position = stalk[4]
		light.light_color = Color("63d8ca")
		light.light_energy = 1.35
		light.omni_range = 6.5
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		lure.add_child(light)
		# 眉脊发光孔：成列的生物光点，让面部在远处也能读出"活物"
		for i: int in range(4):
			_ellipsoid(_head, "BrowPhotophore", Vector3(side * (0.94 + float(i) * 0.26), 0.80 - float(i) * 0.12, 1.80 - float(i) * 0.16),
				Vector3(0.055, 0.055, 0.032), pore_material, 0.0)


# ---------------------------------------------------------------- 肢体

func _build_limbs() -> void:
	# 前肢：与旧版同姿态（命中胶囊是战斗公平性的基准，不改）
	for side: float in [-1.0, 1.0]:
		var arm: Node3D = _pivot(_root, "LeftShoulder" if side < 0.0 else "RightShoulder", Vector3(side * 2.0, 4.4, -0.1))
		_arms.append(arm)
		var arm_points: Array[Vector3] = [Vector3.ZERO, Vector3(side * 0.7, -0.6, 0.25),
			Vector3(side * 0.93, -1.65, 0.66), Vector3(side * 0.73, -2.7, 1.05)]
		_limb(arm, "SinewedArm", arm_points, [0.98, 0.88, 0.67, 0.48], _mat_hide, 20, 7, 0.86)
		_register_sway(arm, arm_points, 0.045, 1.4 if side > 0.0 else 3.1)
		for row: int in range(5):
			for column: int in range(3):
				var p: Vector3 = Vector3(side * (0.47 + float(column) * 0.32), -0.35 - float(row) * 0.43, 0.83 + float(row) * 0.12)
				_shield(arm, "ArmCarapace", p, Vector3(0.32, 0.44, 0.15), Vector3(0.05, side * 0.25, side * 0.12),
					_mat_plate if (row + column) % 3 else _mat_dark_plate)
		for finger: int in range(3):
			var x: float = side * 0.73 + float(finger - 1) * 0.37
			_tube(arm, "HookedTalons", [Vector3(x, -2.45, 1.05), Vector3(x, -2.90, 1.34),
				Vector3(x, -3.05, 1.85), Vector3(x, -3.26, 2.06)], [0.20, 0.17, 0.11, 0.006], _mat_horn, 10, 6)
		_tube(_root, "HindHaunch", [Vector3(side * 1.9, 1.1, -0.6), Vector3(side * 2.1, -0.2, -0.1),
			Vector3(side * 2.25, -0.85, 0.8)], [0.95, 0.72, 0.35], _mat_hide, 16, 6)
	# 六条盘卷巨肢：姿态沿用旧版（命中胶囊基准）
	for side: float in [-1.0, 1.0]:
		for tier: int in range(3):
			var node: Node3D = _pivot(_root, "AncientCoilingLimb", Vector3.ZERO)
			_tentacles.append(node)
			var light_mat: StandardMaterial3D = _glow(Color("2f7f96"), 0.45)
			_tentacle_lights.append(light_mat)
			var points: Array[Vector3] = []
			if tier == 0:
				points = [Vector3(side * 2.4, 1.5, -1.6), Vector3(side * 5.5, 1.9, -2.7), Vector3(side * 8.4, 3.2, -3.3),
					Vector3(side * 9.9, 5.1, -2.7), Vector3(side * 9.2, 6.7, -1.9), Vector3(side * 7.7, 6.8, -1.2), Vector3(side * 7.2, 5.8, -1.0)]
			elif tier == 1:
				points = [Vector3(side * 2.3, 2.4, -2), Vector3(side * 4.0, 5.0, -4), Vector3(side * 6.9, 7.0, -5),
					Vector3(side * 8.7, 9.1, -4.0), Vector3(side * 8.1, 10.8, -2.8), Vector3(side * 6.5, 10.7, -1.6), Vector3(side * 6.0, 9.8, -1.5)]
			else:
				points = [Vector3(side * 1.9, 2.8, -3), Vector3(side * 2.9, 6.0, -6), Vector3(side * 4.9, 10.0, -7),
					Vector3(side * 5.7, 12.4, -5.5), Vector3(side * 4.9, 13.4, -4.0), Vector3(side * 3.5, 13.0, -3.0), Vector3(side * 3.2, 12.0, -3.0)]
			for i: int in range(points.size()):
				if side > 0.0:
					points[i].y *= 0.89 + float(tier) * 0.025
					points[i].x *= 1.035
					points[i].z += sin(float(i) * 1.1) * 0.6
				else:
					points[i].y = points[i].y * 0.88 - float(i) * 0.07 + sin(float(i) * 1.2 + float(tier)) * 0.26
					points[i].x *= 1.07
					points[i].z += sin(float(i) * 0.9 + float(tier)) * 0.26 - float(i) * 0.05
			if tier == 2 and side < 0.0:
				# 左舷最上层巨肢自后上方越过颅顶：破坏镜像对称的主势
				for i: int in range(points.size()):
					points[i].y += float(i) * 0.52
					points[i].x *= 1.0 - float(i) * 0.055
					points[i].z += float(i) * 0.20
			var radii: Array[float] = [1.15, 1.0, 0.85, 0.65, 0.4, 0.22, 0.008]
			var limb: MeshInstance3D = _limb(node, "ContinuousArmoredTentacle", points, radii, _mat_hide, 18, 6, 0.80)
			_build_tentacle_detail(node, points, radii, light_mat, side, tier)
			_limb_fin(node, points, radii)
			_limb_tip_claw(node, points, radii, side)
			_register_sway(node, points, 0.10, float(tier) * 2.1 + (0.9 if side > 0.0 else 0.0))
	# 触须：六根粗短感官须（比二十根细丝更像解剖结构）
	for side: float in [-1.0, 1.0]:
		for strand: int in range(6):
			var spacing: float = 0.30 + float(strand) * 0.28 + sin(float(strand) * 2.3) * 0.05
			var whisker: Node3D = _pivot(_head, "LivingWhisker", Vector3(side * spacing * 0.86, -1.02 + sin(float(strand) * 1.7) * 0.085, 2.70 - float(strand) * 0.19))
			_whiskers.append(whisker)
			var length: float = 0.80 + float(strand) * 0.30 + sin(float(strand) * 2.0 + side) * 0.26
			var spread: float = 0.16 + float(strand) * 0.23
			var end: Vector3 = Vector3(side * spread, -length, 0.34 + cos(float(strand) * 1.7) * 0.22)
			_tube(whisker, "SensoryBarbel", [Vector3.ZERO, Vector3(side * 0.12 + sin(float(strand) * 2.0) * 0.09, -0.45, 0.16 + cos(float(strand)) * 0.12),
				Vector3(side * spread * 0.62 + sin(float(strand)) * 0.12, -length * 0.58, 0.30 + sin(float(strand) * 1.4) * 0.19), end],
				[0.145, 0.100, 0.048, 0.010], _mat_hide, 10, 10)
			if strand < 1:
				_ellipsoid(whisker, "BarbelLamp", end, Vector3(0.07, 0.12, 0.07), _glow(Color("63d8c8"), 1.8), 0.0)
	# 尾：保留原姿态
	_tail = _pivot(_root, "Tail", Vector3(0, 0.7, -1.8))
	_tube(_tail, "LongMuscularTail", [Vector3.ZERO, Vector3(0.6, -0.5, -1.7), Vector3(2.5, -0.9, -3.2),
		Vector3(4.8, -0.3, -3.2), Vector3(5.8, 0.9, -2.1), Vector3(5.9, 2.2, -1.3)], [1.0, 0.85, 0.62, 0.4, 0.22, 0.015], _mat_hide, 18, 9)
	for i: int in range(8):
		var t: float = float(i) / 7.0
		_shield(_tail, "TailFinScute", Vector3(0.4 + t * 5.2, -0.1 + sin(t * PI) * -0.55, -1.1 - t * 1.8),
			Vector3(0.40 - t * 0.21, 0.55 - t * 0.20, 0.17), Vector3(-0.3, 0.4, 0.0), _mat_dark_plate)


func _build_tentacle_detail(node: Node3D, points: Array[Vector3], radii: Array[float], light_mat: StandardMaterial3D, side: float, tier: int) -> void:
	# 吸盘列、背甲列与倒刺：让巨肢在近距离也不空
	for span: int in range(points.size() - 1):
		for sample: int in range(4):
			var t: float = float(sample) / 4.0
			var p: Vector3 = _catmull(points[maxi(0, span - 1)], points[span], points[span + 1], points[mini(span + 2, points.size() - 1)], t)
			var t2: float = t + 0.02
			var tangent: Vector3 = (_catmull(points[maxi(0, span - 1)], points[span], points[span + 1], points[mini(span + 2, points.size() - 1)], t2) - p).normalized()
			var reference: Vector3 = Vector3.FORWARD if absf(tangent.dot(Vector3.FORWARD)) < 0.92 else Vector3.RIGHT
			var axis_a: Vector3 = tangent.cross(reference).normalized()
			var axis_b: Vector3 = tangent.cross(axis_a).normalized()
			var width: float = lerpf(radii[span], radii[span + 1], t)
			if width < 0.16:
				continue
			for column: int in range(3):
				var a: float = -1.35 + float(column) * 0.42
				var normal: Vector3 = cos(a) * axis_a + sin(a) * axis_b
				var at: Vector3 = p + normal * width * 0.98
				_ellipsoid(node, "Sucker", at, Vector3(0.13, 0.13, 0.05), _mat_gum, 0.0)
			if (sample + span) % 3 == 0:
				var outward: Vector3 = Vector3(side * 0.66, 0.52, -0.30).normalized()
				var base: Vector3 = p + outward * width * 0.72
				_tube(node, "LimbRazorSpine", [base, base + outward * (0.30 + width * 0.26),
					base + outward * (0.56 + width * 0.36) + Vector3(0.0, 0.14, 0.0)],
					[0.14 + width * 0.07, 0.09, 0.003], _mat_horn, 8, 4)
	for i: int in range(2, 4):
		if (tier + i) % 2 == 0:
			var glow_at: Vector3 = points[i] + Vector3(0.0, 0.0, radii[i] + 0.12)
			_ellipsoid(node, "LimbPhotophore", glow_at, Vector3(0.14, 0.14, 0.07), light_mat, 0.0)


func _limb(parent: Node3D, label: String, points: Array[Vector3], radii: Array[float], material: Material,
		sides: int, steps: int, flatten: float) -> MeshInstance3D:
	_cache_hit_tube(parent, label, points, radii)
	var centers: Array[Vector3] = []
	var widths: Array[float] = []
	for span: int in range(points.size() - 1):
		for segment: int in range(steps):
			var t: float = float(segment) / float(steps)
			centers.append(_catmull(points[maxi(0, span - 1)], points[span], points[span + 1], points[mini(span + 2, points.size() - 1)], t))
			widths.append(lerpf(radii[span], radii[span + 1], t))
	centers.append(points[-1])
	widths.append(radii[-1])
	var rows: int = centers.size()
	var pts: PackedVector3Array = PackedVector3Array()
	var row_centers: PackedVector3Array = PackedVector3Array()
	var axis_a: Vector3 = Vector3.RIGHT
	var axis_b: Vector3 = Vector3.FORWARD
	var previous: Vector3 = (centers[1] - centers[0]).normalized()
	var reference: Vector3 = Vector3.UP if absf(previous.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	axis_a = previous.cross(reference).normalized()
	axis_b = previous.cross(axis_a).normalized()
	for row: int in range(rows):
		var tangent: Vector3 = (centers[mini(row + 1, rows - 1)] - centers[maxi(0, row - 1)]).normalized()
		# 平行移动：沿曲线旋转标架，触肢不会自己拧麻花
		var rotation: Quaternion = Quaternion(previous, tangent)
		axis_a = (rotation * axis_a).normalized()
		axis_b = (rotation * axis_b).normalized()
		previous = tangent
		row_centers.append(centers[row])
		var width: float = maxf(widths[row], 0.004)
		for column: int in range(sides):
			var angle: float = float(column) * TAU / float(sides)
			var normal: Vector3 = cos(angle) * axis_a + sin(angle) * axis_b
			# 背侧扁、腹侧更扁：真实的触手截面是椭圆，不是圆
			var squash: float = 1.0 if normal.dot(axis_b) >= 0.0 else flatten
			# 腹面吸盘凹陷
			var ventral: float = maxf(0.0, -normal.dot(axis_b))
			var dent: float = -0.10 * width * pow(ventral, 6.0)
			var organic: float = 1.0 + sin(float(row) * 0.55 + angle * 3.0) * 0.035
			pts.append(centers[row] + normal * (width * squash * organic + dent))
	_grid_mesh(parent, label, pts, sides, rows, material, true, row_centers)
	return null



func _torso_surface(y: float, angle: float) -> Vector3:
	var lo: int = 0
	for i: int in range(_torso_sections.size() - 1):
		if y >= _torso_sections[i].y and y <= _torso_sections[i + 1].y:
			lo = i
			break
	var span: float = maxf(0.001, _torso_sections[lo + 1].y - _torso_sections[lo].y)
	var t: float = clampf((y - _torso_sections[lo].y) / span, 0.0, 1.0)
	var sec: Vector4 = (_torso_sections[lo] as Vector4).lerp(_torso_sections[lo + 1] as Vector4, t)
	var seg: Vector2 = _superellipse(angle, sec.x, sec.z, 2.35)
	var ridge: float = pow(maxf(0.0, -cos(angle)), 5.0)
	var belly: float = pow(maxf(0.0, cos(angle)), 3.0)
	var z: float = seg.y - ridge * sec.x * 0.20 - belly * sec.z * 0.10
	var muscle: float = 0.035 * sin(angle * 3.0 + sec.y * 1.6) + 0.02 * sin(angle * 7.0)
	return Vector3(seg.x * (1.0 + muscle), y + ridge * 0.12, sec.w + z)


func _surface_frame(kind: String, u: float, v: float) -> Array:
	var e: float = 0.02
	var p: Vector3
	var du: Vector3
	var dv: Vector3
	if kind == "torso":
		p = _torso_surface(u, v)
		du = _torso_surface(u, v + e) - _torso_surface(u, v - e)
		dv = _torso_surface(u + e, v) - _torso_surface(u - e, v)
	else:
		p = _skull_section(_skull_def, u, v, 0.62, 0.22)
		du = _skull_section(_skull_def, u, v + e, 0.62, 0.22) - _skull_section(_skull_def, u, v - e, 0.62, 0.22)
		dv = _skull_section(_skull_def, u + e, v, 0.62, 0.22) - _skull_section(_skull_def, u - e, v, 0.62, 0.22)
	var n: Vector3 = dv.cross(du).normalized()
	if n.length_squared() < 0.1:
		n = Vector3.FORWARD
	var radial: Vector3 = Vector3(p.x, 0.0, p.z - _axis_z(kind))
	if n.dot(radial) < 0.0:
		n = -n
	var right: Vector3 = Vector3.UP.cross(n).normalized()
	if right.length_squared() < 0.1:
		right = Vector3.RIGHT
	var up: Vector3 = n.cross(right).normalized()
	return [p, n, Basis(right, up, n)]


func _axis_z(kind: String) -> float:
	if kind == "torso":
		var lo: int = clampi(_torso_sections.size() / 2, 0, _torso_sections.size() - 1)
		return _torso_sections[lo].w
	return -0.2


func _add_torso_plates() -> void:
	# 背甲：沿体表切空间铺开的穹顶骨板，向下叠压 —— 让躯干读成"重甲"而不是"光滑管子"
	for row: int in range(10):
		var y: float = 0.20 + float(row) * 0.66
		for col: int in range(16):
			var angle: float = -PI * 0.94 + float(col) * 0.222 + (0.10 if row % 2 == 0 else 0.0)
			if cos(angle) > 0.96:
				continue
			var frame: Array = _surface_frame("torso", y, angle)
			var size: float = 0.50 + 0.09 * sin(float(col) * 1.3 + float(row) * 0.7)
			var basis: Basis = (frame[2] as Basis).rotated(frame[1] as Vector3, sin(float(col) * 1.7 + float(row)) * 0.22)
			var material: Material = _mat_bone if (row * 3 + col) % 7 == 0 else (_mat_plate if (row + col) % 3 else _mat_dark_plate)
			_shield(_root, "DorsalPlate", (frame[0] as Vector3) + (frame[1] as Vector3) * 0.02,
				Vector3(size * 1.15, size * 1.05, 0.15), Vector3.ZERO, material, basis)


func _add_skull_plates() -> void:
	for row: int in range(7):
		var z: float = -1.95 + float(row) * 0.62
		for col: int in range(9):
			var angle: float = -PI * 0.78 + float(col) * 0.60
			if sin(angle) > 0.30 and cos(angle) > 0.0:
				continue
			var frame: Array = _surface_frame("skull", z, angle)
			var size: float = 0.30 + 0.06 * sin(float(col) * 2.1 + float(row))
			var basis: Basis = (frame[2] as Basis).rotated(frame[1] as Vector3, sin(float(col) * 1.4 + float(row) * 0.9) * 0.25)
			var material: Material = _mat_bone if (row + col) % 6 == 0 else (_mat_plate if (row + col) % 3 else _mat_dark_plate)
			_shield(_head, "CranialPlate", (frame[0] as Vector3) + (frame[1] as Vector3) * 0.015,
				Vector3(size * 1.1, size, 0.10), Vector3.ZERO, material, basis)



func _add_shoulder_mantle() -> void:
	# 肩颈披甲：一圈向外翻的骨板，把"脖子插在管子上"的读法彻底打断。
	# 左舷更大更张开（右舷姿态是公平性用例的参数，不加额外外扩）。
	for ring: int in range(2):
		var y: float = 6.35 - float(ring) * 0.62
		var count: int = 14 - ring * 2
		for col: int in range(count):
			var angle: float = -PI * 0.90 + float(col) * (TAU * 0.94 / float(count))
			if cos(angle) > 0.55:
				continue
			var lean: float = 0.62 + 0.10 * float(ring)
			var frame: Array = _surface_frame("torso", y, angle)
			var basis: Basis = frame[2] as Basis
			var right: Vector3 = Vector3.UP.cross(frame[1] as Vector3).normalized()
			# 绕切向轴向外翻，形成张开的甲片
			basis = basis.rotated(right, -lean)
			var flare: float = 1.0 + 0.30 * maxf(0.0, -sin(angle))
			var size: float = (0.90 + 0.42 * absf(sin(float(col) * 1.07)) - float(ring) * 0.16) * flare
			_shield(_root, "ShoulderMantle", (frame[0] as Vector3) + (frame[1] as Vector3) * 0.10,
				Vector3(size * 1.0, size * 1.45, 0.26), Vector3.ZERO,
				_mat_bone if col % 5 == 0 else (_mat_plate if col % 2 else _mat_dark_plate), basis)


func _limb_fin(node: Node3D, points: Array[Vector3], radii: Array[float]) -> void:
	# 触肢背缘的锯齿刃鳍：在剪影上把"光滑章鱼腿"改成"海兽利肢"
	var rows: int = (points.size() - 1) * 5 + 1
	var pts: PackedVector3Array = PackedVector3Array()
	var centers: PackedVector3Array = PackedVector3Array()
	for r: int in range(rows):
		var span: int = mini(int(float(r) / 5.0), points.size() - 2)
		var t: float = float(r % 5) / 5.0
		var p: Vector3 = _catmull(points[maxi(0, span - 1)], points[span], points[span + 1], points[mini(span + 2, points.size() - 1)], t)
		var p2: Vector3 = _catmull(points[maxi(0, span - 1)], points[span], points[span + 1], points[mini(span + 2, points.size() - 1)], minf(t + 0.05, 1.0))
		var tangent: Vector3 = (p2 - p).normalized()
		if tangent.length_squared() < 0.5:
			tangent = Vector3.UP
		var up: Vector3 = (Vector3.UP - tangent * tangent.dot(Vector3.UP)).normalized()
		if up.length_squared() < 0.5:
			up = Vector3.RIGHT
		var width: float = lerpf(radii[span], radii[span + 1], t) * 0.86
		var saw: float = absf(sin(float(r) * 1.35))
		var height: float = maxf(0.0, width * (0.12 + 0.30 * saw)) * clampf(width * 1.9, 0.0, 1.0)
		centers.append(p)
		# 三列：根部、刃腰、刃尖（外缘带锯齿）
		pts.append(p + up * (width * 0.55))
		pts.append(p + up * (width * 0.55 + height * 0.6))
		pts.append(p + up * (width * 0.55 + height) + tangent * height * 0.18)
	_grid_mesh(node, "LimbBladeFin", pts, 3, rows, _mat_dark_plate, false, centers)


func _limb_tip_claw(node: Node3D, points: Array[Vector3], radii: Array[float], side: float) -> void:
	var last: Vector3 = points[points.size() - 1]
	var before: Vector3 = points[points.size() - 2]
	var dir: Vector3 = (last - before).normalized()
	var hook: Array[Vector3] = [last - dir * 0.55, last + dir * 0.55, last + dir * 0.95 + Vector3(0.0, 0.75, 0.0),
		last + dir * 0.35 + Vector3(0.0, 1.55, 0.0)]
	_tube(node, "LimbHookClaw", hook, [maxf(radii[radii.size() - 2] * 0.55, 0.10), 0.16, 0.10, 0.004], _mat_horn, 10, 6)

# ---------------------------------------------------------------- 核心与雷冠

func _build_cores() -> void:
	var positions: Array[Vector3] = [Vector3(-1.08, 5.3, -2.1), Vector3(1.08, 5.3, -2.1), Vector3(0, 7.1, -2.36)]
	for i: int in range(positions.size()):
		var core: Node3D = _pivot(_root, "DorsalBiologicalCore%d" % i, positions[i])
		core.rotation.y = PI
		_back_cores.append(core)
		var tissue: StandardMaterial3D = _mat(Color("120b1e"), 0.01, 0.30)
		var glow: StandardMaterial3D = _glow(Color("8a52d8") if i != 2 else Color("3fb0c8"), 0.9)
		_core_materials.append(glow)
		_ellipsoid(core, "OrganSocket", Vector3.ZERO, Vector3(0.54, 0.72, 0.24), tissue, 0.12)
		_ellipsoid(core, "ExposedTidalCore", Vector3(0, 0, 0.21), Vector3(0.22, 0.42, 0.18), glow, 0.20)
		for side: float in [-1.0, 1.0]:
			_tube(core, "CoreCarapace", [Vector3(side * 0.20, -0.62, 0.0), Vector3(side * 0.48, -0.12, 0.12),
				Vector3(side * 0.42, 0.42, 0.05), Vector3(side * 0.12, 0.66, 0.01)], [0.13, 0.16, 0.12, 0.008], _mat_horn, 10, 6)
			_tube(core, "CoreVascular", [Vector3(0, -0.22, 0.37), Vector3(side * 0.10, 0.02, 0.38), Vector3(side * 0.09, 0.30, 0.31)],
				[0.016, 0.023, 0.006], glow, 6, 4)


func _build_attack_conduits() -> void:
	for side: float in [-1.0, 1.0]:
		_tube(_head, "AntlerLivingConduit", [Vector3(side * 1.46, 1.24, -0.58), Vector3(side * 1.94, 2.02, -0.70),
			Vector3(side * 2.36, 3.02, -0.78), Vector3(side * 2.24, 3.96, -0.82)], [0.022, 0.030, 0.022, 0.008], _crown_material, 6, 8)
		_tube(_head, "AntlerBranchConduit", [Vector3(side * 1.94, 2.06, -0.70), Vector3(side * 2.54, 2.30, -0.58),
			Vector3(side * 2.86, 2.70, -0.50)], [0.024, 0.017, 0.005], _crown_material, 6, 6)
	_electric_forks = _pivot(_head, "LightningCrownForks", Vector3.ZERO)
	_tube(_electric_forks, "CrownCrossArc", [Vector3(-2.1, 2.3, -0.16), Vector3(-1.42, 2.7, 0.08), Vector3(-1.02, 2.4, 0.26),
		Vector3(-0.5, 2.96, 0.28), Vector3(0.1, 2.54, 0.5), Vector3(0.65, 3.04, 0.24), Vector3(1.15, 2.65, 0.12),
		Vector3(2.12, 2.35, -0.12)], [0.017, 0.026, 0.018, 0.026, 0.021, 0.028, 0.018, 0.008], _electric_material, 5, 1)
	for side: float in [-1.0, 1.0]:
		_tube(_electric_forks, "ForkedAntlerDischarge", [Vector3(side * 1.14, 2.65, 0.12), Vector3(side * 1.3, 3.3, -0.05),
			Vector3(side * 1.88, 3.65, -0.22), Vector3(side * 2.5, 3.32, -0.33)], [0.02, 0.025, 0.017, 0.006], _electric_material, 5, 1)
	_electric_forks.visible = false


# ---------------------------------------------------------------- 基础构件

func _pivot(parent: Node3D, label: String, at: Vector3) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = label
	node.position = at
	parent.add_child(node)
	return node


func _mat(color: Color, metal: float, rough: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = rough
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _skin(color: Color, surface_kind: float = 0.0, sss: float = 1.0, cell: float = 6.0) -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = SKIN_SHADER
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("skin_color", color)
	material.set_shader_parameter("surface_kind", surface_kind)
	material.set_shader_parameter("sss_amount", sss)
	material.set_shader_parameter("cell_scale", cell)
	_skin_materials.append(material)
	return material


func _eye_surface(radius: float, glow: float) -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = EYE_SHADER
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("eye_radius", radius)
	material.set_shader_parameter("glow", glow)
	return material


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = _mat(color, 0.07, 0.55)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	_glow_materials.append(material)
	_glow_base.append(energy)
	return material


func _sphere(parent: Node3D, label: String, at: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var rings: int = 22
	var segments: int = 26
	var pts: PackedVector3Array = PackedVector3Array()
	var centers: PackedVector3Array = PackedVector3Array()
	for r: int in range(rings + 1):
		var lat: float = -PI * 0.5 + PI * float(r) / float(rings)
		centers.append(at)
		for c: int in range(segments):
			var theta: float = float(c) * TAU / float(segments)
			pts.append(at + Vector3(cos(lat) * sin(theta), sin(lat), cos(lat) * cos(theta)) * radius)
	return _grid_mesh(parent, label, pts, segments, rings + 1, material, true, centers)


func _ellipsoid(parent: Node3D, label: String, center: Vector3, dimensions: Vector3, material: Material, sculpt: float) -> MeshInstance3D:
	var rings: int = 16
	var segments: int = 24
	var pts: PackedVector3Array = PackedVector3Array()
	var centers: PackedVector3Array = PackedVector3Array()
	for r: int in range(rings + 1):
		var lat: float = -PI * 0.5 + PI * float(r) / float(rings)
		centers.append(center)
		for c: int in range(segments):
			var theta: float = float(c) * TAU / float(segments)
			var n: Vector3 = Vector3(cos(lat) * sin(theta), sin(lat), cos(lat) * cos(theta))
			var disp: float = 1.0 + sculpt * (0.30 * cos(theta * 4.0) * cos(lat) * cos(lat) + 0.12 * sin(lat * 5.0))
			pts.append(center + n * dimensions * disp)
	return _grid_mesh(parent, label, pts, segments, rings + 1, material, true, centers)


func _catmull(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	return 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (-a + 3.0 * b - 3.0 * c + d) * t * t * t)


func _tube(parent: Node3D, label: String, points: Array[Vector3], radii: Array[float], material: Material, sides: int = 12, steps: int = 6) -> MeshInstance3D:
	var centers: Array[Vector3] = []
	var widths: Array[float] = []
	for span: int in range(points.size() - 1):
		for segment: int in range(steps):
			var t: float = float(segment) / float(steps)
			centers.append(_catmull(points[maxi(0, span - 1)], points[span], points[span + 1], points[mini(span + 2, points.size() - 1)], t))
			widths.append(lerpf(radii[span], radii[span + 1], t))
	centers.append(points[-1])
	widths.append(radii[-1])
	var rows: int = centers.size()
	var pts: PackedVector3Array = PackedVector3Array()
	var row_centers: PackedVector3Array = PackedVector3Array()
	for row: int in range(rows):
		var tangent: Vector3 = (centers[mini(row + 1, rows - 1)] - centers[maxi(0, row - 1)]).normalized()
		var reference: Vector3 = Vector3.FORWARD if absf(tangent.dot(Vector3.FORWARD)) < 0.92 else Vector3.RIGHT
		var axis_a: Vector3 = tangent.cross(reference).normalized()
		var axis_b: Vector3 = tangent.cross(axis_a).normalized()
		row_centers.append(centers[row])
		for column: int in range(sides):
			var angle: float = float(column) * TAU / float(sides)
			var normal: Vector3 = cos(angle) * axis_a + sin(angle) * axis_b
			var organic: float = 1.0 + sin(float(row) * 0.9 + angle * 3.0) * 0.03
			pts.append(centers[row] + normal * maxf(widths[row], 0.003) * organic)
	return _grid_mesh(parent, label, pts, sides, rows, material, true, row_centers)


func _spike(parent: Node3D, base: Vector3, direction: Vector3, length: float, radius: float, material: Material) -> void:
	var dir: Vector3 = direction.normalized()
	var side: Vector3 = dir.cross(Vector3.RIGHT)
	if side.length_squared() < 0.01:
		side = dir.cross(Vector3.FORWARD)
	side = side.normalized()
	var bend: Vector3 = side * 0.0 - dir * 0.15
	_tube(parent, "BarbedSpike", [base, base + dir * length * 0.45 + bend * length * 0.2,
		base + dir * length * 0.82 + bend * length * 0.55], [radius, radius * 0.55, 0.003], material, 9, 4)


func _shield(parent: Node3D, label: String, at: Vector3, size: Vector3, rotation: Vector3, material: Material, basis_in: Basis = Basis()) -> MeshInstance3D:
	# 穹顶形甲片：中心隆起、边缘薄，靠自身法线就能吃光
	var cols: int = 9
	var rows: int = 9
	var pts: PackedVector3Array = PackedVector3Array()
	var centers: PackedVector3Array = PackedVector3Array()
	var outline: Array[Vector2] = [Vector2(0, 1.05), Vector2(0.6, 0.72), Vector2(0.98, 0.0),
		Vector2(0.62, -0.55), Vector2(0, -1.28), Vector2(-0.62, -0.55), Vector2(-0.98, 0.0), Vector2(-0.6, 0.72)]
	var basis: Basis = Basis.from_euler(rotation) if basis_in == Basis() else basis_in
	for r: int in range(rows):
		var v: float = float(r) / float(rows - 1) * 2.0 - 1.0
		centers.append(at)
		for c: int in range(cols):
			var u: float = float(c) / float(cols - 1) * 2.0 - 1.0
			var radius: float = sqrt(u * u + v * v)
			if radius > 1.0:
				radius = 1.0
			var dome: float = cos(radius * PI * 0.5)
			var local: Vector3 = Vector3(u * size.x, v * size.y, dome * size.z)
			# 尖端上挑，像真正的骨片
			local.z += (v * 0.5 + 0.5) * size.z * 0.55 * (1.0 - absf(u))
			pts.append(at + basis * local)
	var instance: MeshInstance3D = _grid_mesh(parent, label, pts, cols, rows, material, false, centers)
	instance.name = label
	return instance


func _eye_bowl(parent: Node3D, at: Vector3, size: Vector2, depth: float, angle: float, material: Material) -> void:
	var steps: int = 7
	var segments: int = 32
	var pts: PackedVector3Array = PackedVector3Array()
	var centers: PackedVector3Array = PackedVector3Array()
	for row: int in range(steps + 1):
		var u: float = float(row) / float(steps)
		centers.append(at)
		for c: int in range(segments):
			var theta: float = float(c) * TAU / float(segments)
			var x: float = cos(theta) * size.x * u
			var y: float = sin(theta) * size.y * u * (0.58 + 0.42 * absf(sin(theta)))
			pts.append(at + Vector3(x * cos(angle) - y * sin(angle), x * sin(angle) + y * cos(angle), -depth * (1.0 - u * u)))
	_grid_mesh(parent, "ConcaveOrbit", pts, segments, steps + 1, material, true, centers)


func _membrane(parent: Node3D, a: Vector3, b: Vector3, c: Vector3, material: Material) -> void:
	var steps: int = 14
	var pts: PackedVector3Array = PackedVector3Array()
	var centers: PackedVector3Array = PackedVector3Array()
	for row: int in range(steps + 1):
		var u: float = float(row) / float(steps)
		centers.append(a.lerp(b.lerp(c, u), 0.5))
		for c2: int in range(steps + 1):
			var v: float = float(c2) / float(steps)
			var outer: Vector3 = b.lerp(c, u)
			outer.z -= sin(u * PI) * 0.42
			outer.y += sin(u * PI * 5.0 + 0.25) * sin(u * PI) * 0.24
			var point: Vector3 = a.lerp(outer, v)
			# 撕裂的下缘
			point.z += sin(v * PI) * sin(u * PI) * 0.30
			point.y -= pow(v, 3.0) * sin(u * 9.0) * 0.10
			pts.append(point)
	_grid_mesh(parent, "TornFaceFin", pts, steps + 1, steps + 1, material, false, centers)




func _register_sway(pivot: Node3D, points: Array[Vector3], amplitude: float, phase: float) -> void:
	var axis: Vector3 = (points[points.size() - 1] - points[0])
	var length: float = maxf(axis.length(), 0.001)
	_sway_bindings.append({"pivot": pivot, "axis": axis.normalized(), "length": length,
		"bias": axis.normalized().dot(points[0]), "amplitude": amplitude, "phase": phase})


func _bind_limb_sway() -> void:
	# 每条巨肢按自己的静止轴做相位延迟的行波：无骨骼也能有"一节推着一节"的延迟感。
	# 振幅刻意压在命中胶囊的容差内（0.10 局部单位 = 0.3 m 世界尺度）。
	for binding: Dictionary in _sway_bindings:
		var pivot: Node3D = binding["pivot"] as Node3D
		if not is_instance_valid(pivot):
			continue
		var axis: Vector3 = binding["axis"] as Vector3
		for child: Node in pivot.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).material_override == _mat_hide:
				(child as MeshInstance3D).set_instance_shader_parameter("sway_axis",
					Vector4(axis.x, axis.y, axis.z, float(binding["length"])))
				(child as MeshInstance3D).set_instance_shader_parameter("sway_motion",
					Vector4(float(binding["phase"]), float(binding["amplitude"]), 1.05, float(binding["bias"])))


func _apply_light_layers(parent: Node3D) -> void:
	# 巨兽同时属于默认层与专属轮廓层：既有环境光，也有只照它的造型光。
	for child: Node in parent.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).layers = 1 | 4
		elif child is Node3D:
			_apply_light_layers(child as Node3D)


func _add_silhouette_lights() -> void:
	# 只作用于巨兽的定向轮廓光：在风暴天幕前把剪影"抠"出来。
	# 灯随身体转向，因此无论从哪个方位看都保持同一套明暗关系。
	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.name = "SilhouetteRim"
	rim.light_cull_mask = 4
	rim.light_color = Color("b4d2ec")
	rim.light_energy = 1.35
	rim.shadow_enabled = false
	rim.rotation_degrees = Vector3(-56.0, 28.0, 0.0)
	add_child(rim)
	var kicker: DirectionalLight3D = DirectionalLight3D.new()
	kicker.name = "EdgeKicker"
	kicker.light_cull_mask = 4
	kicker.light_color = Color("6fa6bd")
	kicker.light_energy = 0.55
	kicker.shadow_enabled = false
	kicker.rotation_degrees = Vector3(-18.0, 150.0, 0.0)
	add_child(kicker)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.name = "MawFill"
	fill.light_cull_mask = 4
	fill.light_color = Color("2f6f78")
	fill.light_energy = 0.50
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(26.0, -10.0, 0.0)
	add_child(fill)

# ---------------------------------------------------------------- 合并与绑定

func _merge_static_meshes(parent: Node3D) -> void:
	var builders: Dictionary = {}
	var originals: Array[MeshInstance3D] = []
	for child: Node in parent.get_children():
		if child is MeshInstance3D:
			var instance: MeshInstance3D = child as MeshInstance3D
			if instance.has_meta("no_merge"):
				continue
			var material: Material = instance.material_override
			if material == null or instance.mesh == null:
				continue
			if not builders.has(material):
				var builder: SurfaceTool = SurfaceTool.new()
				builder.begin(Mesh.PRIMITIVE_TRIANGLES)
				builders[material] = builder
			var target: SurfaceTool = builders[material] as SurfaceTool
			for surface: int in range(instance.mesh.get_surface_count()):
				target.append_from(instance.mesh, surface, instance.transform)
			originals.append(instance)
		elif child is Node3D:
			_merge_static_meshes(child as Node3D)
	for material: Material in builders:
		var builder: SurfaceTool = builders[material] as SurfaceTool
		builder.index()
		var combined: MeshInstance3D = MeshInstance3D.new()
		combined.name = "CombinedStaticDetail"
		combined.mesh = builder.commit()
		combined.material_override = material
		parent.add_child(combined)
	for instance: MeshInstance3D in originals:
		instance.free()


func _bind_material_rest_coordinates(parent: Node3D) -> void:
	for child: Node in parent.get_children():
		if child is MeshInstance3D:
			var instance: MeshInstance3D = child as MeshInstance3D
			if not instance.material_override is ShaderMaterial or not _skin_materials.has(instance.material_override):
				continue
			var rest: Transform3D = global_transform.affine_inverse() * instance.global_transform
			var normals: Basis = rest.basis.inverse().transposed()
			for row: int in range(3):
				var axis: String = ["x", "y", "z"][row]
				instance.set_instance_shader_parameter("rest_position_" + axis, Vector4(rest.basis.x[row], rest.basis.y[row], rest.basis.z[row], rest.origin[row]))
				instance.set_instance_shader_parameter("rest_normal_" + axis, Vector4(normals.x[row], normals.y[row], normals.z[row], 0.0))
		elif child is Node3D:
			_bind_material_rest_coordinates(child as Node3D)


func _sync_material_coordinates() -> void:
	var inverse_root: Transform3D = global_transform.affine_inverse()
	for material: ShaderMaterial in _skin_materials:
		material.set_shader_parameter("monster_world_inverse", inverse_root)


# ---------------------------------------------------------------- 命中代理（接口不变）

func _cache_hit_tube(pivot: Node3D, label: String, points: Array[Vector3], radii: Array[float]) -> void:
	var is_tentacle: bool = label == "ContinuousArmoredTentacle"
	var divisions: int = 2 if is_tentacle else 1
	var group: String = "tentacle_%d" % _tentacles.find(pivot) if is_tentacle else "foreclaw_%d" % _arms.find(pivot)
	var tube_id: int = _hit_segments.size()
	var padding: float = 0.01 if is_tentacle else 0.07 if label == "SinewedArm" else 0.025
	for span: int in range(points.size() - 1):
		for section: int in range(divisions):
			var t0: float = float(section) / float(divisions)
			var t1: float = float(section + 1) / float(divisions)
			var a: Vector3 = _catmull(points[maxi(0, span - 1)], points[span], points[span + 1], points[mini(span + 2, points.size() - 1)], t0)
			var b: Vector3 = _catmull(points[maxi(0, span - 1)], points[span], points[span + 1], points[mini(span + 2, points.size() - 1)], t1)
			var width: float = maxf(lerpf(radii[span], radii[span + 1], t0), lerpf(radii[span], radii[span + 1], t1))
			if is_tentacle:
				width = lerpf(radii[span], radii[span + 1], (t0 + t1) * 0.5)
			_hit_segments.append({"pivot": pivot, "part_id": "%s_%s_%d_%d_%d" % [group, label, tube_id, span, section],
				"a": a, "b": b, "radius": width * 1.025 + padding})


func get_hit_capsules() -> Array[Dictionary]:
	var capsules: Array[Dictionary] = []
	var model_inverse: Transform3D = global_transform.affine_inverse()
	for segment: Dictionary in _hit_segments:
		var pivot: Node3D = segment["pivot"] as Node3D
		var local_pose: Transform3D = model_inverse * pivot.global_transform
		var stretch: float = maxf(local_pose.basis.x.length(), maxf(local_pose.basis.y.length(), local_pose.basis.z.length()))
		capsules.append({"part_id": segment["part_id"], "a": (local_pose * (segment["a"] as Vector3)) * 3.0,
			"b": (local_pose * (segment["b"] as Vector3)) * 3.0, "radius": float(segment["radius"]) * stretch * 3.0,
			"surface": "armor", "damage_scale": {"ballista": .70, "cannon": .90, "harpoon": .80}, "poise_scale": 1.0})
	return capsules


# ---------------------------------------------------------------- 动画

func set_state(time: float, attack: String, windup: float, stagger: float, motion_speed: float = 0.0, boss_state: String = "chase") -> void:
	if not is_instance_valid(_root):
		return
	var dt: float = clampf(time - _last_time, 0.0, 0.25)
	_last_time = time
	_flash = maxf(0.0, _flash - dt * 4.5)
	var state: String = boss_state
	if state == "stunned":
		state = "stagger"
	if state != _previous_state or attack != _previous_attack:
		if state == "recovery":
			_recovery_pose = _capture_pose()
		_phase_time = 0.0
		_previous_state = state
		_previous_attack = attack
	else:
		_phase_time += dt
	var charge: float = smoothstep(0.0, 1.0, clampf(windup, 0.0, 1.0))
	var active: bool = state == "active"
	var preparing: bool = state == "windup"
	var interrupted: bool = state == "stagger" or stagger > 0.65
	var hurt: float = clampf(stagger, 0.0, 1.0)
	var speed: float = clampf(motion_speed / 18.0, 0.0, 1.5)
	var breath: float = sin(time * 1.05)
	var stroke_duration: float = 0.22 if attack == "cleave" else 0.58
	var stroke: float = smoothstep(0.0, 1.0, clampf(_phase_time / stroke_duration, 0.0, 1.0))

	# 呼吸：胸腔扩张 + 背脊缓慢起伏，巨兽"活着"
	_root.position = Vector3(0, breath * 0.085, 0)
	_root.rotation = Vector3(0.040 * speed, sin(time * 0.53) * 0.008, sin(time * 0.71) * 0.008)
	_head.position = Vector3(0, 7.0 + sin(time * 1.05 - 0.3) * 0.075, sin(time * 0.37) * 0.06)
	_head.rotation = Vector3(0.014 * breath - 0.030 * speed + sin(time * 0.31) * 0.008, sin(time * 0.41) * 0.030, 0)
	_jaw.rotation.x = _jaw_rest + maxf(0.0, breath) * 0.05
	_tail.rotation = Vector3(-speed * 0.035, sin(time * 0.64) * 0.10, 0)
	for i: int in range(_arms.size()):
		var side: float = -1.0 if i == 0 else 1.0
		_arms[i].rotation = Vector3(-0.14 * speed + sin(time * 1.1 + float(i)) * 0.024, 0, side * 0.025)
		_arms[i].scale = Vector3.ONE
	for i: int in range(_tentacles.size()):
		var side: float = -1.0 if i < 3 else 1.0
		_tentacles[i].position = Vector3.ZERO
		_tentacles[i].rotation = Vector3(-speed * 0.025, sin(time * 0.30 + float(i) * 0.7) * 0.020,
			side * speed * 0.009 + sin(time * 0.38 + float(i) * 0.9) * 0.014)
		_tentacles[i].scale = Vector3.ONE
	# 诱光灯须独立摆动：这是全画面唯一的呼吸光标
	for i: int in range(_lures.size()):
		var side: float = -1.0 if i == 0 else 1.0
		_lures[i].rotation = Vector3(sin(time * 0.87 + float(i) * 1.7) * 0.10, sin(time * 0.61 + float(i)) * 0.12, side * sin(time * 0.53 + float(i) * 2.1) * 0.09)
	if preparing or active:
		match attack:
			"meteor":
				var lift: float = charge if preparing else 1.0
				_root.position.y += lift * 0.30
				_root.rotation.x -= lift * 0.05
				_head.position.y += lift * 0.32
				_head.rotation.x -= lift * 0.46 + (0.09 * (1.0 - stroke) if active else 0.0)
				_jaw.rotation.x += lift * 0.30
				for i: int in range(_arms.size()):
					var side: float = -1.0 if i == 0 else 1.0
					_arms[i].rotation += Vector3(-lift * 0.28, side * lift * 0.06, side * lift * 0.17)
				for i: int in range(_tentacles.size()):
					_tentacles[i].rotation.z += (-1.0 if i < 3 else 1.0) * lift * 0.038
			"lightning":
				var power: float = charge if preparing else 1.0
				_head.rotation.x -= power * 0.18
				_head.rotation.z = sin(time * 19.0) * 0.007 * power
				_jaw.rotation.x += power * 0.12
				_root.rotation.z += sin(_phase_time * 32.0) * 0.015 * power if active else 0.0
				for i: int in range(_arms.size()):
					_arms[i].rotation.x += power * 0.27
				for i: int in range(_tentacles.size()):
					_tentacles[i].rotation.y += (-1.0 if i < 3 else 1.0) * power * 0.075
			"lunge":
				if preparing:
					_root.position += Vector3(0, -charge * 0.46, -charge * 0.38)
					_root.rotation.x -= charge * 0.09
					_head.rotation.x += charge * 0.33
					_jaw.rotation.x = 0.03
					for arm: Node3D in _arms:
						arm.rotation.x += charge * 0.62
				else:
					_root.rotation.x += 0.13
					_root.position.y -= 0.12 + sin(stroke * PI) * 0.18
					_head.rotation.x += 0.26
					_jaw.rotation.x = 0.42
					for arm: Node3D in _arms:
						arm.rotation.x = -1.25
						arm.scale = Vector3(1.0, 1.15, 1.0)
				var reach: float = charge * 0.12 if preparing else 0.8
				_tentacles[0].rotation.y += reach
				_tentacles[3].rotation.y -= reach
			"cleave":
				if preparing:
					_root.rotation.y += charge * 0.25
					_root.rotation.z -= charge * 0.075
					_head.rotation.y -= charge * 0.16
					_arms[1].rotation = Vector3(-0.85 * charge, 0.1, -0.65 * charge)
					_tentacles[3].rotation.y = charge * 0.4
					_tentacles[3].rotation.z = -charge * 0.1
				else:
					_root.rotation.y = lerpf(0.25, -0.48, stroke)
					_root.rotation.z = lerpf(-0.075, 0.1, stroke)
					_head.rotation.y = lerpf(-0.16, 0.27, stroke)
					_arms[1].rotation = Vector3(-1.1, lerpf(0.35, -0.75, stroke), lerpf(-0.6, 0.28, stroke))
					_tentacles[3].rotation.y = lerpf(0.4, -1.55, stroke)
					_tentacles[3].rotation.z = lerpf(-0.1, 0.045, stroke)
				var extension: float = 1.0 + 0.16 * (charge if preparing else 1.0)
				_tentacles[3].scale = Vector3(extension, 1.0, extension)
	for i: int in range(_whiskers.size()):
		var side: float = -1.0 if i < 6 else 1.0
		_whiskers[i].rotation = Vector3(sin(time * 1.06 + float(i) * 0.43) * 0.05 - speed * 0.06, 0,
			sin(time * 0.89 + float(i) * 0.38) * 0.05)
		if attack == "lightning" and (preparing or active):
			_whiskers[i].rotation.x -= charge * 0.12
			_whiskers[i].rotation.z += side * charge * 0.08
		elif attack == "lunge" and active:
			_whiskers[i].rotation.x = -0.23
	if state == "recovery" and not _recovery_pose.is_empty():
		var recover: float = smoothstep(0.0, 0.95, _phase_time)
		for node: Node3D in _recovery_pose:
			var origin: Transform3D = _recovery_pose[node]
			node.transform = origin.interpolate_with(node.transform, recover)
		if attack == "cleave":
			_tentacles[3].position.y -= sin(recover * PI) * 1.6
		elif attack == "lunge":
			_tentacles[0].position.y -= sin(recover * PI) * 0.85
			_tentacles[3].position.y -= sin(recover * PI) * 0.85
	if interrupted:
		_root.position.y -= 0.55 + hurt * 0.2
		_root.rotation = Vector3(-0.07, 0, sin(time * 23.0) * 0.018 * maxf(hurt, 0.4))
		_head.rotation = Vector3(0.34 + hurt * 0.1, 0, -0.035)
		_jaw.rotation.x = 0.34
		for arm: Node3D in _arms:
			arm.rotation.x = 0.25
		for i: int in range(_tentacles.size()):
			_tentacles[i].rotation.z = (-1.0 if i < 3 else 1.0) * 0.065
	if state == "dead":
		_root.rotation.x = 0.30
		_root.position.y = -1.9
		_head.rotation.x = 0.52
		_jaw.rotation.x = 0.46
	_update_attack_light(time, attack, state, charge, interrupted)
	_sync_material_coordinates()


func _capture_pose() -> Dictionary:
	var pose: Dictionary = {}
	var nodes: Array[Node3D] = [_root, _head, _jaw, _tail]
	nodes.append_array(_arms)
	nodes.append_array(_tentacles)
	nodes.append_array(_whiskers)
	nodes.append_array(_lures)
	for node: Node3D in nodes:
		pose[node] = node.transform
	return pose


func _update_attack_light(time: float, attack: String, state: String, charge: float, interrupted: bool) -> void:
	var engaged: bool = (state == "windup" or state == "active") and not interrupted
	var power: float = charge if state == "windup" else 1.0
	var pulse: float = 0.5 + 0.5 * sin(time * 9.0)
	var wound_position: Vector3 = to_local(_wound_pivot.to_global(_wound_local_point)) if is_instance_valid(_wound_pivot) else Vector3.ZERO
	_mat_hide.set_shader_parameter("sway_time", time)
	_mat_fin.set_shader_parameter("sway_time", time)
	for material: ShaderMaterial in _skin_materials:
		material.set_shader_parameter("wound_glow", _flash)
		material.set_shader_parameter("wound_position", wound_position)
		material.set_shader_parameter("time", time)
	if is_instance_valid(_eye_material):
		_eye_material.set_shader_parameter("time", time)
		_eye_material.set_shader_parameter("glow", 1.0 + (0.7 if engaged else 0.0) + _flash * 0.5)
	for i: int in range(_glow_materials.size()):
		_glow_materials[i].emission_energy_multiplier = minf(2.8, _glow_base[i] * (0.94 + sin(time * 1.3) * 0.06))
	_mouth_material.emission_energy_multiplier = 0.18 + _flash * 0.5
	_crown_material.emission = Color("6342a0")
	_crown_material.albedo_color = Color("342446")
	_crown_material.emission_energy_multiplier = 0.10
	_electric_forks.visible = false
	_sensory_material.emission_energy_multiplier = 0.24
	for i: int in range(_tentacle_lights.size()):
		_tentacle_lights[i].emission_energy_multiplier = 0.40
		if engaged and attack == "lightning":
			_tentacle_lights[i].emission_energy_multiplier = 0.7 + power * 0.8
		elif engaged and attack == "cleave" and i == 3:
			_tentacle_lights[i].emission_energy_multiplier = 0.6 + power * 1.0
	for i: int in range(_core_materials.size()):
		_core_materials[i].emission = Color("8a52d8") if i != 2 else Color("3fb0c8")
		_core_materials[i].albedo_color = _core_materials[i].emission * 0.7
		_core_materials[i].emission_energy_multiplier = 0.72 + sin(time * 1.0 + float(i)) * 0.08
		_back_cores[i].scale = Vector3.ONE
		if engaged and attack == "meteor":
			_core_materials[i].emission = Color("d4703a")
			_core_materials[i].albedo_color = Color("4e251c")
			_core_materials[i].emission_energy_multiplier = 0.7 + power * (0.7 + pulse * 0.5)
	if engaged:
		if attack == "meteor":
			_crown_material.emission = Color("bd6735")
			_crown_material.albedo_color = Color("573626")
			_crown_material.emission_energy_multiplier = 0.35 + power * (0.9 + pulse * 0.4)
			_mouth_material.emission_energy_multiplier = 0.3 + power * 0.5
		elif attack == "lightning":
			_electric_forks.visible = power > 0.38
			_electric_forks.scale = Vector3(1.0, 1.0 + sin(time * 31.0) * 0.055, 1.0)
			_electric_material.emission_energy_multiplier = 0.7 + power * (0.7 + pulse * 0.6)
			_crown_material.emission = Color("456bb9")
			_crown_material.emission_energy_multiplier = 0.4 + power * 0.9
			_sensory_material.emission_energy_multiplier = 0.55 + power * (0.5 + pulse * 0.3)
		elif attack == "lunge":
			_mouth_material.emission_energy_multiplier = 0.42 + power * 0.5
	if interrupted or state == "dead":
		_electric_forks.visible = false
		_crown_material.emission_energy_multiplier = 0.06
		for material: StandardMaterial3D in _core_materials:
			material.emission_energy_multiplier = 0.3


func hit_flash(strength: float = 1.0, world_point: Vector3 = Vector3.INF, part_id: String = "") -> void:
	_flash = maxf(_flash, clampf(strength, 0.0, 1.5))
	_wound_pivot = self
	for segment: Dictionary in _hit_segments:
		if str(segment["part_id"]) == part_id:
			_wound_pivot = segment["pivot"] as Node3D
			break
	if part_id.begins_with("weak_"):
		var core_index: int = int(part_id.trim_prefix("weak_"))
		if core_index == 0:
			_wound_pivot = _head
		elif core_index - 1 < _back_cores.size():
			_wound_pivot = _back_cores[core_index - 1]
	_wound_local_point = _wound_pivot.to_local(world_point if world_point.is_finite() else get_weakpoint())


func get_weakpoint() -> Vector3:
	if is_instance_valid(_head):
		return _head.to_global(Vector3(0, 0.98, 2.15))
	return to_global(Vector3(0, 7.98, 2.15))


func get_weakpoints() -> Array[Vector3]:
	var points: Array[Vector3] = [get_weakpoint()]
	for core: Node3D in _back_cores:
		points.append(core.to_global(Vector3(0, 0, 0.36)))
	return points
