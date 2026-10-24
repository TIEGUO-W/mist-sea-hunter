extends Node3D
## A physical hunter encounter. Combat owns world positions and attack geometry.
signal battle_finished(victory: bool, remaining_hull: float)
const Combat = preload("res://scripts/combat.gd")
const Monster = preload("res://scripts/sea_monster.gd")
const Ship = preload("res://scripts/ship.gd")
const BattleHUD = preload("res://scripts/battle_hud.gd")
const Arena = preload("res://scripts/arena.gd")
const CombatVFX = preload("res://scripts/combat_vfx.gd")
const EncounterSettings = preload("res://scripts/encounter_settings.gd")
const BattleAudio = preload("res://scripts/battle_audio.gd")
const BOSS_Y: float = -11.0
const CONTACT_RADIUS: float = 19.0
const ARENA_RADIUS: float = 420.0
const CRUISE_SPEED: float = 20.0
const WEAPON_ORDER: Array[String] = ["ballista", "cannon", "harpoon"]

var combat = Combat.new()
var ship: Node3D
var monster: Node3D
var camera: Camera3D
var hud: CanvasLayer
var arena: Node3D
var vfx: Node3D
var battle_audio: Node
var position_xz: Vector2 = Vector2(0,85)
var velocity_xz: Vector2 = Vector2.ZERO
var dodge_direction: Vector2 = Vector2.RIGHT
var last_direction: Vector2 = Vector2.RIGHT
var ship_heading: float = 0.0
var ship_speed: float = 0.0
var ship_turn: float = 0.0
var return_scene: String = ""
var _previous_mute: bool = false
var weapon: String = "ballista"
var aim: Vector2 = Vector2(800,390)
var time: float = 0.0
var visual_time: float = 0.0
var shake: float = 0.0
const COMBAT_BUS: String = "Combat"
var _stop_timer: float = 0.0
var _stop_scale: float = 1.0
var _push: float = 0.0
var _duck: float = 0.0
var _cam_distance: float = 11.0
var _cam_height: float = 6.4
var _cam_look: float = 10.2
var _cam_roll: float = 0.0
var flash: float = 0.0
var damage_flash: float = 0.0
var tutorial_progress: Dictionary={"moved":false,"fired":false,"switched":false,"dodged":false,"guarded":false}
var _tutorial_travel: float=0.0
var briefing: bool = true
var paused: bool = false
var muted: bool = false
var result_shown: bool = false
var hold_fire: bool = false
var guard_held: bool = false
var demo_mode: bool = false
var demo_angle: float = 0.0
var demo_shots: int = 0
var demo_dodges: int = 0
var _capture_path: String = ""
var _capture_time: float = 12.0
var _capture_done: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _weak_rings: Array[MeshInstance3D] = []
var _demo_label: Label
var _sinking: float = 0.0
var settings: CanvasLayer
var preferences: Dictionary={"quality":2,"fullscreen":false,"volume":.8,"shake":true}
var _previous_volume_db: float=0.0
var _previous_window_mode: int=0
var _previous_window_size: Vector2i=Vector2i.ZERO
var _previous_msaa: int=0
var _settings_return_mode: String="paused"
var _restored_globals: bool=false
var _leaving: bool=false
var _previous_auto_accept_quit: bool=true
var _preparing: bool=false
var _preparation_frames: int=0
var _auto_start: bool=false

