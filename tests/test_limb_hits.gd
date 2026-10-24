extends SceneTree
const Combat=preload("res://scripts/combat.gd")
const DT: float=1.0/60.0
var checks: int=0
var failures: Array[String]=[]

func _initialize() -> void:
	_test_capsule_boundaries()
	_test_nearest_and_weak()
	_test_weapon_surfaces()
	_test_dynamic_sweeps()
	_test_body_core_overlay()
	if checks!=56: failures.append("Incomplete test execution: expected 56 checks, got %d"%checks)
	if failures.is_empty():
		print("PASS: %d limb collision checks: capsule surfaces/gaps, nearest armor, actual weak collision, per-weapon damage and 30/60Hz moving proxies."%checks)
		quit(0)
	else:
		for failure: String in failures: printerr("FAIL: "+failure)
		quit(1)

func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures.append(message)

func fixture() -> Combat:
	var c: Combat=Combat.new()
	c.boss_state="recovery"
	c._boss_timer=999.0
	c.boss_hit_spheres=[]
	c.boss_weakpoints_local=[]
	c.weakpoint=true
	return c

func capsule(a: Vector3,b: Vector3,radius: float=1.0,id: String="claw") -> Dictionary:
	return {"part_id":id,"a":a,"b":b,"radius":radius,"surface":"armor","damage_scale":{"ballista":0.7,"cannon":0.9,"harpoon":0.8},"poise_scale":1.0}

func run(c: Combat,seconds: float) -> Array[Dictionary]:
	var events: Array[Dictionary]=[]
	var left: float=seconds
	while left>0.000001:
		var step: float=minf(DT,left)
		events.append_array(c.tick(step,Vector2(0,85),Vector2.ZERO))
		left-=step
	return events

func _test_capsule_boundaries() -> void:
	var c: Combat=fixture()
	c.boss_hit_capsules_local=[capsule(Vector3(0,3,0),Vector3(0,7,0))]
	var h: Dictionary=c.trace_boss_segment(Vector3(0,5,10),Vector3(0,5,-10))
	check(not h.is_empty() and absf(float(h["fraction"])-0.45)<0.00001 and h["part_id"]=="claw","Cylinder enters its exact front surface")
	check(not c.trace_boss_segment(Vector3(1,5,10),Vector3(1,5,-10)).is_empty(),"Exact tangent counts as contact")
	check(c.trace_boss_segment(Vector3(1.01,5,10),Vector3(1.01,5,-10)).is_empty(),"One centimetre outside is a miss")
	check(c.trace_boss_segment(Vector3(1.2,5,10),Vector3(1.2,5,-10),0.21).size()>0,"Projectile radius expands the physical surface")
	h=c.trace_boss_segment(Vector3(0,12,0),Vector3(0,0,0))
	check(not h.is_empty() and absf((h["position"] as Vector3).y-8.0)<0.00001,"Axis-parallel ray enters rounded endpoint")
	h=c.trace_boss_segment(Vector3(0,5,0),Vector3(0,5,0))
	check(not h.is_empty() and float(h["fraction"])==0.0,"Starting inside, including zero travel, returns zero")
	check(c.trace_boss_segment(Vector3(8,5,0),Vector3(8,5,0)).is_empty(),"Zero travel outside is a miss")
	c.boss_hit_capsules_local=[capsule(Vector3.ZERO,Vector3.ZERO)]
	h=c.trace_boss_segment(Vector3(0,0,3),Vector3(0,0,-3))
	check(not h.is_empty() and absf(float(h["fraction"])-1.0/3.0)<0.00001,"Degenerate capsule becomes a sphere")
	c.boss_hit_capsules_local=[capsule(Vector3(-3,0,0),Vector3(-3,10,0)),capsule(Vector3(3,0,0),Vector3(3,10,0),1,"other")]
	check(c.trace_boss_segment(Vector3(0,5,20),Vector3(0,5,-20)).is_empty(),"Separated limbs retain the open air gap")
	c.boss_position=Vector2(30,40)
	c.boss_origin_y=-11
	c.boss_facing=PI/2
	c.boss_hit_capsules_local=[capsule(Vector3(0,11,5),Vector3(0,14,5))]
	h=c.trace_boss_segment(Vector3(35,1,50),Vector3(35,1,30))
	check(not h.is_empty() and h["part_id"]=="claw","Boss origin/yaw transform applies once to local metre endpoints")

