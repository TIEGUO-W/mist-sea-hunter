extends CanvasLayer
## 战斗界面：黄铜航海仪表的克制排版。
## 信息按重要度分三层：巨兽横幅 → 准星/威胁 → 船只与武器。其余一律退让。

signal action_requested(action: String)
signal start_requested
signal restart_requested
signal pause_requested
signal return_requested

const INK := Color("05080b")
const BONE := Color("ece5d6")
const BRASS := Color("c09154")
const BRASS_HI := Color("e6c48a")
const TEAL := Color("86d8cb")
const BLOOD := Color("c2593f")
const SLATE := Color("8b9dab")
const VIOLET := Color("a992cf")
const WEAPON_ORDER := ["ballista", "cannon", "harpoon"]
const WEAPON_NAMES := {"ballista": "精确连弩", "cannon": "破甲重炮", "harpoon": "牵制鱼叉"}
const WEAPON_ROLES := {"ballista": "走射 · 精确打弱点", "cannon": "慢前摇 · 高破甲", "harpoon": "低伤 · 牵制追击"}
const WEAPON_COSTS := {"ballista": 7, "cannon": 28, "harpoon": 20}


class Meter extends Control:
	var value := 1.0
	var smooth := -1.0
	var fill := Color("86d8cb")
	var ghost := -1.0
	var ghost_color := Color(0.95, 0.78, 0.55, 0.55)
	var segmented := 0
	var framed := true
	func _draw() -> void:
		var back := Color(0.02, 0.03, 0.04, 0.72)
		draw_rect(Rect2(Vector2.ZERO, size), back)
		if ghost >= 0.0 and ghost > value:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(ghost, 0.0, 1.0), size.y)), ghost_color)
		var shown: float = smooth if smooth >= 0.0 else value
		var width: float = size.x * clampf(shown, 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, Vector2(width, size.y)), fill)
		if width > 1.5:
			draw_rect(Rect2(Vector2(width - 1.5, 0.0), Vector2(1.5, size.y)), Color(1, 1, 1, 0.55))
		if framed:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.72, 0.60, 0.40, 0.42), false, 1.0)
		draw_line(Vector2(1, 0.5), Vector2(size.x - 1, 0.5), Color(1, 0.95, 0.86, 0.16), 1.0)
		for i in range(1, segmented):
			var x := size.x * float(i) / float(segmented)
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.02, 0.03, 0.04, 0.85), 1.0)


class AimMarker extends Control:
	var weak := false
	var hit := false
	var in_range := true
	var flash := 0.0
	func _draw() -> void:
		var col := Color("e2c083") if weak else Color("e8e2d4") if hit and in_range else Color("7f8d99")
		for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(dir * 7, dir * 15, Color(col, 0.85), 1.0, true)
		if hit and in_range:
			draw_circle(Vector2.ZERO, 1.6, col)
			draw_arc(Vector2.ZERO, 3.0, 0, TAU, 12, Color(col, 0.55), 1.0, true)
		else:
			draw_circle(Vector2.ZERO, 0.9, Color(col, 0.7))
		if weak:
			for a: float in [0.35, PI + 0.35]:
				draw_arc(Vector2.ZERO, 22.0, a, a + 1.2, 18, col, 1.6, true)
			draw_line(Vector2(-3, -26), Vector2(3, -26), Color(col, 0.9), 1.2, true)
		if flash > 0.0:
			draw_arc(Vector2.ZERO, 30.0, 0, TAU, 40, Color(0.95, 0.80, 0.58, flash), 1.6, true)


class ThreatMarkers extends Control:
	var threats: Array = []
	func _draw() -> void:
		var center := Vector2(800, 452)
		var half := Vector2(742, 280)
		for item: Dictionary in threats:
			var distance := float(item.get("distance", 999))
			if distance > 55.0:
				continue
			var dir: Vector2 = item.get("screen_direction", Vector2.ZERO)
			if dir.length_squared() < 0.001:
				continue
			dir = dir.normalized()
			var edge := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
			var tip := center + dir * edge
			if absf(dir.x) > absf(dir.y):
				tip.y = clampf(tip.y, 178.0, 520.0)
			elif dir.y > 0.0:
				tip.y = 636.0
			var tail := tip - dir * 13.0
			var side := dir.orthogonal() * 4.5
			var col := Color("bdb0d6")
			if str(item.get("kind", "")) in ["meteor", "lightning"]:
				col = Color("d8b37c")
			col.a = clampf(1.0 - distance / 78.0, 0.32, 0.92)
			draw_colored_polygon(PackedVector2Array([tip, tail + side, tail - side]), col)
			draw_line(tail - dir * 5.0 + side, tail - dir * 5.0 - side, Color(col, 0.30), 1.0, true)