func _ready() -> void:
	_rng.seed=43372
	_previous_auto_accept_quit=get_tree().auto_accept_quit
	get_tree().auto_accept_quit=false
	_previous_mute=AudioServer.is_bus_mute(0)
	_previous_volume_db=AudioServer.get_bus_volume_db(0)
	_previous_window_mode=DisplayServer.window_get_mode()
	_previous_window_size=DisplayServer.window_get_size()
	_previous_msaa=get_viewport().msaa_3d
	muted=_previous_mute
	return_scene=str(get_tree().root.get_meta("sea_boss_demo_return_scene",""))
	if get_tree().root.has_meta("sea_boss_demo_return_scene"):
		get_tree().root.remove_meta("sea_boss_demo_return_scene")
	arena=Arena.new()
	add_child(arena)
	ship=Ship.new()
	ship.name="Ship"
	add_child(ship)
	monster=Monster.new()
	monster.name="SeaMonster"
	add_child(monster)
	monster.position=Vector3(0,BOSS_Y,0)
	monster.scale=Vector3.ONE*3.0
	_ensure_combat_bus()
	vfx=CombatVFX.new()
	vfx.name="CombatVFX"
	add_child(vfx)
	camera=Camera3D.new()
	camera.name="HunterBowCamera"
	camera.far=4000
	camera.near=0.2
	camera.current=true
	camera.cull_mask=1|2
	add_child(camera)
	hud=BattleHUD.new()
	add_child(hud)
	hud.action_requested.connect(_on_action)
	hud.start_requested.connect(start_battle)
	hud.restart_requested.connect(restart_battle)
	hud.pause_requested.connect(toggle_pause)
	hud.return_requested.connect(return_to_origin)
	settings=EncounterSettings.new()
	add_child(settings)
	settings.settings_changed.connect(_apply_preferences)
	settings.closed.connect(_settings_closed)
	_apply_preferences(settings.get_values())
	_build_markers()
	battle_audio=BattleAudio.new()
	battle_audio.name="BattleAudio"
	battle_audio.set_paused(true)
	battle_audio.set_muted(muted)
	add_child(battle_audio)
	var grading: CanvasLayer=CanvasLayer.new()
	grading.layer=2
	add_child(grading)
	var film: ColorRect=ColorRect.new()
	grading.add_child(film)
	film.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	film.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var material: ShaderMaterial=ShaderMaterial.new()
	material.shader=preload("res://shaders/film.gdshader")
	film.material=material
	aim=get_viewport().get_visible_rect().size*Vector2(0.5,0.44)
	combat.hit_geometry_updater=_update_hit_geometry
	_update_hit_geometry()
	for arg: String in OS.get_cmdline_user_args():
		if arg=="--demo": demo_mode=true
		elif arg.begins_with("--capture="): _capture_path=arg.trim_prefix("--capture=")
		elif arg.begins_with("--capture-time="): _capture_time=float(arg.trim_prefix("--capture-time="))
	if demo_mode:
		_demo_label=Label.new()
		_demo_label.position=Vector2(32,110)
		_demo_label.add_theme_font_size_override("font_size",15)
		_demo_label.add_theme_color_override("font_color",Color("c4c9d3"))
		(hud.get("_base") as Control).add_child(_demo_label)
	_auto_start=demo_mode or _capture_path!=""
	hud.set_overlay("briefing")
	_update_presentation(0.0)
	_begin_preparation()

func _begin_preparation() -> void:
	_preparing=true
	_preparation_frames=0
	hud.set_preparing(true)
	_sync_audio()
	var result: Dictionary=vfx.prepare_preview(camera)
	if not bool(result.get("draw_required",false)):
		_finish_preparation()
	else:
		RenderingServer.frame_post_draw.connect(_on_preparation_frame)

func _on_preparation_frame() -> void:
	if not _preparing or _leaving: return
	_preparation_frames+=1
	if _preparation_frames>=3: _finish_preparation()

func _finish_preparation() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_preparation_frame):
		RenderingServer.frame_post_draw.disconnect(_on_preparation_frame)
	vfx.finish_preparation()
	_preparing=false
	hud.set_preparing(false)
	if _auto_start and not _leaving: start_battle()
	_sync_audio()

func _process(delta: float) -> void:
	if _leaving: return
	time+=delta
	if not paused and not briefing and not _preparing:
		# 命中冻结：逻辑时间被压慢，表现层仍按真实时间推进（镜头推、粒子、UI 都在动）
		var scaled: float = delta
		if _stop_timer > 0.0:
			_stop_timer = maxf(0.0, _stop_timer - delta)
			scaled = delta * _stop_scale
		_duck = maxf(0.0, _duck - delta * 3.2)
		simulate(minf(scaled, 0.25))
	_update_presentation(delta)
	if _capture_path!="" and visual_time>=_capture_time and not _capture_done:
		_capture_done=true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_capture_path)
		print("CAPTURE_SAVED ",_capture_path," FPS ",Engine.get_frames_per_second())
		_leave_after_audio_drain(false)

func simulate(delta: float, manual_input: Vector2=Vector2.INF) -> void:
	if paused or briefing or _preparing or _leaving or delta<=0: return
	var input_value: Vector2=_read_movement() if manual_input==Vector2.INF else manual_input
	if demo_mode and not combat.ended: input_value=_demo_control()
	var remaining: float=delta
	while remaining>0.000001:
		var step: float=minf(remaining,1.0/60.0)
		visual_time+=step
		if not combat.ended:
			combat.request_guard(guard_held)
			_move_ship(step,input_value)
			_update_hit_geometry()
			combat.muzzle_origin=_current_muzzle()
		for event: Dictionary in combat.tick(step,position_xz,velocity_xz,ship_heading+PI):
			_handle_event(event)
		if combat.guarding and combat.guard_age>=.10: tutorial_progress["guarded"]=true
		_resolve_contact()
		_sync_boss_transform()
		if hold_fire and not combat.ended: fire_weapon()
		remaining-=step
	if combat.ended and combat.won: _sinking=minf(27.0,_sinking+delta*2.5)

func _read_movement() -> Vector2:
	return Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))-float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))).limit_length(1.0)

