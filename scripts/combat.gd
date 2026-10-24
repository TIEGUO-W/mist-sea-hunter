extends RefCounted
## Hunter combat: authoritative moving boss, locked attack volumes and 3D shots.
var max_boss_hp: float=4200.0
var boss_hp: float=4200.0
var max_hull: float=100.0
var hull: float=100.0
var max_stamina: float=100.0
var stamina: float=100.0
var phase: int=1
var attack: String="idle"
var windup: float=0.0
var stagger: float=0.0
var weakpoint: bool=false
var ended: bool=false
var won: bool=false
var elapsed: float=0.0
var notice: String="横移避开锁点；近战可正面格挡，抬掌瞬间格挡可弹反。"
var notice_time: float=6.0
var cooldowns: Dictionary={"ballista":0.0,"cannon":0.0,"harpoon":0.0,"repair":0.0}
var repair_charges: int=2
var action_state: String="free"
var action_weapon: String=""
var action_remaining: float=0.0
var action_total: float=0.0
var move_multiplier: float=1.0
var invulnerable: bool=false
var boss_position: Vector2=Vector2.ZERO
var boss_velocity: Vector2=Vector2.ZERO
var boss_facing: float=0.0
var boss_state: String="chase"
var boss_origin_y: float=0.0
var boss_hit_spheres: Array[Dictionary]=[{"center":Vector3(0,8.5,0),"radius":10.0},{"center":Vector3(0,11.5,0),"radius":10.0},{"center":Vector3(0,2.5,0),"radius":9.0}]
## Local metre-space endpoints, before boss yaw/origin translation. Stable part_id
## permits temporal matching across poses. Radius must fit the actual limb.
var boss_hit_capsules_local: Array[Dictionary]=[]
var hit_geometry_updater: Callable=Callable()
## Maximum conservative endpoint-deformation inflation in the latest logic step.
## Translation is swept analytically; deformation is piecewise linear (<=0.10m
## normally, reported honestly if the 64-slice safety cap is reached).
var sweep_error_budget: float=0.0
var _previous_geometry: Array[Dictionary]=[]
var _current_geometry: Array[Dictionary]=[]
var _geometry_motion: Array[Dictionary]=[]
var boss_weakpoints_local: Array[Vector3]=[Vector3(0,13.5,8),Vector3(0,9,-9)]
var attacks: Array[Dictionary]=[]
var projectiles: Array[Dictionary]=[]
var guard_age: float=0.0
var guarding: bool=false
var tether_remaining: float=0.0
var slowed: float=0.0
var poise: float=0.0

const WEAPONS: Dictionary={
	"ballista":{"cost":7.0,"windup":0.1,"recovery":0.25,"cooldown":0.35,"damage":50.0,"weak":90.0,"speed":125.0,"radius":0.16,"life":5.0,"range":180.0},
	"cannon":{"cost":28.0,"windup":0.7,"recovery":1.0,"cooldown":2.1,"damage":260.0,"weak":520.0,"speed":95.0,"radius":0.42,"life":7.0,"range":310.0},
	"harpoon":{"cost":20.0,"windup":0.4,"recovery":0.6,"cooldown":7.0,"damage":90.0,"weak":150.0,"speed":110.0,"radius":0.18,"life":6.0,"range":135.0}}
var _pending: Array[Dictionary]=[]
var _last_ship_pos: Vector2=Vector2(0,85)
var _ship_heading: float=PI
var muzzle_origin: Vector3=Vector3.INF
var _shot_offset: Vector3=Vector3.ZERO
var _shot_aim: Vector3=Vector3.ZERO
var _shot_weak: bool=false
var _regen_delay: float=0.0
var _hit_protection: float=0.0
var _boss_timer: float=1.8
var _boss_duration: float=1.0
var _pattern_index: int=0
var _attack_id: int=0
var _projectile_id: int=0
var _followup_pending: bool=false

