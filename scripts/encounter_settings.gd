extends CanvasLayer
## Encounter-only preferences. Loading never changes AudioServer/DisplayServer.
signal settings_changed(values: Dictionary)
signal closed

const DEFAULTS: Dictionary={"quality":2,"fullscreen":false,"volume":0.8,"shake":true}
const CONFIG_PATH: String="user://sea_boss_settings.cfg"
const TEXT: Color=Color("ece5d6")
const MUTED: Color=Color("8b9dab")
const ACCENT: Color=Color("c09154")

var override_path: String=""
var load_state: String="not_loaded"
var save_state: String="not_saved"
var last_load_error: Error=OK
var last_save_error: Error=OK
var status_message: String=""
var is_open: bool=false

var _values: Dictionary=DEFAULTS.duplicate()
var _canvas: Control
var _overlay: Control
var _base: Control
var _quality: OptionButton
var _fullscreen: CheckButton
var _volume: HSlider
var _volume_text: Label
var _shake: CheckButton
var _quality_hint: Label
var _status: Label
var _done: Button
var _toast: Panel
var _toast_text: Label
var _toast_tween: Tween
var _syncing: bool=false

func _ready() -> void:
	layer=30
	process_mode=Node.PROCESS_MODE_ALWAYS
	_build_ui()
	load_settings()
	_sync_controls()
	_overlay.hide()
	_toast.hide()
	set_process_input(false)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _path() -> String:
	return override_path if not override_path.is_empty() else CONFIG_PATH

func get_values() -> Dictionary:
	return _values.duplicate()

func _sanitize(input: Dictionary) -> Dictionary:
	var clean: Dictionary=DEFAULTS.duplicate()
	var quality_value: Variant=input.get("quality",DEFAULTS["quality"])
	if typeof(quality_value) in [TYPE_INT,TYPE_FLOAT]:
		var numeric: float=float(quality_value)
		if is_finite(numeric): clean["quality"]=clampi(roundi(clampf(numeric,0,2)),0,2)
	var volume_value: Variant=input.get("volume",DEFAULTS["volume"])
	if typeof(volume_value) in [TYPE_INT,TYPE_FLOAT]:
		var numeric: float=float(volume_value)
		if is_finite(numeric): clean["volume"]=clampf(numeric,0,1)
	for key: String in ["fullscreen","shake"]:
		var value: Variant=input.get(key,DEFAULTS[key])
		if typeof(value)==TYPE_BOOL: clean[key]=bool(value)
	return clean

func load_settings() -> Error:
	var config: ConfigFile=ConfigFile.new()
	last_load_error=config.load(_path())
	_values=DEFAULTS.duplicate()
	if last_load_error==ERR_FILE_NOT_FOUND:
		load_state="missing"
		status_message="首次使用：采用默认设置。"
	elif last_load_error!=OK:
		load_state="error"
		status_message="无法读取设置（错误 %d），已使用默认值。" % last_load_error
	else:
		var raw: Dictionary={}
		for key: String in DEFAULTS:
			raw[key]=config.get_value("settings",key,DEFAULTS[key])
		_values=_sanitize(raw)
		load_state="loaded" if raw==_values else "sanitized"
		status_message="已读取试战设置。" if load_state=="loaded" else "部分设置无效，已修正为合理值。"
	if is_instance_valid(_quality): _sync_controls()
	return last_load_error

func save_settings() -> Error:
	_values=_sanitize(_values)
	var config: ConfigFile=ConfigFile.new()
	for key: String in DEFAULTS:
		config.set_value("settings",key,_values[key])
	last_save_error=config.save(_path())
	if last_save_error==OK:
		save_state="saved"
		status_message="设置已保存。"
	else:
		save_state="error"
		status_message="设置保存失败（错误 %d）。本次设置仍可使用，可继续游戏。" % last_save_error
	_update_status()
	return last_save_error