func _radial() -> Vector2:
	var away: Vector2=position_xz-combat.boss_position
	return away.normalized() if away.length_squared()>0.01 else Vector2.DOWN

func _input_world(input_value: Vector2) -> Vector2:
	var radial: Vector2=_radial()
	return (Vector2(radial.y,-radial.x)*input_value.x-radial*input_value.y).limit_length(1.0)

func _move_ship(delta: float, input_value: Vector2) -> void:
	var desired: Vector2=_input_world(input_value)
	if desired.length()>0.01: last_direction=desired
	var old_position: Vector2=position_xz
	var old_relative: Vector2=position_xz-combat.boss_position
	if combat.action_state=="dodge":
		var progress: float=1.0-combat.action_remaining/maxf(combat.action_total,0.001)
		velocity_xz=dodge_direction*(31.0+sin(progress*PI)*27.0)
	else:
		velocity_xz=velocity_xz.move_toward(desired*CRUISE_SPEED*combat.move_multiplier,delta*75.0)
	position_xz+=velocity_xz*delta
	if position_xz.length()>ARENA_RADIUS:
		position_xz=position_xz.normalized()*ARENA_RADIUS
		velocity_xz=(position_xz-old_position)/delta
	_resolve_contact()
	if desired.length()>.1:
		_tutorial_travel+=position_xz.distance_to(old_position)
		if _tutorial_travel>=2.0: tutorial_progress["moved"]=true
	var relative: Vector2=position_xz-combat.boss_position
	demo_angle+=absf(old_relative.angle_to(relative))
	ship_heading=atan2(relative.x,relative.y)
	ship_turn=lerpf(ship_turn,input_value.x,minf(1,delta*5))
	ship_speed=velocity_xz.length()

func _resolve_contact() -> void:
	var relative: Vector2=position_xz-combat.boss_position
	if relative.length()<CONTACT_RADIUS and not combat.ended:
		var direction: Vector2=relative.normalized() if relative.length()>0.01 else Vector2.DOWN
		position_xz=combat.boss_position+direction*CONTACT_RADIUS
		if position_xz.length()>ARENA_RADIUS: position_xz=position_xz.normalized()*ARENA_RADIUS

func _sync_boss_transform() -> void:
	monster.position=Vector3(combat.boss_position.x,BOSS_Y-_sinking,combat.boss_position.y)
	monster.rotation.y=combat.boss_facing

func _update_hit_geometry() -> void:
	_sync_boss_transform()
	monster.set_state(combat.elapsed,combat.attack,combat.windup,combat.stagger,combat.boss_velocity.length(),combat.boss_state)
	combat.boss_origin_y=BOSS_Y
	var body_spheres: Array[Dictionary]=[{"center":Vector3(0,19.5,0),"radius":8.6},{"center":Vector3(0,22.0,1.0),"radius":8.1},{"center":Vector3(0,13.5,0),"radius":9.0}]
	combat.boss_hit_spheres=body_spheres
	var points: Array[Vector3]=[]
	for point: Vector3 in monster.get_weakpoints():
		points.append(monster.to_local(point)*3.0)
	combat.boss_weakpoints_local=points
	var capsules: Array[Dictionary]=[]
	if monster.has_method("get_hit_capsules"): capsules.assign(monster.get_hit_capsules())
	combat.boss_hit_capsules_local=capsules

func _update_presentation(delta: float) -> void:
	ship.position=Vector3(position_xz.x,arena.sample_wave(position_xz,visual_time)*0.72,position_xz.y)
	ship.rotation=Vector3(sin(visual_time*1.2)*0.018,ship_heading,-ship_turn*0.045+sin(visual_time*1.7)*0.016)
	ship.set_weapon(weapon)
	ship.animate_ship(visual_time,ship_turn,ship_speed)
	_sync_boss_transform()
	monster.set_state(visual_time,combat.attack,combat.windup,combat.stagger,combat.boss_velocity.length(),combat.boss_state)
	arena.animate(visual_time,ship.global_position,ship_heading,monster.global_position,combat.attack,combat.windup,combat.phase,ship_speed)
	_update_camera(delta)
	if not _preparing:
		vfx.update_state(visual_time,combat.attacks,combat.projectiles,monster.global_position,ship.global_position,combat.guarding,combat.guard_age)
	_sync_audio()
	battle_audio.update_listener(ship.global_position,monster.global_position,ship_speed,delta)
	if battle_audio.has_method("update_music"):
		var intensity: float=clampf(1.0-combat.boss_hp/maxf(combat.max_boss_hp,1.0),0.0,1.0)*0.55
		intensity+=clampf(combat.windup,0.0,1.0)*0.45
		battle_audio.update_music(combat.phase,intensity,delta)
	_update_markers()
	_update_hud()
	shake=maxf(0,shake-delta*2)
	flash=maxf(0,flash-delta*3)
	damage_flash=maxf(0,damage_flash-delta*3)