func _test_nearest_and_weak() -> void:
	var c: Combat=fixture()
	c.boss_hit_spheres=[{"center":Vector3(0,5,-8),"radius":2.0}]
	c.boss_weakpoints_local=[Vector3(0,5,-2)]
	c.boss_hit_capsules_local=[capsule(Vector3(0,3,5),Vector3(0,7,5))]
	var h: Dictionary=c.trace_boss_segment(Vector3(0,5,30),Vector3(0,5,-30))
	check(h.get("surface","")=="armor" and not bool(h.get("weak",false)),"Foreground claw blocks a farther exposed weak core")
	check(c.request_shot("cannon",Vector3(0,5,30),Vector3(0,5,-2),true),"Weak-aim reservation can be made behind foreground armor")
	var events: Array[Dictionary]=run(c,1.2)
	var armor_hit: Dictionary={}
	for e: Dictionary in events:
		if e["type"]=="boss_hit": armor_hit=e
	check(armor_hit.get("surface","")=="armor" and not bool(armor_hit.get("weak",false)) and absf(float(armor_hit.get("damage",0))-234.0)<0.0001,"Weak reservation never penetrates nearest armor or grants critical damage")
	c=fixture()
	c.boss_weakpoints_local=[Vector3(0,5,0)]
	c.boss_hit_spheres=[{"center":Vector3(0,5,-5),"radius":1.0}]
	check(c.request_shot("ballista",Vector3(0,5,20),Vector3(0,5,0),false),"Shot without weak reservation is accepted")
	events=run(c,0.5)
	var actual_critical: bool=false
	for e: Dictionary in events:
		if e["type"]=="boss_hit": actual_critical=bool(e["weak"]) and float(e["damage"])==90
	check(actual_critical,"Actual open-core collision grants critical independently of stale weak-aim flag")
	c.weakpoint=false
	h=c.trace_boss_segment(Vector3(0,5,20),Vector3(0,5,-20))
	check(h["surface"]=="weak" and not bool(h["weak"]),"Closed core remains hittable but does not claim an open weakpoint")
	c.boss_hit_spheres=[{"center":Vector3(0,5,5),"radius":1.0}]
	h=c.trace_boss_segment(Vector3(0,5,30),Vector3(0,5,-30))
	check(h["surface"]=="body","A nearer body surface also occludes the core without normalized tolerance")

func _test_weapon_surfaces() -> void:
	for weapon: String in ["ballista","cannon","harpoon"]:
		var c: Combat=fixture()
		c.boss_hit_capsules_local=[capsule(Vector3(0,3,0),Vector3(0,7,0))]
		c.tick(DT,Vector2(0,85),Vector2.ZERO)
		c.request_shot(weapon,Vector3(0,5,20),Vector3(0,5,0))
		var events: Array[Dictionary]=run(c,1.3)
		var hit: Dictionary={}
		for event: Dictionary in events:
			if event["type"]=="boss_hit": hit=event
		var expected: float=35.0 if weapon=="ballista" else (234.0 if weapon=="cannon" else 72.0)
		check(not hit.is_empty() and absf(float(hit["damage"])-expected)<0.0001 and absf(c.boss_hp-(4200-expected))<0.0001,"%s limb damage multiplier changes shared boss HP"%weapon)
		check(hit.has("raw_damage") and hit.get("part_id","")=="claw" and hit.get("surface","")=="armor","%s event includes surface, part and unscaled damage"%weapon)
		if weapon=="cannon": check(c.poise>65,"Armor keeps the full heavy-cannon poise effect")
		if weapon=="harpoon": check(c.tether_remaining>2.2,"Armor keeps the full three-second tether effect")

func _translate(c: Combat) -> void:
	var x: float=-3.0+c.elapsed*360.0
	c.boss_hit_capsules_local=[capsule(Vector3(x,4,-0.05),Vector3(x,6,-0.05),0.2)]

func _deform(c: Combat) -> void:
	var z: float=-3.0+c.elapsed*360.0
	c.boss_hit_capsules_local=[capsule(Vector3(-3,5,z),Vector3(3,5,-z),0.15)]

func _injected_projectile(c: Combat,position: Vector3,velocity: Vector3) -> void:
	c.projectiles.append({"id":1,"owner":"player","weapon":"ballista","position":position,"velocity":velocity,"age":0.0,"life":5.0,"radius":0.05,"weak_aim":false,"travelled":0.0,"max_range":180.0})