func open(values: Dictionary={}) -> void:
	if not values.is_empty(): _values=_sanitize(values)
	if not is_instance_valid(_overlay): return
	_sync_controls()
	_layout()
	is_open=true
	_overlay.show()
	set_process_input(true)
	_quality.grab_focus()

func close() -> void:
	if not is_open: return
	var error: Error=save_settings()
	is_open=false
	_overlay.hide()
	set_process_input(false)
	if error!=OK: _show_failure_toast()
	closed.emit()

func _input(event: InputEvent) -> void:
	if is_open and event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode==KEY_ESCAPE or event.keycode==KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		close()

func _control_changed(_unused: Variant=null) -> void:
	if _syncing: return
	_values={"quality":_quality.get_selected_id(),"fullscreen":_fullscreen.button_pressed,"volume":_volume.value,"shake":_shake.button_pressed}
	_values=_sanitize(_values)
	save_state="not_saved"
	status_message="设置已应用，点击「完成并返回」保存。"
	_sync_labels()
	settings_changed.emit(get_values())

func _sync_controls() -> void:
	_syncing=true
	_quality.select(int(_values["quality"]))
	_fullscreen.set_pressed_no_signal(bool(_values["fullscreen"]))
	_volume.set_value_no_signal(float(_values["volume"]))
	_shake.set_pressed_no_signal(bool(_values["shake"]))
	_syncing=false
	_sync_labels()

func _sync_labels() -> void:
	_volume_text.text="%d%%" % roundi(float(_values["volume"])*100)
	var hints: Array[String]=["低：关闭体积雾与环境遮蔽，优先保持流畅。","中：保留主要环境层次，平衡画面与性能。","高：完整环境光影与水雾，适合性能充裕的设备。"]
	_quality_hint.text=hints[int(_values["quality"])]
	_update_status()

func _update_status() -> void:
	if not is_instance_valid(_status): return
	_status.text=status_message
	_status.modulate=Color("e7b68e") if save_state=="error" or load_state=="error" else MUTED

func _show_failure_toast() -> void:
	_toast_text.text=status_message
	_toast.modulate.a=1
	_toast.show()
	if is_instance_valid(_toast_tween): _toast_tween.kill()
	_toast_tween=create_tween()
	_toast_tween.tween_interval(7.0)
	_toast_tween.tween_property(_toast,"modulate:a",0.0,0.5)
	_toast_tween.tween_callback(_toast.hide)

func _layout() -> void:
	if not is_instance_valid(_canvas): return
	var viewport_size: Vector2=get_viewport().get_visible_rect().size
	_canvas.size=viewport_size
	_overlay.size=viewport_size
	var factor: float=maxf(0.01,minf(viewport_size.x/1600.0,viewport_size.y/900.0))
	_base.scale=Vector2.ONE*factor
	_base.position=(viewport_size-Vector2(1600,900)*factor)*0.5
	_toast.scale=Vector2.ONE*factor
	_toast.position=Vector2((viewport_size.x-760*factor)*0.5,viewport_size.y-110*factor)

