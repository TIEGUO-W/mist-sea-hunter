extends Node
## Original offline-style DSP synthesis, cached once at setup. No sampled audio.
## See assets/audio/DSP_SOURCES.md for audit, design and preview provenance.
const RATE: int=22050
const VOICE_LIMIT: int=16
const TAP_SECONDS: Array[float]=[0.041,0.089,0.173]
const TAP_GAINS: Array[float]=[0.16,0.10,0.055]
var generation_ms: float=0.0
var baked_loaded_count: int=0
var fallback_generated_count: int=0
var peak_active_voices: int=0
var dropped_events: int=0
var estimated_peak_bound: float=0.0
var max_estimated_peak_bound: float=0.0
var stream_peaks: Dictionary={}
var stream_rms: Dictionary={}
var _streams: Dictionary={}
var _voices: Array[AudioStreamPlayer3D]=[]
var _voice_data: Array[Dictionary]=[]
var _ambience: Array[AudioStreamPlayer]=[]
var _music: Array[AudioStreamPlayer]=[]
var _music_targets: Array[float]=[-19.0,-22.0,-80.0]
var _rng: RandomNumberGenerator=RandomNumberGenerator.new()
var _ready_audio: bool=false
var _stopped: bool=false
var _paused: bool=false
var _muted: bool=false
var _serial: int=0
var _ship: Vector3=Vector3(0,0,85)
var _boss: Vector3=Vector3.ZERO
var _speed: float=0.0

func _ready() -> void:
	setup()

func setup() -> void:
	if _ready_audio or _stopped: return
	var started: int=Time.get_ticks_usec()
	_rng.seed=1593486421
	var durations: Dictionary={"ballista":0.43,"cannon":1.5,"harpoon":0.75,"body_hit":0.58,"weak_hit":0.8,"meteor_tell":1.55,"lightning_tell":1.4,"lunge_tell":1.0,"cleave_tell":0.8,"meteor":1.8,"lightning":1.65,"lunge":1.15,"cleave":0.85,"parry":0.85,"blocked":0.55,"guard_break":0.85,"dodge":0.62,"repair":1.1,"phase":2.15,"end":2.1,"sea_loop":8.0,"ship_loop":8.0}
	durations["target_lock"]=0.24
	durations["drone_loop"]=16.0
	durations["pulse_loop"]=7.5
	durations["tension_loop"]=16.0
	for key: String in durations:
		var path: String="res://assets/audio/original_dsp/"+key+".wav"
		var stream: AudioStreamWAV=null
		# Imported resources follow Godot's export remap. Raw source WAVs in a
		# minimal PCK use FileAccess-backed res:// loading, never an OS path.
		if ResourceLoader.exists(path) and (FileAccess.file_exists(path+".import") or not FileAccess.file_exists(path)):
			stream=ResourceLoader.load(path,"AudioStreamWAV") as AudioStreamWAV
		elif FileAccess.file_exists(path):
			stream=AudioStreamWAV.load_from_file(path)
		if stream!=null:
			baked_loaded_count+=1
			if key.ends_with("_loop"):
				stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
				stream.loop_begin=0
				stream.loop_end=int(stream.data.size()/4)
		else:
			stream=_render(key,float(durations[key]),key.ends_with("_loop"))
			fallback_generated_count+=1
		_streams[key]=stream
	for index: int in range(VOICE_LIMIT):
		var voice: AudioStreamPlayer3D=AudioStreamPlayer3D.new()
		voice.name="EncounterVoice%02d" % index
		voice.max_polyphony=1
		voice.max_distance=650.0
		voice.unit_size=65.0
		voice.max_db=0.0
		voice.attenuation_model=AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		voice.panning_strength=0.65
		add_child(voice)
		_voices.append(voice)
		_voice_data.append({"serial":-1,"priority":0,"gain":-12.0})
	for index: int in range(2):
		var ambient: AudioStreamPlayer=AudioStreamPlayer.new()
		ambient.name="SeaBed" if index==0 else "HullBed"
		ambient.max_polyphony=1
		ambient.stream=_streams["sea_loop" if index==0 else "ship_loop"] as AudioStreamWAV
		ambient.volume_db=-23.0 if index==0 else -26.0
		add_child(ambient)
		_ambience.append(ambient)
		ambient.play()
		ambient.stream_paused=_paused
	# 三条程序化配乐 stem：低音床 / 心跳 / 张力弦，按阶段交叉淡入
	for index: int in range(3):
		var music: AudioStreamPlayer=AudioStreamPlayer.new()
		music.name=["MusicDrone","MusicPulse","MusicTension"][index]
		music.max_polyphony=1
		music.stream=_streams[["drone_loop","pulse_loop","tension_loop"][index]] as AudioStreamWAV
		music.volume_db=-80.0
		add_child(music)
		_music.append(music)
		music.play()
		music.stream_paused=_paused
	_ready_audio=true
	_stopped=false
	generation_ms=float(Time.get_ticks_usec()-started)/1000.0
	_apply_gains()