class TacticalRadar extends Control:
	var ship_pos := Vector2(0, 85)
	var boss_pos := Vector2.ZERO
	var heading := 0.0
	var boss_facing := 0.0
	var attacks: Array = []
	var arena_radius := 420.0
	func _center() -> Vector2:
		return size * 0.5
	func _radius() -> float:
		return minf(size.x, size.y) * 0.5 - 10.0
	func _scale_factor() -> float:
		return _radius() / 180.0
	func _point(world: Vector2) -> Vector2:
		return _center() + (world - ship_pos) * _scale_factor()
	func _inside(point: Vector2) -> bool:
		return point.distance_squared_to(_center()) < _radius() * _radius()
	func _line(a: Vector2, b: Vector2, color: Color, width: float = 1.0) -> void:
		var vector := b - a
		var length_squared := vector.length_squared()
		if length_squared < 0.00001:
			return
		var offset := a - _center()
		var b_term := 2.0 * offset.dot(vector)
		var c_term := offset.length_squared() - _radius() * _radius()
		var discriminant := b_term * b_term - 4.0 * length_squared * c_term
		if discriminant < 0.0:
			return
		var enter := maxf(0.0, (-b_term - sqrt(discriminant)) / (2.0 * length_squared))
		var leave := minf(1.0, (-b_term + sqrt(discriminant)) / (2.0 * length_squared))
		if leave > enter:
			draw_line(a + vector * enter, a + vector * leave, color, width, true)
	func _circle(point: Vector2, radius: float, color: Color, dashed: bool = false) -> void:
		if point.distance_to(_center()) + radius < _radius():
			draw_circle(point, radius, Color(color, 0.07))
		for i in range(44):
			if dashed and i % 4 >= 2:
				continue
			_line(point + Vector2.from_angle(float(i) * TAU / 44.0) * radius,
				point + Vector2.from_angle(float(i + 1) * TAU / 44.0) * radius, color, 1.1)
	func _shape(item: Dictionary) -> void:
		if bool(item.get("cancelled", false)):
			return
		var age := float(item.get("age", 0))
		var delay := float(item.get("delay", 1))
		var active := float(item.get("active", 0.3))
		var life := float(item.get("life", delay + active))
		if age > life:
			return
		var armed := age >= delay and age <= delay + active
		var kind := str(item.get("kind", "target"))
		var color := Color("d8b98a") if kind in ["meteor", "meteorite", "target"] else Color("b7a6d6")
		color.a = 0.95 if armed else 0.60
		var tracking := kind in ["meteor", "meteorite"] and bool(item.get("tracking", false)) and not bool(item.get("locked", false))
		if tracking:
			color = Color(0.52, 0.64, 0.71, 0.45)
		elif kind in ["meteor", "meteorite"] and bool(item.get("locked", false)):
			color = Color(0.92, 0.76, 0.46, 0.95)
		var origin: Vector2 = item.get("origin", boss_pos)
		var target: Vector2 = item.get("target", origin)
		if kind in ["cleave", "claw", "sweep", "lunge", "charge"]:
			var direction: Vector2 = item.get("direction", (target - origin).normalized())
			if direction.length_squared() < 0.001:
				direction = Vector2(sin(boss_facing), cos(boss_facing))
			direction = direction.normalized()
			var start := _point(origin)
			var reach := maxf(0.0, float(item.get("range", 35))) * _scale_factor()
			if kind in ["lunge", "charge"]:
				var path := target - origin
				if path.length_squared() > 0.001:
					direction = path.normalized()
				var radius := maxf(0.0, float(item.get("radius", 5))) * _scale_factor()
				var side := direction.orthogonal() * radius
				var finish := _point(target)
				_line(start + side, finish + side, color, 1.3)
				_line(start - side, finish - side, color, 1.3)
				for i in range(20):
					var a := direction.angle() - PI * 0.5 + PI * float(i) / 20.0
					var b := direction.angle() - PI * 0.5 + PI * float(i + 1) / 20.0
					_line(finish + Vector2.from_angle(a) * radius, finish + Vector2.from_angle(b) * radius, color, 1.3)
					_line(start - Vector2.from_angle(a) * radius, start - Vector2.from_angle(b) * radius, color, 1.3)
			else:
				var width := clampf(float(item.get("angle", PI * 0.65)), 0.0, TAU)
				var angle := direction.angle() - width * 0.5
				_line(start, start + Vector2.from_angle(angle) * reach, color)
				_line(start, start + Vector2.from_angle(angle + width) * reach, color)
				for i in range(24):
					_line(start + Vector2.from_angle(angle + width * float(i) / 24.0) * reach,
						start + Vector2.from_angle(angle + width * float(i + 1) / 24.0) * reach, color, 1.2)
		else:
			var point := _point(target)
			var radius := maxf(0.0, float(item.get("radius", 8))) * _scale_factor()
			_circle(point, radius, color, tracking)
			if _inside(point):
				draw_circle(point, 1.1 if tracking else 1.9, color)
				var progress := clampf(age / maxf(delay, 0.001), 0.0, 1.0)
				if kind in ["meteor", "meteorite"]:
					var lock_age := float(item.get("lock_age", maxf(0.0, delay - 1.05)))
					progress = clampf(age / maxf(lock_age, 0.001), 0.0, 1.0) if tracking else clampf((age - lock_age) / maxf(delay - lock_age, 0.001), 0.0, 1.0)
				if radius > 2.0 and progress > 0.0:
					for i in range(20):
						var a := float(i) * TAU * progress / 20.0 - PI * 0.5
						var b := float(i + 1) * TAU * progress / 20.0 - PI * 0.5
						_line(point + Vector2.from_angle(a) * (radius + 3.0), point + Vector2.from_angle(b) * (radius + 3.0), Color(color, 0.8), 1.3)
	func _draw() -> void:
		var font := get_theme_default_font()
		var center := _center()
		var radius := _radius()
		draw_circle(center, radius, Color(0.014, 0.024, 0.034, 0.66))
		draw_arc(center, radius, 0, TAU, 96, Color(0.72, 0.60, 0.40, 0.55), 1.0, true)
		draw_arc(center, radius * 0.66, 0, TAU, 80, Color(0.52, 0.63, 0.70, 0.14), 1.0, true)
		draw_arc(center, radius * 0.33, 0, TAU, 64, Color(0.52, 0.63, 0.70, 0.12), 1.0, true)
		for i in range(24):
			var dir := Vector2.from_angle(float(i) * TAU / 24.0)
			draw_line(center + dir * radius, center + dir * (radius + (6.0 if i % 6 == 0 else 3.0)),
				Color(0.72, 0.62, 0.44, 0.45 if i % 6 == 0 else 0.25), 1.0, true)
		for item: Dictionary in attacks:
			_shape(item)
		var delta := (boss_pos - ship_pos) * _scale_factor()
		var boss := center + delta.limit_length(radius - 7.0)
		draw_line(center, boss, Color(0.66, 0.58, 0.78, 0.22), 1.0, true)
		draw_arc(boss, 4.6, 0, TAU, 20, Color("b09ac8"), 1.3, true)
		draw_circle(boss, 1.9, Color("b09ac8"))
		draw_line(boss, boss + Vector2(sin(boss_facing), cos(boss_facing)) * 10.0, Color("b09ac8"), 1.4, true)
		if delta.length() > radius - 7.0:
			var dir := delta.normalized()
			draw_line(boss, boss - dir.rotated(0.6) * 7.0, Color("d8b37c"), 1.4, true)
			draw_line(boss, boss - dir.rotated(-0.6) * 7.0, Color("d8b37c"), 1.4, true)
		var forward := Vector2(-sin(heading), -cos(heading))
		draw_colored_polygon(PackedVector2Array([center + forward * 7.5,
			center + forward.rotated(2.5) * 5.5, center + forward.rotated(-2.5) * 5.5]), Color("a9e0d1"))
		if arena_radius - ship_pos.length() < 50.0:
			draw_arc(center, radius - 2.0, 0, TAU, 96, Color(0.82, 0.38, 0.28, 0.75), 1.4, true)
		draw_string(font, center + Vector2(-4, -radius - 8.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("c09154"))


class Icon extends Control:
	var kind := "ballista"
	func _draw() -> void:
		var c := size * 0.5
		var col := Color("cfd8d2")
		match kind:
			"ballista":
				draw_line(c + Vector2(0, 13), c + Vector2(0, -15), col, 1.6, true)
				draw_polyline(PackedVector2Array([c + Vector2(-18, -1), c + Vector2(-9, -8), c + Vector2(0, -5),
					c + Vector2(9, -8), c + Vector2(18, -1)]), col, 1.6, true)
				draw_line(c + Vector2(-18, -1), c + Vector2(0, 9), Color(col, 0.7), 1.0, true)
				draw_line(c + Vector2(18, -1), c + Vector2(0, 9), Color(col, 0.7), 1.0, true)
			"cannon":
				draw_arc(c + Vector2(-9, 8), 4.0, 0, TAU, 18, col, 1.6, true)
				draw_arc(c + Vector2(9, 8), 4.0, 0, TAU, 18, col, 1.6, true)
				draw_polyline(PackedVector2Array([c + Vector2(-16, 3), c + Vector2(-13, -5), c + Vector2(15, -12),
					c + Vector2(18, -4), c + Vector2(-11, 6)]), col, 1.6, true)
				draw_line(c + Vector2(12, -11), c + Vector2(15, -3), col, 2.0, true)
			"harpoon":
				draw_line(c + Vector2(-11, 14), c + Vector2(12, -13), col, 2.0, true)
				draw_polyline(PackedVector2Array([c + Vector2(1, -10), c + Vector2(14, -15), c + Vector2(11, -1)]), col, 1.6, true)
				draw_arc(c + Vector2(-7, 9), 10.0, 0.4, 2.8, 18, Color(col, 0.8), 1.0, true)
			"ship":
				draw_polyline(PackedVector2Array([c + Vector2(0, -18), c + Vector2(9, -1), c + Vector2(5, 16),
					c + Vector2(-5, 16), c + Vector2(-9, -1), c + Vector2(0, -18)]), col, 1.5, true)
				draw_line(c + Vector2(0, -10), c + Vector2(0, 11), Color(col, 0.7), 1.0, true)
			"gear":
				draw_arc(c, 9.0, 0, TAU, 24, col, 1.4, true)
				draw_arc(c, 3.4, 0, TAU, 16, col, 1.4, true)
				for i in range(8):
					var dir := Vector2.from_angle(float(i) * TAU / 8.0)
					draw_line(c + dir * 9.0, c + dir * 13.0, col, 1.6, true)
			"pause":
				draw_line(c + Vector2(-4, -9), c + Vector2(-4, 9), col, 2.4, true)
				draw_line(c + Vector2(4, -9), c + Vector2(4, 9), col, 2.4, true)
			"sound":
				draw_polyline(PackedVector2Array([c + Vector2(-9, -4), c + Vector2(-3, -4), c + Vector2(3, -9),
					c + Vector2(3, 9), c + Vector2(-3, 4), c + Vector2(-9, 4)]), col, 1.4, true)
				draw_arc(c + Vector2(4, 0), 7.0, -0.9, 0.9, 14, Color(col, 0.8), 1.2, true)
			"mute":
				draw_polyline(PackedVector2Array([c + Vector2(-9, -4), c + Vector2(-3, -4), c + Vector2(3, -9),
					c + Vector2(3, 9), c + Vector2(-3, 4), c + Vector2(-9, 4)]), Color(col, 0.7), 1.4, true)
				draw_line(c + Vector2(7, -6), c + Vector2(15, 6), Color("c2593f"), 1.4, true)
				draw_line(c + Vector2(15, -6), c + Vector2(7, 6), Color("c2593f"), 1.4, true)


var _base: Control
var _gameplay: Control
var _boss_meter: Meter
var _boss_value: Label
var _phase_label: Label
var _hull_meter: Meter
var _hull_value: Label
var _hull_caption: Label
var _stamina_meter: Meter
var _stamina_value: Label
var _repair_label: Label
var _speed_label: Label
var _notice_label: Label
var _notice_panel: Panel
var _attack_label: Label
var _windup_meter: Meter
var _weak_label: Label
var _action_label: Label
var _action_meter: Meter
var _distance_label: Label
var _heading_label: Label
var _guard_label: Label
var _weapon_icon: Icon
var _weapon_name: Label
var _weapon_role: Label
var _weapon_cost: Label
var _weapon_cd: Label
var _weapon_cd_meter: Meter
var _weapon_card: Panel
var _previous_button: Button
var _next_button: Button
var _overlay: Control
var _overlay_scrim: ColorRect
var _overlay_title: Label
var _title_rule: ColorRect
var _overlay_eyebrow: Label
var _overlay_body: Control
var _briefing_body: Control
var _result_body: Control
var _result_stats: Label
var _result_shade: ColorRect
var _result_data: Dictionary = {}
var _last_data: Dictionary = {}
var _primary_button: Button
var _restart_button: Button
var _return_button: Button
var _settings_button_overlay: Button
var _reticle: AimMarker
var _range_label: Label
var _tutorial_label: Label
var _tutorial_rule: ColorRect
var _tutorial_alpha_target := 0.0
var _tutorial_step := -1
var _repair_hint_shown := false
var _repair_hint_remaining := 0.0
var _threats: ThreatMarkers
var _radar: TacticalRadar
var _hit_shade: ColorRect
var _mute_icon: Icon
var _overlay_mode := "briefing"
var _preparing := false
var _last_notice := ""
var _notice_remaining := 0.0
var _scale := Vector2.ONE
var _card_energy := 0.0
var _boss_ghost := 1.0
var _display_hull := 100.0
var _hull_target := 100.0
var _hull_punch := 0.0
var _punch_time := 0.0
var _weapon_punch := 0.0
var _was_gameplay := false
var _title_font: Font


func _ready() -> void:
	layer = 10
	_base = Control.new()
	_base.name = "BattleHUD"
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base.size = Vector2(1600, 900)
	add_child(_base)
	_base.theme = _make_theme()
	_title_font = _make_font(true)
	_gameplay = Control.new()
	_gameplay.size = Vector2(1600, 900)
	_gameplay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base.add_child(_gameplay)
	_hit_shade = ColorRect.new()
	_hit_shade.size = Vector2(1600, 900)
	_hit_shade.color = Color(0.55, 0.09, 0.05, 0.0)
	_hit_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base.add_child(_hit_shade)
	_build_boss_banner()
	_build_ship_seal()
	_build_weapon_card()
	_build_radar()
	_build_center_layer()
	_build_overlay()
	_layout()
	set_overlay("briefing")


func _make_font(bold: bool) -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	if bold:
		font.font_weight = 600
	return font


func _make_theme() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Segoe UI"])
	theme.default_font = font
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", BONE)
	theme.set_color("font_color", "Button", BONE)
	theme.set_color("font_hover_color", "Button", BRASS_HI)
	theme.set_color("font_disabled_color", "Button", Color(0.42, 0.48, 0.54, 0.7))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var col := Color(0.026, 0.038, 0.048, 0.80)
		var border := Color(0.62, 0.50, 0.33, 0.34)
		if state == "hover" or state == "focus":
			col = Color(0.075, 0.095, 0.11, 0.94)
			border = Color(0.78, 0.62, 0.40, 0.95)
		elif state == "pressed":
			col = Color(0.10, 0.12, 0.13, 0.96)
			border = BRASS_HI
		theme.set_stylebox(state, "Button", _style(col, border, 1))
	return theme


func _build_boss_banner() -> void:
	var title := _text(_gameplay, "沧 溟 · 角 渊", Vector2(560, 12), Vector2(480, 40), 30, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_font_override("font", _title_font)
	_phase_label = _text(_gameplay, "Ⅰ · 潜海之怒", Vector2(560, 50), Vector2(480, 20), 12, BRASS, HORIZONTAL_ALIGNMENT_CENTER)
	var frame := Control.new()
	frame.position = Vector2(430, 76)
	frame.size = Vector2(740, 12)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gameplay.add_child(frame)
	_boss_meter = Meter.new()
	_boss_meter.position = Vector2(0, 2)
	_boss_meter.size = Vector2(740, 8)
	_boss_meter.fill = Color("6d2f44")
	_boss_meter.segmented = 4
	_boss_meter.ghost = 1.0
	frame.add_child(_boss_meter)
	_boss_value = _text(_gameplay, "4200", Vector2(1180, 70), Vector2(120, 18), 12, SLATE, HORIZONTAL_ALIGNMENT_RIGHT)
	windup_build()


func windup_build() -> void:
	_windup_meter = Meter.new()
	_windup_meter.position = Vector2(430, 92)
	_windup_meter.size = Vector2(740, 3)
	_windup_meter.fill = VIOLET
	_windup_meter.framed = false
	_windup_meter.visible = false
	_gameplay.add_child(_windup_meter)
	_attack_label = _text(_gameplay, "", Vector2(430, 100), Vector2(740, 22), 13, VIOLET, HORIZONTAL_ALIGNMENT_CENTER)


func _build_ship_seal() -> void:
	var panel := _panel(_gameplay, Vector2(30, 726), Vector2(322, 148))
	_icon(panel, "ship", Vector2(14, 14), Vector2(34, 40))
	_text(panel, "猎 神 号", Vector2(58, 12), Vector2(150, 26), 17, BONE)
	_hull_caption = _text(panel, "HULL", Vector2(58, 36), Vector2(80, 16), 10, Color(0.55, 0.60, 0.64, 0.75))
	_hull_value = _text(panel, "100", Vector2(150, 8), Vector2(90, 44), 34, BONE, HORIZONTAL_ALIGNMENT_RIGHT)
	_hull_value.add_theme_font_override("font", _title_font)
	var pct := _text(panel, "%", Vector2(238, 26), Vector2(20, 20), 13, SLATE)
	_hull_meter = Meter.new()
	_hull_meter.position = Vector2(16, 62)
	_hull_meter.size = Vector2(290, 6)
	_hull_meter.fill = Color("b8c6c9")
	panel.add_child(_hull_meter)
	_stamina_meter = Meter.new()
	_stamina_meter.position = Vector2(16, 74)
	_stamina_meter.size = Vector2(290, 3)
	_stamina_meter.fill = TEAL
	_stamina_meter.framed = false
	panel.add_child(_stamina_meter)
	_stamina_value = _text(panel, "100", Vector2(256, 82), Vector2(48, 18), 11, TEAL, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(panel, "体力", Vector2(16, 80), Vector2(60, 18), 11, Color(0.55, 0.60, 0.64, 0.85))
	_guard_label = _text(panel, "右键格挡 · 起手可弹反", Vector2(16, 100), Vector2(290, 18), 12, BONE)
	_repair_label = _text(panel, "抢修 ◆◆", Vector2(16, 122), Vector2(130, 18), 12, BRASS)
	_speed_label = _text(panel, "0.0 节", Vector2(176, 122), Vector2(130, 18), 12, SLATE, HORIZONTAL_ALIGNMENT_RIGHT)


func _build_weapon_card() -> void:
	_weapon_card = _panel(_gameplay, Vector2(596, 782), Vector2(408, 88))
	_previous_button = _chip_button(_weapon_card, "‹", Vector2(10, 26), Vector2(44, 38))
	_previous_button.pressed.connect(_emit_action.bind("cycle_previous"))
	_next_button = _chip_button(_weapon_card, "›", Vector2(354, 26), Vector2(44, 38))
	_next_button.pressed.connect(_emit_action.bind("cycle_next"))
	_weapon_icon = _icon(_weapon_card, "ballista", Vector2(66, 20), Vector2(46, 46))
	_text(_weapon_card, "当 前 武 器", Vector2(120, 10), Vector2(180, 16), 10, Color(0.55, 0.60, 0.64, 0.8))
	_weapon_name = _text(_weapon_card, "精确连弩", Vector2(120, 24), Vector2(220, 30), 22, BONE)
	_weapon_name.add_theme_font_override("font", _title_font)
	_weapon_role = _text(_weapon_card, "走射 · 精确打弱点", Vector2(120, 54), Vector2(230, 18), 11, SLATE)
	_weapon_cost = _text(_weapon_card, "体力 7", Vector2(120, 70), Vector2(120, 16), 11, TEAL)
	_weapon_cd = _text(_weapon_card, "就绪", Vector2(246, 30), Vector2(112, 20), 12, BRASS, HORIZONTAL_ALIGNMENT_RIGHT)
	_weapon_cd_meter = Meter.new()
	_weapon_cd_meter.position = Vector2(246, 54)
	_weapon_cd_meter.size = Vector2(112, 3)
	_weapon_cd_meter.fill = BRASS
	_weapon_cd_meter.framed = false
	_weapon_card.add_child(_weapon_cd_meter)


func _build_radar() -> void:
	_radar = TacticalRadar.new()
	_radar.position = Vector2(1370, 636)
	_radar.size = Vector2(200, 200)
	_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gameplay.add_child(_radar)
	_distance_label = _text(_gameplay, "77 m", Vector2(1330, 842), Vector2(280, 22), 15, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_heading_label = _text(_gameplay, "000° / 追猎海域", Vector2(1330, 862), Vector2(280, 18), 11, SLATE, HORIZONTAL_ALIGNMENT_CENTER)


func _build_center_layer() -> void:
	_notice_panel = Panel.new()
	_notice_panel.position = Vector2(470, 636)
	_notice_panel.size = Vector2(660, 40)
	_notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_panel.add_theme_stylebox_override("panel", _style(Color(0.02, 0.03, 0.04, 0.62), Color.TRANSPARENT, 1))
	_gameplay.add_child(_notice_panel)
	_notice_label = _text(_notice_panel, "", Vector2(0, 8), Vector2(660, 26), 17, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_notice_label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.03, 0.92))
	_notice_label.add_theme_constant_override("outline_size", 4)
	_notice_panel.modulate.a = 0.0
	_weak_label = _text(_gameplay, "", Vector2(460, 560), Vector2(680, 24), 14, BRASS, HORIZONTAL_ALIGNMENT_CENTER)
	_weak_label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.03, 0.9))
	_weak_label.add_theme_constant_override("outline_size", 4)
	_action_label = _text(_gameplay, "", Vector2(500, 720), Vector2(600, 22), 14, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_action_label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.03, 0.9))
	_action_label.add_theme_constant_override("outline_size", 4)
	_action_meter = Meter.new()
	_action_meter.position = Vector2(600, 746)
	_action_meter.size = Vector2(400, 3)
	_action_meter.fill = BRASS
	_action_meter.framed = false
	_action_meter.visible = false
	_gameplay.add_child(_action_meter)
	_reticle = AimMarker.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.size = Vector2.ZERO
	_base.add_child(_reticle)
	_range_label = _text(_base, "", Vector2.ZERO, Vector2(180, 18), 11, BLOOD, HORIZONTAL_ALIGNMENT_CENTER)
	_tutorial_rule = ColorRect.new()
	_tutorial_rule.color = Color(0.75, 0.58, 0.36, 0.55)
	_tutorial_rule.position = Vector2(30, 672)
	_tutorial_rule.size = Vector2(2, 34)
	_tutorial_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gameplay.add_child(_tutorial_rule)
	_tutorial_label = _text(_gameplay, "", Vector2(44, 674), Vector2(430, 34), 14, BONE)
	_tutorial_label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.03, 0.9))
	_tutorial_label.add_theme_constant_override("outline_size", 4)
	_tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_label.modulate.a = 0.0
	_tutorial_rule.modulate.a = 0.0
	_threats = ThreatMarkers.new()
	_threats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_base.add_child(_threats)
	# 右上角图标按钮：设置 / 暂停 / 声音
	var settings := _icon_button(_gameplay, "gear", Vector2(1378, 20))
	settings.pressed.connect(_emit_action.bind("settings"))
	var pause := _icon_button(_gameplay, "pause", Vector2(1420, 20))
	pause.pressed.connect(func() -> void: pause_requested.emit())
	var sound := _icon_button(_gameplay, "sound", Vector2(1462, 20))
	sound.pressed.connect(_emit_action.bind("mute"))
	_mute_icon = sound.get_child(0) as Icon
	_text(_gameplay, "猎神号 · 追猎海域", Vector2(30, 20), Vector2(300, 20), 12, BONE)
	_text(_gameplay, "第 一 章 · 雾 海", Vector2(30, 40), Vector2(300, 16), 10, Color(0.55, 0.60, 0.64, 0.8))


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.size = Vector2(1600, 900)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_base.add_child(_overlay)
	_overlay_scrim = ColorRect.new()
	_overlay_scrim.size = Vector2(1600, 900)
	_overlay_scrim.color = Color(1, 1, 1, 1)
	_overlay_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ShaderMaterial.new()
	scrim.shader = preload("res://shaders/scrim.gdshader")
	_overlay_scrim.material = scrim
	_overlay.add_child(_overlay_scrim)
	# 电影黑边
	for edge: int in [0, 1]:
		var bar := ColorRect.new()
		bar.color = Color(0.004, 0.006, 0.008, 0.90)
		bar.position = Vector2(0, 0 if edge == 0 else 868)
		bar.size = Vector2(1600, 32)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.add_child(bar)
		var rule := ColorRect.new()
		rule.color = Color(0.72, 0.56, 0.36, 0.30)
		rule.position = Vector2(0, 32 if edge == 0 else 867)
		rule.size = Vector2(1600, 1)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.add_child(rule)
	_overlay_eyebrow = _text(_overlay, "SEA HUNT", Vector2(112, 150), Vector2(760, 20), 11, BRASS)
	_overlay_title = _text(_overlay, "雾 海 猎 神", Vector2(110, 172), Vector2(820, 78), 58, BONE)
	_overlay_title.add_theme_font_override("font", _title_font)
	_title_rule = ColorRect.new()
	_title_rule.color = Color(0.72, 0.56, 0.36, 0.75)
	_title_rule.position = Vector2(112, 262)
	_title_rule.size = Vector2(210, 1)
	_title_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_title_rule)
	_briefing_body = Control.new()
	_briefing_body.position = Vector2.ZERO
	_briefing_body.size = Vector2(1600, 900)
	_briefing_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_briefing_body)
	var subtitle := _text(_briefing_body, "追 猎 角 渊", Vector2(112, 280), Vector2(400, 26), 17, BRASS)
	var rows := [
		[["WASD", "航行"], ["左键", "攻击"], ["滚轮", "换武器"]],
		[["右键", "格挡"], ["Space", "闪避"], ["R", "抢修 ×2"]],
	]
	for row_index: int in range(rows.size()):
		for cell: int in range(3):
			var at := Vector2(112 + cell * 210, 348 + row_index * 40)
			var pair: Array = rows[row_index][cell]
			_chip(_briefing_body, str(pair[0]), at, 66)
			_text(_briefing_body, str(pair[1]), at + Vector2(78, 2), Vector2(120, 24), 14, BONE)
	var tactic := _text(_briefing_body, "锁定的落点会先在甲板上亮起。移开，再还手。\n近战爪扫可正面格挡；抬掌瞬间格挡即弹反，使巨兽失衡。\n连弩走射、重炮破甲、鱼叉牵制 —— 出手不可取消，不要贪炮。",
		Vector2(112, 456), Vector2(600, 96), 14, Color(0.74, 0.79, 0.82))
	tactic.add_theme_constant_override("line_spacing", 8)
	_primary_button = _button(_overlay, "开 始 狩 猎", Vector2(112, 590), Vector2(260, 56), true)
	_primary_button.pressed.connect(_on_primary)
	_restart_button = _button(_overlay, "重新出航", Vector2(388, 590), Vector2(160, 56))
	_restart_button.pressed.connect(func() -> void: restart_requested.emit())
	_return_button = _button(_overlay, "返 回", Vector2(564, 590), Vector2(120, 56))
	_return_button.pressed.connect(func() -> void: return_requested.emit())
	_result_shade = ColorRect.new()
	_result_shade.size = Vector2(1600, 900)
	_result_shade.color = Color(0.008, 0.012, 0.016, 0.86)
	_result_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_result_shade)
	_overlay.move_child(_result_shade, 2)
	var footer := _text(_briefing_body, "真实追猎海域 · 锁定落点可躲 · 起手弹反 · 抢修仅两次", Vector2(112, 664), Vector2(700, 20), 11, Color(0.52, 0.58, 0.62))
	# 结算面板
	_result_body = Control.new()
	_result_body.position = Vector2.ZERO
	_result_body.size = Vector2(1600, 900)
	_result_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_body.visible = false
	_overlay.add_child(_result_body)
	_result_stats = _text(_result_body, "", Vector2(400, 452), Vector2(800, 40), 15, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	var spacer := ColorRect.new()
	spacer.color = Color(0.72, 0.56, 0.36, 0.45)
	spacer.position = Vector2(700, 432)
	spacer.size = Vector2(200, 1)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_body.add_child(spacer)
	_settings_button_overlay = _button(_overlay, "设置", Vector2(1318, 44), Vector2(96, 32))
	_settings_button_overlay.pressed.connect(_emit_action.bind("settings"))


func _process(delta: float) -> void:
	if not is_instance_valid(_base):
		return
	_layout()
	_notice_remaining = maxf(0.0, _notice_remaining - delta)
	var notice_target: float = 1.0 if _notice_remaining > 0.0 and _overlay_mode == "none" else 0.0
	_notice_panel.modulate.a = move_toward(_notice_panel.modulate.a, notice_target, delta * 6.0)
	_repair_hint_remaining = maxf(0.0, _repair_hint_remaining - delta)
	_tutorial_label.modulate.a = move_toward(_tutorial_label.modulate.a, _tutorial_alpha_target, delta * 2.4)
	_tutorial_rule.modulate.a = _tutorial_label.modulate.a
	_boss_ghost = move_toward(_boss_ghost, _boss_meter.value, delta * 0.34)
	_boss_meter.ghost = _boss_ghost
	_boss_meter.queue_redraw()
	_card_energy = maxf(0.0, _card_energy - delta)
	_weapon_card.modulate.a = lerpf(_weapon_card.modulate.a, 1.0 if _card_energy > 0.0 or _overlay_mode != "none" else 0.82, delta * 5.0)
	_punch_time += delta
	# 数值滚动：船体数字追着真实值跑，掉血时再补一记回弹
	_display_hull = move_toward(_display_hull, _hull_target, delta * 46.0)
	if _hull_punch > 0.0:
		_hull_punch = maxf(0.0, _hull_punch - delta * 1.6)
	var punch: float = sin(_hull_punch * PI) * 0.9
	_hull_value.text = "%d" % roundi(_display_hull)
	_hull_value.scale = Vector2.ONE * (1.0 + punch * 0.14)
	_hull_value.pivot_offset = _hull_value.size * 0.5
	_hull_value.modulate = Color(1.0, 1.0 - punch * 0.35, 1.0 - punch * 0.45) if _hull_punch > 0.0 else (BLOOD if _hull_target < 35.0 else BONE)
	if _weapon_punch > 0.0:
		_weapon_punch = maxf(0.0, _weapon_punch - delta * 3.4)
		_weapon_card.scale = Vector2.ONE * (1.0 + sin(_weapon_punch * PI) * 0.035)
		_weapon_card.pivot_offset = _weapon_card.size * 0.5
	else:
		_weapon_card.scale = Vector2.ONE
	# 弱点窗口的呼吸，只在真的开放时跳
	if _overlay_mode == "none" and not _weak_label.text.is_empty():
		_weak_label.modulate.a = 0.74 + 0.26 * sin(_punch_time * 5.2)
	else:
		_weak_label.modulate.a = 1.0
	_boss_meter.queue_redraw()
	_hull_meter.queue_redraw()
	_stamina_meter.queue_redraw()


func _layout() -> void:
	var dimensions := get_viewport().get_visible_rect().size
	var uniform := minf(maxf(1.0, dimensions.x) / 1600.0, maxf(1.0, dimensions.y) / 900.0)
	_scale = Vector2.ONE * uniform
	_base.scale = _scale
	_base.position = (dimensions - Vector2(1600, 900) * uniform) * 0.5
	if is_instance_valid(_overlay_scrim):
		_overlay_scrim.position = -_base.position / _scale
		_overlay_scrim.size = dimensions / _scale


func update_state(data: Dictionary) -> void:
	if not is_instance_valid(_base):
		return
	var hp := float(data.get("hp", 2400))
	var maximum := maxf(1.0, float(data.get("max_hp", data.get("maxhp", 2400))))
	var hull := float(data.get("hull", 100))
	var stamina := float(data.get("stamina", 100))
	var max_stamina := maxf(1.0, float(data.get("maxstamina", data.get("max_stamina", 100))))
	var charges := int(data.get("repair_charges", 2))
	var selected := str(data.get("weapon", "ballista"))
	if not WEAPON_ORDER.has(selected):
		selected = "ballista"
	var cooldowns: Dictionary = data.get("cooldowns", {})
	var action := str(data.get("action_state", "free"))
	var remaining := float(data.get("action_remaining", 0))
	var total := maxf(0.001, float(data.get("action_total", 1)))
	var guarding := bool(data.get("guarding", action == "guard"))

	_boss_meter.value = clampf(hp / maximum, 0.0, 1.0)
	_boss_meter.queue_redraw()
	_boss_value.text = "%d / %d" % [ceili(maxf(hp, 0.0)), ceili(maximum)]
	_phase_label.text = "Ⅱ · 深 渊 追 猎" if int(data.get("phase", 1)) == 2 else "Ⅰ · 潜 海 之 怒"
	_hull_meter.value = clampf(hull / 100.0, 0.0, 1.0)
	_hull_meter.smooth = clampf(_display_hull / 100.0, 0.0, 1.0)
	_hull_meter.fill = BLOOD if hull < 35.0 else Color("b8c6c9")
	_hull_meter.queue_redraw()
	if absf(hull - _hull_target) > 0.4:
		_hull_punch = 1.0
	_hull_target = maxf(hull, 0.0)
	_stamina_meter.value = clampf(stamina / max_stamina, 0.0, 1.0)
	_stamina_meter.fill = BLOOD if stamina < 25.0 else TEAL
	_stamina_meter.queue_redraw()
	_stamina_value.text = "%d" % ceili(maxf(stamina, 0.0))
	_stamina_value.modulate = BLOOD if stamina < 25.0 else TEAL
	var pips := ""
	for i in range(2):
		pips += "◆" if i < charges else "◇"
	_repair_label.text = "抢修 " + pips
	_speed_label.text = "%.1f 节" % absf(float(data.get("speed", 0)))
	if action == "guard_break":
		_guard_label.text = "破防 · 暂无法防御"
	elif guarding and float(data.get("guard_age", 1)) < 0.2:
		_guard_label.text = "弹反窗口 · 起手瞬间"
	elif guarding:
		_guard_label.text = "格挡中 · 持续消耗体力"
	else:
		_guard_label.text = "右键格挡 · 起手可弹反"
	_guard_label.modulate = BLOOD if action == "guard_break" else TEAL if guarding else BONE

	var index := WEAPON_ORDER.find(selected)
	if str(WEAPON_NAMES[selected]) != _weapon_name.text:
		_weapon_punch = 1.0
		_card_energy = 2.0
	_weapon_name.text = str(WEAPON_NAMES[selected])
	_weapon_role.text = str(WEAPON_ROLES[selected])
	_weapon_icon.kind = selected
	_weapon_icon.queue_redraw()
	_weapon_cost.text = "体力 %d / 次" % int(WEAPON_COSTS.get(selected, 0))
	var cd := float(cooldowns.get(selected, 0.0))
	_weapon_cd.text = "冷却 %.1fs" % cd if cd > 0.0 else "就绪"
	_weapon_cd.modulate = SLATE if cd > 0.0 else BRASS
	_weapon_cd_meter.value = clampf(1.0 - cd / 2.4, 0.0, 1.0)
	_weapon_cd_meter.queue_redraw()
	_previous_button.tooltip_text = str(WEAPON_NAMES[WEAPON_ORDER[posmod(index - 1, 3)]])
	_next_button.tooltip_text = str(WEAPON_NAMES[WEAPON_ORDER[(index + 1) % 3]])
	var locked := action not in ["free", "guard"]
	_previous_button.disabled = locked
	_next_button.disabled = locked

	var actions := {"free": "可行动", "windup": "前摇", "recovery": "恢复", "dodge": "闪避", "guard": "格挡", "guard_break": "破防"}
	var weapons := {"ballista": "连弩", "cannon": "重炮", "harpoon": "鱼叉", "repair": "抢修"}
	var committed := action in ["windup", "recovery", "guard_break"]
	if committed:
		_action_label.text = "%s · %s %.1fs · 不可取消" % [str(weapons.get(str(data.get("action_weapon", "")), "船体")), str(actions.get(action, action)), remaining]
		_action_label.modulate = BRASS_HI
	elif action == "dodge":
		_action_label.text = "闪避中 · 留意落点"
		_action_label.modulate = TEAL
	else:
		_action_label.text = ""
	_action_meter.visible = committed or action == "dodge"
	_action_meter.value = clampf(1.0 - remaining / total, 0.0, 1.0)
	_action_meter.queue_redraw()

	var attack := str(data.get("attack", "idle"))
	var boss_state := str(data.get("boss_state", "idle"))
	var attacks := {
		"meteor": "陨星坠海 · 锁点后移出落区", "meteorite": "陨星坠海 · 锁点后移出落区",
		"lightning": "断潮雷击 · 连续移开雷点", "thunder": "断潮雷击 · 连续移开雷点",
		"lunge": "巨兽扑击 · 横移避开走廊", "charge": "巨兽扑击 · 横移避开走廊",
		"cleave": "碎浪爪 · 退离 / 格挡 / 弹反", "claw": "碎浪爪 · 退离 / 格挡 / 弹反",
	}
	var states := {"idle": "游弋", "chase": "追猎逼近", "pursuit": "追猎逼近", "windup": "锁定蓄力", "active": "招式释放", "recovery": "恢复窗口", "stagger": "失衡窗口"}
	_attack_label.text = str(attacks.get(attack, "保持机动")) + "   /   " + str(states.get(boss_state, boss_state))
	_attack_label.modulate = VIOLET
	_windup_meter.visible = boss_state == "windup" or float(data.get("windup", 0.0)) > 0.0
	_windup_meter.value = clampf(float(data.get("windup", 0.0)), 0.0, 1.0)
	_windup_meter.queue_redraw()
	var meteor := _nearest_meteor(data.get("attacks", []))
	if not meteor.is_empty():
		var meteor_age := float(meteor.get("age", 0))
		var delay := float(meteor.get("delay", 1.9))
		var lock_age := float(meteor.get("lock_age", maxf(0.0, delay - 1.05)))
		var tracking := bool(meteor.get("tracking", false)) and not bool(meteor.get("locked", false))
		if meteor_age >= delay:
			_attack_label.text = "陨星坠海 · 落地冲击"
		elif tracking:
			_attack_label.text = "预瞄跟随 · %.1fs 后锁定落点" % maxf(0.0, lock_age - meteor_age)
		else:
			_attack_label.text = "落点已定 · %.1fs 后坠落" % maxf(0.0, delay - meteor_age)
		_attack_label.modulate = SLATE if tracking else BRASS_HI
		_windup_meter.visible = meteor_age < delay
		_windup_meter.value = clampf(meteor_age / maxf(lock_age, 0.001), 0.0, 1.0) if tracking else clampf((meteor_age - lock_age) / maxf(delay - lock_age, 0.001), 0.0, 1.0)
		_windup_meter.queue_redraw()

	var window_open := bool(data.get("weak", false))
	_reticle.in_range = bool(data.get("aim_in_range", true))
	_reticle.hit = bool(data.get("aim_hit", false)) and _reticle.in_range
	_reticle.weak = _reticle.hit and bool(data.get("aim_weak", false)) and window_open
	_reticle.flash = clampf(float(data.get("hit_flash", 0.0)), 0.0, 1.0)
	var aim: Vector2 = data.get("aim", get_viewport().get_visible_rect().size * 0.5)
	_reticle.position = (aim - _base.position) / _scale
	_reticle.visible = _overlay_mode == "none"
	_reticle.queue_redraw()
	var aim_distance := float(data.get("aim_distance", -1.0))
	_range_label.text = "超出射程" if not _reticle.in_range and is_finite(aim_distance) and aim_distance > 0.0 else ""
	_range_label.position = Vector2(clampf(_reticle.position.x - 90, 6, 1414), clampf(_reticle.position.y + 26, 6, 872))
	_range_label.visible = _overlay_mode == "none"
	_threats.threats = data.get("threats", [])
	_threats.queue_redraw()
	var tether := float(data.get("tether_remaining", 0.0))
	if window_open and tether > 0.0:
		_weak_label.text = "弱 点 开 放 　·　 牵 制 %.1fs" % tether
	elif window_open:
		_weak_label.text = "弱 点 开 放 　·　 反 击 窗 口"
	elif tether > 0.0:
		_weak_label.text = "牵 制 %.1fs 　·　 追击减缓" % tether
	else:
		_weak_label.text = ""
	_hit_shade.color.a = clampf(float(data.get("damage_flash", 0.0)), 0.0, 1.0) * 0.12
	_update_tutorial(data)
	if is_instance_valid(_mute_icon):
		var muted := bool(data.get("muted", false))
		if (_mute_icon.kind == "mute") != muted:
			_mute_icon.kind = "mute" if muted else "sound"
			_mute_icon.queue_redraw()
	_last_data = data
	_radar.ship_pos = data.get("ship_pos", Vector2(0, 85))
	_radar.boss_pos = data.get("boss_pos", Vector2.ZERO)
	_radar.heading = float(data.get("heading", 0.0))
	_radar.boss_facing = float(data.get("boss_facing", 0.0))
	_radar.attacks = data.get("attacks", [])
	_radar.arena_radius = float(data.get("arena_radius", 420))
	_radar.queue_redraw()
	var boss_distance := float(data.get("bossdistance", data.get("boss_distance", _radar.ship_pos.distance_to(_radar.boss_pos))))
	_distance_label.text = "%d m" % roundi(boss_distance)
	_heading_label.text = "%03d° / 海域 %dm" % [posmod(roundi(rad_to_deg(_radar.heading)), 360), roundi(_radar.arena_radius)]
	var message := str(data.get("notice", ""))
	if message != _last_notice:
		_last_notice = message
		if not message.is_empty():
			show_notice(message)


func _nearest_meteor(descriptors: Array) -> Dictionary:
	var next: Dictionary = {}
	var active: Dictionary = {}
	var nearest := INF
	for descriptor: Dictionary in descriptors:
		if str(descriptor.get("kind", "")) not in ["meteor", "meteorite"] or bool(descriptor.get("cancelled", false)):
			continue
		var age := float(descriptor.get("age", 0.0))
		var delay := float(descriptor.get("delay", 1.9))
		if age >= delay + float(descriptor.get("active", 0.24)):
			continue
		var eta := delay - age
		if eta > 0.0 and eta < nearest:
			nearest = eta
			next = descriptor
		elif eta <= 0.0:
			active = descriptor
	return next if not next.is_empty() else active


func _update_tutorial(data: Dictionary) -> void:
	var progress: Dictionary = data.get("tutorial_progress", {})
	var keys := ["moved", "fired", "switched", "dodged", "guarded"]
	var hints := ["WASD 航行，先移开甲板上的落点", "左键发射当前武器；留意出手与恢复", "滚轮每格换一档：连弩 / 重炮 / 鱼叉", "Space 闪避；前摇与恢复不可取消", "右键按住格挡，起手瞬间可弹反"]
	var step := keys.size()
	for i in range(keys.size()):
		if not bool(progress.get(keys[i], false)):
			step = i
			break
	_tutorial_step = step
	var hull := float(data.get("hull", 100))
	var charges := int(data.get("repair_charges", 2))
	if hull >= 99.0 and charges == 2:
		_repair_hint_shown = false
	var cooldowns: Dictionary = data.get("cooldowns", {})
	if hull <= 45.0 and charges > 0 and float(cooldowns.get("repair", 0.0)) <= 0.0 and not _repair_hint_shown:
		_repair_hint_shown = true
		_repair_hint_remaining = 5.0
	if _repair_hint_remaining > 0.0 and hull <= 45.0 and charges > 0:
		_tutorial_label.text = "船体告急 · R 抢修（剩 %d 次），先脱离落区" % charges
		_tutorial_alpha_target = 1.0
	elif step < keys.size():
		_tutorial_label.text = str(hints[step])
		_tutorial_alpha_target = 1.0
	else:
		_tutorial_alpha_target = 0.0
	_tutorial_label.visible = _overlay_mode == "none"


func set_overlay(mode: String) -> void:
	if not is_instance_valid(_overlay):
		return
	_overlay_mode = mode
	_overlay.visible = mode != "none"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE if mode == "none" else Control.MOUSE_FILTER_STOP
	_reticle.visible = mode == "none"
	if mode == "none" and not _was_gameplay:
		_gameplay.modulate.a = 0.0
		var enter := create_tween()
		enter.tween_property(_gameplay, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_reticle.scale = Vector2.ONE * 1.9
		var pop := create_tween()
		pop.tween_property(_reticle, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_gameplay.modulate.a = 1.0 if mode == "none" else 0.0
	_was_gameplay = mode == "none"
	_range_label.visible = mode == "none"
	_tutorial_label.visible = mode == "none"
	_tutorial_rule.visible = mode == "none"
	_threats.visible = mode == "none"
	var result_mode := mode in ["victory", "defeat"]
	_briefing_body.visible = mode in ["briefing", "paused"]
	_result_body.visible = result_mode
	_result_shade.visible = result_mode
	_overlay_scrim.visible = not result_mode
	_title_rule.visible = not result_mode
	_primary_button.visible = mode != "none"
	_restart_button.visible = mode == "paused"
	_return_button.visible = mode in ["briefing", "paused", "victory", "defeat"]
	_primary_button.disabled = false
	_primary_button.size = Vector2(260, 56) if mode == "briefing" else Vector2(220, 56)
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if result_mode else HORIZONTAL_ALIGNMENT_LEFT
	_overlay_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if result_mode else HORIZONTAL_ALIGNMENT_LEFT
	_overlay_eyebrow.size = Vector2(1020, 20) if result_mode else Vector2(760, 20)
	_overlay_eyebrow.position = Vector2(290, 150) if result_mode else Vector2(112, 150)
	_overlay_title.size = Vector2(1020, 78) if result_mode else Vector2(820, 78)
	if result_mode:
		_refresh_result()
	match mode:
		"briefing":
			_overlay_eyebrow.text = "SEA HUNT   ·   第 一 章   雾 海"
			_overlay_title.text = "雾 海 猎 神"
			_overlay_title.position = Vector2(110, 172)
			_primary_button.text = "开 始 狩 猎"
			_primary_button.position = Vector2(112, 590)
			_restart_button.position = Vector2(388, 590)
			_return_button.position = Vector2(564, 590)
		"paused":
			_overlay_eyebrow.text = "SUSPENDED   ·   战 斗 已 暂 停"
			_overlay_title.text = "风 浪 暂 歇"
			_overlay_title.position = Vector2(110, 172)
			_primary_button.text = "继 续 战 斗"
			_primary_button.position = Vector2(112, 590)
			_restart_button.position = Vector2(348, 590)
			_return_button.position = Vector2(524, 590)
		"victory":
			_overlay_eyebrow.text = "VICTORY   ·   深 海 回 应 了 炮 火"
			_overlay_title.text = "角 渊 已 沉"
			_overlay_title.position = Vector2(290, 208)
			_primary_button.text = "再 次 出 航"
			_primary_button.position = Vector2(560, 540)
			_restart_button.position = Vector2(836, 540)
			_return_button.position = Vector2(836, 540)
		"defeat":
			_overlay_eyebrow.text = "LOST   ·   猎 神 号 未 能 归 航"
			_overlay_title.text = "未 能 归 航"
			_overlay_title.position = Vector2(290, 208)
			_primary_button.text = "再 次 出 航"
			_primary_button.position = Vector2(560, 540)
			_restart_button.position = Vector2(836, 540)
			_return_button.position = Vector2(836, 540)
	if mode == "briefing":
		set_preparing(_preparing)


func set_result(stats: Dictionary) -> void:
	_result_data = stats
	_refresh_result()


func _refresh_result() -> void:
	if not is_instance_valid(_result_stats):
		return
	var elapsed := float(_result_data.get("time", 0.0))
	var minutes := int(elapsed) / 60
	var seconds := int(elapsed) % 60
	var hull := float(_result_data.get("hull", 0.0))
	var repairs := int(_result_data.get("repairs", 0))
	var boss := float(_result_data.get("boss_hp", 0.0))
	var maximum := maxf(1.0, float(_result_data.get("max_hp", 1.0)))
	_result_stats.text = "历 战 %d:%02d　　·　　剩 余 船 体 %d%%　　·　　抢 修 %d 次　　·　　残 留 敌 血 %d%%" % [
		minutes, seconds, roundi(hull), repairs, roundi(boss / maximum * 100.0)]


func set_preparing(enabled: bool) -> void:
	_preparing = enabled
	if not is_instance_valid(_primary_button) or _overlay_mode != "briefing":
		return
	_primary_button.disabled = enabled
	_primary_button.text = "准 备 海 域 …" if enabled else "开 始 狩 猎"


func show_damage(amount: float, screen_pos: Vector2, critical: bool, armored: bool = false) -> void:
	if not is_instance_valid(_base):
		return
	var caption := ("破核 " if critical else "鳞甲 " if armored else "") + str(roundi(amount))
	var color := BRASS_HI if critical else Color("8fa4b0") if armored else BONE
	var label := _text(_base, caption, (screen_pos - _base.position) / _scale - Vector2(90, 20), Vector2(180, 40),
		30 if critical else 20, color, HORIZONTAL_ALIGNMENT_CENTER)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.92))
	label.add_theme_constant_override("shadow_offset_y", 2)
	if critical:
		label.add_theme_font_override("font", _title_font)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 68.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)


