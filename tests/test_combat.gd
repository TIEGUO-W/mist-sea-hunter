extends SceneTree
## v3 hunter rules. Geometry fixtures isolate individual collisions; the final
## complete-victory run uses untouched initial HP, AI, stamina and navigation.
const Combat=preload("res://scripts/combat.gd")
const DT: float=1.0/60.0
var checks: int=0
var failures: Array[String]=[]

func _initialize() -> void:
	_test_commitment_and_flight()
	_test_moving_shooter_and_target()
	_test_chase_and_locks()
	_test_attack_geometry()
	_test_guard_parry_break()
	_test_dodge_and_repair()
	_test_phase_and_endings()
	_test_ranges_and_predictive_lunge()
	_test_timing_and_greed()
	_test_complete_battle()
	if failures.is_empty():
		print("PASS: %d v3 hunter combat checks: physical shots, moving boss, locked attacks, guard/parry, commitments and legal full victory." % checks)
		quit(0)
	else:
		for message: String in failures: printerr("FAIL: "+message)
		printerr("%d/%d hunter checks failed" % [failures.size(),checks])
		quit(1)

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message)

func advance(combat: RefCounted,duration: float,pos: Vector2=Vector2(0,100),heading: float=PI) -> Array[Dictionary]:
	var events: Array[Dictionary]=[]
	var left: float=duration
	while left>0.000001:
		var delta: float=minf(DT,left)
		events.append_array(combat.tick(delta,pos,Vector2.ZERO,heading))
		left-=delta
	return events

func count(events: Array[Dictionary],type: String) -> int:
	var value: int=0
	for event: Dictionary in events:
		if str(event.get("type",""))==type: value+=1
	return value

func stationary() -> RefCounted:
	var combat: RefCounted=Combat.new()
	combat.boss_state="recovery"
	combat._boss_timer=999.0
	return combat

func descriptor(kind: String,origin: Vector2,target: Vector2,delay: float=0.15) -> Dictionary:
	return {"id":9000,"kind":kind,"origin":origin,"target":target,"direction":(target-origin).normalized(),"age":0.0,"delay":delay,"active":0.3,"life":delay+1.0,"radius":9.0,"range":40.0,"angle":deg_to_rad(115),"damage":28.0,"struck":false,"started":false,"cancelled":false}

func _test_commitment_and_flight() -> void:
	var combat: RefCounted=stationary()
	advance(combat,DT)
	check(combat.request_shot("cannon",Vector3(0,8.5,100),Vector3(0,8.5,0)),"Free cannon reserves a physical shot")
	check(not combat.request_dodge() and not combat.request_guard(true) and not combat.can_switch_weapon() and not combat.request_shot("ballista",Vector3.ZERO,Vector3.UP),"Windup cannot cancel into dodge, guard, gun switch or another gun")
	var early: Array[Dictionary]=advance(combat,0.5)
	check(count(early,"player_shot")==0 and float(combat.boss_hp)==4200,"No instant reservation damage or premature projectile")
	var launch: Array[Dictionary]=advance(combat,0.25)
	check(count(launch,"player_shot")==1 and count(launch,"boss_hit")==0 and float(combat.boss_hp)==4200,"Launch emits a projectile without pre-travel damage")
	check(combat.action_state=="recovery" and not combat.request_guard(true) and not combat.can_switch_weapon(),"Recovery also preserves attack commitment")
	var landed: Array[Dictionary]=advance(combat,1.2)
	check(count(landed,"boss_hit")==1 and float(combat.boss_hp)<4200,"Real flight collision, not launch, deducts boss HP")
	check(combat.can_switch_weapon(),"Weapon switch becomes legal after recovery")
	var miss: RefCounted=stationary()
	advance(miss,DT)
	miss.request_shot("ballista",Vector3(0,8.5,100),Vector3(300,8.5,100))
	var missed: Array[Dictionary]=advance(miss,5.5)
	check(count(missed,"boss_hit")==0 and count(missed,"projectile_miss")==1 and float(miss.boss_hp)==4200,"Aimed miss flies past and expires without hidden damage")
	var weak: RefCounted=stationary()
	advance(weak,DT)
	weak.request_shot("ballista",Vector3(0,13.5,100),Vector3(0,13.5,8),true)
	var exposed: Array[Dictionary]=advance(weak,1.1)
	var critical: bool=false
	for event: Dictionary in exposed:
		if str(event.get("type",""))=="boss_hit": critical=bool(event["weak"]) and float(event["damage"])==90.0
	check(critical,"Exposed weakpoint requires and rewards an actual 3D weak-sphere collision")