func set_paused(value: bool) -> void:
	if _paused==value: return
	_paused=value
	for index: int in range(_voices.size()):
		var voice: AudioStreamPlayer3D=_voices[index]
		if not is_instance_valid(voice): continue
		if value:
			var position_value: float=voice.get_playback_position()
			var was_playing: bool=voice.playing
			voice.stream_paused=true
			# 3D play() can still be waiting for the physics/audio server on its
			# first frame; pausing that pending request is otherwise discarded.
			if was_playing and not voice.stream_paused:
				voice.stop()
				_voice_data[index]["resume_at"]=position_value
				_voice_data[index]["resume_pending"]=true
		else:
			if bool(_voice_data[index].get("resume_pending",false)):
				voice.play(float(_voice_data[index].get("resume_at",0.0)))
				_voice_data[index]["resume_pending"]=false
			voice.stream_paused=false
	for ambient: AudioStreamPlayer in _ambience:
		if is_instance_valid(ambient): ambient.stream_paused=value
	for music: AudioStreamPlayer in _music:
		if is_instance_valid(music): music.stream_paused=value
	_apply_gains()

func set_muted(value: bool) -> void:
	_muted=value
	_apply_gains()

func update_music(phase: int,intensity: float,delta: float) -> void:
	# 第一阶段只有低音床 + 心跳；第二阶段加入张力弦；濒死时把心跳推上来
	if _stopped:
		return
	var tight: float=clampf(intensity,0.0,1.0)
	_music_targets[0]=-19.0+2.0*tight
	_music_targets[1]=-22.0+7.0*tight
	_music_targets[2]=(-80.0 if phase<2 else -27.0+8.0*tight)
	for index: int in range(_music.size()):
		if not is_instance_valid(_music[index]):
			continue
		var target: float=-80.0 if (_muted or _paused) else _music_targets[index]
		_music[index].volume_db=lerpf(_music[index].volume_db,target,clampf(delta*1.6,0.0,1.0))


func update_listener(ship_pos: Vector3,boss_pos: Vector3,speed: float,delta: float) -> void:
	_ship=ship_pos
	_boss=boss_pos
	if _stopped or _paused: return
	_speed=lerpf(_speed,clampf(absf(speed)/20.0,0,1),clampf(delta*2.0,0,1))
	_apply_gains()

