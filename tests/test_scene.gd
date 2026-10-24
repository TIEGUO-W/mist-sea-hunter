extends SceneTree
const DT: float=1.0/60.0
var battle: Node3D
var checks: int=0
var failures: Array[String]=[]
var results: Array[Dictionary]=[]
var evidence: Dictionary={"version":"hunter-v3"}

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	root.set_meta("sea_boss_demo_return_scene","res://scenes/ui/title_screen.tscn")
	battle=(load("res://scenes/sea_battle.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	battle.set_process(false)
	battle.muted=true
	battle.battle_finished.connect(_finished_battle)
	check(battle.briefing and str(battle.hud.get("_overlay_mode"))=="briefing","Scene starts in a usable briefing")
	battle.hud.start_requested.emit()
	check(not battle.briefing,"HUD starts actual encounter")
	_test_controls()
	_test_pause_restart()
	await _test_settings()
	await _test_navigation()
	_test_physical_aim()
	_test_actual_hunter()
	await _test_demo()
	_test_terminal()
	_test_hud_return()
	_test_cancelled_threat()
	_test_camera_visibility()
	battle.queue_free()
	var drain_started: int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-drain_started<160: await process_frame
	var path: String="user://hunter-v3-scene-evidence.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): path=arg.trim_prefix("--evidence=")
	evidence["checks"]=checks
	evidence["failures"]=failures
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(evidence,"  "))
		file.close()
	if failures.is_empty():
		print("PASS: %d hunter packed-scene checks" % checks)
		quit(0)
	else:
		for message: String in failures: printerr("FAIL: "+message)
		quit(1)

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message)

func _finished_battle(won: bool,hull: float) -> void: results.append({"won":won,"hull":hull})

func _step(frames: int,present: bool=false,manual: Vector2=Vector2.ZERO) -> void:
	for frame: int in range(frames):
		battle.simulate(DT,manual)
		if present: battle._update_presentation(DT)

func _mouse(button: MouseButton,pressed: bool,factor: float=1.0) -> void:
	var event: InputEventMouseButton=InputEventMouseButton.new()
	event.button_index=button
	event.pressed=pressed
	event.factor=factor
	event.position=Vector2(800,390)
	battle._unhandled_input(event)

func _key(code: Key) -> void:
	var event: InputEventKey=InputEventKey.new()
	event.physical_keycode=code
	event.keycode=code
	event.pressed=true
	battle._unhandled_input(event)

func _freeze_ai() -> void:
	battle.combat.boss_state="recovery"
	battle.combat._boss_timer=999.0