func _update_camera(delta: float) -> void:
	var distance: float=position_xz.distance_to(combat.boss_position)
	var radial: Vector2=_radial()
	var behind: Vector3=Vector3(radial.x,0,radial.y)
	var close: float=clampf((60.0-distance)/35.0,0,1)
	var windup: float=clampf(combat.windup,0.0,1.0) if combat.boss_state=="windup" else 0.0
	# 机位是一部小状态机：默认 → 逼近 → 蓄力压低 → 释放后拉 → 击杀抬升
	var want_distance: float=11.0-close*0.9+float(combat.boss_state=="active")*0.9+windup*-0.5
	var want_height: float=6.4-close*0.5-windup*1.15
	var want_look: float=10.2+close*0.7+windup*1.35
	var want_roll: float=0.0
	if combat.boss_state=="active":
		want_roll=sin(combat.elapsed*17.0)*0.007
	if combat.ended:
		var settle: float=1.0 if not combat.won else clampf(_sinking/27.0,0.0,1.0)
		want_height+=(4.8 if combat.won else 1.2)*maxf(settle,0.35)
		want_distance+=(3.2 if combat.won else 1.6)*maxf(settle,0.35)
		want_look+=(3.4 if combat.won else 1.0)*maxf(settle,0.35)
	_cam_distance=lerpf(_cam_distance,want_distance,minf(1.0,delta*3.4))
	_cam_height=lerpf(_cam_height,want_height,minf(1.0,delta*3.4))
	_cam_look=lerpf(_cam_look,want_look,minf(1.0,delta*3.4))
	_cam_roll=lerpf(_cam_roll,want_roll,minf(1.0,delta*4.0))
	# 命中推力：向目标推 0.9 米并收 2.4° 视角，随后指数回落
	_push=maxf(0.0,_push-delta*4.6)
	var punch: float=_push*_push
	var shift: Vector3=behind*(-punch*0.9)+Vector3.UP*(punch*0.22)
	var jolt: Vector3=Vector3(_rng.randf_range(-1,1),_rng.randf_range(-.5,.5),0)*shake*.10*(1.0 if bool(preferences["shake"]) else 0.0)
	camera.position=ship.position+behind*_cam_distance+Vector3.UP*_cam_height+shift+jolt
	camera.look_at(Vector3(combat.boss_position.x,_cam_look,combat.boss_position.y))
	camera.fov=60.0+close*22.0+(2.0 if combat.action_state=="dodge" else 0.0)-punch*2.4
	if absf(_cam_roll)>0.0001:
		camera.rotate_object_local(Vector3.BACK,_cam_roll)

func _aim_result() -> Dictionary:
	var origin: Vector3=camera.project_ray_origin(aim)
	var direction: Vector3=camera.project_ray_normal(aim)
	var contact: Dictionary=combat.trace_boss_segment(origin,origin+direction*900.0)
	var hit_point: Vector3=origin+direction*400.0
	if not contact.is_empty(): hit_point=contact["position"] as Vector3
	var muzzle: Vector3=_current_muzzle()
	var muzzle_contact: Dictionary={}
	if not contact.is_empty():
		var shot_direction: Vector3=(hit_point-muzzle).normalized()
		var projectile_radius: float=float(Combat.WEAPONS[weapon]["radius"])
		muzzle_contact=combat.trace_boss_segment(muzzle,hit_point+shot_direction*.05,projectile_radius)
	var max_range: float={"ballista":180.0,"cannon":310.0,"harpoon":135.0}.get(weapon,180.0)
	var actual_distance: float=muzzle.distance_to(muzzle_contact["position"] as Vector3) if not muzzle_contact.is_empty() else -1.0
	var in_range: bool=actual_distance>=0 and actual_distance<=max_range
	var hit: bool=not muzzle_contact.is_empty() and in_range
	if contact.is_empty() and direction.y<-.001: hit_point=origin+direction*((0.1-origin.y)/direction.y)
	return {"hit":hit,"weak":bool(muzzle_contact.get("weak",false)) and hit,"point":hit_point,"distance":actual_distance,"in_range":in_range,"part_id":muzzle_contact.get("part_id",""),"surface":muzzle_contact.get("surface","")}

func _current_muzzle() -> Vector3:
	return Vector3(position_xz.x,ship.position.y,position_xz.y)+Basis(Vector3.UP,ship_heading)*ship.get_muzzle_local()

func fire_weapon() -> bool:
	if briefing or paused or _preparing or _leaving or combat.ended: return false
	ship.set_weapon(weapon)
	var result: Dictionary=_aim_result()
	var muzzle: Vector3=_current_muzzle()
	return combat.request_shot(weapon,muzzle,result["point"],bool(result["weak"]))