func _test_moving_shooter_and_target() -> void:
	var moving: RefCounted=stationary()
	advance(moving,DT)
	moving.request_shot("ballista",Vector3(2,5,92),Vector3.ZERO)
	var events: Array[Dictionary]=moving.tick(0.1,Vector2(12,100),Vector2(120,0),PI)
	var translated: bool=false
	for event: Dictionary in events:
		if str(event.get("type",""))=="player_shot": translated=absf(float((event["position"] as Vector3).x)-14)<0.01
	check(translated,"Muzzle follows ship translation during weapon windup")
	var evasive: RefCounted=Combat.new()
	evasive.tick(DT,Vector2(0,100),Vector2.ZERO)
	evasive.boss_position=Vector2.ZERO
	evasive.boss_state="active"
	evasive.attack="lunge"
	evasive._boss_timer=2.0
	evasive.attacks.append(descriptor("lunge",Vector2.ZERO,Vector2(100,0),0))
	evasive.attacks[0]["active"]=2.0
	evasive.attacks[0]["life"]=3.0
	evasive.request_shot("ballista",Vector3(0,8.5,100),Vector3(0,8.5,0))
	advance(evasive,1.5)
	check(float(evasive.boss_hp)==4200 and evasive.boss_position.x>50,"A real perpendicular boss lunge evades a stale aimed physical shot")
	var tether: RefCounted=Combat.new()
	tether.tick(DT,Vector2(0,100),Vector2.ZERO)
	tether.request_shot("harpoon",Vector3(0,8.5,100),Vector3(0,8.5,0))
	advance(tether,1.3)
	check(float(tether.tether_remaining)>0 and is_zero_approx(float(tether.stagger)),"Harpoon collision applies timed pursuit slow instead of instant permanent stagger")

func _test_chase_and_locks() -> void:
	var combat: RefCounted=Combat.new()
	advance(combat,1.0,Vector2(100,0))
	check(combat.boss_position.x>8 and (combat.boss_velocity as Vector2).length()>0,"Boss genuinely pursues the ship in world space")
	var found: bool=false
	for frame: int in range(180):
		combat.tick(DT,Vector2(100,0),Vector2.ZERO)
		if not combat.attacks.is_empty(): found=true; break
	check(found,"Distance AI produces a locked attack descriptor")
	if found:
		# Meteor has an explicit preview stage; only the final lock is fixed.
		advance(combat,0.90,Vector2(100,0))
		var target: Vector2=combat.attacks[0]["target"] as Vector2
		var origin: Vector2=combat.attacks[0]["origin"] as Vector2
		advance(combat,0.4,Vector2(100,60))
		check((combat.attacks[0]["target"] as Vector2).is_equal_approx(target) and (combat.attacks[0]["origin"] as Vector2).is_equal_approx(origin),"Visible attack lock does not secretly follow later ship movement")
		var complete: bool=true
		for key: String in ["id","kind","origin","target","direction","age","delay","active","life","radius","range","angle"]: complete=complete and combat.attacks[0].has(key)
		check(complete,"Attack descriptors contain the complete authoritative VFX contract")
	var lunge: RefCounted=Combat.new()
	var lunge_origin: Vector2=Vector2.ZERO
	var saw_lunge: bool=false
	for frame: int in range(1500):
		lunge.tick(DT,Vector2(0,200),Vector2.ZERO)
		for item: Dictionary in lunge.attacks:
			if item["kind"]=="lunge":
				saw_lunge=true
				lunge_origin=item["origin"] as Vector2
		if saw_lunge and lunge.boss_state=="active": break
	var position_before: Vector2=lunge.boss_position
	advance(lunge,0.5,Vector2(0,200))
	var fixed: bool=true
	for item: Dictionary in lunge.attacks:
		if item["kind"]=="lunge": fixed=fixed and (item["origin"] as Vector2).is_equal_approx(lunge_origin)
	check(saw_lunge and (lunge.boss_position as Vector2).distance_to(position_before)>20 and fixed,"Lunge moves the boss while its telegraphed launch origin stays fixed")