func _test_controls() -> void:
	battle.restart_battle()
	_freeze_ai()
	_mouse(MOUSE_BUTTON_WHEEL_DOWN,true,5.0)
	check(battle.weapon=="cannon","One wheel event advances exactly one adjacent weapon")
	_mouse(MOUSE_BUTTON_WHEEL_DOWN,true)
	check(battle.weapon=="harpoon","Next notch advances to harpoon")
	_mouse(MOUSE_BUTTON_WHEEL_DOWN,true)
	check(battle.weapon=="ballista","Wheel cycles three distinct current weapons")
	_mouse(MOUSE_BUTTON_WHEEL_UP,true)
	check(battle.weapon=="harpoon","Reverse wheel selects previous adjacent weapon")
	_mouse(MOUSE_BUTTON_WHEEL_UP,true)
	battle._update_presentation(0)
	battle.aim=Vector2.ZERO
	check(battle.weapon=="cannon" and battle.fire_weapon(),"Current heavy weapon begins committed attack")
	_mouse(MOUSE_BUTTON_WHEEL_DOWN,true)
	_mouse(MOUSE_BUTTON_RIGHT,true)
	check(battle.weapon=="cannon" and battle.combat.action_state=="windup" and not battle.combat.guarding and not battle.request_dodge(),"Wheel, guard and dodge cannot cancel heavy windup")
	_mouse(MOUSE_BUTTON_RIGHT,false)
	_step(45)
	check(battle.combat.action_state=="recovery" and not battle.cycle_weapon(1) and not battle.request_dodge(),"Heavy recovery also prevents swap and dodge cancellation")
	_step(65)
	check(battle.cycle_weapon(1) and battle.weapon=="harpoon","Swap resumes after actual heavy recovery")
	_mouse(MOUSE_BUTTON_RIGHT,true)
	check(battle.combat.guarding and battle.guard_held,"Right button holds actual guard")
	var release: InputEventMouseButton=InputEventMouseButton.new()
	release.button_index=MOUSE_BUTTON_RIGHT
	release.pressed=false
	battle._input(release)
	check(not battle.guard_held and not battle.combat.guarding,"Right release over HUD clears guard")
	battle.hold_fire=true
	release.button_index=MOUSE_BUTTON_LEFT
	battle._input(release)
	check(not battle.hold_fire,"Left release over HUD clears firing")
	var old_weapon: String=battle.weapon
	_key(KEY_1)
	_key(KEY_Q)
	_key(KEY_E)
	_key(KEY_F)
	check(battle.weapon==old_weapon and battle.combat.action_state=="free","Retired number and crew shortcuts do nothing")
	battle.combat.hull=50
	_key(KEY_R)
	check(battle.combat.action_weapon=="repair" and battle.combat.repair_charges==1 and battle.combat.hull==50,"R reserves risky limited repair rather than restarting encounter")
	_step(150)
	check(battle.combat.hull==75,"R repair completes through the actual action clock")

func _test_pause_restart() -> void:
	battle.restart_battle()
	_step(120,true)
	battle.hud.pause_requested.emit()
	var elapsed: float=battle.combat.elapsed
	var clock: float=battle.visual_time
	var boss: Vector2=battle.combat.boss_position
	var stamina: float=battle.combat.stamina
	for frame: int in range(30): battle._process(DT)
	check(battle.paused and battle.combat.elapsed==elapsed and battle.visual_time==clock and battle.combat.boss_position==boss and battle.combat.stamina==stamina,"Pause freezes simulation, boss pursuit, stamina and VFX clock")
	battle.hud.pause_requested.emit()
	_step(3)
	check(not battle.paused and battle.combat.elapsed>elapsed,"Resume restores combat")
	battle.hold_fire=true
	battle.guard_held=true
	battle.hud.restart_requested.emit()
	check(battle.position_xz==Vector2(0,85) and battle.combat.hull==100 and battle.combat.stamina==100 and battle.combat.boss_position==Vector2.ZERO,"Restart restores boat, boss, hull and stamina")
	check(not battle.hold_fire and not battle.guard_held and not battle.result_shown and battle.combat.attacks.is_empty() and battle.combat.projectiles.is_empty() and battle.weapon=="ballista","Restart clears all held inputs, attacks, shots and weapon")

func _test_navigation() -> void:
	battle.restart_battle()
	_freeze_ai()
	battle.combat.boss_position=Vector2(120,-40)
	battle.position_xz=Vector2(120,45)
	var quadrants: Dictionary={}
	var angle: float=0
	var previous: Vector2=battle.position_xz-battle.combat.boss_position
	var minimum: float=INF
	var maximum: float=0
	for frame: int in range(1800):
		battle.simulate(DT,Vector2.RIGHT)
		var relative: Vector2=battle.position_xz-battle.combat.boss_position
		angle+=absf(previous.angle_to(relative))
		previous=relative
		quadrants[(1 if relative.x<0 else 0)+(2 if relative.y<0 else 0)]=true
		minimum=minf(minimum,relative.length())
		maximum=maxf(maximum,relative.length())
		if frame%180==179: await process_frame
	check(quadrants.size()==4 and angle>=TAU,"Navigation orbits the actual relocated boss through all four quadrants")
	check(minimum>=84.0 and maximum<90,"Tangential course follows moved boss instead of fixed world origin")
	battle.position_xz=Vector2.ZERO
	battle.velocity_xz=Vector2.ZERO
	_step(1)
	check(battle.position_xz.length()<.1,"Old fixed inner circle no longer teleports boat away from world origin")
	battle.position_xz=Vector2(120,-5)
	battle.velocity_xz=Vector2.ZERO
	_step(180,false,Vector2(0,1))
	check(battle.position_xz.distance_to(battle.combat.boss_position)>=18.99 and battle.position_xz.distance_to(battle.combat.boss_position)<20,"Close collision follows actual boss body")
	battle.position_xz=Vector2(0,419.8)
	battle.velocity_xz=Vector2.ZERO
	_step(180,false,Vector2(0,-1))
	check(battle.position_xz.length()<=420.001,"Outer world boundary remains enforced")
	evidence["navigation"]={"degrees":rad_to_deg(angle),"quadrants":quadrants.size(),"orbit_min":minimum,"orbit_max":maximum}