func cycle_weapon(direction: int) -> bool:
	if briefing or paused or _preparing or _leaving or combat.ended or direction==0: return false
	if not combat.can_switch_weapon():
		hud.show_notice("动作结束后才能切换武器")
		return false
	var index: int=WEAPON_ORDER.find(weapon)
	weapon=WEAPON_ORDER[posmod(index+(1 if direction>0 else -1),WEAPON_ORDER.size())]
	ship.set_weapon(weapon)
	tutorial_progress["switched"]=true
	return true

func request_dodge(input_value: Vector2=Vector2.INF) -> bool:
	if briefing or paused or _preparing or _leaving or combat.ended: return false
	var chosen: Vector2=_read_movement() if input_value==Vector2.INF else input_value
	var desired: Vector2=_input_world(chosen).normalized()
	if desired.length()<0.1: desired=last_direction.normalized()
	if not combat.request_dodge():
		hud.show_notice("当前动作未恢复，或体力不足")
		return false
	dodge_direction=desired
	if demo_mode: demo_dodges+=1
	return true

func issue_command(action: String) -> bool:
	return false if briefing or paused or _preparing or _leaving or combat.ended else combat.command(action)

func _impact(duration: float, freeze_scale: float) -> void:
	# 只有更强的冲击才能覆盖正在进行的冻结，避免连击把时间轴压死
	var strength: float = duration * (1.0 - freeze_scale)
	if strength > _stop_timer * (1.0 - _stop_scale):
		_stop_timer = duration
		_stop_scale = freeze_scale
	_push = maxf(_push, clampf(duration / 0.11, 0.35, 1.0))
	_duck = maxf(_duck, clampf(duration / 0.11, 0.40, 1.0))


func _ensure_combat_bus() -> void:
	if AudioServer.get_bus_index(COMBAT_BUS) != -1:
		return
	AudioServer.add_bus()
	var index: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, COMBAT_BUS)
	AudioServer.set_bus_send(index, "Master")
	var lowpass: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = 20500.0
	lowpass.resonance = 0.45
	AudioServer.add_bus_effect(index, lowpass)
	var reverb: AudioEffectReverb = AudioEffectReverb.new()
	reverb.room_size = 0.58
	reverb.damping = 0.55
	reverb.spread = 0.6
	reverb.wet = 0.13
	reverb.dry = 0.9
	AudioServer.add_bus_effect(index, reverb)


func _handle_event(event: Dictionary) -> void:
	vfx.on_event(event)
	battle_audio.on_event(event)
	match str(event["type"]):
		"player_shot":
			tutorial_progress["fired"]=true
			var kind: String=str(event["weapon"])
			ship.recoil(kind)
			shake=maxf(shake,.42 if kind=="cannon" else .1)
			if demo_mode: demo_shots+=1
		"boss_hit":
			var point: Vector3=event["position"]
			var critical: bool=bool(event.get("weak",false))
			monster.hit_flash(1.0 if critical else .7,point,str(event.get("part_id","")))
			if critical:
				_impact(0.090,0.14)
			elif str(event.get("weapon",""))=="cannon":
				_impact(0.070,0.20)
			else:
				_impact(0.040,0.36)
			flash=.45
			shake=maxf(shake,.55 if critical else .18)
			hud.show_damage(float(event["damage"]),camera.unproject_position(point),critical,str(event.get("surface",""))=="armor")
		"hit":
			shake=1.0
			_impact(0.110,0.24)
			damage_flash=1
			hud.show_notice("船体受击 −%d" % int(event["damage"]))
		"dodge":
			tutorial_progress["dodged"]=true
		"impact":
			if bool(event.get("hit",false)):
				shake=1.0
				_impact(0.115,0.24)
				damage_flash=1.0
				hud.show_notice("船体受击 −%d" % int(event.get("damage",0)))
		"parry":
			tutorial_progress["guarded"]=true
			shake=.5
			_impact(0.170,0.16)
			hud.show_notice("完美格挡 · 海怪失衡！")
		"blocked":
			tutorial_progress["guarded"]=true
			shake=.28
		"guard_break":
			shake=.9
			_impact(0.130,0.20)
			hud.show_notice("体力耗尽 · 破防！")
		"phase":
			shake=.65
			_impact(0.220,0.28)
		"end":
			if not result_shown:
				result_shown=true
				_impact(0.300,0.12)
				hold_fire=false
				guard_held=false
				hud.set_result({"time":combat.elapsed,"hull":combat.hull,"repairs":2-combat.repair_charges,
					"boss_hp":combat.boss_hp,"max_hp":combat.max_boss_hp,"won":combat.won})
				hud.set_overlay("victory" if combat.won else "defeat")
				battle_finished.emit(combat.won,combat.hull)