func _test_attack_geometry() -> void:
	for kind: String in ["meteor","lightning"]:
		var hit: RefCounted=stationary()
		hit.attacks.append(descriptor(kind,Vector2.ZERO,Vector2(60,50),0.4))
		advance(hit,0.3,Vector2(60,50))
		check(float(hit.hull)==100,"%s cannot hit before its visible delay" % kind)
		advance(hit,0.2,Vector2(60,50))
		check(float(hit.hull)<100,"%s damages the exact locked target circle" % kind)
		var avoid: RefCounted=stationary()
		avoid.attacks.append(descriptor(kind,Vector2.ZERO,Vector2(60,50)))
		advance(avoid,0.5,Vector2(75,50))
		check(float(avoid.hull)==100,"%s leaves positions beyond its radius+ship radius safe" % kind)
	var corridor: RefCounted=stationary()
	corridor.attacks.append(descriptor("lunge",Vector2.ZERO,Vector2(0,150)))
	advance(corridor,0.4,Vector2(0,100))
	check(float(corridor.hull)==100,"Lunge corridor cannot hurt a ship before the real boss reaches it")
	var contact: RefCounted=stationary()
	contact.boss_position=Vector2(0,81)
	contact.attacks.append(descriptor("lunge",Vector2.ZERO,Vector2(0,150)))
	advance(contact,0.4,Vector2(0,100))
	check(float(contact.hull)<100,"Lunge damages a ship held at the actual root19m entity-contact distance")
	var front: RefCounted=stationary()
	front.attacks.append(descriptor("cleave",Vector2.ZERO,Vector2(0,30)))
	advance(front,0.4,Vector2(0,20))
	var behind: RefCounted=stationary()
	behind.attacks.append(descriptor("cleave",Vector2.ZERO,Vector2(0,30)))
	advance(behind,0.4,Vector2(0,-20))
	check(float(front.hull)<100 and float(behind.hull)==100,"Cleave uses a finite facing sector with a safe rear")

func _test_guard_parry_break() -> void:
	var parry: RefCounted=stationary()
	parry.request_guard(true)
	parry.attacks.append(descriptor("cleave",Vector2.ZERO,Vector2(0,30),0.1))
	var parried: Array[Dictionary]=advance(parry,0.2,Vector2(0,20),PI)
	check(count(parried,"parry")==1 and float(parry.hull)==100 and float(parry.stagger)>0,"Fresh frontal guard parries melee into a boss stagger")
	check(parry.can_switch_weapon() and not parry.request_shot("ballista",Vector3.ZERO,Vector3.ONE),"Guard allows weapon selection but cannot attack while held")
	var block: RefCounted=stationary()
	block.request_guard(true)
	advance(block,0.3,Vector2(0,20))
	block.attacks.append(descriptor("cleave",Vector2.ZERO,Vector2(0,30)))
	var blocked: Array[Dictionary]=advance(block,0.3,Vector2(0,20),PI)
	check(count(blocked,"blocked")==1 and count(blocked,"parry")==0 and float(block.hull)>90,"Late guard blocks at health/stamina cost rather than parrying")
	var back: RefCounted=stationary()
	back.request_guard(true)
	back.attacks.append(descriptor("cleave",Vector2.ZERO,Vector2(0,30),0.1))
	var back_hit: Array[Dictionary]=advance(back,0.2,Vector2(0,20),0)
	check(count(back_hit,"blocked")==0 and count(back_hit,"parry")==0 and float(back.hull)<90,"Guard cannot protect attacks coming from behind")
	var magic: RefCounted=stationary()
	magic.request_guard(true)
	magic.attacks.append(descriptor("meteor",Vector2.ZERO,Vector2(0,20),0.1))
	var magic_hit: Array[Dictionary]=advance(magic,0.2,Vector2(0,20),PI)
	check(count(magic_hit,"parry")==0 and float(magic.hull)<100,"Meteor cannot be melee-parried and still deals guarded chip damage")
	var broken: RefCounted=stationary()
	broken.stamina=10
	broken.request_guard(true)
	broken.attacks.append(descriptor("cleave",Vector2.ZERO,Vector2(0,30),0.3))
	var break_events: Array[Dictionary]=advance(broken,0.4,Vector2(0,20),PI)
	check(count(break_events,"guard_break")==1 and broken.action_state=="guard_break" and not broken.request_dodge(),"Insufficient stamina causes committed guard break")
	var dodge_guard: RefCounted=stationary()
	dodge_guard.request_guard(true)
	check(dodge_guard.request_dodge() and dodge_guard.action_state=="dodge" and not dodge_guard.guarding,"Held guard can transition into paid dodge without cancelling an attack")
	var held: RefCounted=stationary()
	held.request_guard(true)
	advance(held,0.5)
	check(float(held.stamina)<100 and held.request_guard(false) and held.action_state=="free","Held guard drains stamina and release returns to free")

