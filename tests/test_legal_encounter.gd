extends SceneTree
## Full packed-scene playtest: original HP, normal AI, no state overrides or revival.
var failures: Array[String]=[]
var records: Array[Dictionary]=[]
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	for rate: int in [30,60]:
		var battle: Node3D=(load("res://scenes/sea_battle.tscn") as PackedScene).instantiate()
		root.add_child(battle)
		battle.set_process(false)
		battle.muted=true
		if battle.combat.boss_hp!=4200 or battle.combat.hull!=100: failures.append("Initial state was modified")
		battle.demo_mode=true
		battle.start_battle()
		var skills: Dictionary={}
		var frames: int=0
		while not battle.combat.ended and battle.visual_time<300:
			battle._process(1.0/float(rate))
			for hazard: Dictionary in battle.combat.attacks: skills[hazard["kind"]]=true
			frames+=1
			if frames%120==0: await process_frame
		var record: Dictionary={"purpose":"normal_midrange_full_victory","rate":rate,"won":battle.combat.won,"seconds":battle.visual_time,"hull":battle.combat.hull,"boss_hp":battle.combat.boss_hp,"shots":battle.demo_shots,"dodges":battle.demo_dodges,"skills":skills.keys()}
		records.append(record)
		print("LEGAL_PACKED_SCENE ",JSON.stringify(record))
		if not battle.combat.won or battle.combat.boss_hp!=0: failures.append("No legal full victory at %dHz" % rate)
		for kind: String in ["meteor","lightning","lunge"]:
			if not skills.has(kind): failures.append("Missing skill %s at %dHz" % [kind,rate])
		battle.queue_free()
		var drain_started: int=Time.get_ticks_msec()
		while Time.get_ticks_msec()-drain_started<160: await process_frame
	for rate: int in [30,60]:
		await _near_range_route(rate)
	var path: String="user://hunter-legal-encounter.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--evidence="): path=arg.trim_prefix("--evidence=")
	var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify({"records":records,"failures":failures},"  "))
	for message: String in failures: printerr(message)
	print("PASS: legal midrange victories and separately sailed close-range cleave/guard routes at 30/60Hz" if failures.is_empty() else "FAIL: legal full encounter")
	quit(0 if failures.is_empty() else 1)

func _near_range_route(rate: int) -> void:
	# Reach melee through normal W navigation; never assign positions, AI, or HP.
	var battle: Node3D=(load("res://scenes/sea_battle.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	battle.set_process(false)
	battle.muted=true
	battle.start_battle()
	if battle.combat.boss_hp!=4200 or battle.combat.hull!=100: failures.append("Near route initial state was modified")
	var arrived: bool=false
	var cleave_id: int=-1
	var visible_warning: bool=false
	var guarded_impact: bool=false
	var damage: float=0
	var arrival_distance: float=0
	var frames: int=0
	while not battle.combat.ended and battle.visual_time<20 and not guarded_impact:
		var distance: float=battle.position_xz.distance_to(battle.combat.boss_position)
		if not arrived and distance<=28:
			arrived=true
			arrival_distance=distance
		var previous_hull: float=battle.combat.hull
		battle.simulate(1.0/float(rate),Vector2.ZERO if arrived else Vector2(0,1))
		battle._update_presentation(1.0/float(rate))
		for hazard: Dictionary in battle.combat.attacks:
			if str(hazard["kind"])!="cleave" or bool(hazard.get("cancelled",false)): continue
			cleave_id=int(hazard["id"])
			visible_warning=visible_warning or battle.vfx._attacks.has(cleave_id)
			# The real held-right-button path enters guard before the active frame.
			battle.guard_held=true
			if bool(hazard["struck"]) and battle.combat.hull<previous_hull:
				damage=previous_hull-battle.combat.hull
				guarded_impact=battle.combat.guarding and is_equal_approx(damage,float(hazard["damage"])*.2)
		frames+=1
		if frames%120==0: await process_frame
	var record: Dictionary={"purpose":"sailed_close_range_cleave_guard","rate":rate,"seconds":battle.visual_time,"arrived":arrived,"arrival_distance":arrival_distance,"cleave_id":cleave_id,"warning_exists":visible_warning,"guarded_impact":guarded_impact,"cleave_damage":damage,"hull":battle.combat.hull,"boss_hp":battle.combat.boss_hp,"shots":battle.demo_shots}
	records.append(record)
	print("LEGAL_PACKED_SCENE ",JSON.stringify(record))
	if not arrived or cleave_id<0: failures.append("Natural sailing did not reach a normal cleave decision at %dHz"%rate)
	if not visible_warning: failures.append("Normal cleave descriptor did not create a production VFX warning at %dHz"%rate)
	if not guarded_impact: failures.append("Normal cleave did not resolve through real held guard with20%% damage at %dHz"%rate)
	if battle.combat.boss_hp!=4200 or battle.demo_shots!=0: failures.append("Close route attacked or modified Boss HP at %dHz"%rate)
	battle.queue_free()
	var drain_started: int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-drain_started<160: await process_frame
