extends SceneTree
## Isolated aim/UI contracts. This is not full-battle or difficulty evidence.
var battle: Node3D
var failures: Array[String]=[]
var checks: int=0
func _initialize() -> void: call_deferred("_run")
func _check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
func _run() -> void:
	battle=(load("res://scenes/sea_battle.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	battle.set_process(false)
	battle.muted=true
	battle.start_battle()
	_test_aim_states()
	_test_muzzle_obstruction()
	_test_muzzle_range()
	_test_real_progress()
	_test_distinct_flashes()
	battle.queue_free()
	var drain: int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-drain<160: await process_frame
	for message: String in failures: printerr("FAIL: "+message)
	print("PASS: %d aim and successful-action tutorial integration checks" % checks if failures.is_empty() else "FAIL: aim integration")
	quit(0 if failures.is_empty() else 1)
func _freeze_ai() -> void:
	battle.combat.boss_state="recovery"
	battle.combat._boss_timer=999
func _step(frames: int,input: Vector2=Vector2.ZERO) -> void:
	for frame: int in range(frames):
		battle.simulate(1.0/60.0,input)
		battle._update_presentation(1.0/60.0)
func _aim_point(point: Vector3) -> void:
	battle.aim=battle.camera.unproject_position(point)
	battle._update_hud()
func _test_aim_states() -> void:
	battle.restart_battle()
	_freeze_ai()
	battle.combat.weakpoint=true
	battle._update_presentation(0)
	battle.aim=Vector2.ZERO
	battle._update_hud()
	_check(not battle.hud.get("_reticle").hit and not battle.hud.get("_reticle").weak,"Sky never looks like a body or weakpoint hit despite global opening")
	_check(not str(battle.hud.get("_weak_label").text).is_empty(),"Global opening banner stays independent of aim")
	_aim_point(battle.monster.to_global(Vector3(0,4.5,0)))
	_check(battle.hud.get("_reticle").hit and not battle.hud.get("_reticle").weak,"Actual torso ray gives body hit feedback")
	_aim_point(battle.monster.get_weakpoint())
	_check(battle.hud.get("_reticle").hit and battle.hud.get("_reticle").weak,"Actual open front weakpoint ray gets gold feedback")
	battle.combat.weakpoint=false
	battle._update_hud()
	_check(not battle.hud.get("_reticle").weak,"Closed weakpoint cannot remain gold")
func _test_muzzle_obstruction() -> void:
	battle.restart_battle()
	battle.position_xz=Vector2(85,0)
	battle.ship_heading=PI*.5
	battle.combat.boss_state="chase"
	battle.combat._boss_timer=999.0
	battle.combat.weakpoint=true
	battle._update_hit_geometry()
	battle._update_presentation(0)
	_aim_point(battle.monster.get_weakpoints()[3])
	var origin: Vector3=battle.camera.project_ray_origin(battle.aim)
	var direction: Vector3=battle.camera.project_ray_normal(battle.aim)
	var camera_contact: Dictionary=battle.combat.trace_boss_segment(origin,origin+direction*900.0)
	_check(bool(camera_contact.get("weak",false)),"Counterexample has a camera-visible exposed back core")
	var result: Dictionary=battle._aim_result()
	_check(bool(result.hit) and not bool(result.weak) and str(result.surface)=="armor","Real muzzle detects the nearer physical tentacle despite camera seeing the core")
	_check(battle.hud.get("_reticle").hit and not battle.hud.get("_reticle").weak,"Reticle follows the muzzle obstruction instead of promising a critical hit")
func _test_muzzle_range() -> void:
	battle.restart_battle()
	_freeze_ai()
	battle.position_xz=Vector2(0,185)
	battle.combat.tick(1.0/60.0,battle.position_xz,Vector2.ZERO)
	battle._update_presentation(0)
	_aim_point(battle.monster.get_weakpoint())
	var result: Dictionary=battle._aim_result()
	_check(bool(result.hit) and float(result.distance)<180,"Range is measured from the real muzzle, not the camera nineteen metres behind it")
	battle.fire_weapon()
	_step(120)
	_check(battle.combat.boss_hp<4200,"Muzzle-in-range feedback corresponds to an actual physical hit")
	battle.restart_battle()
	_freeze_ai()
	battle.position_xz=Vector2(0,210)
	battle.combat.tick(1.0/60.0,battle.position_xz,Vector2.ZERO)
	battle._update_presentation(0)
	_aim_point(battle.monster.get_weakpoint())
	result=battle._aim_result()
	_check(not bool(result.hit) and not bool(result.in_range) and float(result.distance)>180,"Physical out-of-range target is reported accurately")
	battle.fire_weapon()
	_step(120)
	_check(battle.combat.boss_hp==4200,"Out-of-range physical shot expires without false damage")
func _test_real_progress() -> void:
	battle.restart_battle()
	_freeze_ai()
	battle.tutorial_progress={"moved":false,"fired":false,"switched":false,"dodged":false,"guarded":false}
	battle._tutorial_travel=0
	battle._update_presentation(0)
	_check(not bool(battle.tutorial_progress.moved),"Tutorial does not complete movement from intent alone")
	_step(60,Vector2.RIGHT)
	_check(bool(battle.tutorial_progress.moved),"Actual travel completes movement hint")
	_aim_point(battle.monster.get_weakpoint())
	battle.fire_weapon()
	_check(not bool(battle.tutorial_progress.fired),"Reserved windup alone does not complete firing hint")
	_step(30)
	_check(bool(battle.tutorial_progress.fired),"Released physical shot completes firing hint")
	_check(battle.cycle_weapon(1) and bool(battle.tutorial_progress.switched),"Only an accepted adjacent weapon switch completes switch hint")
	battle.request_dodge(Vector2.RIGHT)
	_step(12)
	_check(bool(battle.tutorial_progress.dodged),"Executed dodge completes dodge hint")
	_step(24)
	battle.guard_held=true
	_step(8)
	_check(bool(battle.tutorial_progress.guarded) and battle.combat.guarding,"Actually held, stamina-consuming guard completes guard hint")
	battle.guard_held=false
	battle.combat.request_guard(false)
func _test_distinct_flashes() -> void:
	battle.flash=0
	battle.damage_flash=0
	battle._handle_event({"type":"impact","kind":"cleave","hit":true,"damage":26.0,"position":battle.position_xz})
	_check(battle.damage_flash>0 and battle.flash==0,"Player damage cannot fake a boss-hit confirmation")
	battle.flash=0
	battle.damage_flash=0
	battle._handle_event({"type":"boss_hit","weapon":"ballista","weak":false,"damage":32.0,"position":battle.monster.get_weakpoint()})
	_check(battle.flash>0 and battle.damage_flash==0,"Boss-hit confirmation cannot fake red player damage")
