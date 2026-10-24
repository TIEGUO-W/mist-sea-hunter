extends Node3D
## Procedural junk-style warship. The bow points toward local -Z.

var muzzle: Vector3 = Vector3(0, 3, -7)
var _crew: Array[Node3D] = []
var _barrels: Array[Node3D] = []
var _barrel_homes: Array[Vector3] = []
var _kick: Array[float] = []
var _last_time: float = -1.0
var _wood: Material
var _dark: Material
var _gold: Material
var _iron: Material
var _rope: Material
var _weapon_kind: String = "ballista"
var _weapon_mounts: Dictionary = {}
var _weapon_slides: Dictionary = {}
var _weapon_slide_homes: Dictionary = {}
var _muzzle_markers: Dictionary = {}
var _weapon_kick: float = 0.0
var _harpoon_spear: Node3D
var _ballista_bolt: Node3D


func _ready() -> void:
	_wood = _surface_material(Color("443628"), 0)
	_dark = _surface_material(Color("241f1a"), 0)
	_gold = _surface_material(Color("655039"), 1)
	_iron = _surface_material(Color("20292b"), 1)
	_rope = _surface_material(Color("665d47"), 2)
	_build_hull()
	_build_rig()
	_build_weapons()
	_build_crew()
	_build_deck_props()
	set_weapon(_weapon_kind)