func _apply_gains() -> void:
	# Worst-case source-peak sum, not an RMS guess: event transients share a
	# bounded headroom budget without touching the project's global mix buses.
	var event_peak: float=0.0
	for index: int in range(_voices.size()):
		if is_instance_valid(_voices[index]) and _voices[index].playing:
			event_peak+=0.72*db_to_linear(float(_voice_data[index]["gain"]))
	var headroom: float=minf(1.0,0.78/maxf(event_peak,0.00001))
	var ambient_peak: float=0.0
	for index: int in range(_voices.size()):
		if is_instance_valid(_voices[index]):
			_voices[index].volume_linear=0.0 if _muted or _paused else db_to_linear(float(_voice_data[index]["gain"]))*headroom
	for index: int in range(_ambience.size()):
		if is_instance_valid(_ambience[index]):
			var db: float=(-24.0+_speed*2.0) if index==0 else (-29.0+_speed*4.0)
			_ambience[index].volume_linear=0.0 if _muted or _paused else db_to_linear(db)
			_ambience[index].pitch_scale=1.0 if index==0 else 0.93+_speed*0.1
			ambient_peak+=0.56*db_to_linear(db)
	estimated_peak_bound=0.0 if _muted or _paused else event_peak*headroom+ambient_peak
	max_estimated_peak_bound=maxf(max_estimated_peak_bound,estimated_peak_bound)

func _position(event: Dictionary,fallback: Vector3) -> Vector3:
	var value: Variant=event.get("position",event.get("pos",fallback))
	if value is Vector3: return value as Vector3
	if value is Vector2:
		var point: Vector2=value as Vector2
		return Vector3(point.x,1.0,point.y)
	return fallback

func on_event(event: Dictionary) -> void:
	if not _ready_audio or _stopped or _paused: return
	var type: String=str(event.get("type",""))
	var kind: String=str(event.get("kind",event.get("attack","meteor")))
	var weapon: String=str(event.get("weapon","ballista"))
	match type:
		"player_shot": _play(weapon,_position(event,_ship+Vector3.UP*3),-9.0 if weapon=="cannon" else -13.0,3)
		"boss_hit": _play("weak_hit" if bool(event.get("weak",false)) else "body_hit",_position(event,_boss+Vector3.UP*8),-8.0 if bool(event.get("weak",false)) else -12.0,3)
		"telegraph": _play(kind+"_tell",_boss+Vector3.UP*18,-5.0,5)
		"target_locked": _play("target_lock",_position(event,_ship),-9.0,6)
		"impact": _play(kind,_position(event,_ship if bool(event.get("hit",false)) else _boss),-6.0 if bool(event.get("hit",false)) else -11.0,5)
		"parry": _play("parry",_position(event,_ship),-7.0,6)
		"blocked": _play("blocked",_position(event,_ship),-10.0,4)
		"guard_break": _play("guard_break",_ship,-8.0,6)
		"dodge": _play("dodge",_ship,-16.0,2)
		"repair": _play("repair",_ship,-15.0,2)
		"phase": _play("phase",_boss+Vector3.UP*18,-5.0,7)
		"end":
			_play("end",_boss if bool(event.get("won",false)) else _ship,-8.0,7)

func _play(key: String,position_value: Vector3,gain: float,priority: int) -> void:
	if not _streams.has(key): return
	var selected: int=-1
	var oldest: int=2147483647
	var lowest_priority: int=2147483647
	var active: int=0
	for index: int in range(_voices.size()):
		var voice: AudioStreamPlayer3D=_voices[index]
		if not voice.playing:
			if selected<0: selected=index
		else: active+=1
	if selected<0:
		for index: int in range(_voices.size()):
			var existing_priority: int=int(_voice_data[index]["priority"])
			var serial: int=int(_voice_data[index]["serial"])
			if existing_priority<lowest_priority or (existing_priority==lowest_priority and serial<oldest):
				lowest_priority=existing_priority
				oldest=serial
				selected=index
		if lowest_priority>priority:
			dropped_events+=1
			return
	var chosen: AudioStreamPlayer3D=_voices[selected]
	chosen.stop()
	chosen.stream=_streams[key] as AudioStreamWAV
	chosen.global_position=position_value
	chosen.pitch_scale=_rng.randf_range(0.965,1.035)
	chosen.volume_linear=0.0
	chosen.unit_size=110.0 if priority>=5 else 65.0
	chosen.play()
	chosen.stream_paused=_paused
	_serial+=1
	_voice_data[selected]={"serial":_serial,"priority":priority,"gain":gain}
	peak_active_voices=maxi(peak_active_voices,mini(VOICE_LIMIT,active+1))
	_apply_gains()