func _test_dodge_and_repair() -> void:
	var dodge: RefCounted=stationary()
	check(dodge.request_dodge() and not dodge.invulnerable,"Dodge starts vulnerable")
	advance(dodge,0.12)
	check(dodge.invulnerable,"Dodge middle has finite invulnerability")
	dodge.attacks.append(descriptor("meteor",Vector2.ZERO,Vector2(0,100),0))
	advance(dodge,0.03)
	check(float(dodge.hull)==100,"Correct dodge timing avoids a real attack volume")
	advance(dodge,0.27)
	check(not dodge.invulnerable,"Dodge recovery becomes vulnerable again")
	var repair: RefCounted=stationary()
	check(not repair.request_repair() and int(repair.repair_charges)==2,"Full hull cannot waste repair charges")
	repair.hull=90
	check(repair.request_repair() and not repair.request_guard(true) and not repair.request_dodge(),"Repair reserves a finite charge and commits its action")
	advance(repair,1.0)
	check(float(repair.hull)==90,"Repair does not heal before commitment finishes")
	advance(repair,1.3)
	check(float(repair.hull)==100,"Completed repair heals and respects maximum hull")
	advance(repair,8.0)
	repair.hull=60
	repair.request_repair()
	repair.attacks.append(descriptor("meteor",Vector2.ZERO,Vector2(0,100),0.1))
	advance(repair,0.2)
	var after: float=repair.hull
	advance(repair,2.5)
	check(float(repair.hull)==after and int(repair.repair_charges)==0,"Incoming attack interrupts final repair without delayed phantom healing")
	check(not repair.command("volley") and not repair.command("brace") and not repair.spend_stamina(-1),"Retired crew commands and negative stamina spending are rejected")

func _test_phase_and_endings() -> void:
	var combat: RefCounted=stationary()
	advance(combat,DT)
	combat.boss_hp=2101
	combat.request_shot("ballista",Vector3(0,8.5,100),Vector3(0,8.5,0))
	check(count(advance(combat,1.4),"phase")==1 and int(combat.phase)==2,"Actual physical hit crosses half health and emits one phase event")
	advance(combat,0.4)
	combat.boss_hp=1
	combat.request_shot("ballista",Vector3(0,8.5,100),Vector3(0,8.5,0))
	var ending: Array[Dictionary]=advance(combat,1.4)
	check(count(ending,"end")==1 and combat.ended and combat.won and float(combat.boss_hp)==0,"Physical lethal hit emits one victory and clamps HP")
	check(combat.tick(1,Vector2.ZERO,Vector2.ZERO).is_empty() and not combat.request_guard(true),"Ended battle cannot repeat events or accept guard")
	var loss: RefCounted=stationary()
	loss.hull=1
	loss.attacks.append(descriptor("meteor",Vector2.ZERO,Vector2(0,100),0.1))
	var defeat: Array[Dictionary]=advance(loss,0.3)
	check(count(defeat,"end")==1 and loss.ended and not loss.won and float(loss.hull)==0,"Authoritative attack volume produces one defeat")