func _build_markers() -> void:
	for index: int in range(4):
		var ring: MeshInstance3D=MeshInstance3D.new()
		var mesh: TorusMesh=TorusMesh.new()
		mesh.inner_radius=1.8
		mesh.outer_radius=1.86
		mesh.rings=32
		mesh.ring_segments=6
		ring.mesh=mesh
		var material: StandardMaterial3D=StandardMaterial3D.new()
		material.albedo_color=Color("bba487")
		material.emission_enabled=true
		material.emission=Color("bba487")
		material.emission_energy_multiplier=.7
		ring.material_override=material
		add_child(ring)
		_weak_rings.append(ring)

func _update_markers() -> void:
	var points: Array[Vector3]=monster.get_weakpoints()
	for index: int in range(_weak_rings.size()):
		var ring: MeshInstance3D=_weak_rings[index]
		ring.visible=combat.weakpoint and not combat.ended and index<points.size() and not briefing
		if index<points.size():
			ring.position=points[index]
			ring.look_at(camera.position)
			ring.rotate_object_local(Vector3.RIGHT,PI*.5)

func _threat_markers() -> Array[Dictionary]:
	var markers: Array[Dictionary]=[]
	var viewport_size: Vector2=get_viewport().get_visible_rect().size
	for hazard: Dictionary in combat.attacks:
		if bool(hazard.get("cancelled",false)): continue
		if float(hazard["age"])>float(hazard["delay"])+float(hazard["active"]): continue
		var point: Vector2=hazard["target"]
		if point.distance_to(position_xz)>65: continue
		var world: Vector3=Vector3(point.x,.5,point.y)
		var screen: Vector2=camera.unproject_position(world)
		if camera.is_position_behind(world) or not Rect2(Vector2.ZERO,viewport_size).has_point(screen):
			var offset: Vector3=world-ship.position
			markers.append({"screen_direction":Vector2(offset.dot(camera.global_basis.x),offset.dot(camera.global_basis.z)).normalized(),"distance":point.distance_to(position_xz),"kind":hazard["kind"]})
	return markers

func _update_hud() -> void:
	var aiming: Dictionary=_aim_result()
	hud.update_state({"hp":combat.boss_hp,"max_hp":combat.max_boss_hp,"hull":combat.hull,"stamina":combat.stamina,"maxstamina":combat.max_stamina,"phase":combat.phase,"cooldowns":combat.cooldowns,"weapon":weapon,"attack":combat.attack,"windup":combat.windup,"weak":combat.weakpoint,"notice":combat.notice if combat.notice_time>0 else "锁点后移开 · 近战格挡 · 恢复窗口反击","speed":ship_speed*1.94,"aim":aim,"hit_flash":flash,"damage_flash":damage_flash,"aim_hit":bool(aiming["hit"]),"aim_weak":bool(aiming["weak"]) and combat.weakpoint,"aim_distance":float(aiming["distance"]),"aim_in_range":bool(aiming["in_range"]),"tutorial_progress":tutorial_progress,"muted":muted or float(preferences["volume"])<=0.0,"action_state":combat.action_state,"action_weapon":combat.action_weapon,"action_remaining":combat.action_remaining,"action_total":combat.action_total,"repair_charges":combat.repair_charges,"ship_pos":position_xz,"boss_pos":combat.boss_position,"bossdistance":position_xz.distance_to(combat.boss_position),"heading":ship_heading,"boss_facing":combat.boss_facing,"arena_radius":ARENA_RADIUS,"dodge_ready":combat.action_state in ["free","guard"] and combat.stamina>=28,"threats":_threat_markers(),"attacks":combat.attacks,"guarding":combat.guarding,"guard_age":combat.guard_age,"tether_remaining":combat.tether_remaining,"boss_state":combat.boss_state})