func tick(delta: float, ship_pos: Vector2, ship_velocity: Vector2, ship_heading: float=INF) -> Array[Dictionary]:
	var events: Array[Dictionary]=[]
	events.append_array(_pending)
	_pending.clear()
	if ended or delta<=0.0: return events
	var remaining: float=delta
	var walked: float=0.0
	var origin: Vector2=ship_pos-ship_velocity*delta
	while remaining>0.000001 and not ended:
		_previous_geometry=_capture_geometry()
		var step: float=minf(remaining,1.0/60.0)
		walked+=step
		_last_ship_pos=origin+ship_velocity*walked
		_ship_heading=ship_heading if is_finite(ship_heading) else atan2(boss_position.x-_last_ship_pos.x,boss_position.y-_last_ship_pos.y)
		elapsed+=step
		for key: String in cooldowns: cooldowns[key]=maxf(0,float(cooldowns[key])-step)
		notice_time=maxf(0,notice_time-step)
		_hit_protection=maxf(0,_hit_protection-step)
		_regen_delay=maxf(0,_regen_delay-step)
		slowed=maxf(0,slowed-step)
		tether_remaining=slowed
		poise=maxf(0,poise-step*6.0)
		if action_state=="guard":
			guard_age+=step
			stamina=maxf(0,stamina-step*7.0)
			_regen_delay=0.55
			if stamina<=0: _break_guard(events)
		elif action_state=="free" and _regen_delay<=0:
			stamina=minf(max_stamina,stamina+step*20.0)
		_advance_action(step,events)
		var old_boss: Vector2=boss_position
		_advance_boss(step,_last_ship_pos,ship_velocity,events)
		boss_velocity=(boss_position-old_boss)/step
		weakpoint=stagger>0 or (boss_state=="recovery" and not _followup_pending)
		if hit_geometry_updater.is_valid(): hit_geometry_updater.call()
		_current_geometry=_capture_geometry()
		_prepare_geometry_motion()
		_advance_projectiles(step,events)
		if ended: break
		_advance_attacks(step,_last_ship_pos,events,ship_velocity)
		remaining-=step
	_refresh_action()
	return events

func spend_stamina(amount: float) -> bool:
	if ended or amount<0 or stamina+0.00001<amount: return false
	stamina=maxf(0,stamina-amount)
	_regen_delay=0.55
	return true

func can_switch_weapon() -> bool:
	return not ended and action_state in ["free","guard"]

func request_shot(weapon: String, origin: Vector3, aim_point: Vector3, weak_aim: bool=false) -> bool:
	if ended or action_state!="free" or not WEAPONS.has(weapon) or float(cooldowns[weapon])>0: return false
	var config: Dictionary=WEAPONS[weapon] as Dictionary
	if not spend_stamina(float(config["cost"])): return false
	cooldowns[weapon]=float(config["cooldown"])
	action_state="windup"
	action_weapon=weapon
	action_total=float(config["windup"])
	action_remaining=action_total
	_shot_offset=origin-Vector3(_last_ship_pos.x,0,_last_ship_pos.y)
	_shot_aim=aim_point
	_shot_weak=weak_aim
	_refresh_action()
	return true

func request_dodge() -> bool:
	if ended or action_state not in ["free","guard"] or not spend_stamina(28.0): return false
	action_state="dodge"
	action_weapon=""
	action_total=0.5
	action_remaining=0.5
	_refresh_action()
	_pending.append({"type":"dodge"})
	return true

func request_guard(held: bool) -> bool:
	if ended: return false
	if not held:
		if action_state!="guard": return false
		action_state="free"
		guard_age=0
		_refresh_action()
		return true
	if action_state=="guard": return true
	if action_state!="free" or stamina<8: return false
	action_state="guard"
	action_weapon=""
	guard_age=0
	_refresh_action()
	return true

func command(action: String) -> bool:
	return request_repair() if action=="repair" else false

func request_repair() -> bool:
	if ended or action_state!="free" or repair_charges<=0 or hull>=max_hull or float(cooldowns["repair"])>0: return false
	if not spend_stamina(20): return false
	repair_charges-=1
	cooldowns["repair"]=10.0
	action_state="windup"
	action_weapon="repair"
	action_total=2.1
	action_remaining=action_total
	_set_notice("正在抢修：受击会中断。",2.1)
	_refresh_action()
	return true

func _advance_action(delta: float, events: Array[Dictionary]) -> void:
	if action_state in ["free","guard"]: return
	action_remaining=maxf(0,action_remaining-delta)
	_refresh_action()
	if action_remaining>0.00001: return
	if action_state=="windup":
		if action_weapon=="repair":
			hull=minf(max_hull,hull+25)
			events.append({"type":"repair","hull":hull})
			action_total=0.3
		else:
			_launch_shot(events)
			action_total=float((WEAPONS[action_weapon] as Dictionary)["recovery"])
		action_state="recovery"
		action_remaining=action_total
	else:
		action_state="free"
		action_weapon=""
		action_remaining=0
		action_total=0
	_refresh_action()