func show_notice(message: String) -> void:
	if not is_instance_valid(_notice_label):
		return
	_notice_label.text = message
	_notice_remaining = 3.2
	_notice_panel.position.y = 644.0
	create_tween().tween_property(_notice_panel, "position:y", 636.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _overlay_mode == "none":
		_notice_panel.modulate.a = 1.0


func _on_primary() -> void:
	if _overlay_mode == "briefing":
		if _preparing:
			return
		start_requested.emit()
	elif _overlay_mode == "paused":
		pause_requested.emit()
	elif _overlay_mode in ["victory", "defeat"]:
		restart_requested.emit()


func _emit_action(action: String) -> void:
	action_requested.emit(action)


func _style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 6
	style.content_margin_right = 6
	return style


func _panel(parent: Node, at: Vector2, dimensions: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = at
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(Color(0.016, 0.026, 0.034, 0.80), Color(0.72, 0.58, 0.38, 0.34), 0))
	parent.add_child(panel)
	var hairline := ColorRect.new()
	hairline.color = Color(1.0, 0.95, 0.86, 0.14)
	hairline.position = Vector2(1, 0)
	hairline.size = Vector2(dimensions.x - 2, 1)
	hairline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hairline)
	return panel


func _text(parent: Node, text: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, at: Vector2, dimensions: Vector2, emphasis: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = dimensions
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16 if emphasis else 14)
	if emphasis:
		button.add_theme_color_override("font_color", Color("140e08"))
		button.add_theme_color_override("font_hover_color", Color("0b0703"))
		button.add_theme_stylebox_override("normal", _style(Color(0.75, 0.59, 0.36, 1.0), Color(0.92, 0.78, 0.55, 1.0), 0))
		button.add_theme_stylebox_override("hover", _style(Color(0.86, 0.70, 0.45, 1.0), Color(1.0, 0.90, 0.70, 1.0), 0))
		button.add_theme_stylebox_override("pressed", _style(Color(0.64, 0.49, 0.29, 1.0), Color(1.0, 0.90, 0.70, 1.0), 0))
		button.add_theme_stylebox_override("disabled", _style(Color(0.34, 0.28, 0.19, 0.85), Color(0.5, 0.42, 0.3, 0.6), 0))
		button.add_theme_color_override("font_disabled_color", Color(0.72, 0.65, 0.55, 0.8))
	else:
		button.add_theme_stylebox_override("normal", _style(Color(0.02, 0.03, 0.04, 0.78), Color(0.62, 0.52, 0.38, 0.42), 0))
		button.add_theme_stylebox_override("hover", _style(Color(0.07, 0.09, 0.10, 0.94), Color(0.78, 0.63, 0.42, 0.95), 0))
		button.add_theme_stylebox_override("pressed", _style(Color(0.10, 0.12, 0.13, 0.96), BRASS_HI, 0))
	parent.add_child(button)
	button.pivot_offset = dimensions * 0.5
	button.mouse_entered.connect(func() -> void:
		create_tween().tween_property(button, "modulate", Color(1.14, 1.12, 1.06, 1.0), 0.12))
	button.mouse_exited.connect(func() -> void:
		create_tween().tween_property(button, "modulate", Color.WHITE, 0.16))
	return button