func _build_ui() -> void:
	_canvas=Control.new()
	_canvas.name="EncounterSettings"
	_canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	var font: SystemFont=SystemFont.new()
	font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Noto Sans CJK SC","Segoe UI"])
	var theme: Theme=Theme.new()
	theme.default_font=font
	theme.default_font_size=16
	theme.set_color("font_color","Label",TEXT)
	theme.set_color("font_color","Button",TEXT)
	theme.set_color("font_hover_color","Button",ACCENT)
	theme.set_stylebox("normal","Button",_style(Color(0.02,0.03,0.04,0.85),Color(0.62,0.52,0.38,0.34)))
	theme.set_stylebox("hover","Button",_style(Color(0.07,0.09,0.10,0.95),Color(0.78,0.63,0.42,0.95)))
	theme.set_stylebox("pressed","Button",_style(Color(0.10,0.12,0.13,0.96),ACCENT))
	theme.set_stylebox("focus","Button",_style(Color.TRANSPARENT,ACCENT))
	_canvas.theme=theme
	_overlay=Control.new()
	_overlay.name="ModalOverlay"
	_overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	_canvas.add_child(_overlay)
	var shade: ColorRect=ColorRect.new()
	_overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color=Color(0.006,0.010,0.014,0.86)
	shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_base=Control.new()
	_base.size=Vector2(1600,900)
	_base.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_base)
	var panel: Panel=Panel.new()
	panel.position=Vector2(420,160)
	panel.size=Vector2(760,580)
	panel.add_theme_stylebox_override("panel",_style(Color(0.016,0.026,0.034,0.97),Color(0.72,0.58,0.38,0.40)))
	_base.add_child(panel)
	_label(panel,"试 战 设 置",Vector2(38,25),Vector2(680,45),26,TEXT)
	_label(panel,"显示与声音 · 仅保存本试战偏好",Vector2(40,80),Vector2(680,26),13,MUTED)
	_label(panel,"画面质量",Vector2(40,132),Vector2(230,34),20,TEXT)
	_quality=OptionButton.new()
	_quality.name="Quality"
	_quality.position=Vector2(320,126)
	_quality.size=Vector2(398,44)
	for title: String in ["低","中","高"]: _quality.add_item(title)
	panel.add_child(_quality)
	_quality.item_selected.connect(_control_changed)
	_quality_hint=_label(panel,"",Vector2(40,184),Vector2(680,32),14,MUTED)
	_label(panel,"全屏显示",Vector2(40,236),Vector2(230,36),20,TEXT)
	_fullscreen=CheckButton.new()
	_fullscreen.name="Fullscreen"
	_fullscreen.position=Vector2(320,230)
	_fullscreen.size=Vector2(398,44)
	_fullscreen.text="启用全屏"
	panel.add_child(_fullscreen)
	_fullscreen.toggled.connect(_control_changed)
	_label(panel,"主音量",Vector2(40,304),Vector2(230,36),20,TEXT)
	_volume=HSlider.new()
	_volume.name="Volume"
	_volume.position=Vector2(320,304)
	_volume.size=Vector2(308,35)
	_volume.min_value=0
	_volume.max_value=1
	_volume.step=0.01
	panel.add_child(_volume)
	_volume.value_changed.connect(_control_changed)
	_volume_text=_label(panel,"80%",Vector2(644,302),Vector2(75,34),18,ACCENT)
	_label(panel,"镜头震动",Vector2(40,372),Vector2(230,36),20,TEXT)
	_shake=CheckButton.new()
	_shake.name="CameraShake"
	_shake.position=Vector2(320,366)
	_shake.size=Vector2(398,44)
	_shake.text="启用镜头震动"
	panel.add_child(_shake)
	_shake.toggled.connect(_control_changed)
	_label(panel,"关闭震动后，仍会保留预警、受击提示与动作反馈。",Vector2(40,424),Vector2(680,28),14,MUTED)
	_status=_label(panel,"",Vector2(40,464),Vector2(680,42),14,MUTED)
	_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_done=Button.new()
	_done.name="Done"
	_done.text="完成并返回  Esc"
	_done.position=Vector2(40,520)
	_done.size=Vector2(680,40)
	panel.add_child(_done)
	_done.pressed.connect(close)
	_toast=Panel.new()
	_toast.name="SaveFailureNotice"
	_toast.size=Vector2(760,75)
	_toast.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("panel",_style(Color(0.05,0.02,0.02,0.96),Color(0.72,0.46,0.32,0.9)))
	_canvas.add_child(_toast)
	_toast_text=_label(_toast,"",Vector2(18,14),Vector2(724,52),16,Color("edd2b8"))
	_toast_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func _style(background: Color,border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat=StyleBoxFlat.new()
	style.bg_color=background
	style.border_color=border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left=12
	style.content_margin_right=12
	return style

func _label(parent: Node,text: String,at: Vector2,dimensions: Vector2,font_size: int,color: Color) -> Label:
	var label: Label=Label.new()
	label.text=text
	label.position=at
	label.size=dimensions
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label