func _launch_shot(events: Array[Dictionary]) -> void:
	var config: Dictionary=WEAPONS[action_weapon] as Dictionary
	var origin: Vector3=muzzle_origin if muzzle_origin.is_finite() else Vector3(_last_ship_pos.x,0,_last_ship_pos.y)+_shot_offset
	var direction: Vector3=(_shot_aim-origin).normalized()
	if direction.length_squared()<0.01: direction=Vector3(0,0,-1)
	_projectile_id+=1
	var velocity: Vector3=direction*float(config["speed"])
	projectiles.append({"id":_projectile_id,"owner":"player","weapon":action_weapon,"position":origin,"velocity":velocity,"age":0.0,"life":float(config["life"]),"radius":float(config["radius"]),"weak_aim":_shot_weak,"travelled":0.0,"max_range":float(config["range"])})
	events.append({"type":"player_shot","weapon":action_weapon,"id":_projectile_id,"position":origin,"velocity":velocity})

func _refresh_action() -> void:
	invulnerable=false
	guarding=action_state=="guard"
	move_multiplier=1.0
	if action_state=="guard": move_multiplier=0.5
	elif action_state=="guard_break": move_multiplier=0.25
	elif action_state=="dodge":
		var progress: float=action_total-action_remaining
		invulnerable=progress>=0.08 and progress<=0.36
		move_multiplier=2.4
	elif action_state in ["windup","recovery"]:
		if action_weapon=="ballista": move_multiplier=0.85
		elif action_weapon=="cannon": move_multiplier=0.35 if action_state=="windup" else 0.55
		elif action_weapon=="repair": move_multiplier=0.3
		else: move_multiplier=0.65

func _advance_boss(delta: float, ship_pos: Vector2, ship_velocity: Vector2, events: Array[Dictionary]) -> void:
	if stagger>0:
		stagger=maxf(0,stagger-delta)
		return
	_boss_timer-=delta
	if boss_state=="chase":
		var offset: Vector2=ship_pos-boss_position
		if offset.length()>22:
			var speed: float=(14.0 if phase==2 else 11.0)*(0.55 if slowed>0 else 1.0)
			boss_position+=offset.normalized()*minf(offset.length()-22,speed*delta)
		boss_facing=rotate_toward(boss_facing,atan2(offset.x,offset.y),delta*1.6)
		if _boss_timer<=0: _begin_attack(ship_pos,ship_velocity,events)
	elif boss_state=="windup":
		windup=clampf(1.0-_boss_timer/_boss_duration,0,1)
		if _boss_timer<=0:
			boss_state="active"
			windup=1.0
			_boss_timer=_active_duration()
	elif boss_state=="active":
		if attack=="lunge":
			for descriptor: Dictionary in attacks:
				if str(descriptor["kind"])=="lunge" and not bool(descriptor.get("cancelled",false)) and float(descriptor["age"])<float(descriptor["delay"])+float(descriptor["active"]):
					var target: Vector2=descriptor["target"] as Vector2
					boss_position=boss_position.move_toward(target,delta*(78.0 if phase==1 else 88.0)*(0.65 if slowed>0 else 1.0))
					break
		if _boss_timer<=0:
			_followup_pending=attack=="lunge" and boss_position.distance_to(ship_pos)<=48.0
			boss_state="recovery"
			attack="idle"
			windup=0
			_boss_timer=0.6 if _followup_pending else 2.4
			_set_notice("扑击未收招：准备侧移，警惕接续爪扫。" if _followup_pending else "海怪恢复：弱点暴露，伺机反击。",_boss_timer)
	elif boss_state=="recovery" and _boss_timer<=0:
		if _followup_pending and boss_position.distance_to(ship_pos)<=48.0:
			_followup_pending=false
			_begin_attack(ship_pos,ship_velocity,events,"cleave")
		else:
			_followup_pending=false
			boss_state="chase"
			_boss_timer=0.9 if phase==1 else 0.65
	boss_position=boss_position.limit_length(414.0)

func _active_duration() -> float:
	var duration: float=0.35
	for descriptor: Dictionary in attacks:
		if not bool(descriptor.get("cancelled",false)):
			duration=maxf(duration,float(descriptor["delay"])+float(descriptor["active"])-_boss_duration)
	return duration