func stop_all() -> void:
	if _stopped: return
	_stopped=true
	for voice: AudioStreamPlayer3D in _voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream=null
			voice.queue_free()
	for ambient: AudioStreamPlayer in _ambience:
		if is_instance_valid(ambient):
			ambient.stop()
			ambient.stream=null
			ambient.queue_free()
	for music: AudioStreamPlayer in _music:
		if is_instance_valid(music):
			music.stop()
			music.stream=null
			music.queue_free()
	_music.clear()
	_voices.clear()
	_voice_data.clear()
	_ambience.clear()
	_streams.clear()
	_ready_audio=false

func reset() -> void:
	if not _ready_audio or _stopped: return
	# Restart is a playback reset, not a bank/player reallocation.
	for index: int in range(_voices.size()):
		var voice: AudioStreamPlayer3D=_voices[index]
		voice.stop()
		voice.stream=null
		_voice_data[index]={"serial":-1,"priority":0,"gain":-12.0}
	for ambient: AudioStreamPlayer in _ambience:
		ambient.stop()
		ambient.play(0.0)
		ambient.stream_paused=_paused
	_serial=0
	_speed=0
	_apply_gains()

func _render(key: String,duration: float,looped: bool) -> AudioStreamWAV:
	# 配乐是低频，用半采样率生成：样本数减半，加载停顿从 1.6s 降到 ~0.7s
	var rate: float=11025.0 if key in ["drone_loop","pulse_loop","tension_loop"] else float(RATE)
	var count: int=roundi(duration*rate)
	var channels: int=2 if looped else 1
	var raw: PackedFloat32Array=PackedFloat32Array()
	raw.resize(count*channels)
	var generator: RandomNumberGenerator=RandomNumberGenerator.new()
	generator.seed=1593486421+absi(key.hash())
	var low: Array[float]=[0.0,0.0]
	var deep: Array[float]=[0.0,0.0]
	for frame: int in range(count):
		var t: float=float(frame)/rate
		for channel: int in range(channels):
			var white: float=generator.randf_range(-1,1)
			low[channel]=lerpf(low[channel],white,0.035)
			deep[channel]=lerpf(deep[channel],white,0.002)
			var value: float=_sample(key,t,white,low[channel],deep[channel],channel)
			if not looped:
				value*=minf(1,t*900.0)*clampf((duration-t)/0.04,0,1)
			raw[frame*channels+channel]=value
	if looped:
		var blend: int=int(rate*0.4)
		for frame: int in range(blend):
			var weight: float=float(frame)/float(blend-1)
			for channel: int in range(channels):
				raw[frame*channels+channel]=lerpf(raw[(count-blend+frame)*channels+channel],raw[frame*channels+channel],weight)
		count-=blend
		raw.resize(count*channels)
	else:
		# Short, dark early-reflection taps: shared physical room, not a huge wash.
		for frame: int in range(count-1,-1,-1):
			var value: float=raw[frame]
			for tap: int in range(3):
				var offset: int=roundi(TAP_SECONDS[tap]*rate)
				if frame>=offset: value+=raw[frame-offset]*TAP_GAINS[tap]
			raw[frame]=value
	var mean: float=0.0
	for value: float in raw: mean+=value
	mean/=maxi(1,raw.size())
	var peak: float=0.0
	for value: float in raw: peak=maxf(peak,absf(value-mean))
	var target_peak: float=0.56 if looped else 0.72
	var scale_value: float=target_peak/maxf(peak,0.00001)
	var bytes: PackedByteArray=PackedByteArray()
	bytes.resize(raw.size()*2)
	var squares: float=0.0
	for index: int in range(raw.size()):
		var value: float=(raw[index]-mean)*scale_value
		squares+=value*value
		bytes.encode_s16(index*2,roundi(clampf(value,-0.98,0.98)*32767))
	stream_peaks[key]=target_peak
	stream_rms[key]=sqrt(squares/maxi(1,raw.size()))
	var stream: AudioStreamWAV=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=int(rate)
	stream.stereo=channels==2
	stream.data=bytes
	if looped:
		stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin=0
		stream.loop_end=count
	return stream