func _aim_weakpoint() -> void:
	var target: Vector3=battle.monster.get_weakpoint()
	var nearest: float=INF
	for point: Vector3 in battle.monster.get_weakpoints():
		if point.distance_to(battle.camera.position)<nearest:
			target=point
			nearest=point.distance_to(battle.camera.position)
	battle.aim=battle.camera.unproject_position(target)

func _test_physical_aim() -> void:
	for position_value: Vector2 in [Vector2(85,0),Vector2(0,-85),Vector2(-85,0),Vector2(0,85)]:
		battle.restart_battle()
		_freeze_ai()
		battle.position_xz=position_value
		battle.combat.tick(DT,position_value,Vector2.ZERO)
		battle._update_presentation(0)
		_aim_weakpoint()
		var before: float=battle.combat.boss_hp
		var accepted: bool=battle.fire_weapon()
		_step(8)
		check(accepted and battle.combat.boss_hp==before and not battle.combat.projectiles.is_empty(),"Shot is physical in-flight before reaching target from %s" % position_value)
		_step(70)
		check(battle.combat.boss_hp<before,"Actual projectile hits anatomy from quadrant %s" % position_value)
		check(not battle.camera.is_position_behind(battle.monster.position+Vector3.UP*20),"Bow camera keeps relocated boss ahead from %s" % position_value)
	battle.restart_battle()
	_freeze_ai()
	battle._update_presentation(0)
	battle.aim=Vector2.ZERO
	battle.weapon="cannon"
	battle.fire_weapon()
	_step(180)
	check(battle.combat.boss_hp==4200 and battle.combat.stamina<100,"Actual sky shot misses while spending heavy attack resources")

func _test_actual_hunter() -> void:
	battle.restart_battle()
	var start: Vector2=battle.combat.boss_position
	_step(60)
	check(battle.combat.boss_position.distance_to(start)>9.5 and battle.position_xz.distance_to(battle.combat.boss_position)<85,"Actual boss closes distance by pursuing boat")
	check(Vector2(battle.monster.position.x,battle.monster.position.z).distance_to(battle.combat.boss_position)<.01,"Rendered boss transform matches authoritative pursuit")
	var skills: Dictionary={}
	var actual_hits: Array[Dictionary]=[]
	var previous_hull: float=100
	for frame: int in range(28*60):
		battle.simulate(DT,Vector2.ZERO)
		for descriptor: Dictionary in battle.combat.attacks: skills[descriptor["kind"]]=true
		if battle.combat.hull<previous_hull:
			actual_hits.append({"time":battle.combat.elapsed,"hp":battle.combat.hull,"attack":battle.combat.attack,"distance":battle.position_xz.distance_to(battle.combat.boss_position)})
			previous_hull=battle.combat.hull
		if battle.combat.ended: break
	check(battle.combat.hull<100 and actual_hits.size()>0,"Unmoving actual boat suffers targeted delayed attack damage")
	check(skills.has("meteor") and skills.has("lunge"),"Actual scene executes targeted meteor and real lunge")
	evidence["stationary_hunter"]={"skills":skills.keys(),"hits":actual_hits,"ended":battle.combat.ended}

