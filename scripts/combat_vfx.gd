extends Node3D
## Deterministic combat presentation: all timing is supplied by the combat model.
const ATTACK_LIMIT := 48
const PROJECTILE_LIMIT := 128
var _attacks: Dictionary = {}
var _projectiles: Dictionary = {}
var _events: Array[Dictionary] = []
var _clock := 0.0
var _preparation: Node3D
var _impact_shader: Shader
var _scale_fragment: ArrayMesh
var _iron_spark: CylinderMesh
var _impact_mist: QuadMesh
var _ship_world: Vector3=Vector3(0,0,85)
var _guard: MeshInstance3D
var _guard_material: ShaderMaterial
var _telegraph_shader: Shader
var _effect_shader: Shader
var _meteor_shader: Shader
var _rock_mesh: SphereMesh
var _bolt_mesh: CylinderMesh
var _cannon_mesh: SphereMesh
var _harpoon_mesh: CylinderMesh
var _white: StandardMaterial3D
var _iron: StandardMaterial3D
var _steel: StandardMaterial3D
var _cyan: StandardMaterial3D

func _ready() -> void:
	_build_resources()
	_build_impact_resources()
	_guard_material = _effect(Color(.22,.73,.86),.38)
	_guard = _mesh(_vertical_arc(5.8,2.8,1.8),_guard_material,self)
	_guard.visible = false

func _build_resources() -> void:
	_telegraph_shader = Shader.new()
	_telegraph_shader.code = """
shader_type spatial;
render_mode unshaded,blend_mix,depth_draw_never,cull_disabled,shadows_disabled;
uniform vec4 tint:source_color;
uniform int shape=0;
uniform float radius=5.0;
uniform float reach=20.0;
uniform float sector_angle=1.2;
uniform float progress=0.0;
uniform float opacity=0.5;
uniform float clock=0.0;
uniform bool tracking=false;
uniform bool conform_wave=true;
varying vec2 p;
float wave(vec2 q){return sin(dot(q,vec2(.075,.125))+clock*.76)*.78+sin(dot(q,vec2(-.16,.065))+clock*1.05)*.34+sin(dot(q,vec2(.31,.19))+clock*1.51)*.13;}
void vertex(){p=VERTEX.xz;if(conform_wave){vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;VERTEX.y+=wave(world.xz);}}
void fragment(){
 float d=length(p)-radius;
 if(shape==1){vec2 q=p-vec2(0.0,clamp(p.y,0.0,reach));d=length(q)-radius;}
 if(shape==2){float a=abs(atan(p.x,p.y));d=max(length(p)-reach,(a-sector_angle*.5)*length(p));}
 float edge=1.0-smoothstep(.08,.34,abs(d));
 float inside=(1.0-smoothstep(-.08,.08,d));
 if(d>.42){discard;}
 float dash=tracking?smoothstep(-.15,.15,sin(atan(p.x,p.y)*18.0)):1.0;
 float fill=inside*(tracking?.006:.018);
 float inner=0.0;
 if(shape==0&&!tracking){inner=(1.0-smoothstep(.08,.28,abs(length(p)-radius*progress)))*.12*inside;}
 ALBEDO=tint.rgb;EMISSION=tint.rgb*.24;
 ALPHA=(edge*.9*dash+fill+inner)*opacity;
}
"""
	_effect_shader = Shader.new()
	_effect_shader.code = """
shader_type spatial;
render_mode unshaded,blend_mix,depth_draw_never,cull_disabled,shadows_disabled;
uniform vec4 tint:source_color;
uniform float opacity=.5;
uniform float clock=0.0;
uniform int mode=0;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.54);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void fragment(){float n=noise(UV*vec2(18,6)+vec2(clock*.3,-clock*.7));float edge=sin(UV.y*3.14159);if(mode==1){edge=(1.0-smoothstep(.4,1.0,length(UV*2.0-1.0)));}ALBEDO=tint.rgb;EMISSION=tint.rgb*.32;ALPHA=opacity*edge*mix(.3,1.0,n);}
"""
	_meteor_shader = Shader.new()
	_meteor_shader.code = """
shader_type spatial;
varying vec3 p;
uniform float clock=0.0;
void vertex(){p=VERTEX;float f=sin(VERTEX.x*13.0+VERTEX.y*7.0)*sin(VERTEX.z*11.0-VERTEX.y*9.0);VERTEX+=NORMAL*(f*.19+sin(VERTEX.x*4.7+VERTEX.z*3.1)*.09);}
void fragment(){vec3 q=p*2.3;vec3 cell=floor(q);vec3 f=fract(q);float nearest=9.0;float next=9.0;for(int x=-1;x<=1;x++){for(int y=-1;y<=1;y++){for(int z=-1;z<=1;z++){vec3 g=vec3(float(x),float(y),float(z));vec3 c=cell+g;vec3 jitter=fract(sin(vec3(dot(c,vec3(127.1,311.7,74.7)),dot(c,vec3(269.5,183.3,246.1)),dot(c,vec3(113.5,271.9,124.6))))*43758.5453);float d=length(g+jitter-f);if(d<nearest){next=nearest;nearest=d;}else if(d<next){next=d;}}}}float hot=1.0-smoothstep(.025,.09,next-nearest);ALBEDO=mix(vec3(.035,.025,.022),vec3(.55,.10,.018),hot);EMISSION=vec3(1.0,.16,.015)*hot*2.3;ROUGHNESS=.91;}
"""
	_rock_mesh = SphereMesh.new()
	_rock_mesh.radius = 1.0
	_rock_mesh.height = 2.0
	_rock_mesh.radial_segments = 20
	_rock_mesh.rings = 12
	_bolt_mesh = CylinderMesh.new()
	_bolt_mesh.top_radius = .045
	_bolt_mesh.bottom_radius = .065
	_bolt_mesh.height = 1.8
	_bolt_mesh.radial_segments = 6
	_cannon_mesh = SphereMesh.new()
	_cannon_mesh.radius = .29
	_cannon_mesh.height = .58
	_cannon_mesh.radial_segments = 12
	_cannon_mesh.rings = 6
	_harpoon_mesh = CylinderMesh.new()
	_harpoon_mesh.top_radius = 0
	_harpoon_mesh.bottom_radius = .22
	_harpoon_mesh.height = 1.1
	_harpoon_mesh.radial_segments = 6
	_iron = _surface(Color(.035,.043,.05),.7,.4)
	_steel = _surface(Color(.33,.42,.47),.32,.8)
	_white = _surface(Color(.6,.78,.86),.5,0)
	_white.emission_enabled = true
	_white.emission = Color(.25,.46,.7)
	_white.emission_energy_multiplier = 1.4
	_cyan = _surface(Color(.08,.3,.35),.5,.4)