func _demo_control() -> Vector2:
	var distance: float=position_xz.distance_to(combat.boss_position)
	var move: Vector2=Vector2(1,clampf((distance-88.0)*.07,-.8,.6)).limit_length(1.0)
	var danger: bool=false
	var incoming: bool=false
	for hazard: Dictionary in combat.attacks:
		if bool(hazard.get("cancelled",false)): continue
		var eta: float=float(hazard["delay"])-float(hazard["age"])
		var kind: String=str(hazard["kind"])
		if float(hazard["age"])>=float(hazard["delay"])+float(hazard["active"]): continue
		incoming=true
		if eta>1.3: continue
		if kind=="meteor" and (not bool(hazard.get("locked",false)) or float(hazard["age"])-float(hazard["lock_age"])<.50): continue
		if kind in ["meteor","lightning"]:
			var offset: Vector2=position_xz-(hazard["target"] as Vector2)
			if offset.length()<float(hazard["radius"])+10.0:
				var desired: Vector2=offset.normalized() if offset.length()>1.0 else Vector2(_radial().y,-_radial().x)
				move=Vector2(desired.dot(Vector2(_radial().y,-_radial().x)),-desired.dot(_radial())).normalized()
				if eta<.30 and offset.length()<float(hazard["radius"])+4: danger=true
		elif kind=="cleave" and distance<float(hazard["range"])+12:
			move=Vector2(1,-.85).normalized()
			if eta<.22: danger=true
		elif kind=="lunge":
			var side: Vector2=Vector2((hazard["direction"] as Vector2).y,-(hazard["direction"] as Vector2).x)
			var across: float=(position_xz-(hazard["origin"] as Vector2)).dot(side)
			var escape: Vector2=side if across>=0 else -side
			move=Vector2(escape.dot(Vector2(_radial().y,-_radial().x)),-escape.dot(_radial()))
			if eta<.20 and distance<52 and absf(across)<float(hazard["radius"])+6: danger=true
	var counter_time: float=float(combat._boss_timer) if combat.boss_state=="recovery" and not combat._followup_pending and not incoming else 0.0
	if combat.action_state=="free":
		if danger and combat.stamina>=28: request_dodge(move)
		elif combat.hull<=62 and combat.repair_charges>0 and counter_time>2.2 and combat.stamina>=55: issue_command("repair")
		elif combat.stamina>58 and (counter_time>.4 or (combat.boss_state=="chase" and not incoming)):
			var chosen: String="ballista"
			if counter_time>1.8 and combat.stamina>78 and float(combat.cooldowns["cannon"])<=0: chosen="cannon"
			elif combat.boss_state=="chase" and distance<110 and float(combat.cooldowns["harpoon"])<=0: chosen="harpoon"
			if chosen!=weapon:
				var delta_index: int=posmod(WEAPON_ORDER.find(chosen)-WEAPON_ORDER.find(weapon),3)
				cycle_weapon(1 if delta_index==1 else -1)
			var target: Vector3=monster.get_weakpoint()
			var nearest: float=INF
			for point: Vector3 in monster.get_weakpoints():
				if point.distance_to(camera.position)<nearest:
					target=point
					nearest=point.distance_to(camera.position)
			var travel: float=ship.position.distance_to(target)/float(Combat.WEAPONS[weapon]["speed"])+float(Combat.WEAPONS[weapon]["windup"])
			target+=Vector3(combat.boss_velocity.x,0,combat.boss_velocity.y)*travel
			aim=camera.unproject_position(target)
			fire_weapon()
	if _demo_label!=null:
		_demo_label.text="实机自动操控 / %.0fs · 距离 %.0fm · 发射 %d · 闪避 %d" % [visual_time,distance,demo_shots,demo_dodges]
	return move

func _unhandled_input(event: InputEvent) -> void:
	if _leaving or _preparing or (is_instance_valid(settings) and settings.is_open): return
	if event is InputEventMouseMotion: aim=event.position
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:
			hold_fire=event.pressed and not briefing and not paused
			if hold_fire: fire_weapon()
		elif event.button_index==MOUSE_BUTTON_RIGHT:
			guard_held=event.pressed and not briefing and not paused and not combat.ended
			combat.request_guard(guard_held)
		elif event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed: cycle_weapon(-1)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed: cycle_weapon(1)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ENTER:
				if briefing: start_battle()
			KEY_SPACE:
				if briefing: start_battle()
				else: request_dodge()
			KEY_ESCAPE: toggle_pause()
			KEY_R:
				if combat.ended: restart_battle()
				elif not paused: issue_command("repair")

func _input(event: InputEvent) -> void:
	# Releases are observed even when a UI control consumes the event.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index==MOUSE_BUTTON_LEFT: hold_fire=false
		elif event.button_index==MOUSE_BUTTON_RIGHT:
			guard_held=false
			combat.request_guard(false)

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		_leave_after_audio_drain(false)
		return
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(hud):
		hold_fire=false
		guard_held=false
		combat.request_guard(false)
		if not briefing and not paused and not combat.ended: toggle_pause()

func _on_action(action: String) -> void:
	if _leaving or _preparing: return
	match action:
		"cycle_previous": cycle_weapon(-1)
		"cycle_next": cycle_weapon(1)
		"settings": open_settings()
		"mute":
			muted=not muted
			AudioServer.set_bus_mute(0,muted or float(preferences["volume"])<=0.0)
		"dodge": request_dodge()
		_: issue_command(action)