func _test_dynamic_sweeps() -> void:
	var results: Array[float]=[]
	for hz: int in [30,60]:
		var c: Combat=fixture()
		_translate(c)
		c.hit_geometry_updater=_translate.bind(c)
		_injected_projectile(c,Vector3(0,5,0),Vector3(0,0,-10))
		check(c.trace_boss_segment(Vector3(0,5,0),Vector3(0,5,-0.2),0.05).is_empty(),"%dHz translating claw starts outside projectile path"%hz)
		var events: Array[Dictionary]=c.tick(1.0/float(hz),Vector2(0,85),Vector2.ZERO)
		var hits: int=0
		for e: Dictionary in events:
			if e["type"]=="boss_hit": hits+=1
		check(hits==1 and c.projectiles.is_empty(),"%dHz fast claw crossing between both static endpoints still catches the projectile exactly once"%hz)
		results.append(c.boss_hp)
		c.hit_geometry_updater=Callable()
		check(c.sweep_error_budget<0.0001,"Uniform translation is swept analytically without deformation inflation")
	check(results[0]==results[1] and results[0]<4200,"30/60Hz translating geometry gives identical shared-HP damage")
	for hz: int in [30,60]:
		var c: Combat=fixture()
		_deform(c)
		c.hit_geometry_updater=_deform.bind(c)
		_injected_projectile(c,Vector3(2,5,0),Vector3(0,0,-0.01))
		check(c.trace_boss_segment(Vector3(2,5,0),Vector3(2,5,-0.001),0.05).is_empty(),"%dHz rotating span initially misses"%hz)
		var events: Array[Dictionary]=c.tick(1.0/float(hz),Vector2(0,85),Vector2.ZERO)
		var hits: int=0
		for e: Dictionary in events:
			if e["type"]=="boss_hit": hits+=1
		check(hits==1 and c.sweep_error_budget<=0.10001,"%dHz deforming claw crossing is caught with reported <=0.10m approximation"%hz)
		c.hit_geometry_updater=Callable()


func _overlay_fixture(depth: float) -> Combat:
	var c: Combat=fixture()
	c.boss_hit_spheres=[{"center":Vector3(0,5,0),"radius":1.0}]
	c.boss_weakpoints_local=[Vector3(0,5,-1.6-depth)]
	return c

func _overlay_motion(c: Combat, depth: float) -> void:
	var shift: float=c.elapsed*0.6
	c.boss_hit_spheres=[{"center":Vector3(0,5,shift),"radius":1.0}]
	c.boss_weakpoints_local=[Vector3(0,5,-1.6-depth+shift)]

func _test_body_core_overlay() -> void:
	for depth: float in [0.34,0.36]:
		var c: Combat=_overlay_fixture(depth)
		for finish: float in [0.9,-30.0]:
			var hit: Dictionary=c.trace_boss_segment(Vector3(0,5,3),Vector3(0,5,finish))
			check(bool(hit.get("weak",false))==(depth<0.35),"Body overlay %.2fm has the same rule on %.1fm segment"%[depth,3.0-finish])
			check(absf((hit["position"] as Vector3).z-1.0)<0.0001,"Overlay tags actual body contact without extra projectile travel")
		if depth<0.35:
			var hit: Dictionary=c.trace_boss_segment(Vector3(0,5,3),Vector3(0,5,-30))
			check(absf(float(hit.get("overlay_depth",0))-0.34)<0.0001,"Overlay depth is recorded in true world metres")
		c.boss_hit_capsules_local=[capsule(Vector3(0,4,0.83),Vector3(0,6,0.83),0.02,"intervening_armor")]
		var blocked: Dictionary=c.trace_boss_segment(Vector3(0,5,3),Vector3(0,5,0.9))
		check(blocked["surface"]=="body" and not bool(blocked["weak"]),"Armor between body and core prevents %.2fm overlay even beyond the short segment"%depth)
	var behind: Combat=_overlay_fixture(0.34)
	behind.boss_hit_capsules_local=[capsule(Vector3(0,4,0.3),Vector3(0,6,0.3),0.02)]
	check(bool(behind.trace_boss_segment(Vector3(0,5,3),Vector3(0,5,0.9))["weak"]),"Armor behind the core does not disable the visible overlay")
	for depth: float in [0.34,0.36]:
		for armor: bool in [false,true]:
			var c: Combat=_overlay_fixture(depth)
			if armor: c.boss_hit_capsules_local=[capsule(Vector3(0,4,0.83),Vector3(0,6,0.83),0.02,"intervening_armor")]
			c.hit_geometry_updater=_overlay_motion.bind(c,depth)
			_injected_projectile(c,Vector3(0,5,1.1),Vector3(0,0,-10))
			var events: Array[Dictionary]=c.tick(DT,Vector2(0,85),Vector2.ZERO)
			var hit: Dictionary={}
			for event: Dictionary in events:
				if event["type"]=="boss_hit": hit=event
			var expected_weak: bool=depth<0.35 and not armor
			check(not hit.is_empty() and bool(hit["weak"])==expected_weak,"Moving-pose projectile uses same %.2fm overlay / intervening armor=%s at a segment boundary"%[depth,armor])
			check(absf(float(hit.get("damage",0))-(90.0 if expected_weak else 50.0))<0.0001,"Actual moving collision damage agrees with overlay material")
			c.hit_geometry_updater=Callable()