func _music_drone(t: float,white: float,low: float,deep: float,channel: int) -> float:
	# A1 持续低音：三根弦堆叠 + 海面风噪，极慢的呼吸
	var detune: float = 0.35 if channel==0 else -0.35
	var lfo: float = 0.62+0.38*sin(TAU*0.0625*t+(0.0 if channel==0 else 1.7))
	var root: float = 55.0+detune
	var value: float = sin(TAU*root*t)*0.50+sin(TAU*root*2.0*t)*0.26
	value+=sin(TAU*root*3.0*t+0.4)*0.14+sin(TAU*82.5*t+1.1)*0.16+sin(TAU*110.0*t+2.3)*0.09
	value*=lfo*0.55
	value+=deep*1.6*(0.4+0.6*sin(TAU*0.03125*t))
	return value

func _music_pulse(t: float,low: float) -> float:
	# 心跳：64 BPM，7.5 秒八拍，每四拍一次重音
	var beat: float = 0.9375
	var index: int = int(t/beat)
	var local: float = t-float(index)*beat
	var accent: float = 1.0 if index%4==0 else 0.62
	var body: float = sin(TAU*(58.0*local-18.0*local*local))*exp(-local*7.5)*accent
	var sub: float = sin(TAU*41.0*local)*exp(-local*11.0)*accent*0.85
	var click: float = low*exp(-local*42.0)*0.55
	return (body+sub+click)*0.72

func _music_tension(t: float,white: float,low: float,channel: int) -> float:
	# 小二度音簇 + 颤音：第二阶段"绷紧"的弦，两端淡到 0 以便无缝循环
	var swell: float = pow(maxf(sin(PI*t/16.0),0.0),1.4)
	var detune: float = 0.0 if channel==0 else 0.9
	var trem: float = 0.55+0.45*sin(TAU*5.2*t)
	var value: float = sin(TAU*(440.0+detune)*t)*0.50+sin(TAU*(466.16+detune)*t)*0.42
	value+=sin(TAU*(220.0+detune)*t)*0.30
	return value*trem*swell*0.30+low*swell*0.30