func _apply_preferences(values: Dictionary) -> void:
	preferences=values.duplicate()
	var quality: int=clampi(int(preferences.get("quality",2)),0,2)
	arena.environment.ssao_enabled=quality>0
	arena.environment.volumetric_fog_enabled=quality>0
	arena.environment.glow_enabled=quality>0
	get_viewport().msaa_3d=[Viewport.MSAA_DISABLED,Viewport.MSAA_2X,Viewport.MSAA_4X][quality]
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(float(preferences.get("volume",.8)),.0001)))
	AudioServer.set_bus_mute(0,muted or float(preferences.get("volume",.8))<=0.0)
	_sync_audio()
	if DisplayServer.get_name()!="headless":
		var wanted: int=DisplayServer.WINDOW_MODE_FULLSCREEN if bool(preferences.get("fullscreen",false)) else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode()!=wanted: DisplayServer.window_set_mode(wanted)

func open_settings() -> void:
	if _leaving or _preparing: return
	if settings.get("is_open")==true: return
	_settings_return_mode="briefing" if briefing else ("victory" if combat.won else "defeat") if combat.ended else "paused"
	if not briefing and not combat.ended:
		paused=true
		hud.set_overlay("paused")
	hold_fire=false
	guard_held=false
	combat.request_guard(false)
	_sync_audio()
	settings.open(preferences)

func _settings_closed() -> void:
	hud.set_overlay(_settings_return_mode)

func _restore_global_preferences() -> void:
	if _restored_globals: return
	_restored_globals=true
	get_tree().auto_accept_quit=_previous_auto_accept_quit
	AudioServer.set_bus_mute(0,_previous_mute)
	AudioServer.set_bus_volume_db(0,_previous_volume_db)
	get_viewport().msaa_3d=_previous_msaa
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_mode(_previous_window_mode)
		if _previous_window_mode==DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_size(_previous_window_size)

func _sync_audio() -> void:
	if not is_instance_valid(battle_audio): return
	battle_audio.set_muted(muted or float(preferences["volume"])<=0.0)
	battle_audio.set_paused(paused or briefing or _preparing or _leaving)
	# 战斗音全部走 Combat 总线：混响 + 冲击瞬间的低通挤压
	var index: int=AudioServer.get_bus_index(COMBAT_BUS)
	if index<0: return
	for child: Node in battle_audio.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).bus!=COMBAT_BUS:
			(child as AudioStreamPlayer).bus=COMBAT_BUS
	AudioServer.set_bus_volume_db(index,lerpf(0.0,-7.0,_duck))
	var lowpass=AudioServer.get_bus_effect(index,0)
	if lowpass is AudioEffectLowPassFilter:
		(lowpass as AudioEffectLowPassFilter).cutoff_hz=lerpf(20500.0,760.0,_duck)

func _stop_audio() -> void:
	if is_instance_valid(battle_audio): battle_audio.stop_all()

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_preparation_frame):
		RenderingServer.frame_post_draw.disconnect(_on_preparation_frame)
	_stop_audio()
	_restore_global_preferences()

func return_to_origin() -> void:
	_leave_after_audio_drain(true)

func _leave_after_audio_drain(to_title: bool) -> void:
	if _leaving: return
	_leaving=true
	if RenderingServer.frame_post_draw.is_connected(_on_preparation_frame):
		RenderingServer.frame_post_draw.disconnect(_on_preparation_frame)
	if _preparing:
		vfx.finish_preparation()
		_preparing=false
	paused=true
	hold_fire=false
	guard_held=false
	combat.request_guard(false)
	_stop_audio()
	# Playback references are retired asynchronously by the audio mixing thread.
	var drain_started: int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-drain_started<150:
		await get_tree().process_frame
	_restore_global_preferences()
	if to_title and return_scene=="res://scenes/ui/title_screen.tscn" and ResourceLoader.exists(return_scene):
		get_tree().change_scene_to_file(return_scene)
	else: get_tree().quit()

func start_battle() -> void:
	if _leaving or _preparing or (is_instance_valid(settings) and settings.is_open): return
	briefing=false
	paused=false
	hold_fire=false
	guard_held=false
	hud.set_overlay("none")
	_sync_audio()

func toggle_pause() -> void:
	if _leaving or _preparing or briefing or combat.ended: return
	paused=not paused
	hold_fire=false
	guard_held=false
	combat.request_guard(false)
	hud.set_overlay("paused" if paused else "none")
	_sync_audio()

func restart_battle() -> void:
	if _leaving or _preparing or (is_instance_valid(settings) and settings.is_open): return
	battle_audio.reset()
	combat=Combat.new()
	combat.hit_geometry_updater=_update_hit_geometry
	position_xz=Vector2(0,85)
	velocity_xz=Vector2.ZERO
	ship_heading=0
	ship_speed=0
	ship_turn=0
	_sinking=0
	_sync_boss_transform()
	visual_time=0
	demo_angle=0
	demo_shots=0
	demo_dodges=0
	shake=0
	flash=0
	damage_flash=0
	weapon="ballista"
	ship.set_weapon(weapon)
	result_shown=false
	vfx.reset()
	_update_hit_geometry()
	start_battle()