func _begin_attack(ship_pos: Vector2, ship_velocity: Vector2, events: Array[Dictionary], forced: String="") -> void:
	var distance: float=boss_position.distance_to(ship_pos)
	if not forced.is_empty(): attack=forced
	elif distance<34 and _pattern_index%3!=0: attack="cleave"
	elif distance>52 and _pattern_index%3==1: attack="lunge"
	else: attack="meteor" if _pattern_index%2==0 else "lightning"
	_pattern_index+=1
	boss_state="windup"
	var target: Vector2=(ship_pos+ship_velocity*0.2).limit_length(416)
	var direction: Vector2=(target-boss_position).normalized()
	boss_facing=atan2(direction.x,direction.y)
	match attack:
		"meteor":
			_boss_duration=2.2
			var predicted: Vector2=(ship_pos+ship_velocity*1.35).limit_length(416)
			_descriptor("meteor",boss_position,predicted,direction,2.2,0.24,9.0,0,TAU,28)
			_mark_tracking_meteor(0.85)
			if phase==2:
				_descriptor("meteor",boss_position,predicted,direction,3.55,0.24,9.0,0,TAU,28)
				_mark_tracking_meteor(2.20)
		"lightning":
			_boss_duration=1.35
			var side: Vector2=Vector2(direction.y,-direction.x)
			for index: int in range(3 if phase==2 else 2):
				var point: Vector2=(target+side*(float(index)-0.5)*12.0).limit_length(416)
				_descriptor("lightning",boss_position,point,direction,_boss_duration+float(index)*0.45,0.22,6.5,0,TAU,24)
		"lunge":
			_boss_duration=1.2
			var predicted: Vector2=(ship_pos+ship_velocity*1.2).limit_length(416)
			direction=(predicted-boss_position).normalized()
			boss_facing=atan2(direction.x,direction.y)
			var charge_target: Vector2=(boss_position+direction*minf(boss_position.distance_to(predicted)+4.0,170.0)).limit_length(414)
			var duration: float=clampf(boss_position.distance_to(charge_target)/(78.0 if phase==1 else 88.0)+0.15,0.6,2.6)
			_descriptor("lunge",boss_position,charge_target,direction,_boss_duration,duration,18.5,boss_position.distance_to(charge_target),0,32)
		"cleave":
			_boss_duration=1.0
			_descriptor("cleave",boss_position,target,direction,_boss_duration+0.20,0.24,0,40.0,deg_to_rad(115),26)
	_boss_timer=_boss_duration
	windup=0
	_set_notice({"meteor":"陨星锁点：离开海面圆环！","lightning":"断潮雷击：横移脱离顺序雷点！","lunge":"巨兽扑击：锁定方向，侧移躲开走廊！","cleave":"碎浪爪：退出扇区，或正面格挡/弹反！"}[attack],_boss_duration+0.8)
	events.append({"type":"telegraph","kind":attack,"attack":attack,"id":_attack_id})

func _descriptor(kind: String, origin: Vector2, target: Vector2, direction: Vector2, delay: float, active: float, radius: float, reach: float, angle: float, damage: float) -> void:
	_attack_id+=1
	attacks.append({"id":_attack_id,"kind":kind,"origin":origin,"target":target,"direction":direction,"age":0.0,"delay":delay,"active":active,"life":delay+active+0.7,"radius":radius,"range":reach,"angle":angle,"damage":damage,"struck":false,"started":false,"cancelled":false})

func _mark_tracking_meteor(lock_age: float) -> void:
	var descriptor: Dictionary=attacks[-1]
	descriptor["tracking"]=true
	descriptor["locked"]=false
	descriptor["lock_age"]=lock_age

func _inside(descriptor: Dictionary, ship_pos: Vector2) -> bool:
	var kind: String=str(descriptor["kind"])
	var target: Vector2=descriptor["target"] as Vector2
	var origin: Vector2=descriptor["origin"] as Vector2
	if kind in ["meteor","lightning"]: return ship_pos.distance_to(target)<=float(descriptor["radius"])+3.0
	if kind=="lunge":
		return boss_position.distance_to(ship_pos)<=24.0 and Geometry2D.get_closest_point_to_segment(ship_pos,origin,target).distance_to(ship_pos)<=float(descriptor["radius"])+3.0
	var offset: Vector2=ship_pos-origin
	return offset.length()<=float(descriptor["range"])+3.0 and absf((descriptor["direction"] as Vector2).angle_to(offset))<=float(descriptor["angle"])*0.5