func _test_complete_battle() -> void:
	var combat: RefCounted=Combat.new()
	var ship: Vector2=Vector2(0,110)
	var angle: float=PI*0.5
	var shots: int=0
	var impacts: int=0
	for frame: int in range(240*60):
		var old_ship: Vector2=ship
		var radial: Vector2=(ship-combat.boss_position).normalized()
		var direction: Vector2=Vector2(radial.y,-radial.x)
		var danger: bool=false
		for hazard: Dictionary in combat.attacks:
			if bool(hazard["cancelled"]): continue
			var eta: float=float(hazard["delay"])-float(hazard["age"])
			if str(hazard["kind"]) in ["meteor","lightning"] and bool(hazard.get("locked",true)) and eta> -float(hazard["active"]) and eta<1.1:
				var offset: Vector2=ship-(hazard["target"] as Vector2)
				if offset.length()<float(hazard["radius"])+18:
					direction=offset.normalized() if offset.length()>0.1 else direction
					danger=true
					if eta<0.25 and offset.length()<float(hazard["radius"])+3 and combat.action_state=="free": combat.request_dodge()
					break
			elif str(hazard["kind"])=="cleave" and eta> -float(hazard["active"]) and eta<1.3 and ship.distance_to(hazard["origin"] as Vector2)<float(hazard["range"])+10:
				direction=(ship-(hazard["origin"] as Vector2)).normalized()
				danger=true
				if eta<0.22 and ship.distance_to(hazard["origin"] as Vector2)<float(hazard["range"])+3 and combat.action_state=="free": combat.request_dodge()
			elif str(hazard["kind"])=="lunge" and combat.boss_state=="active" and ship.distance_to(combat.boss_position)<36:
				danger=true
				if combat.action_state=="free": combat.request_dodge()
		ship+=direction*20.0*DT*float(combat.move_multiplier)
		ship=ship.limit_length(400)
		if combat.action_state=="free" and float(combat.stamina)>66 and not danger:
			var distance: float=ship.distance_to(combat.boss_position)
			var lead: Vector2=combat.boss_position+combat.boss_velocity*(distance/125.0+0.1)
			if combat.request_shot("ballista",Vector3(ship.x,8.5,ship.y),Vector3(lead.x,8.5,lead.y)):
				shots+=1
		var events: Array[Dictionary]=combat.tick(DT,ship,(ship-old_ship)/DT)
		impacts+=count(events,"boss_hit")
		if combat.ended: break
	print("LEGAL_FULL_BATTLE elapsed=%.3f won=%s hull=%.1f bossHP=%.1f requests=%d physical_hits=%d" % [combat.elapsed,combat.won,combat.hull,combat.boss_hp,shots,impacts])
	check(combat.ended and combat.won and float(combat.hull)>0,"Unmodified 4200-HP boss can be legally defeated by mobile physical counterfire")
	check(impacts>=int(ceil(4200.0/50.0)),"Complete victory relies on numerous actual projectile collisions, not a seeded lethal HP fixture")


func _test_timing_and_greed() -> void:
	var fine: RefCounted=Combat.new()
	var coarse: RefCounted=Combat.new()
	var spike: RefCounted=Combat.new()
	for frame: int in range(720): fine.tick(1.0/60.0,Vector2(0,180),Vector2.ZERO)
	for frame: int in range(360): coarse.tick(1.0/30.0,Vector2(0,180),Vector2.ZERO)
	for frame: int in range(60): spike.tick(0.2,Vector2(0,180),Vector2.ZERO)
	check((fine.boss_position as Vector2).distance_to(coarse.boss_position)<0.1 and (fine.boss_position as Vector2).distance_to(spike.boss_position)<0.1,"30Hz and200ms spikes preserve actual boss pursuit via internal substeps")
	check(is_equal_approx(float(fine.hull),float(coarse.hull)) and is_equal_approx(float(fine.hull),float(spike.hull)),"Damage agrees across60Hz,30Hz and frame spikes")
	var empty: RefCounted=stationary()
	empty.spend_stamina(95)
	check(not empty.request_dodge() and not empty.request_shot("ballista",Vector3.ZERO,Vector3.UP),"Exhausted shared stamina rejects dodge and gunfire")
	advance(empty,0.4)
	check(is_equal_approx(float(empty.stamina),5.0),"Stamina regeneration respects its spending delay")
	advance(empty,1.0)
	check(float(empty.stamina)>5 and float(empty.stamina)<=100,"Free recovery regenerates stamina within its cap")
	var greedy: RefCounted=Combat.new()
	var ship: Vector2=Vector2(0,100)
	for frame: int in range(90*60):
		if greedy.action_state=="free":
			greedy.request_shot("cannon",Vector3(0,8.5,100),Vector3(greedy.boss_position.x,8.5,greedy.boss_position.y))
		greedy.tick(DT,ship,Vector2.ZERO)
		if greedy.ended: break
	print("GREED_PENALTY elapsed=%.3f won=%s hull=%.1f bossHP=%.1f" % [greedy.elapsed,greedy.won,greedy.hull,greedy.boss_hp])
	check(greedy.ended and not greedy.won,"Stationary heavy-cannon greed loses to real hunter attacks without seeded player HP")