func _test_demo() -> void:
	battle.restart_battle()
	battle.demo_mode=true
	var kinds: Dictionary={}
	var snapshots: Array[Dictionary]=[]
	var max_hazards: int=0
	for frame: int in range(3600):
		battle._process(DT)
		for descriptor: Dictionary in battle.combat.attacks: kinds[descriptor["kind"]]=true
		max_hazards=maxi(max_hazards,battle.combat.attacks.size())
		if frame%600==599: snapshots.append({"second":(frame+1)/60.0,"hull":battle.combat.hull,"boss_hp":battle.combat.boss_hp,"boss_pos":[battle.combat.boss_position.x,battle.combat.boss_position.y],"shots":battle.demo_shots,"dodges":battle.demo_dodges,"stamina":battle.combat.stamina})
		if frame%120==119: await process_frame
	var demo: Dictionary={"seconds":battle.visual_time,"hp":battle.combat.boss_hp,"hull":battle.combat.hull,"won":battle.combat.won,"ended":battle.combat.ended,"shots":battle.demo_shots,"dodges":battle.demo_dodges,"skills":kinds.keys(),"max_hazards":max_hazards,"snapshots":snapshots}
	evidence["actual_demo"]=demo
	print("HUNTER_DEMO ",JSON.stringify(demo))
	check(battle.demo_shots>0 and battle.combat.boss_hp<4200,"Actual demonstration attacks and damages a moving boss")
	check(kinds.has("meteor") and kinds.has("lightning") and kinds.has("lunge"),"Demo includes meteor, lightning and real pursuit lunge")
	check(battle.combat.hull>0 and (not battle.combat.ended or (battle.combat.won and battle.combat.boss_hp==0)),"Actual demo remains alive or wins legitimately during sixty seconds without cheats or revival")
	check(battle.hud.get("_radar").get("boss_pos")==battle.combat.boss_position,"Radar receives the actual moving boss position")
	battle.demo_mode=false

func _test_terminal() -> void:
	battle.restart_battle()
	_freeze_ai()
	results.clear()
	battle._update_presentation(0)
	_aim_weakpoint()
	battle.combat.boss_hp=1 # Terminal transition unit, not victory-balance evidence.
	battle.fire_weapon()
	_step(120)
	check(battle.combat.ended and battle.combat.won and str(battle.hud.get("_overlay_mode"))=="victory","Real delayed projectile reaches victory overlay")
	_step(30)
	check(results.size()==1 and bool(results[0]["won"]),"Victory emits exactly one completion signal")
	battle.restart_battle()
	results.clear()
	battle.combat.hull=1 # Terminal transition unit, normal starting-state playtest separate.
	_step(600)
	check(battle.combat.ended and not battle.combat.won and str(battle.hud.get("_overlay_mode"))=="defeat","Actual targeted attack reaches defeat overlay")
	_step(30)
	check(results.size()==1 and not bool(results[0]["won"]),"Defeat emits exactly one completion signal")

func _test_hud_return() -> void:
	check(battle.return_scene=="res://scenes/ui/title_screen.tscn" and not root.has_meta("sea_boss_demo_return_scene"),"Trial return metadata is consumed without leaking")
	check(battle.hud.return_requested.is_connected(battle.return_to_origin),"Return remains connected to isolated title flow")
	battle._update_presentation(0)
	var reticle: Control=battle.hud.get("_reticle") as Control
	check(reticle!=null and reticle.global_position.distance_to(battle.aim)<1.0,"Scaled HUD crosshair matches actual pixel aim")