func _advance_attacks(delta: float, ship_pos: Vector2, events: Array[Dictionary], ship_velocity: Vector2=Vector2.ZERO) -> void:
	for index: int in range(attacks.size()-1,-1,-1):
		var descriptor: Dictionary=attacks[index]
		descriptor["age"]=float(descriptor["age"])+delta
		var age: float=float(descriptor["age"])
		if bool(descriptor.get("tracking",false)) and not bool(descriptor.get("cancelled",false)):
			var lock_age: float=float(descriptor["lock_age"])
			# Interpolate back to the exact crossing time within this <=60Hz
			# step, so a30Hz outer tick cannot change the locked target.
			var crossing: float=maxf(0.0,age-lock_age) if age>=lock_age else 0.0
			var lock_position: Vector2=ship_pos-ship_velocity*crossing
			descriptor["target"]=(lock_position+ship_velocity*1.35).limit_length(416)
			if age+0.000001>=lock_age:
				descriptor["tracking"]=false
				descriptor["locked"]=true
				events.append({"type":"target_locked","kind":descriptor["kind"],"id":descriptor["id"],"position":descriptor["target"],"target":descriptor["target"],"remaining":float(descriptor["delay"])-lock_age})
		if not bool(descriptor["cancelled"]) and age>=float(descriptor["delay"]) and age<float(descriptor["delay"])+float(descriptor["active"]):
			var hit: bool=not bool(descriptor["struck"]) and _inside(descriptor,ship_pos)
			if hit:
				descriptor["struck"]=true
				_resolve_attack(descriptor,ship_pos,events)
				if ended: return
			elif not bool(descriptor["started"]):
				events.append({"type":"impact","kind":descriptor["kind"],"attack":descriptor["kind"],"id":descriptor["id"],"hit":false,"damage":0.0,"position":descriptor["target"]})
			descriptor["started"]=true
		if age>=float(descriptor["life"]): attacks.remove_at(index)

func _resolve_attack(descriptor: Dictionary, ship_pos: Vector2, events: Array[Dictionary]) -> void:
	if invulnerable or _hit_protection>0: return
	var kind: String=str(descriptor["kind"])
	var melee: bool=kind in ["lunge","cleave"]
	var source: Vector2=(descriptor["origin"] as Vector2)-ship_pos
	if kind=="lunge": source=boss_position-ship_pos
	var front: Vector2=Vector2(sin(_ship_heading),cos(_ship_heading))
	var frontal: bool=source.length()<0.1 or front.dot(source.normalized())>=0.25
	var damage: float=float(descriptor["damage"])*(1.08 if phase==2 else 1.0)
	if action_state=="guard" and frontal:
		if melee and guard_age<=0.20 and stamina>=12:
			spend_stamina(12)
			_interrupt_boss(1.4)
			events.append({"type":"parry","kind":kind,"id":descriptor["id"],"position":ship_pos})
			_hit_protection=0.65
			return
		var cost: float=24.0 if melee else 30.0
		if spend_stamina(cost):
			damage*=0.2 if melee else 0.55
			events.append({"type":"blocked","kind":kind,"damage":damage,"position":ship_pos})
		else: _break_guard(events)
	hull=maxf(0,hull-damage)
	_hit_protection=0.65
	if action_weapon=="repair" and action_state=="windup":
		action_state="recovery"
		action_total=0.4
		action_remaining=0.4
		_set_notice("抢修被打断！",2)
	events.append({"type":"impact","kind":kind,"attack":kind,"id":descriptor["id"],"hit":true,"damage":damage,"position":ship_pos})
	if hull<=0: _finish(false,events)

func _break_guard(events: Array[Dictionary]) -> void:
	stamina=0
	action_state="guard_break"
	action_weapon=""
	action_total=1.0
	action_remaining=1.0
	_regen_delay=0.75
	events.append({"type":"guard_break"})
	_refresh_action()

func _interrupt_boss(duration: float) -> void:
	stagger=duration
	_followup_pending=false
	boss_state="recovery"
	_boss_timer=1.8
	attack="idle"
	windup=0
	weakpoint=true
	for descriptor: Dictionary in attacks:
		if str(descriptor["kind"]) in ["cleave","lunge"]: descriptor["cancelled"]=true
		elif str(descriptor["kind"])=="meteor" and bool(descriptor.get("tracking",false)) and not bool(descriptor.get("locked",false)):
			descriptor["cancelled"]=true
			descriptor["tracking"]=false