func lunge_trial(response: String) -> Dictionary:
	var combat: RefCounted=Combat.new()
	combat._pattern_index=1 # Isolate the real AI's next lunge; do not inject damage.
	combat._boss_timer=0.01
	var ship: Vector2=Vector2(0,85)
	var saved_target: Vector2=Vector2.ZERO
	var saved_origin: Vector2=Vector2.ZERO
	var locked: bool=true
	var found: bool=false
	var hits: int=0
	var dodged: bool=false
	for frame: int in range(300):
		var direction: float=-1.0 if response=="turn" and frame>=27 else 1.0
		var velocity: Vector2=Vector2(direction*20.0,0)
		ship+=velocity*DT
		if response=="dodge" and combat.boss_state=="active" and (combat.boss_position as Vector2).distance_to(ship)<33 and not dodged:
			dodged=combat.request_dodge()
		var events: Array[Dictionary]=combat.tick(DT,ship,velocity)
		for item: Dictionary in combat.attacks:
			if item["kind"]=="lunge":
				if not found:
					saved_target=item["target"] as Vector2
					saved_origin=item["origin"] as Vector2
					found=true
				locked=locked and (item["target"] as Vector2).is_equal_approx(saved_target) and (item["origin"] as Vector2).is_equal_approx(saved_origin)
		for event: Dictionary in events:
			if event.get("type","")=="impact" and event.get("kind","")=="lunge" and bool(event.get("hit",false)): hits+=1
	return {"hits":hits,"locked":locked,"found":found,"dodged":dodged,"hull":combat.hull}

func _test_ranges_and_predictive_lunge() -> void:
	var ranges: Dictionary={"ballista":180.0,"cannon":310.0,"harpoon":135.0}
	for weapon: String in ranges:
		var limit: float=float(ranges[weapon])
		var far: RefCounted=stationary()
		advance(far,DT)
		far.request_shot(weapon,Vector3(0,8.5,limit+25),Vector3(0,8.5,0))
		var events: Array[Dictionary]=[]
		var bounded: bool=true
		for frame: int in range(360):
			events.append_array(far.tick(DT,Vector2(0,100),Vector2.ZERO))
			for shot: Dictionary in far.projectiles:
				bounded=bounded and float(shot["travelled"])<=limit+0.0001
		check(bounded and count(events,"boss_hit")==0 and float(far.boss_hp)==4200 and count(events,"projectile_miss")==1,"%s actual flight expires at its physical%.0fm range rather than its longer lifetime" % [weapon,limit])
		var near: RefCounted=stationary()
		advance(near,DT)
		near.request_shot(weapon,Vector3(0,8.5,limit-20),Vector3(0,8.5,0))
		check(count(advance(near,5.0),"boss_hit")==1,"%s still lands an actual shot within its range" % weapon)
	var blind: Dictionary=lunge_trial("blind")
	var turn: Dictionary=lunge_trial("turn")
	var dodge: Dictionary=lunge_trial("dodge")
	check(int(blind["hits"])>0,"Predictive lunge can punish unchanged full-speed sideways sailing")
	check(bool(turn["locked"]) and int(turn["hits"])==0,"Changing course after the tell evades the same fixed lock without hidden tracking")
	check(bool(dodge["dodged"]) and int(dodge["hits"])==0,"A timed paid dodge avoids the predictive lunge")
	var chain: RefCounted=Combat.new()
	chain._pattern_index=1
	chain._boss_timer=0.01
	var recovery_start: float=-1.0
	var cleave_time: float=-1.0
	var full_recovery: bool=false
	var previous_state: String=chain.boss_state
	var previous_attack: String=chain.attack
	for frame: int in range(600):
		var events: Array[Dictionary]=chain.tick(DT,Vector2(0,85),Vector2.ZERO)
		if previous_state=="active" and previous_attack=="lunge" and chain.boss_state=="recovery": recovery_start=chain.elapsed
		for event: Dictionary in events:
			if event.get("type","")=="telegraph" and event.get("kind","")=="cleave" and cleave_time<0: cleave_time=chain.elapsed
		if previous_state=="active" and previous_attack=="cleave" and chain.boss_state=="recovery":
			full_recovery=chain.weakpoint
			advance(chain,1.4,Vector2(0,85))
			full_recovery=full_recovery and chain.boss_state=="recovery" and chain.weakpoint
			break
		previous_state=chain.boss_state
		previous_attack=chain.attack
	check(recovery_start>0 and cleave_time-recovery_start>=0.59 and cleave_time-recovery_start<0.7,"A truly close lunge follows only after a visible0.6s recovery into a fresh cleave tell")
	check(full_recovery,"After the short melee combo the full weakpoint recovery window remains")
	print("PREDICTIVE_LUNGE blind=%d turn=%d dodge=%d locked=%s" % [blind["hits"],turn["hits"],dodge["hits"],turn["locked"]])