func _surface_material(tint: Color, kind: int) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform vec4 tint : source_color;
uniform int kind = 0;
varying vec3 p;
float hash(vec3 q) {return fract(sin(dot(q,vec3(12.9898,78.233,39.425)))*43758.5453);}
float noise(vec3 q) {
 vec3 i=floor(q), f=fract(q); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex(){p=VERTEX;}
void fragment(){
 float n=noise(p*19.0), wear=noise(p*3.1);
 if(kind==0){
   float grain=noise(vec3(p.x*1.2,p.y*18.0,p.z*95.0));
   float fibers=pow(abs(sin(p.z*210.0+noise(p*4.0)*9.0)),12.0);
   float split=smoothstep(0.976,0.995,abs(sin((p.x+floor(p.z*2.0)*0.43)*1.9)));
   ALBEDO=tint.rgb*(0.57+grain*0.65+n*0.18)*(1.0-fibers*0.24)*(1.0-split*0.5);
   ROUGHNESS=0.80+wear*0.13; SPECULAR=0.22;
   NORMAL_MAP=vec3(0.5+(grain-0.5)*0.07,0.5+(fibers-0.4)*0.08,1.0);
 }else if(kind==1){
   float pits=smoothstep(0.68,0.83,n);
   ALBEDO=tint.rgb*(0.64+wear*0.7)+vec3(0.038,0.028,0.016)*pits;
   METALLIC=0.68;ROUGHNESS=0.68+pits*0.18+wear*0.08; SPECULAR=0.35;
   NORMAL_MAP=vec3(0.5+(n-0.5)*0.12,0.5+(wear-0.5)*0.1,1.0);
 }else if(kind==3){
   float weave=sin(p.x*225.0)*sin(p.y*265.0);
   float detail=1.0-smoothstep(0.003,0.022,length(fwidth(p)));
   ALBEDO=tint.rgb*(0.86+wear*0.14+weave*detail*0.035);
   ROUGHNESS=0.94; SPECULAR=0.16;
   NORMAL_MAP=vec3(0.5+(n-0.5)*0.045,0.5+weave*detail*0.02,1.0);
 }else{
   float twist=sin(UV.y*125.0+UV.x*31.4159);
   ALBEDO=tint.rgb*(0.6+twist*0.12+n*0.35);ROUGHNESS=0.98;
 }
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("kind", kind)
	return material


func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = 0.7
	return mat


func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node


func _cylinder(parent: Node3D, radius: float, height: float, at: Vector3, mat: Material, top: float = -1.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0.0 else top
	mesh.height = height
	mesh.radial_segments = 12
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node


func _beam(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var node := _cylinder(parent, radius, a.distance_to(b), (a + b) * 0.5, mat)
	node.quaternion = Quaternion(Vector3.UP, (b - a).normalized())


func _oval(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	node.mesh = sphere
	node.material_override = mat
	node.position = at
	node.scale = size
	parent.add_child(node)
	return node


func _ring(parent: Node3D, at: Vector3, radius: float, thickness: float, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - thickness
	torus.outer_radius = radius + thickness
	torus.rings = 20
	torus.ring_segments = 6
	node.mesh = torus
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node


func _triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _build_hull() -> void:
	var outline: Array[Vector3] = [Vector3(0, 1.3, -10), Vector3(3, 1.3, -7), Vector3(4, 1.3, 3), Vector3(3.3, 1.3, 8), Vector3(2.6, 1.3, 10), Vector3(-2.6, 1.3, 10), Vector3(-3.3, 1.3, 8), Vector3(-4, 1.3, 3), Vector3(-3, 1.3, -7)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var lower_a := Vector3(a.x * 0.5, -1.8, a.z * 0.88)
		var lower_b := Vector3(b.x * 0.5, -1.8, b.z * 0.88)
		_triangle(st, a, lower_a, b)
		_triangle(st, b, lower_a, lower_b)
		_triangle(st, Vector3(0, -1.8, 0), lower_b, lower_a)
	st.generate_normals()
	var hull := MeshInstance3D.new()
	hull.mesh = st.commit()
	hull.material_override = _dark
	add_child(hull)
	# Individual deck planks remain inside the bow/stern outline.
	for i in range(40):
		var z := -9.75 + float(i) * 0.5
		var half_width: float
		if z < -7.0:
			half_width = (z + 10.0)
		elif z < 3.0:
			half_width = 3.0 + (z + 7.0) * 0.1
		elif z < 8.0:
			half_width = 4.0 - (z - 3.0) * 0.14
		else:
			half_width = 3.3 - (z - 8.0) * 0.35
		_box(self, Vector3(maxf(0.15, half_width * 2.0 - 0.15), 0.16, 0.47), Vector3(0, 1.36, z), _wood)
		if i % 2 == 0 and half_width > 1.0:
			for side in [-1.0, 1.0]:
				_cylinder(self, 0.025, 0.012, Vector3(side * (half_width - 0.28), 1.448, z), _iron)
		# Staggered plank joints, with sunk iron fixing pins.
		if half_width > 2.0:
			var joint_x := -0.9 if i % 2 == 0 else 1.1
			_box(self, Vector3(0.012, 0.006, 0.43), Vector3(joint_x, 1.444, z), _dark)
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		_beam(self, a + Vector3.UP * 0.15, b + Vector3.UP * 0.15, 0.09, _dark)
		_beam(self, a + Vector3.UP * 1.15, b + Vector3.UP * 1.15, 0.09, _wood)
		var count := maxi(1, int(a.distance_to(b) / 1.8))
		for j in range(count):
			var p := a.lerp(b, float(j) / float(count))
			_beam(self, p, p + Vector3.UP * 1.2, 0.075, _wood)
			_cylinder(self, 0.089, 0.14, p + Vector3.UP * 1.06, _iron)
			_cylinder(self, 0.089, 0.13, p + Vector3.UP * 0.2, _iron)
	# Raised stern, hatch, forward gilded cutwater and dragon-like crest.
	_box(self, Vector3(4.5, 0.5, 3), Vector3(0, 1.7, 7.4), _wood)
	_box(self, Vector3(1.8, 0.18, 2), Vector3(0, 1.5, 1.5), _dark)
	for x in [-0.7, 0.0, 0.7]:
		_box(self, Vector3(0.07, 0.05, 1.8), Vector3(x, 1.61, 1.5), _iron)
	_beam(self, Vector3(0, -1, -8.8), Vector3(0, 2.15, -10.3), 0.12, _iron)
	_oval(self, Vector3(0, 2.38, -10.45), Vector3(0.48, 0.55, 0.95), _gold)
	_oval(self, Vector3(0, 2.43, -10.94), Vector3(0.35, 0.24, 0.5), _gold)
	_box(self, Vector3(0.25, 0.035, 0.5), Vector3(0, 2.33, -10.99), _dark)
	for side in [-1.0, 1.0]:
		_beam(self, Vector3(side * 0.15, 2.6, -10.35), Vector3(side * 0.36, 2.99, -10.0), 0.045, _gold)
		_oval(self, Vector3(side * 0.22, 2.53, -10.62), Vector3(0.07, 0.06, 0.1), _iron)
		for fin in range(4):
			_beam(self, Vector3(side * 0.1, 2.5, -10.15 + fin * 0.2), Vector3(side * 0.3, 2.71, -10.01 + fin * 0.2), 0.035, _gold)
		for z in [-5.0, 0.0, 5.0]:
			_box(self, Vector3(0.12, 0.5, 0.4), Vector3(side * 3.35, 0.5, z), _gold)


func _build_rig() -> void:
	var rig: Node3D=Node3D.new()
	rig.name="CameraOccludingRig"
	add_child(rig)
	_beam(rig, Vector3(0, 1.6, 6.5), Vector3(0, 15.4, 6.5), 0.19, _dark)
	var sail_mat := _material(Color("b9a079"))
	sail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0, 1.0]:
		_beam(rig, Vector3(0, 14.7, 6.5), Vector3(side * 3.6, 1.8, 5.5), 0.035, _rope)
		_beam(rig, Vector3(0, 14.7, 6.5), Vector3(side * 2.8, 2, 9), 0.035, _rope)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var a := Vector3(side * 0.35, 7, 6.7)
		var b := Vector3(side * 5.3, 7.5, 7.3)
		var c := Vector3(side * 4.0, 13.8, 7.1)
		var d := Vector3(side * 0.35, 14.5, 6.7)
		_triangle(st, a, b, c)
		_triangle(st, a, c, d)
		st.generate_normals()
		var sail := MeshInstance3D.new()
		sail.mesh = st.commit()
		sail.material_override = sail_mat
		rig.add_child(sail)
		for j in range(5):
			var t := float(j) / 4.0
			_beam(rig, a.lerp(d, t), b.lerp(c, t), 0.055, _dark)
	_beam(rig, Vector3(-4.1, 14, 6.7), Vector3(4.1, 14, 6.7), 0.07, _dark)

	# Keep a complete ship for world/editor cameras; the bow combat camera
	# excludes this layer so canvas and stays cannot conceal a locked attack.
	for child: Node in rig.get_children():
		if child is VisualInstance3D: (child as VisualInstance3D).layers=4


func _build_weapons() -> void:
	# All primary weapons share one forward turntable; only one rig is visible.
	var pedestal: Node3D = _weapon_node(self,"ForwardWeaponStation",Vector3(0,1.5,-5.9))
	_cylinder(pedestal,0.82,0.08,Vector3.ZERO,_dark)
	_ring(pedestal,Vector3(0,0.06,0),0.7,0.055,_iron)
	for i in range(12):
		var angle: float = float(i)*TAU/12.0
		_cylinder(pedestal,0.035,0.055,Vector3(cos(angle)*0.69,0.12,sin(angle)*0.69),_gold)
	_build_primary_ballista(pedestal)
	_build_primary_cannon(pedestal)
	_build_primary_harpoon(pedestal)
	_merge_weapon_meshes(pedestal)
	for side in [-1.0, 1.0]:
		for z in [-3.0, 0.0, 3.0, 6.0]:
			var x: float = side * (3.05 if z < 4 else 2.7)
			var mount := Node3D.new()
			mount.position = Vector3(x, 1.48, z)
			mount.rotation.y = -side * PI * 0.5
			add_child(mount)
			_box(mount, Vector3(0.74, 0.18, 1.32), Vector3(0, 0.27, 0), _wood)
			for wheel_side in [-1.0, 1.0]:
				_box(mount, Vector3(0.13, 0.46, 0.98), Vector3(wheel_side * 0.3, 0.49, 0), _wood)
				for wheel_z in [-0.42, 0.42]:
					var wheel := _cylinder(mount, 0.22, 0.13, Vector3(wheel_side * 0.44, 0.22, wheel_z), _dark)
					wheel.rotation.z = PI * 0.5
					var tyre := _ring(mount, Vector3(wheel_side * 0.44, 0.22, wheel_z), 0.2, 0.025, _iron)
					tyre.rotation.z = PI * 0.5
					_beam(mount, Vector3(wheel_side * 0.53, 0.22, wheel_z), Vector3(wheel_side * 0.6, 0.22, wheel_z), 0.06, _iron)
				_beam(mount, Vector3(wheel_side * 0.36, 0.44, 0.45), Vector3(wheel_side * 0.69, 0.12, -0.52), 0.035, _rope)
			var gun := Node3D.new()
			gun.position = Vector3(x, 2.15, z)
			gun.rotation.y = -side * PI * 0.5
			add_child(gun)
			var barrel := _cylinder(gun, 0.22, 1.35, Vector3(0, 0, -0.3), _iron, 0.17)
			barrel.rotation.x = PI * 0.5
			var rim := _cylinder(gun, 0.24, 0.12, Vector3(0, 0, -0.98), _iron)
			rim.rotation.x = PI * 0.5
			var bore := _cylinder(gun, 0.145, 0.015, Vector3(0, 0, -1.05), _dark)
			bore.rotation.x = PI * 0.5
			for band_z in [-0.65, 0.05, 0.31]:
				var band := _cylinder(gun, 0.24, 0.065, Vector3(0, 0, band_z), _iron)
				band.rotation.x = PI * 0.5
			_oval(gun, Vector3(0, 0, 0.47), Vector3(0.4, 0.4, 0.38), _iron)
			_beam(gun, Vector3(-0.35, 0, 0.04), Vector3(0.35, 0, 0.04), 0.09, _iron)
			_register_barrel(gun)


func _weapon_node(parent: Node3D,label: String,at: Vector3) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name=label
	node.position=at
	parent.add_child(node)
	return node


func _primary_rig(parent: Node3D,kind: String,slide_at: Vector3,muzzle_at: Vector3) -> Node3D:
	var rig: Node3D = _weapon_node(parent,kind.capitalize()+"Primary",Vector3.ZERO)
	_weapon_mounts[kind]=rig
	var slide: Node3D = _weapon_node(rig,"RecoilingAssembly",slide_at)
	_weapon_slides[kind]=slide
	_weapon_slide_homes[kind]=slide_at
	var marker: Marker3D = Marker3D.new()
	marker.name="ActualMuzzle"
	marker.position=muzzle_at
	slide.add_child(marker)
	_muzzle_markers[kind]=marker
	return rig


func _build_primary_ballista(parent: Node3D) -> void:
	var rig: Node3D = _primary_rig(parent,"ballista",Vector3(0,1.34,-0.1),Vector3(0,0.18,-1.83))
	var main: Node3D = _weapon_slides["ballista"] as Node3D
	_cylinder(rig,0.27,1.08,Vector3(0,0.6,0),_wood)
	_cylinder(rig,0.39,0.14,Vector3(0,1.12,0),_iron)
	for side: float in [-1.0,1.0]:
		_beam(rig,Vector3(side*0.65,0.1,0.45),Vector3(side*0.18,1.15,0),0.085,_wood)
	_box(main,Vector3(0.24,0.24,2.75),Vector3(0,0,-0.16),_dark)
	_box(main,Vector3(0.58,0.3,0.9),Vector3(0,-0.02,0.43),_wood)
	for side: float in [-1.0,1.0]:
		_box(main,Vector3(0.05,0.06,2.55),Vector3(side*0.15,0.14,-0.16),_iron)
		for layer in range(4):
			var y: float = -0.09+layer*0.055
			_beam(main,Vector3(side*0.12,y,-0.58),Vector3(side*0.69,y,-0.86),0.043,_wood)
			_beam(main,Vector3(side*0.69,y,-0.86),Vector3(side*1.19,y,-0.79),0.037,_dark)
			_beam(main,Vector3(side*1.19,y,-0.79),Vector3(side*1.65,y,-0.46),0.028,_wood)
		for brace in range(3):
			_box(main,Vector3(0.07,0.28,0.15),Vector3(side*(0.49+brace*0.38),0,-0.74),_iron)
		_cylinder(main,0.075,0.32,Vector3(side*0.32,0,0.45),_iron)
		for winding in range(6):
			var rope_ring: MeshInstance3D = _ring(main,Vector3(side*(0.17+winding*0.028),0.14,0.72),0.13,0.016,_rope)
			rope_ring.rotation.z=PI*0.5
	_beam(main,Vector3(-0.55,0.14,0.72),Vector3(0.55,0.14,0.72),0.055,_iron)
	_beam(main,Vector3(0.55,0.14,0.72),Vector3(0.55,0.4,0.72),0.04,_iron)
	_beam(main,Vector3(-1.65,0,-0.46),Vector3(0,0.08,0.69),0.018,_rope)
	_beam(main,Vector3(1.65,0,-0.46),Vector3(0,0.08,0.69),0.018,_rope)
	_ballista_bolt=_weapon_node(main,"LoadedBolt",Vector3(0,0.18,0))
	_beam(_ballista_bolt,Vector3(0,0,0.48),Vector3(0,0,-1.53),0.035,_wood)
	var head: MeshInstance3D = _cylinder(_ballista_bolt,0.09,0.28,Vector3(0,0,-1.68),_iron,0.0)
	head.rotation.x=-PI*0.5
	for side: float in [-1.0,1.0]:
		_box(_ballista_bolt,Vector3(0.12,0.016,0.32),Vector3(side*0.045,0,0.32),_dark)
	for bolt in range(4):
		_beam(rig,Vector3(0.42+bolt*0.095,1.17,0.9),Vector3(0.42+bolt*0.095,1.17,-0.15),0.024,_wood)


func _build_primary_cannon(parent: Node3D) -> void:
	var rig: Node3D = _primary_rig(parent,"cannon",Vector3(0,1.06,0),Vector3(0,0,-2.73))
	var main: Node3D = _weapon_slides["cannon"] as Node3D
	_box(rig,Vector3(1.35,0.16,2.55),Vector3(0,0.43,-0.12),_dark)
	for side: float in [-1.0,1.0]:
		_box(rig,Vector3(0.21,0.72,2.65),Vector3(side*0.56,0.72,-0.18),_wood)
		for strap_z: float in [-0.93,-0.05,0.83]:
			_box(rig,Vector3(0.24,0.055,0.17),Vector3(side*0.56,1.1,strap_z),_iron)
			for bolt_y: float in [0.65,0.87]:
				var bolt: MeshInstance3D = _cylinder(rig,0.045,0.025,Vector3(side*0.68,bolt_y,strap_z),_gold)
				bolt.rotation.z=PI*0.5
		for wheel_z: float in [-0.88,0.76]:
			var wheel: MeshInstance3D = _cylinder(rig,0.31,0.16,Vector3(side*0.79,0.33,wheel_z),_dark)
			wheel.rotation.z=PI*0.5
			var tyre: MeshInstance3D = _ring(rig,Vector3(side*0.8,0.33,wheel_z),0.29,0.033,_iron)
			tyre.rotation.z=PI*0.5
			for spoke in range(6):
				var phi: float = float(spoke)*TAU/6.0
				_beam(rig,Vector3(side*0.89,0.33,wheel_z),Vector3(side*0.89,0.33+sin(phi)*0.26,wheel_z+cos(phi)*0.26),0.027,_wood)
		_beam(rig,Vector3(side*0.69,0.59,0.63),Vector3(side*0.95,0.18,1.28),0.043,_rope)
		_beam(main,Vector3(side*0.25,0,0.06),Vector3(side*0.66,0,0.06),0.12,_iron)
	_cannon_shell(main)
	var bore: MeshInstance3D = _cylinder(main,0.17,0.02,Vector3(0,0,-1.68),_dark)
	bore.rotation.x=PI*0.5
	for z: float in [-1.87,-0.73,0.3,0.67]:
		var radius: float = 0.3 if z< -1.0 else 0.405
		var band: MeshInstance3D = _ring(main,Vector3(0,0,z),radius,0.033,_iron)
		band.rotation.x=PI*0.5
	_oval(main,Vector3(0,0,0.9),Vector3(0.5,0.5,0.46),_iron)
	_beam(main,Vector3(0,0,1.03),Vector3(0,0,1.3),0.12,_gold)
	_beam(main,Vector3(0,0.38,0.4),Vector3(0,0.56,0.35),0.043,_gold)
	_box(main,Vector3(0.08,0.13,0.13),Vector3(0,0.4,-1.75),_iron)
	_box(main,Vector3(0.14,0.15,0.08),Vector3(0,0.44,0.65),_iron)
	for side: float in [-1.0,1.0]:
		_beam(rig,Vector3(side*0.95,0.13,0.96),Vector3(side*0.4,0.35,-0.3),0.035,_rope)


func _cannon_shell(parent: Node3D) -> void:
	# A continuous cast profile returns inside the muzzle to form a real dark bore.
	var profile: Array[Vector2] = [Vector2(0.82,0.26),Vector2(0.61,0.39),Vector2(0.18,0.42),Vector2(-0.64,0.36),Vector2(-1.7,0.28),Vector2(-2.42,0.265),Vector2(-2.55,0.335),Vector2(-2.69,0.335),Vector2(-2.72,0.205),Vector2(-2.34,0.185),Vector2(-1.7,0.17)]
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var sides: int = 40
	for row in range(profile.size()):
		var before: Vector2 = profile[maxi(0,row-1)]
		var after: Vector2 = profile[mini(row+1,profile.size()-1)]
		var direction: Vector2 = (after-before).normalized()
		for column in range(sides+1):
			var angle: float = float(column)*TAU/sides
			vertices.append(Vector3(cos(angle)*profile[row].y,sin(angle)*profile[row].y,profile[row].x))
			normals.append(Vector3(-direction.x*cos(angle),-direction.x*sin(angle),direction.y).normalized())
			uvs.append(Vector2(float(column)/sides,float(row)/profile.size()))
			if row<profile.size()-1 and column<sides:
				var index: int = row*(sides+1)+column
				indices.append_array(PackedInt32Array([index,index+sides+1,index+1,index+1,index+sides+1,index+sides+2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uvs
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name="HollowCastIronBarrel"
	instance.mesh=mesh
	instance.material_override=_iron
	parent.add_child(instance)


func _build_primary_harpoon(parent: Node3D) -> void:
	var rig: Node3D = _primary_rig(parent,"harpoon",Vector3(0,1.07,0),Vector3(0,0.14,-2.99))
	var main: Node3D = _weapon_slides["harpoon"] as Node3D
	_box(rig,Vector3(1.24,0.18,2.1),Vector3(0,0.23,0.13),_dark)
	for side: float in [-1.0,1.0]:
		_box(rig,Vector3(0.16,0.8,1.6),Vector3(side*0.44,0.64,-0.22),_wood)
		_beam(rig,Vector3(side*0.57,0.2,0.63),Vector3(side*0.33,1.02,-0.58),0.07,_iron)
	_box(main,Vector3(0.45,0.3,1.48),Vector3(0,-0.05,-0.31),_wood)
	for side: float in [-1.0,1.0]:
		_box(main,Vector3(0.07,0.11,2.05),Vector3(side*0.22,0.12,-0.6),_iron)
		for z: float in [-1.38,-0.74,-0.14]:
			var band: MeshInstance3D = _ring(main,Vector3(0,0.12,z),0.21,0.027,_iron)
			band.rotation.x=PI*0.5
			band.scale.y=0.78
	var drum: MeshInstance3D = _cylinder(rig,0.33,0.84,Vector3(0,0.62,0.64),_wood)
	drum.rotation.z=PI*0.5
	for winding in range(19):
		var coil: MeshInstance3D = _ring(rig,Vector3(-0.35+winding*0.039,0.62,0.64),0.345,0.022,_rope)
		coil.rotation.z=PI*0.5
	for side: float in [-1.0,1.0]:
		var flange: MeshInstance3D = _cylinder(rig,0.41,0.05,Vector3(side*0.46,0.62,0.64),_iron)
		flange.rotation.z=PI*0.5
		_beam(rig,Vector3(side*0.49,0.62,0.64),Vector3(side*0.7,0.62,0.64),0.07,_iron)
		_beam(rig,Vector3(side*0.7,0.62,0.64),Vector3(side*0.7,0.9,0.78),0.045,_gold)
		_beam(rig,Vector3(side*0.7,0.9,0.78),Vector3(side*0.89,0.9,0.78),0.055,_wood)
	_harpoon_spear=_weapon_node(main,"LoadedBarbedHarpoon",Vector3(0,0.14,-0.45))
	_beam(_harpoon_spear,Vector3(0,0,0.85),Vector3(0,0,-2.17),0.046,_iron)
	var point: MeshInstance3D = _cylinder(_harpoon_spear,0.155,0.38,Vector3(0,0,-2.35),_iron,0.0)
	point.rotation.x=-PI*0.5
	for side: float in [-1.0,1.0]:
		_beam(_harpoon_spear,Vector3(0,0,-2.24),Vector3(side*0.25,0,-1.91),0.042,_iron)
		_beam(_harpoon_spear,Vector3(side*0.25,0,-1.91),Vector3(side*0.2,0,-1.78),0.027,_iron)
	_beam(rig,Vector3(0.33,0.84,0.65),Vector3(0.34,1.12,0.2),0.022,_rope)
	_beam(rig,Vector3(0.34,1.12,0.2),Vector3(0,1.2,-0.12),0.022,_rope)
	_beam(main,Vector3(0,0.14,-0.12),Vector3(0,0.14,-0.7),0.022,_rope)


func _merge_weapon_meshes(parent: Node3D) -> void:
	var builders: Dictionary = {}
	var originals: Array[MeshInstance3D] = []
	for child: Node in parent.get_children():
		if child is MeshInstance3D:
			var instance: MeshInstance3D = child as MeshInstance3D
			var material: Material = instance.material_override
			if material==null:
				continue
			if not builders.has(material):
				var tool: SurfaceTool = SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				builders[material]=tool
			var tool: SurfaceTool = builders[material] as SurfaceTool
			for surface in range(instance.mesh.get_surface_count()):
				tool.append_from(instance.mesh,surface,instance.transform)
			originals.append(instance)
		elif child is Node3D:
			_merge_weapon_meshes(child as Node3D)
	for material: Material in builders:
		var tool: SurfaceTool = builders[material] as SurfaceTool
		tool.index()
		var combined: MeshInstance3D = MeshInstance3D.new()
		combined.name="CombinedWeaponDetail"
		combined.mesh=tool.commit()
		combined.material_override=material
		parent.add_child(combined)
	for instance: MeshInstance3D in originals:
		instance.free()


func _register_barrel(node: Node3D) -> void:
	_barrels.append(node)
	_barrel_homes.append(node.position)
	_kick.append(0.0)


## Elliptical tailored sections: profile=(half-width,height,half-depth).
## A few changing sections give shoulders, waist, jaw and cloth wraps real
## volume; no textures, external assets or camera-facing costume cards.
func _crew_loft(parent: Node3D, label: String, profile: Array[Vector3], at: Vector3, material: Material) -> void:
	var tool: SurfaceTool=SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides: int=12
	for row: int in range(profile.size()-1):
		for side: int in range(sides):
			var angle_a: float=float(side)*TAU/float(sides)
			var angle_b: float=float(side+1)*TAU/float(sides)
			var lower: Vector3=profile[row]
			var upper: Vector3=profile[row+1]
			var a: Vector3=at+Vector3(cos(angle_a)*lower.x,lower.y,sin(angle_a)*lower.z)
			var b: Vector3=at+Vector3(cos(angle_b)*lower.x,lower.y,sin(angle_b)*lower.z)
			var c: Vector3=at+Vector3(cos(angle_a)*upper.x,upper.y,sin(angle_a)*upper.z)
			var d: Vector3=at+Vector3(cos(angle_b)*upper.x,upper.y,sin(angle_b)*upper.z)
			_triangle(tool,a,b,c)
			_triangle(tool,b,d,c)
	tool.generate_normals()
	# Match indexed primitive surfaces before append_from batches this mesh.
	tool.index()
	var mesh: MeshInstance3D=MeshInstance3D.new()
	mesh.name=label
	mesh.mesh=tool.commit()
	mesh.material_override=material
	parent.add_child(mesh)

func _crew_panel(parent: Node3D, corners: Array[Vector3], material: Material) -> void:
	var tool: SurfaceTool=SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(1,corners.size()-1): _triangle(tool,corners[0],corners[index+1],corners[index])
	tool.generate_normals()
	# Match indexed primitive surfaces before append_from batches this mesh.
	tool.index()
	var mesh: MeshInstance3D=MeshInstance3D.new()
	mesh.mesh=tool.commit()
	mesh.material_override=material
	parent.add_child(mesh)

func _build_crew() -> void:
	var positions: Array[Vector3]=[Vector3(-1.4,1.48,-3.8),Vector3(1.6,1.48,-1.6),Vector3(-1.5,1.48,3.8)]
	var colors: Array[Color]=[Color("1b2530"),Color("222d36"),Color("1d2731")]
	var skin: StandardMaterial3D=_material(Color("4a372d"))
	skin.roughness=.90
	skin.metallic_specular=.16
	var shadow: StandardMaterial3D=_material(Color("503a30"))
	shadow.roughness=.94
	var hair: StandardMaterial3D=_material(Color("182022"))
	hair.roughness=.94
	var trousers: ShaderMaterial=_surface_material(Color("202e37"),3)
	var linen: ShaderMaterial=_surface_material(Color("40463f"),3)
	var shoes: StandardMaterial3D=_material(Color("1c2425"))
	shoes.roughness=.95
	shoes.metallic_specular=.15
	for index: int in range(3):
		var crew: Node3D=Node3D.new()
		crew.name="NavalSailor%d"%index
		crew.position=positions[index]
		crew.rotation.y=-.2 if index==0 else .2
		add_child(crew)
		_crew.append(crew)
		var coat: ShaderMaterial=_surface_material(colors[index],3)
		var sash: ShaderMaterial=_surface_material(Color("655b46") if index==1 else Color("68483c"),3)
		for side: float in [-1.0,1.0]:
			_oval(crew,Vector3(side*.12,.38,.015),Vector3(.235,.66,.28),trousers)
			_oval(crew,Vector3(side*.12,.085,-.055),Vector3(.23,.15,.37),shoes)
			_box(crew,Vector3(.23,.025,.29),Vector3(side*.12,.035,-.04),_dark)
			for wrap: int in range(2):
				var ankle: MeshInstance3D=_cylinder(crew,.112,.035,Vector3(side*.12,.18+float(wrap)*.045,0),linen,.105)
				ankle.scale.z=1.12
			var shoulder: Vector3=Vector3(side*.235,1.155,0)
			var elbow: Vector3=Vector3(side*.32,.94,-.10)
			var wrist: Vector3=Vector3(side*.24,.985,-.34)
			var sleeve: MeshInstance3D=_cylinder(crew,.114,shoulder.distance_to(elbow),(shoulder+elbow)*.5,coat,.10)
			sleeve.quaternion=Quaternion(Vector3.UP,(shoulder-elbow).normalized())
			_beam(crew,elbow,wrist,.081,coat)
			var cuff: MeshInstance3D=_cylinder(crew,.091,.085,wrist+Vector3(0,-.005,.035),linen)
			cuff.quaternion=Quaternion(Vector3.UP,(wrist-elbow).normalized())
			_oval(crew,Vector3(side*.24,.986,-.392),Vector3(.105,.13,.13),skin)
			_oval(crew,Vector3(side*.197,.986,-.41),Vector3(.048,.065,.072),skin)
			for finger: int in range(3):
				var x: float=side*.24+(float(finger)-1)*.025
				_beam(crew,Vector3(x,.975,-.424),Vector3(x,.925,-.443),.014,skin)
		_crew_loft(crew,"TailoredIndigoJacket",[Vector3(.245,.62,.145),Vector3(.205,.81,.14),Vector3(.265,1.13,.16),Vector3(.245,1.24,.135),Vector3(.11,1.28,.085)],Vector3.ZERO,coat)
		_crew_panel(crew,[Vector3(-.16,1.23,-.145),Vector3(.055,1.20,-.164),Vector3(.175,.84,-.153),Vector3(-.035,.82,-.151)],linen)
		_crew_panel(crew,[Vector3(-.165,1.235,-.15),Vector3(-.10,1.225,-.167),Vector3(.095,.855,-.17),Vector3(.025,.84,-.17)],coat)
		_beam(crew,Vector3(-.13,1.235,-.17),Vector3(.065,.85,-.18),.009,linen)
		# Broad woven sash, off-centre knot and hanging ends replace a gold buckle.
		_crew_loft(crew,"WovenWaistSash",[Vector3(.222,.78,.154),Vector3(.225,.855,.157)],Vector3.ZERO,sash)
		_oval(crew,Vector3(-.20,.82,-.12),Vector3(.10,.105,.085),sash)
		var sash_tail: MeshInstance3D=_box(crew,Vector3(.064,.24,.018),Vector3(-.19,.68,-.154),sash)
		sash_tail.rotation.z=-.17
		# A back yoke/seam and small asymmetric folds read from the ship camera.
		_beam(crew,Vector3(-.20,1.17,.126),Vector3(.20,1.17,.126),.011,linen)
		_beam(crew,Vector3(0,1.15,.163),Vector3(.025,.88,.151),.008,trousers)
		for fold: int in range(3):
			_beam(crew,Vector3(-.19+float(fold)*.11,.90,.14),Vector3(-.145+float(fold)*.095,1.08,.16),.007,trousers)
		_cylinder(crew,.075,.15,Vector3(0,1.31,0),skin)
		_crew_loft(crew,"ShapedJawAndBrow",[Vector3(.075,1.32,.075),Vector3(.117,1.37,.105),Vector3(.135,1.48,.117),Vector3(.124,1.59,.11),Vector3(.08,1.64,.08)],Vector3(0,0,-.018),skin)
		for side: float in [-1.0,1.0]:
			_oval(crew,Vector3(side*.137,1.475,-.01),Vector3(.04,.085,.055),skin)
			_oval(crew,Vector3(side*.08,1.45,-.118),Vector3(.085,.052,.035),skin)
			var eye: MeshInstance3D=_box(crew,Vector3(.052,.014,.014),Vector3(side*.058,1.502,-.132),shadow)
			eye.rotation.z=side*.07
			_beam(crew,Vector3(side*.025,1.527,-.135),Vector3(side*.092,1.524,-.123),.01,hair)
		_oval(crew,Vector3(0,1.463,-.15),Vector3(.063,.093,.095),skin)
		_beam(crew,Vector3(-.035,1.396,-.122),Vector3(.032,1.396,-.122),.007,shadow)
		# Folded headwrap has no wide brim or modern hat silhouette.
		_crew_loft(crew,"FoldedNavalHeadwrap",[Vector3(.143,1.565,.122),Vector3(.148,1.615,.124),Vector3(.10,1.68,.10),Vector3(.023,1.71,.034)],Vector3(0,0,-.015),coat)
		_beam(crew,Vector3(-.125,1.603,-.087),Vector3(.12,1.62,-.082),.012,trousers)
		_oval(crew,Vector3(.085,1.603,.108),Vector3(.105,.075,.075),coat)
		for tail_index: int in range(2):
			var tail: MeshInstance3D=_box(crew,Vector3(.043,.20-float(tail_index)*.025,.017),Vector3(.055+float(tail_index)*.047,1.505,.12),coat)
			tail.rotation.z=.12+float(tail_index)*.13
		# Static costume/face details batch per material; the original crew root
		# remains the animated node, keeping draw calls and scene nodes bounded.
		_merge_weapon_meshes(crew)
		for child: Node in crew.get_children():
			if child is MeshInstance3D: child.name="CombinedCrewSurface"


func _build_deck_props() -> void:
	# Small service props live along the sides, leaving the forward sightline open.
	for at in [Vector3(-2.55, 1.47, -5.35), Vector3(2.6, 1.47, 1.6)]:
		var barrel := Node3D.new()
		barrel.position = at
		add_child(barrel)
		_cylinder(barrel, 0.29, 0.7, Vector3(0, 0.35, 0), _wood, 0.26)
		for h in [0.08, 0.35, 0.62]:
			_ring(barrel, Vector3(0, h, 0), 0.28, 0.025, _iron)
		_cylinder(barrel, 0.255, 0.035, Vector3(0, 0.72, 0), _dark)
		for angle in range(10):
			var phi := float(angle) * TAU / 10.0
			_beam(barrel, Vector3(cos(phi) * 0.28, 0.05, sin(phi) * 0.28), Vector3(cos(phi) * 0.255, 0.68, sin(phi) * 0.255), 0.009, _dark)
	for i in range(5):
		_ring(self, Vector3(-2.55, 1.48 + i * 0.018, -1.2), 0.19 + i * 0.045, 0.022, _rope)
	_beam(self, Vector3(-2.5, 1.5, -1.2), Vector3(-3.2, 1.5, -0.8), 0.025, _rope)
	var hook := _ring(self, Vector3(-3.2, 1.55, -0.8), 0.1, 0.024, _iron)
	hook.rotation.x = 0.8
	_box(self, Vector3(0.9, 0.42, 0.75), Vector3(2.6, 1.67, -5.2), _dark)
	for side in [-1.0, 1.0]:
		_box(self, Vector3(0.06, 0.45, 0.78), Vector3(2.6 + side * 0.3, 1.68, -5.2), _iron)
	for row in range(2):
		for col in range(3):
			_oval(self, Vector3(2.35 + col * 0.23, 1.94, -5.36 + row * 0.23), Vector3(0.2, 0.2, 0.2), _iron)


func animate_ship(time: float, turn: float, speed: float) -> void:
	var dt := clampf(time - _last_time, 0.0, 0.1) if _last_time >= 0.0 else 0.016
	_last_time = time
	for i in range(_crew.size()):
		_crew[i].rotation.z = sin(time * 2.5 + float(i) * 1.8) * 0.035 - turn * 0.04
		_crew[i].rotation.x = sin(time * 3.0 + float(i)) * 0.025 * clampf(absf(speed) * 0.1, 0.2, 1.0)
	for i in range(_barrels.size()):
		_kick[i] = move_toward(_kick[i], 0.0, dt * 1.8)
		_barrels[i].position = _barrel_homes[i] + _barrels[i].basis.z * _kick[i]
	var return_speed: float = 1.05 if _weapon_kind=="cannon" else 1.5
	_weapon_kick=move_toward(_weapon_kick,0.0,dt*return_speed)
	if _weapon_slides.has(_weapon_kind):
		var slide: Node3D = _weapon_slides[_weapon_kind] as Node3D
		var home: Vector3 = _weapon_slide_homes[_weapon_kind]
		slide.position=home+Vector3.BACK*_weapon_kick
	if is_instance_valid(_harpoon_spear):
		_harpoon_spear.visible=not (_weapon_kind=="harpoon" and _weapon_kick>0.15)
	if is_instance_valid(_ballista_bolt):
		_ballista_bolt.visible=not (_weapon_kind=="ballista" and _weapon_kick>0.06)
	get_muzzle_local()


func recoil(weapon: String) -> void:
	var kind: String = weapon.to_lower()
	if kind in ["broadside", "cannons", "volley", "crew"]:
		for i in range(_kick.size()):
			_kick[i] = 0.45
	elif kind==_weapon_kind:
		_weapon_kick={"ballista":0.19,"cannon":0.68,"harpoon":0.4}.get(kind,0.0)
		if _weapon_slides.has(kind):
			var slide: Node3D = _weapon_slides[kind] as Node3D
			var home: Vector3 = _weapon_slide_homes[kind]
			slide.position=home+Vector3.BACK*_weapon_kick
		if kind=="harpoon" and is_instance_valid(_harpoon_spear):
			_harpoon_spear.hide()
		if kind=="ballista" and is_instance_valid(_ballista_bolt):
			_ballista_bolt.hide()
		get_muzzle_local()


func set_weapon(kind: String) -> void:
	var selected: String = kind.to_lower()
	if selected not in ["ballista","cannon","harpoon"]:
		selected="ballista"
	if selected!=_weapon_kind:
		_weapon_kick=0.0
	_weapon_kind=selected
	for key: String in _weapon_mounts:
		(_weapon_mounts[key] as Node3D).visible=key==selected
		if key!=selected:
			(_weapon_slides[key] as Node3D).position=_weapon_slide_homes[key]
	if is_instance_valid(_harpoon_spear):
		_harpoon_spear.visible=not (selected=="harpoon" and _weapon_kick>0.15)
	if is_instance_valid(_ballista_bolt):
		_ballista_bolt.visible=not (selected=="ballista" and _weapon_kick>0.06)
	get_muzzle_local()


func get_muzzle_local() -> Vector3:
	if _muzzle_markers.has(_weapon_kind):
		var marker: Marker3D = _muzzle_markers[_weapon_kind] as Marker3D
		muzzle=to_local(marker.global_position)
	return muzzle


func get_muzzle_world() -> Vector3:
	return to_global(get_muzzle_local())