func _world_offset(local: Vector3, position_value: Vector2) -> Vector3:
	return Vector3(position_value.x+cos(boss_facing)*local.x+sin(boss_facing)*local.z,boss_origin_y+local.y,position_value.y-sin(boss_facing)*local.x+cos(boss_facing)*local.z)

func _segment_sphere(from: Vector3, to: Vector3, center: Vector3, radius: float) -> float:
	var offset: Vector3=from-center
	var segment: Vector3=to-from
	var a: float=segment.length_squared()
	if offset.length_squared()<=radius*radius: return 0
	if a<0.000001: return INF
	var b: float=offset.dot(segment)
	var discriminant: float=b*b-a*(offset.length_squared()-radius*radius)
	if discriminant<0: return INF
	var fraction: float=(-b-sqrt(discriminant))/a
	return fraction if fraction>=0 and fraction<=1 else INF


## Authoritative current-pose query used by aim and by projectile collision.
## Fractions are normalized segment distance, never a weakpoint tolerance.
func trace_boss_segment(from: Vector3, to: Vector3, radius: float=0.0) -> Dictionary:
	var shapes: Array[Dictionary]=_capture_geometry()
	var nearest: float=INF
	var selected: Dictionary={}
	for shape: Dictionary in shapes:
		var fraction: float=_segment_capsule(from,to,shape["a"] as Vector3,shape["b"] as Vector3,float(shape["radius"])+maxf(0,radius))
		# Armor wins an exactly coincident surface; cores cannot pass through it.
		if fraction<nearest or (is_finite(fraction) and absf(fraction-nearest)<0.0000001 and str(shape["surface"])=="armor"):
			nearest=fraction
			selected=shape
	return _resolve_surface(selected,nearest,from,to,maxf(0,radius),shapes,false)

func _capture_geometry() -> Array[Dictionary]:
	var shapes: Array[Dictionary]=[]
	for index: int in range(boss_hit_spheres.size()):
		var sphere: Dictionary=boss_hit_spheres[index]
		var center: Vector3=_world_offset(sphere["center"] as Vector3,boss_position)
		shapes.append({"part_id":str(sphere.get("part_id","body_%d"%index)),"surface":"body","a":center,"b":center,"radius":float(sphere["radius"]),"damage_scale":{},"poise_scale":1.0})
	for index: int in range(boss_weakpoints_local.size()):
		var center: Vector3=_world_offset(boss_weakpoints_local[index],boss_position)
		shapes.append({"part_id":"weak_%d"%index,"surface":"weak","a":center,"b":center,"radius":2.6,"damage_scale":{},"poise_scale":1.0})
	for capsule: Dictionary in boss_hit_capsules_local:
		shapes.append({"part_id":str(capsule["part_id"]),"surface":str(capsule.get("surface","armor")),"a":_world_offset(capsule["a"] as Vector3,boss_position),"b":_world_offset(capsule["b"] as Vector3,boss_position),"radius":maxf(0,float(capsule["radius"])),"damage_scale":capsule.get("damage_scale",{"ballista":0.7,"cannon":0.9,"harpoon":0.8}),"poise_scale":float(capsule.get("poise_scale",1.0))})
	return shapes

func _hit_result(shape: Dictionary, fraction: float, from: Vector3, to: Vector3) -> Dictionary:
	if shape.is_empty() or not is_finite(fraction): return {}
	return {"fraction":fraction,"position":from.lerp(to,fraction),"part_id":shape["part_id"],"surface":shape["surface"],"weak":str(shape["surface"])=="weak" and weakpoint,"damage_scale":shape["damage_scale"],"poise_scale":shape["poise_scale"]}