func _surface(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color=color
	result.roughness=roughness
	result.metallic=metallic
	return result

func _effect(color: Color, opacity: float) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader=_effect_shader
	result.set_shader_parameter("tint",color)
	result.set_shader_parameter("opacity",opacity)
	return result

func _mesh(mesh: Mesh, material: Material, parent: Node3D) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh=mesh
	result.material_override=material
	result.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	return result

func _vertical_arc(radius: float,height: float,angle: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(24):
		var a: float = -angle*.5+angle*float(i)/24.0
		var b: float = -angle*.5+angle*float(i+1)/24.0
		var points: Array[Vector3] = [Vector3(sin(a)*radius,0,cos(a)*radius),Vector3(sin(a)*radius,height,cos(a)*radius),Vector3(sin(b)*radius,0,cos(b)*radius),Vector3(sin(b)*radius,0,cos(b)*radius),Vector3(sin(a)*radius,height,cos(a)*radius),Vector3(sin(b)*radius,height,cos(b)*radius)]
		var uv: Array[Vector2] = [Vector2(float(i)/24,0),Vector2(float(i)/24,1),Vector2(float(i+1)/24,0),Vector2(float(i+1)/24,0),Vector2(float(i)/24,1),Vector2(float(i+1)/24,1)]
		for j: int in range(6):
			st.set_uv(uv[j])
			st.add_vertex(points[j])
	st.generate_normals()
	return st.commit()

func _line(parent: Node3D, from: Vector3, to: Vector3, width: float, material: Material) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius=width*.65
	cylinder.bottom_radius=width
	cylinder.height=1
	cylinder.radial_segments=5
	var node := _mesh(cylinder,material,parent)
	_position_line(node,from,to)
	return node

func _position_line(node: Node3D, from: Vector3, to: Vector3) -> void:
	var delta: Vector3 = to-from
	node.position=(from+to)*.5
	if delta.length_squared()<.00001:
		node.visible=false
		return
	node.visible=true
	var axis: Vector3 = delta.normalized()
	var right: Vector3 = axis.cross(Vector3.FORWARD).normalized()
	if right.length_squared()<.01:
		right=Vector3.RIGHT
	node.basis=Basis(right,axis,right.cross(axis)).scaled(Vector3(1,delta.length(),1))

func _new_attack(a: Dictionary) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var kind: String = a.kind
	var radius: float = float(a.get("radius",5))
	var reach: float = float(a.get("range",20))
	var origin: Vector2 = a.get("origin",Vector2.ZERO)
	var target: Vector2 = a.get("target",origin)
	var color: Color = Color(.95,.32,.08) if kind=="meteor" else Color(.3,.66,1) if kind=="lightning" else Color(1,.53,.19)
	var warning := ShaderMaterial.new()
	warning.shader=_telegraph_shader
	warning.set_shader_parameter("tint",color)
	warning.set_shader_parameter("radius",radius)
	warning.set_shader_parameter("reach",origin.distance_to(target) if kind=="lunge" else reach)
	warning.set_shader_parameter("sector_angle",float(a.get("angle",1.2)))
	warning.set_shader_parameter("shape",1 if kind=="lunge" else 2 if kind=="cleave" else 0)
	var plane := PlaneMesh.new()
	var extent: float = (reach if kind=="cleave" else radius)+1
	plane.size=Vector2.ONE*extent*2
	if kind=="lunge":
		plane.size=Vector2((radius+1)*2,origin.distance_to(target)+(radius+1)*2)
		plane.center_offset.z=origin.distance_to(target)*.5
	plane.subdivide_width=maxi(0,int(ceil(plane.size.x/2.0))-1)
	plane.subdivide_depth=maxi(0,int(ceil(plane.size.y/2.0))-1)
	var telegraph := _mesh(plane,warning,root)
	telegraph.position=Vector3(target.x,.24,target.y) if kind in ["meteor","lightning"] else Vector3(origin.x,.24,origin.y)
	var direction: Vector2 = (target-origin).normalized() if kind=="lunge" else a.get("direction",Vector2.DOWN)
	telegraph.rotation.y=atan2(direction.x,direction.y)
	var steam_material := _effect(Color(.34,.5,.56),.6)
	var steam := _mesh(_vertical_arc(radius,4.0,TAU),steam_material,root)
	steam.position=Vector3(target.x,0,target.y)
	steam.visible=false
	var data: Dictionary = {"node":root,"warning":warning,"telegraph":telegraph,"steam":steam,"steam_material":steam_material,"kind":kind,"arcs":[]}
	if kind=="meteor":
		var rock_material := ShaderMaterial.new()
		rock_material.shader=_meteor_shader
		data.rock=_mesh(_rock_mesh,rock_material,root)
		data.rock.scale=Vector3(1.4,1.7,1.25)*clampf(radius*.24,.7,2.3)
		var tail_material := _effect(Color(.8,.19,.035),.55)
		data.tail=_line(root,Vector3.ZERO,Vector3(0,10,0),.65,tail_material)
		data.tail_material=tail_material
	elif kind=="lightning":
		var bolt_root := Node3D.new()
		root.add_child(bolt_root)
		bolt_root.position=Vector3(target.x,0,target.y)
		var points: Array[Vector3] = []
		for i: int in range(10):
			points.append(Vector3(sin(float(a.id)*2.3+i*9.7)*2.1, float(i)*8.5,cos(float(a.id)+i*8.3)*1.6) if i>0 else Vector3.ZERO)
		for i: int in range(9):
			_line(bolt_root,points[i],points[i+1],.18,_white)
			if i%2==1:
				_line(bolt_root,points[i],points[i]+Vector3(sin(i*3.7)*9,-4,cos(i*7.3)*7),.045,_white)
		data.bolt=bolt_root
	else:
		var wave_material := _effect(Color(.43,.68,.74),.65)
		data.wave=_mesh(_vertical_arc(reach if kind=="cleave" else radius*1.2,4.0,float(a.get("angle",1.3)) if kind=="cleave" else 2.5),wave_material,root)
		data.wave_material=wave_material
	return data

func update_state(time: float, attacks: Array[Dictionary], projectiles: Array[Dictionary], boss_pos: Vector3, ship_pos: Vector3, guarding: bool, guard_age: float=0.0) -> void:
	if _telegraph_shader==null: return
	_clock=time
	_ship_world=ship_pos
	var live: Dictionary={}
	for a: Dictionary in attacks:
		var id: int=int(a.id)
		if bool(a.get("cancelled",false)) or float(a.age)>=float(a.life):
			continue
		live[id]=true
		if not _attacks.has(id):
			if _attacks.size()>=ATTACK_LIMIT: continue
			_attacks[id]=_new_attack(a)
		_draw_attack(_attacks[id],a,time,boss_pos)
	for id: Variant in _attacks.keys():
		if not live.has(id):
			_attacks[id].node.visible=false
			_attacks[id].node.queue_free()
			_attacks.erase(id)
	_draw_projectiles(projectiles,time)
	_guard.visible=guarding
	_guard.position=ship_pos+Vector3(0,-.2,0)
	var facing: Vector3=boss_pos-ship_pos
	_guard.rotation.y=atan2(facing.x,facing.z)
	_guard_material.set_shader_parameter("clock",time)
	_guard_material.set_shader_parameter("opacity",.48 if guard_age<.24 else .22)
	for i: int in range(_events.size()-1,-1,-1):
		var event: Dictionary=_events[i]
		var age: float=time-float(event.time)
		if age>float(event.get("life",.55)):
			event.node.queue_free()
			_events.remove_at(i)
		elif str(event.get("presentation",""))=="directional_hit":
			_draw_impact(event,age)
		else:
			event.node.scale=Vector3.ONE*(1.0+age*2.0)
			event.material.set_shader_parameter("opacity",(1.0-age/.55)*.7)
			event.material.set_shader_parameter("clock",time)

func _draw_attack(data: Dictionary,a: Dictionary,time: float,boss_pos: Vector3) -> void:
	var age: float=float(a.age)
	var delay: float=maxf(.01,float(a.delay))
	var active: float=maxf(.01,float(a.active))
	var elapsed: float=age-delay
	var warning: ShaderMaterial=data.warning
	var tracking: bool=bool(a.get("tracking",false)) and not bool(a.get("locked",false))
	warning.set_shader_parameter("clock",time)
	warning.set_shader_parameter("tracking",tracking)
	var lock_age: float=float(a.get("lock_age",0.0))
	warning.set_shader_parameter("progress",clampf((age-lock_age)/maxf(.01,delay-lock_age),0,1))
	warning.set_shader_parameter("opacity",(.36 if tracking else .86) if age<delay else maxf(0.0,1.0-elapsed/.3)*.72)
	var target: Vector2=a.target
	# Descriptors are authoritative every step, including the pre-lock moving aim.
	if data.kind in ["meteor","lightning"]:
		data.telegraph.position=Vector3(target.x,.24,target.y)
		data.steam.position=Vector3(target.x,0,target.y)
		if data.has("bolt"): data.bolt.position=Vector3(target.x,0,target.y)
	var radius: float=float(a.radius)
	var impact: float=clampf(elapsed/maxf(.01,float(a.life)-delay),0,1)
	data.steam.visible=elapsed>=0 and data.kind in ["meteor","lightning"]
	data.steam.scale=Vector3(1+impact*.5,1+impact*1.8,1+impact*.5)
	data.steam_material.set_shader_parameter("opacity",(1-impact)*.43)
	data.steam_material.set_shader_parameter("clock",time)
	if data.kind=="meteor":
		var descent: float=clampf((age-delay+.72)/.72,0,1)
		var point:=Vector3(target.x-26*(1-descent),pow(1-descent,1.25)*86,target.y-14*(1-descent))
		data.rock.visible=age>=delay-.72 and elapsed<.12
		data.rock.position=point
		data.rock.rotation=Vector3(age*1.8,age*1.2,age*.7)
		data.tail.visible=data.rock.visible
		if data.tail.visible: _position_line(data.tail,point,point+Vector3(-4,13,-2)*(1-descent*.65))
		data.tail_material.set_shader_parameter("clock",time)
	elif data.kind=="lightning":
		data.bolt.visible=elapsed>=0 and elapsed<active
		data.steam.scale.y=.28+impact*.4
	else:
		var origin: Vector2=a.origin
		var direction: Vector2=a.direction
		data.wave.visible=elapsed>=-.10 and elapsed<active+.35
		data.wave_material.set_shader_parameter("clock",time)
		data.wave_material.set_shader_parameter("opacity",maxf(0,1-maxf(0,elapsed)/maxf(.1,active+.35))*.68)
		if data.kind=="lunge":
			data.wave.position=Vector3(boss_pos.x,0,boss_pos.z)
			data.wave.rotation.y=atan2((target-origin).x,(target-origin).y)
		else:
			data.wave.position=Vector3(origin.x,0,origin.y)
			data.wave.rotation.y=atan2(direction.x,direction.y)
			data.wave.scale.y=1.0+sin(clampf(elapsed/active,0,1)*PI)*.8

func _new_projectile(p: Dictionary) -> Dictionary:
	var root:=Node3D.new()
	add_child(root)
	var weapon: String=str(p.get("weapon","ballista"))
	var mesh: Mesh = _cannon_mesh if weapon=="cannon" else _harpoon_mesh if weapon=="harpoon" else _bolt_mesh
	var body:=_mesh(mesh,_iron if weapon=="cannon" else _steel,root)
	body.rotation.x=-PI*.5
	if weapon=="harpoon":
		var shaft:=_mesh(_bolt_mesh,_iron,root)
		shaft.rotation.x=PI*.5
		shaft.position.z=.8
	var tail_material:=_effect(Color(.12,.15,.17) if weapon=="cannon" else Color(.13,.39,.44) if weapon=="harpoon" else Color(.28,.36,.38),.3)
	var tail:=_line(root,Vector3.ZERO,Vector3(0,0,2.8 if weapon=="cannon" else 5.5 if weapon=="harpoon" else 1.2),.16 if weapon=="cannon" else .035,tail_material)
	return {"node":root,"tail":tail,"material":tail_material}

func _draw_projectiles(projectiles: Array[Dictionary],time: float) -> void:
	var live: Dictionary={}
	for p: Dictionary in projectiles:
		var id: int=int(p.id)
		live[id]=true
		if not _projectiles.has(id):
			if _projectiles.size()>=PROJECTILE_LIMIT: continue
			_projectiles[id]=_new_projectile(p)
		var data: Dictionary=_projectiles[id]
		data.node.position=p.position
		var velocity: Vector3=p.get("velocity",Vector3.FORWARD)
		if velocity.length_squared()>.001:
			data.node.look_at(data.node.position+velocity,Vector3.UP)
		data.material.set_shader_parameter("clock",time)
	for id: Variant in _projectiles.keys():
		if not live.has(id):
			_projectiles[id].node.queue_free()
			_projectiles.erase(id)

func on_event(event: Dictionary) -> void:
	if _effect_shader==null: return
	var kind: String=str(event.get("type",event.get("kind","")))
	if kind=="end":
		reset()
		return
	if kind=="parry":
		for data: Dictionary in _attacks.values():
			if data.kind in ["lunge","cleave"]: data.node.visible=false
	if kind=="boss_hit":
		if _events.size()<12: _events.append(_new_impact(event))
		return
	if _events.size()>=12 or not kind in ["parry","guard_break","blocked","guard_hit","projectile_hit"]: return
	var material:=_effect(Color(1,.36,.13) if kind=="guard_break" else Color(.35,.85,1) if kind=="parry" else Color(.6,.7,.74),.7)
	var node:=_mesh(_vertical_arc(3.5,2.0,TAU),material,self)
	var point: Variant=event.get("position",_guard.position)
	node.position=point if point is Vector3 else Vector3(point.x,0,point.y)
	_events.append({"node":node,"material":material,"time":_clock})

func reset() -> void:
	if is_instance_valid(_preparation):
		_preparation.visible=false
		_preparation.queue_free()
		_preparation=null
	for data: Dictionary in _attacks.values():
		data.node.visible=false
		data.node.queue_free()
	for data: Dictionary in _projectiles.values():
		data.node.visible=false
		data.node.queue_free()
	for data: Dictionary in _events:
		data.node.visible=false
		data.node.queue_free()
	_attacks.clear()
	_projectiles.clear()
	_events.clear()
	if is_instance_valid(_guard): _guard.visible=false







## Build actual encounter materials in the current viewport before input unlock.
## The controller must render at least two frames, then call finish_preparation().
## This function never advances combat, clocks, HP or AI.
func prepare_preview(view_camera: Camera3D) -> Dictionary:
	reset()
	if DisplayServer.get_name()=="headless" or not is_instance_valid(view_camera):
		return {"draw_required":false,"sample_groups":0}
	_preparation=Node3D.new()
	_preparation.name="CombatMaterialPreparation"
	add_child(_preparation)
	_preparation.global_transform=view_camera.global_transform
	var kinds: Array[String]=["meteor","lightning","lunge","cleave"]
	for index: int in range(kinds.size()):
		var descriptor: Dictionary={"id":-100-index,"kind":kinds[index],"origin":Vector2.ZERO,"target":Vector2(0,7) if kinds[index]=="lunge" else Vector2.ZERO,"direction":Vector2.DOWN,"age":1.02,"delay":1.0,"active":.4,"life":2.1,"radius":3.0,"range":9.0,"angle":1.8}
		var data: Dictionary=_new_attack(descriptor)
		_draw_attack(data,descriptor,0.0,Vector3.ZERO)
		data.warning.set_shader_parameter("conform_wave",false)
		var node: Node3D=data.node
		node.reparent(_preparation,false)
		node.position=Vector3((float(index%2)-.5)*4.6,(.5-floorf(float(index)/2.0))*3.0,-12.0)
		# Local water plane faces the camera; lightning's vertical extent stays in front.
		node.basis=Basis(Vector3.RIGHT,Vector3.BACK,Vector3.DOWN).scaled(Vector3.ONE*.10)
	var weapons: Array[String]=["ballista","cannon","harpoon"]
	for index: int in range(weapons.size()):
		var data: Dictionary=_new_projectile({"id":-200-index,"weapon":weapons[index],"position":Vector3.ZERO,"velocity":Vector3.FORWARD,"radius":.2,"age":0.0,"life":1.0})
		var node: Node3D=data.node
		node.reparent(_preparation,false)
		node.position=Vector3((float(index)-1.0)*2.2,-3.4,-12.0)
		node.rotation.y=PI*.5
	var guard_sample: MeshInstance3D=_mesh(_guard.mesh,_guard_material,_preparation)
	guard_sample.position=Vector3(4.0,-3.0,-16.0)
	guard_sample.scale=Vector3.ONE*.45
	for index: int in range(3):
		var event: Dictionary={"type":"boss_hit","position":Vector3.ZERO,"incoming":Vector3.FORWARD,"weapon":weapons[index],"surface":"armor" if index==0 else "body","weak":index==2,"id":-300-index}
		var data: Dictionary=_new_impact(event)
		_draw_impact(data,.08)
		var node: Node3D=data.node
		node.reparent(_preparation,false)
		node.position=Vector3((float(index)-1.0)*3.3,3.6,-11.0)
		node.scale=Vector3.ONE*.8
	return {"draw_required":true,"sample_groups":11}

func finish_preparation() -> void:
	reset()



func _build_impact_resources() -> void:
	_impact_shader=Shader.new()
	_impact_shader.code="""
shader_type spatial;
render_mode blend_mix,depth_draw_never,cull_disabled,shadows_disabled;
uniform vec4 tint:source_color;
uniform float opacity=1.0;
uniform float clock=0.0;
uniform int mode=0;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){if(mode==2){vec3 s=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));MODELVIEW_MATRIX=VIEW_MATRIX*mat4(vec4(INV_VIEW_MATRIX[0].xyz*s.x,0.0),vec4(INV_VIEW_MATRIX[1].xyz*s.y,0.0),vec4(INV_VIEW_MATRIX[2].xyz*s.z,0.0),MODEL_MATRIX[3]);MODELVIEW_NORMAL_MATRIX=mat3(MODELVIEW_MATRIX);}}
void fragment(){float alpha=opacity;ALBEDO=tint.rgb;ROUGHNESS=.64;METALLIC=.16;if(mode==0){ALBEDO*=.65+UV.y*.35;}else if(mode==1){EMISSION=tint.rgb*1.4;ROUGHNESS=.4;METALLIC=.45;}else{vec2 p=UV*2.0-1.0;float n=noise(UV*5.0+vec2(clock*.7,-clock*.5));float edge=1.0-smoothstep(.12,1.0,length(p));alpha*=edge*smoothstep(.18,.75,n)*.48;ROUGHNESS=.95;METALLIC=0.0;}ALPHA=alpha;}
"""
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array[Vector3]=[Vector3(-.42,0,0),Vector3(-.08,.62,.08),Vector3(.34,.07,0),Vector3(.12,-.32,.025)]
	for index: int in [0,1,2,0,2,3]:
		st.set_uv(Vector2(points[index].x+.5,points[index].y+.35))
		st.add_vertex(points[index])
	st.generate_normals()
	_scale_fragment=st.commit()
	_iron_spark=CylinderMesh.new()
	_iron_spark.top_radius=.3
	_iron_spark.bottom_radius=1.0
	_iron_spark.height=1.0
	_iron_spark.radial_segments=4
	_impact_mist=QuadMesh.new()
	_impact_mist.size=Vector2.ONE

func _impact_material(color: Color,mode: int) -> ShaderMaterial:
	var material:=ShaderMaterial.new()
	material.shader=_impact_shader
	material.set_shader_parameter("tint",color)
	material.set_shader_parameter("mode",mode)
	return material

func _impact_multimesh(mesh: Mesh,count: int,material: Material,parent: Node3D) -> MultiMeshInstance3D:
	var node:=MultiMeshInstance3D.new()
	node.multimesh=MultiMesh.new()
	node.multimesh.transform_format=MultiMesh.TRANSFORM_3D
	node.multimesh.mesh=mesh
	node.multimesh.instance_count=count
	node.multimesh.custom_aabb=AABB(Vector3.ONE*-6.0,Vector3.ONE*12.0)
	node.material_override=material
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _impact_seed(index: int,salt: float) -> float:
	return fposmod(sin(float(index)*127.1+salt*311.7)*43758.5453,1.0)

func _new_impact(event: Dictionary) -> Dictionary:
	var point: Vector3=event.get("position",Vector3.ZERO)
	var incoming: Vector3=event.get("incoming",point-_ship_world)
	if incoming.length_squared()<.0001: incoming=Vector3.FORWARD
	var normal: Vector3=-incoming.normalized()
	var side: Vector3=Vector3.UP.cross(normal).normalized()
	if side.length_squared()<.01: side=Vector3.RIGHT
	var frame:=Basis(side,normal.cross(side).normalized(),normal)
	var weapon: String=str(event.get("weapon","ballista"))
	var armor: bool=str(event.get("surface","body"))=="armor"
	var weak: bool=bool(event.get("weak",false))
	var size: float=1.45 if weapon=="cannon" else 1.0 if weapon=="harpoon" else .72
	var life: float=.42 if weapon=="cannon" else .32 if weapon=="harpoon" else .24
	var count: int=12 if weapon=="cannon" else 8 if weapon=="harpoon" else 6
	var spark_count: int=0 if weapon=="harpoon" else 4 if weapon=="cannon" else 2 if armor else 1
	var root:=Node3D.new()
	root.name="DirectionalScaleImpact"
	add_child(root)
	root.global_position=point
	var shard_color:=Color(.13,.23,.28) if armor else Color(.11,.27,.28)
	var mist_color:=Color(.31,.43,.48) if armor else Color(.20,.40,.44)
	if weak:
		shard_color=Color(.25,.12,.31)
		mist_color=Color(.36,.26,.43)
	var shards_material:=_impact_material(shard_color,0)
	var sparks_material:=_impact_material(Color(.95,.63,.24) if weak else Color(.70,.78,.82) if armor else Color(.82,.59,.29),1)
	var mist_material:=_impact_material(mist_color,2)
	var shards:=_impact_multimesh(_scale_fragment,count,shards_material,root)
	var sparks: MultiMeshInstance3D
	if spark_count>0: sparks=_impact_multimesh(_iron_spark,spark_count,sparks_material,root)
	var mist: Array[MeshInstance3D]=[]
	for index: int in range(2): mist.append(_mesh(_impact_mist,mist_material,root))
	var data: Dictionary={"presentation":"directional_hit","node":root,"time":_clock,"life":life,"frame":frame,"size":size,"weapon":weapon,"armor":armor,"weak":weak,"seed":int(event.get("id",0)),"shards":shards,"sparks":sparks,"mist":mist,"shards_material":shards_material,"sparks_material":sparks_material,"mist_material":mist_material}
	_draw_impact(data,0.0)
	return data

func _draw_impact(data: Dictionary,age: float) -> void:
	var life: float=float(data.life)
	var progress: float=clampf(age/life,0,1)
	var fade: float=pow(1.0-progress,1.3)
	var size: float=float(data.size)
	var frame: Basis=data.frame
	var salt: float=float(data.seed)
	var shards: MultiMeshInstance3D=data.shards
	for index: int in range(shards.multimesh.instance_count):
		var a: float=_impact_seed(index,salt+.2)
		var b: float=_impact_seed(index,salt+1.7)
		var c: float=_impact_seed(index,salt+3.9)
		# A forward hemisphere cone, never a complete radial ring.
		var velocity: Vector3=frame*Vector3((a-.5)*4.0,(b-.35)*3.1,3.3+c*4.0)*size
		var position_value: Vector3=velocity*age+Vector3.UP*(-4.0*age*age)
		var rotation_value:=Vector3(a*TAU+age*(b*12-6),b*TAU+age*8,c*TAU-age*7)
		var scale_value: float=(.16+c*.20)*size*maxf(.08,fade)
		shards.multimesh.set_instance_transform(index,Transform3D(Basis.from_euler(rotation_value).scaled(Vector3(scale_value,.7*scale_value,scale_value)),position_value))
	var sparks: MultiMeshInstance3D=data.sparks
	if is_instance_valid(sparks):
		sparks.visible=age<minf(.22,life*.75)
		for index: int in range(sparks.multimesh.instance_count):
			var a: float=_impact_seed(index,salt+6.0)
			var b: float=_impact_seed(index,salt+7.0)
			var direction: Vector3=(frame*Vector3((a-.5)*.8,b*.65,1.0)).normalized()
			var speed: float=(8+a*6)*size
			var axis: Vector3=direction.cross(Vector3.UP).normalized()
			if axis.length_squared()<.01: axis=Vector3.RIGHT
			var basis:=Basis(axis,direction,axis.cross(direction)).scaled(Vector3(.014*size,(.20+a*.24)*size*fade,.014*size))
			sparks.multimesh.set_instance_transform(index,Transform3D(basis,direction*speed*age+Vector3.UP*(-3*age*age)))
	for index: int in range(data.mist.size()):
		var mist: MeshInstance3D=data.mist[index]
		mist.position=frame*Vector3((float(index)-.5)*.45,age*.8,age*2.2)*size
		mist.scale=Vector3.ONE*(.45+age*4.2)*size
	data.shards_material.set_shader_parameter("opacity",fade)
	data.sparks_material.set_shader_parameter("opacity",maxf(0.0,1.0-age/.22))
	data.mist_material.set_shader_parameter("opacity",sin(progress*PI)*.7)
	data.mist_material.set_shader_parameter("clock",age)


