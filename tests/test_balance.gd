extends SceneTree
const Combat=preload("res://scripts/combat.gd")
const Controller=preload("res://scripts/sea_battle.gd")
const DT: float=1.0/60.0
var checks: int=0
var failures: Array[String]=[]
var matrix: Array[Dictionary]=[]
func check(value: bool,message: String) -> void:
	checks+=1
	if not value: failures.append(message)
func _initialize() -> void:
	_test_lock_contract()
	_test_interrupt_contract()
	_test_real_recovery_windows()
	for phase: int in [1,2]:
		for mode: String in ["stationary","straight","orbit"]:
			var result: Dictionary=trial(mode,phase)
			matrix.append(result)
			check(float(result["hull"])<100,"Phase%d blind %s remains threatened"%[phase,mode])
		for mode: String in ["turn90","turn180","start_move"]:
			for rate: int in [30,60]:
				var result: Dictionary=trial(mode,phase,.50,rate)
				matrix.append(result)
				check(float(result["hull"])==100,"Phase%d %s .50s reaction at%dHz uses production75m/s² inertia and avoids every meteor"%[phase,mode,rate])
		var dodged: Dictionary=trial("dodge",phase)
		matrix.append(dodged)
		check(float(dodged["hull"])==100 and int(dodged["dodges"])>0,"Phase%d actual production dodge motion and resource payment avoid meteor(s)"%phase)
		var guarded: Dictionary=trial("guard",phase)
		matrix.append(guarded)
		check(float(guarded["hull"])<100 and float(guarded["hull"])>65 and int(guarded["blocks"])==phase,"Phase%d frontal guard mitigates each meteor without invulnerability"%phase)
		var late: Dictionary=trial("turn180",phase,1.2)
		matrix.append(late)
		check(float(late["hull"])<100,"Phase%d last-moment ordinary turn is not an instant teleport out of impact"%phase)
	if checks!=40: failures.append("Incomplete test execution: expected40, got%d"%checks)
	var output: Dictionary={"engine":Engine.get_version_info()["string"],"timing":".85 preview +1.35 final /2.20 total; phase2 +1.35 offset","movement":"production Controller._move_ship,75m/s² and actual dodge curve; input decisions30/60Hz, physics60Hz","checks":checks,"failures":failures,"matrix":matrix}
	var file: FileAccess=FileAccess.open("D:/codex/2026-10-23/https-github-com-aeolianii-changche-yingxiongzhuan/work/balance-final-inertia-matrix.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"  "))
	file.close()
	for row: Dictionary in matrix: print("ACTUAL_SHIP_INERTIA ",JSON.stringify(row))
	if failures.is_empty():
		print("PASS: %d fairness checks: actual75m/s² ship .50s90/180/rest reactions, sequential pair, paid dodge/guard, final locks and stagger cancellation."%checks)
		quit(0)
	else:
		for failure: String in failures: printerr("FAIL: "+failure)
		quit(1)
func _test_lock_contract() -> void:
	var c: Combat=Combat.new()
	c.phase=2
	var events: Array[Dictionary]=[]
	c._begin_attack(Vector2(0,85),Vector2(20,0),events,"meteor")
	check(c.attacks.size()==2 and is_equal_approx(float(c.attacks[0]["delay"]),2.2) and is_equal_approx(float(c.attacks[1]["delay"]),3.55),"Base meteor2.20s and phase2 second3.55s")
	check(bool(c.attacks[0]["tracking"]) and not bool(c.attacks[0]["locked"]) and is_equal_approx(float(c.attacks[0]["lock_age"]),.85) and is_equal_approx(float(c.attacks[1]["lock_age"]),2.2),"Second meteor locks only when the first impacts")
	var locks: Dictionary={}
	var saved: Vector2=Vector2.ZERO
	var fixed: bool=true
	var first_preview: Vector2=c.attacks[0]["target"] as Vector2
	for frame: int in range(146):
		var time: float=float(frame+1)*DT
		var velocity: Vector2=Vector2(20,0) if time<=.85 else Vector2(-20,0)
		var position: Vector2=Vector2(20*time,85) if time<=.85 else Vector2(17-(time-.85)*20,85)
		events=c.tick(DT,position,velocity)
		for event: Dictionary in events:
			if event["type"]=="target_locked":
				locks[event["id"]]=int(locks.get(event["id"],0))+1
				if int(event["id"])==1: saved=event["target"] as Vector2
				check(is_equal_approx(float(event["remaining"]),1.35) and (event["target"] as Vector2).is_equal_approx(event["position"] as Vector2),"Lock event supplies exact1.35s remaining and authoritative target")
		if time>.85: fixed=fixed and (c.attacks[0]["target"] as Vector2).is_equal_approx(saved)
	check(not first_preview.is_equal_approx(saved) and fixed and saved.distance_to(Vector2(44,85))<.01,"Preview follows until exact lock; reversal never drags final circle")
	check(locks.size()==2 and int(locks[1])==1 and int(locks[2])==1,"Each sequential target locks exactly once")
	check(not bool(c.attacks[0]["tracking"]) and bool(c.attacks[0]["locked"]),"Locked target explicitly retires tracking")
	var fixture: Combat=Combat.new()
	fixture.boss_state="recovery"
	fixture._boss_timer=999
	fixture._descriptor("meteor",Vector2.ZERO,Vector2(10,80),Vector2.DOWN,1.9,.24,9,0,TAU,28)
	fixture.tick(.2,Vector2(100,100),Vector2(20,0))
	check((fixture.attacks[0]["target"] as Vector2).is_equal_approx(Vector2(10,80)),"Legacy crafted descriptors without tracking stay fixed")
func _test_interrupt_contract() -> void:
	var c: Combat=Combat.new()
	c.phase=2
	var events: Array[Dictionary]=[]
	c._begin_attack(Vector2(0,85),Vector2.ZERO,events,"meteor")
	c.tick(.9,Vector2(0,85),Vector2.ZERO)
	var locked: Vector2=c.attacks[0]["target"] as Vector2
	c._interrupt_boss(1.25)
	check(not bool(c.attacks[0]["cancelled"]) and bool(c.attacks[1]["cancelled"]) and not bool(c.attacks[1]["tracking"]),"Stagger preserves launched meteor but cancels unlocked second cast")
	c._boss_timer=999
	var impacts: int=0
	var second_locks: int=0
	for frame: int in range(180):
		events=c.tick(DT,Vector2(0,85),Vector2.ZERO)
		for event: Dictionary in events:
			if event["type"]=="impact" and bool(event.get("hit",false)): impacts+=1
			if event["type"]=="target_locked": second_locks+=1
	check(impacts==1 and second_locks==0 and c.hull<100,"Already locked physical impact survives interruption; canceled preview never locks or hits")
	# Trigger the cancellation by two legitimate physical cannon hits: first
	# builds real poise in recovery, second arrives before the next cast locks.
	var real: Combat=Combat.new()
	real.phase=2
	real.boss_state="recovery"
	real._boss_timer=999
	real.tick(DT,Vector2(0,20),Vector2.ZERO)
	real.request_shot("cannon",Vector3(0,13.5,20),Vector3(0,13.5,8))
	for frame: int in range(132): real.tick(DT,Vector2(0,20),Vector2.ZERO)
	real._begin_attack(Vector2(0,20),Vector2.ZERO,events,"meteor")
	var accepted: bool=real.request_shot("cannon",Vector3(0,13.5,20),Vector3(0,13.5,8))
	for frame: int in range(66): real.tick(DT,Vector2(0,20),Vector2.ZERO)
	var cancelled: bool=true
	for descriptor: Dictionary in real.attacks:
		if descriptor["kind"]=="meteor": cancelled=cancelled and bool(descriptor["cancelled"])
	check(accepted and real.stagger>0 and cancelled and real.boss_hp<4200,"Actual cannon poise break cancels preview casts before lock, without editing poise or HP")
	check(locked.is_equal_approx(Vector2(0,85)),"Locked projectile target remains unchanged by stagger")
func _test_real_recovery_windows() -> void:
	var lunge: Combat=Combat.new()
	var events: Array[Dictionary]=[]
	lunge._begin_attack(Vector2(0,85),Vector2.ZERO,events,"lunge")
	for frame: int in range(240):
		lunge.tick(DT,Vector2(0,85),Vector2.ZERO)
		if lunge.boss_state=="recovery": break
	check(lunge._followup_pending and lunge.boss_state=="recovery" and lunge._boss_timer<=.60 and not lunge.weakpoint,"Short .60s lunge-to-cleave transition is not a counterfire weakpoint window")
	check(not lunge.notice.contains("弱点暴露") and not lunge.notice.contains("伺机反击"),"Short transition never promises the complete counterattack opportunity")
	var recovery: Combat=Combat.new()
	recovery._begin_attack(Vector2(0,85),Vector2.ZERO,events,"meteor")
	for frame: int in range(240):
		recovery.tick(DT,Vector2(0,85),Vector2.ZERO)
		if recovery.boss_state=="recovery": break
	check(not recovery._followup_pending and recovery.weakpoint and recovery._boss_timer>2.3,"Actual2.4s post-attack recovery still opens the real weakpoint window")
	lunge._interrupt_boss(1.25)
	lunge.tick(DT,Vector2(0,85),Vector2.ZERO)
	check(lunge.stagger>0 and not lunge._followup_pending and lunge.weakpoint,"Real stagger cancels followup and creates its own weakpoint counterattack window")

func trial(mode: String,phase: int,reaction: float=.50,input_rate: int=60) -> Dictionary:
	var controller: Node3D=Controller.new() # No scene _ready, assets, audio or AI overrides.
	var c: Combat=controller.combat
	c.phase=phase
	controller.position_xz=Vector2(0,85)
	controller.velocity_xz=Vector2.RIGHT*20 if mode not in ["stationary","start_move","dodge","guard"] else Vector2.ZERO
	var events: Array[Dictionary]=[]
	c._begin_attack(controller.position_xz,controller.velocity_xz,events,"meteor")
	var lock_headings: Dictionary={}
	var reacted: Dictionary={}
	var desired: Vector2=Vector2.RIGHT if mode not in ["stationary","start_move","dodge","guard"] else Vector2.ZERO
	var held_input: Vector2=Vector2.ZERO
	var blocks: int=0
	var dodges: int=0
	var damage: float=0
	for frame: int in range(246):
		if frame%(60/input_rate)==0:
			if mode=="orbit": desired=Vector2(controller.position_xz.y,-controller.position_xz.x).normalized()
			if mode in ["turn90","turn180","start_move"]:
				for hazard: Dictionary in c.attacks:
					var id: int=int(hazard["id"])
					if not bool(hazard.get("locked",false)) or reacted.has(id) or float(hazard["age"])+.000001<float(hazard["lock_age"])+reaction: continue
					var heading: Vector2=lock_headings.get(id,Vector2.RIGHT) as Vector2
					if heading.length()<.1: desired=Vector2.RIGHT
					else: desired=heading.rotated(PI/2 if mode=="turn90" else PI)
					reacted[id]=true
			if mode=="dodge":
				for hazard: Dictionary in c.attacks:
					var eta: float=float(hazard["delay"])-float(hazard["age"])
					if eta<=.22 and eta>0 and c.action_state=="free" and c.request_dodge():
						controller.dodge_direction=Vector2.RIGHT
						dodges+=1
			if mode=="guard" and c.elapsed>=1.7: c.request_guard(true)
			var radial: Vector2=controller._radial()
			held_input=Vector2(desired.dot(Vector2(radial.y,-radial.x)),-desired.dot(radial))
		controller._move_ship(DT,held_input)
		events=c.tick(DT,controller.position_xz,controller.velocity_xz,controller.ship_heading+PI)
		for event: Dictionary in events:
			if event["type"]=="target_locked": lock_headings[event["id"]]=controller.velocity_xz.normalized()
			if event["type"]=="blocked": blocks+=1
			if event["type"]=="impact" and bool(event.get("hit",false)): damage+=float(event["damage"])
	var result: Dictionary={"phase":phase,"mode":mode,"reaction_s":reaction,"input_rate":input_rate,"hull":c.hull,"stamina":c.stamina,"blocks":blocks,"dodges":dodges,"damage":damage,"locks":lock_headings.size()}
	controller.free()
	return result