func _sample(key: String,t: float,white: float,low: float,deep: float,channel: int) -> float:
	var high: float=white-low
	if key=="drone_loop": return _music_drone(t,white,low,deep,channel)
	if key=="pulse_loop": return _music_pulse(t,low)
	if key=="tension_loop": return _music_tension(t,white,low,channel)
	match key:
		"target_lock":
			return sin(TAU*(920*t-500*t*t))*exp(-t*32)*.22+sin(TAU*1470*t)*exp(-t*45)*.06+high*exp(-t*70)*.16
		"ballista":
			return high*exp(-t*95)*0.55+sin(TAU*(205*t-45*t*t))*exp(-t*18)*0.23+(sin(TAU*485*t)+sin(TAU*1273*t)*0.4)*exp(-t*42)*0.12+low*exp(-absf(t-0.075)*100)*0.8
		"cannon":
			return low*exp(-t*5.5)*3.4+sin(TAU*(54*t+1.9*(1-exp(-t*14))))*exp(-t*5.0)*0.55+high*exp(-t*70)*0.45+sin(TAU*93*t)*exp(-t*9)*0.16
		"harpoon":
			return (sin(TAU*940*t)+sin(TAU*1371*t)*0.5)*exp(-t*25)*0.2+high*exp(-t*65)*0.3+low*exp(-absf(t-0.12)*13)*sin(TAU*(34*t+60*t*t))*0.9
		"body_hit":
			return low*exp(-t*9)*2.3+sin(TAU*67*t)*exp(-t*14)*0.38+high*exp(-t*55)*0.18+low*sin(TAU*21*t)*exp(-t*7)*0.4
		"weak_hit":
			return _sample("body_hit",t,white,low,deep,channel)+(sin(TAU*730*t)+sin(TAU*1127*t)*0.42)*exp(-t*14)*0.16
		"meteor_tell":
			var rise: float=pow(clampf(t/1.55,0,1),1.3)
			return low*rise*(0.8+sin(TAU*2.7*t)*0.2)+sin(TAU*(38*t+17*t*t))*rise*0.12
		"lightning_tell":
			var rise: float=clampf(t/1.4,0,1)
			return high*rise*(0.04+pow(0.5+0.5*sin(TAU*(6*t+9*t*t)),10)*0.3)+sin(TAU*(110*t+70*t*t))*rise*0.08
		"lunge_tell":
			var envelope: float=sin(clampf(t,0,1)*PI)
			return (sin(TAU*(38*t+2*sin(TAU*2*t)))+sin(TAU*79*t)*0.3)*envelope*0.3+low*envelope*1.4
		"cleave_tell":
			var envelope: float=sin(clampf(t/0.8,0,1)*PI)
			return sin(TAU*(72*t+6*t*t))*envelope*0.2+high*envelope*0.06+low*envelope*0.8
		"meteor":
			return sin(TAU*(39*t+0.8*(1-exp(-t*20))))*exp(-t*4)*0.45+low*exp(-t*3.3)*3.6+high*exp(-t*36)*0.15+low*exp(-absf(t-0.28)*5)*1.3
		"lightning":
			return high*exp(-t*65)*0.5+high*exp(-absf(t-0.055)*125)*0.24+low*exp(-t*2.6)*2.6+sin(TAU*38*t)*exp(-t*3)*0.18
		"lunge":
			return low*exp(-t*4.5)*2.4+high*exp(-absf(t-0.065)*17)*0.15+sin(TAU*(49*t+3*(1-exp(-t*8))))*exp(-t*7)*0.25
		"cleave":
			return low*exp(-t*8)*1.8+high*exp(-absf(t-0.06)*20)*0.16+(sin(TAU*286*t)+sin(TAU*593*t)*0.35)*exp(-t*21)*0.18
		"parry":
			return (sin(TAU*1143*t)+sin(TAU*1717*t)*0.55+sin(TAU*2603*t)*0.22)*exp(-t*8)*0.25+high*exp(-t*90)*0.27+low*exp(-t*18)*0.9
		"blocked":
			return low*exp(-t*17)*1.9+(sin(TAU*359*t)+sin(TAU*813*t)*0.5)*exp(-t*26)*0.2+high*exp(-t*62)*0.24
		"guard_break":
			return high*exp(-t*18)*0.22+sin(TAU*(270*t-75*t*t))*exp(-t*9)*0.22+low*exp(-t*8)*1.4
		"dodge": return high*exp(-absf(t-0.12)*13)*0.1+low*exp(-absf(t-0.18)*8)*0.9
		"repair": return (sin(TAU*310*t)*exp(-t*26)+sin(TAU*442*t)*exp(-absf(t-0.19)*27)+sin(TAU*505*t)*exp(-absf(t-0.39)*25))*0.12+low*exp(-t*4)*0.4
		"phase","end":
			return (sin(TAU*35*t+sin(TAU*1.7*t))*0.3+sin(TAU*71*t)*0.12+low*1.7)*sin(clampf(t/2.1,0,1)*PI)*exp(-t*0.8)
		"sea_loop":
			var swell: float=0.55+0.22*sin(TAU*t/7.6+channel*0.4)+0.16*sin(TAU*t/3.8)
			return (low*2.5+high*0.06+deep*2.0)*swell
		"ship_loop":
			var creak: float=pow(maxf(0,sin(TAU*t/3.4+channel*0.3)),9)
			return (sin(TAU*(93*t+1.5*sin(TAU*t/4)))+sin(TAU*237*t)*0.2)*creak*0.08+low*0.22+high*0.012
	return 0.0