## The core is an overlay on a slightly overlapping body proxy, not an
## extra travel allowance. Probe at the actual body-contact pose, in metres,
## including beyond the current projectile segment so substep boundaries do
## not change the material. Armor between body and core always blocks it.
func _resolve_surface(selected: Dictionary, fraction: float, from: Vector3, to: Vector3, radius: float, shapes: Array[Dictionary], moving: bool) -> Dictionary:
	if selected.is_empty() or str(selected["surface"])!="body": return _hit_result(selected,fraction,from,to)
	var point: Vector3=from.lerp(to,fraction)
	var direction: Vector3=(to-from).normalized()
	var probe_end: Vector3=point+direction*0.35
	var weak_shape: Dictionary={}
	var weak_depth: float=INF
	for index: int in range(shapes.size()):
		var shape: Dictionary=shapes[index]
		if str(shape["surface"])!="weak": continue
		var entry: float=_surface_entry_at_contact(shape,index,point,probe_end,radius,fraction,moving)
		if entry<weak_depth:
			weak_depth=entry
			weak_shape=shape
	if weak_shape.is_empty(): return _hit_result(selected,fraction,from,to)
	var weak_point: Vector3=point.lerp(probe_end,weak_depth)
	for index: int in range(shapes.size()):
		var shape: Dictionary=shapes[index]
		if str(shape["surface"])!="armor": continue
		if is_finite(_surface_entry_at_contact(shape,index,point,weak_point,radius,fraction,moving)):
			return _hit_result(selected,fraction,from,to)
	var result: Dictionary=_hit_result(weak_shape,fraction,from,to)
	result["overlay_depth"]=point.distance_to(weak_point)
	return result

func _surface_entry_at_contact(shape: Dictionary, index: int, from: Vector3, to: Vector3, radius: float, fraction: float, moving: bool) -> float:
	var a: Vector3=shape["a"] as Vector3
	var b: Vector3=shape["b"] as Vector3
	var width: float=float(shape["radius"])
	if moving:
		var entry: Dictionary=_geometry_motion[index]
		var previous: Dictionary=entry["previous"] as Dictionary
		a=(previous["a"] as Vector3).lerp(a,fraction)
		b=(previous["b"] as Vector3).lerp(b,fraction)
		width=lerpf(float(previous["radius"]),width,fraction)
	return _segment_capsule(from,to,a,b,width+radius)

func _segment_capsule(from: Vector3, to: Vector3, a: Vector3, b: Vector3, radius: float) -> float:
	var axis: Vector3=b-a
	var length2: float=axis.length_squared()
	if length2<0.00000001: return _segment_sphere(from,to,a,radius)
	var closest: Vector3=a+axis*clampf((from-a).dot(axis)/length2,0,1)
	if from.distance_squared_to(closest)<=radius*radius: return 0.0
	var d: Vector3=to-from
	var offset: Vector3=from-a
	var axis_d: float=axis.dot(d)
	var axis_o: float=axis.dot(offset)
	var aa: float=length2*d.length_squared()-axis_d*axis_d
	var bb: float=length2*d.dot(offset)-axis_o*axis_d
	var cc: float=length2*(offset.length_squared()-radius*radius)-axis_o*axis_o
	var nearest: float=minf(_segment_sphere(from,to,a,radius),_segment_sphere(from,to,b,radius))
	var disc: float=bb*bb-aa*cc
	if aa>0.00000001 and disc>=0:
		var fraction: float=(-bb-sqrt(disc))/aa
		var height: float=axis_o+fraction*axis_d
		if fraction>=0 and fraction<=1 and height>=0 and height<=length2: nearest=minf(nearest,fraction)
	return nearest

## Cache correspondence once per logic step, rather than rebuilding all poses
## for every projectile. A/B endpoint deformation is bounded independently of
## translation. Linear interpolation is the pose contract between 60Hz samples.
func _prepare_geometry_motion() -> void:
	_geometry_motion.clear()
	sweep_error_budget=0.0
	var previous_by_id: Dictionary={}
	for shape: Dictionary in _previous_geometry: previous_by_id[shape["part_id"]]=shape
	for shape: Dictionary in _current_geometry:
		var previous: Dictionary=previous_by_id.get(shape["part_id"],shape) as Dictionary
		var da: Vector3=(shape["a"] as Vector3)-(previous["a"] as Vector3)
		var db: Vector3=(shape["b"] as Vector3)-(previous["b"] as Vector3)
		var motion: Vector3=(da+db)*0.5
		var deformation: float=maxf((da-motion).length(),(db-motion).length())
		var slices: int=clampi(int(ceil(deformation/0.2)),1,64)
		var error: float=deformation/(2.0*float(slices))
		sweep_error_budget=maxf(sweep_error_budget,error)
		_geometry_motion.append({"shape":shape,"previous":previous,"motion":motion,"slices":slices,"error":error})