func _chip_button(parent: Node, text: String, at: Vector2, dimensions: Vector2) -> Button:
	var button := _button(parent, text, at, dimensions, false)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", SLATE)
	return button


func _chip(parent: Node, text: String, at: Vector2, width: float) -> void:
	var frame := Panel.new()
	frame.position = at
	frame.size = Vector2(width, 26)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _style(Color(0.03, 0.04, 0.05, 0.70), Color(0.70, 0.56, 0.36, 0.55), 1))
	parent.add_child(frame)
	var label := _text(frame, text, Vector2.ZERO, Vector2(width, 26), 12, BRASS_HI, HORIZONTAL_ALIGNMENT_CENTER)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _icon(parent: Control, kind: String, at: Vector2, dimensions: Vector2) -> Icon:
	var icon := Icon.new()
	icon.kind = kind
	icon.position = at
	icon.size = dimensions
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon


func _icon_button(parent: Control, kind: String, at: Vector2) -> Button:
	var button := Button.new()
	button.position = at
	button.size = Vector2(38, 34)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _style(Color(0.02, 0.03, 0.04, 0.62), Color(0.60, 0.50, 0.36, 0.30), 0))
	button.add_theme_stylebox_override("hover", _style(Color(0.07, 0.09, 0.10, 0.92), Color(0.78, 0.63, 0.42, 0.95), 0))
	button.add_theme_stylebox_override("pressed", _style(Color(0.10, 0.12, 0.13, 0.96), BRASS_HI, 0))
	parent.add_child(button)
	_icon(button, kind, Vector2(3, 3), Vector2(32, 28))
	return button