func _test_settings() -> void:
	battle.restart_battle()
	battle.settings.override_path="user://test_sea_boss_scene_preferences.cfg"
	var original: Dictionary=battle.preferences.duplicate()
	battle.open_settings()
	check(battle.paused and battle.settings.is_open and str(battle.hud.get("_overlay_mode"))=="paused","Settings opens above a paused encounter")
	var before: float=battle.combat.elapsed
	battle.settings.get("_quality").select(0)
	battle.settings.get("_volume").value=0.0
	battle.settings.get("_shake").button_pressed=false
	battle.settings._control_changed()
	check(not battle.arena.environment.ssao_enabled and not battle.arena.environment.volumetric_fog_enabled and battle.get_viewport().msaa_3d==Viewport.MSAA_DISABLED,"Low profile disables costly effects while combat geometry stays intact")
	check(AudioServer.is_bus_mute(0) and not bool(battle.preferences["shake"]),"Zero volume mutes audio and shake toggle updates real preferences")
	var escape: InputEventKey=InputEventKey.new()
	escape.physical_keycode=KEY_ESCAPE
	escape.keycode=KEY_ESCAPE
	escape.pressed=true
	Input.parse_input_event(escape)
	Input.flush_buffered_events()
	await process_frame
	check(not battle.settings.is_open and battle.paused and battle.combat.elapsed==before,"Esc closes settings without unpausing the encounter in the same event")
	check(battle.settings.save_state=="saved","Settings close saves the dedicated trial preferences")
	battle.settings.open(original)
	battle._apply_preferences(original)
	battle.settings.close()
	battle.toggle_pause()
	battle.briefing=true
	battle.hud.set_overlay("briefing")
	battle.open_settings()
	_key(KEY_ENTER)
	battle.start_battle()
	check(battle.briefing and battle.settings.is_open,"Settings modal blocks Enter and direct start behind briefing")
	battle.settings.close()
	check(str(battle.hud.get("_overlay_mode"))=="briefing","Closing briefing settings restores the correct overlay")
	battle.briefing=false
	battle.combat.ended=true
	battle.combat.won=false
	battle.open_settings()
	_key(KEY_R)
	battle.restart_battle()
	check(battle.combat.ended and battle.settings.is_open,"Settings modal blocks R and direct restart behind result screen")
	battle.settings.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_sea_boss_scene_preferences.cfg"))
	battle.restart_battle()

func _test_cancelled_threat() -> void:
	battle.restart_battle()
	battle._update_presentation(0)
	battle.combat._descriptor("meteor",Vector2.ZERO,Vector2(0,95),Vector2.DOWN,1.9,.24,9.0,0.0,TAU,28.0)
	check(battle._threat_markers().size()==1,"Offscreen nearby locked hazard produces an edge warning")
	battle.combat.attacks[0]["cancelled"]=true
	check(battle._threat_markers().is_empty(),"Cancelled hazard immediately removes edge warning")

func _test_camera_visibility() -> void:
	battle.restart_battle()
	battle._update_presentation(0)
	var rig: Node=battle.ship.get_node("CameraOccludingRig")
	var excluded: bool=rig.get_child_count()>0
	for child: Node in rig.get_children():
		if child is VisualInstance3D:
			excluded=excluded and ((child as VisualInstance3D).layers & battle.camera.cull_mask)==0
	check(excluded,"Tall rig remains modeled but is excluded from combat camera")
	var muzzle: Vector3=battle.ship.get_muzzle_world()
	var screen: Vector2=battle.camera.unproject_position(muzzle)
	var viewport_size: Vector2=battle.get_viewport().get_visible_rect().size
	check(not battle.camera.is_position_behind(muzzle) and screen.y<viewport_size.y*.84,"Current physical muzzle is visible above the weapon HUD card")
	var front_ring: Vector3=Vector3(battle.position_xz.x,0,battle.position_xz.y)-Vector3(battle._radial().x,0,battle._radial().y)*9.0
	var ring_screen: Vector2=battle.camera.unproject_position(front_ring)
	check(Rect2(Vector2.ZERO,viewport_size).has_point(ring_screen),"The forward boundary of a player-centered meteor warning is on screen")