func _trace_moving_geometry(from: Vector3, to: Vector3, radius: float) -> Dictionary:
	var nearest: float=INF
	var selected: Dictionary={}
	for entry: Dictionary in _geometry_motion:
		var shape: Dictionary=entry["shape"] as Dictionary
		var previous: Dictionary=entry["previous"] as Dictionary
		var motion: Vector3=entry["motion"] as Vector3
		var slices: int=int(entry["slices"])
		var old_a: Vector3=previous["a"] as Vector3
		var old_b: Vector3=previous["b"] as Vector3
		var new_a: Vector3=shape["a"] as Vector3
		var new_b: Vector3=shape["b"] as Vector3
		var expanded_radius: float=maxf(float(previous["radius"]),float(shape["radius"]))+radius+float(entry["error"])
		for index: int in range(slices):
			var start: float=float(index)/float(slices)
			if start>nearest: break
			var finish: float=float(index+1)/float(slices)
			var mid: float=(start+finish)*0.5
			# Remove uniform motion exactly, freeze only endpoint deformation at
			# the interval midpoint, conservatively expanded by <=error metres.
			var a: Vector3=old_a.lerp(new_a,mid)-motion*mid
			var b: Vector3=old_b.lerp(new_b,mid)-motion*mid
			var fraction: float=_segment_capsule(from.lerp(to,start)-motion*start,from.lerp(to,finish)-motion*finish,a,b,expanded_radius)
			if not is_finite(fraction): continue
			var total: float=lerpf(start,finish,fraction)
			if total<nearest or (absf(total-nearest)<0.0000001 and str(shape["surface"])=="armor"):
				nearest=total
				selected=shape
	return _resolve_surface(selected,nearest,from,to,radius,_current_geometry,true)

func _advance_projectiles(delta: float, events: Array[Dictionary]) -> void:
	for index: int in range(projectiles.size()-1,-1,-1):
		var projectile: Dictionary=projectiles[index]
		var origin: Vector3=projectile["position"] as Vector3
		var velocity: Vector3=projectile["velocity"] as Vector3
		var remaining_range: float=maxf(0,float(projectile["max_range"])-float(projectile["travelled"]))
		var travel: float=minf(velocity.length()*delta,remaining_range)
		var target: Vector3=origin+velocity.normalized()*travel
		projectile["travelled"]=float(projectile["travelled"])+travel
		var hit: Dictionary=_trace_moving_geometry(origin,target,float(projectile["radius"]))
		projectile["age"]=float(projectile["age"])+delta
		projectile["position"]=target
		if not hit.is_empty():
			var point: Vector3=hit["position"] as Vector3
			var critical: bool=bool(hit["weak"])
			var weapon: String=str(projectile["weapon"])
			var config: Dictionary=WEAPONS[weapon] as Dictionary
			var raw_damage: float=float(config["weak"] if critical else config["damage"])
			var damage: float=raw_damage*float((hit["damage_scale"] as Dictionary).get(weapon,1.0))
			boss_hp=maxf(0,boss_hp-damage)
			events.append({"type":"boss_hit","weapon":weapon,"damage":damage,"raw_damage":raw_damage,"part_id":hit["part_id"],"surface":hit["surface"],"weak":critical,"position":point,"incoming":velocity,"id":projectile["id"]})
			if weapon=="harpoon":
				slowed=3.0
				tether_remaining=3.0
			elif weapon=="cannon":
				poise+=(100.0 if critical else 70.0)*float(hit["poise_scale"])
				if poise>=130:
					poise=0
					_interrupt_boss(1.25)
			projectiles.remove_at(index)
			if boss_hp<=0:
				_finish(true,events)
				return
			if boss_hp<max_boss_hp*0.5 and phase==1:
				phase=2
				events.append({"type":"phase","phase":2})
				_set_notice("角渊暴怒：追击与连锁落点强化。",4)
		elif float(projectile["age"])>=float(projectile["life"]) or float(projectile["travelled"])>=float(projectile["max_range"])-0.0001:
			events.append({"type":"projectile_miss","id":projectile["id"],"weapon":projectile["weapon"]})
			projectiles.remove_at(index)

func _finish(victory: bool, events: Array[Dictionary]) -> void:
	if ended: return
	ended=true
	won=victory
	attack="idle"
	windup=0
	weakpoint=false
	invulnerable=false
	action_state="free"
	action_remaining=0
	action_total=0
	action_weapon=""
	boss_velocity=Vector2.ZERO
	attacks.clear()
	projectiles.clear()
	_set_notice("角渊伏诛，猎神号归航。" if victory else "猎神号沉入深海。",999)
	events.append({"type":"end","won":won})

func _set_notice(message: String, duration: float) -> void:
	notice=message
	notice_time=duration




