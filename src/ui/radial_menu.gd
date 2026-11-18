class_name RadialMenu
extends Control
## 画面右側に出す円形の発動方式メニュー（企画書 8: ホイール押し込み＋ドラッグ）。
## 描画だけを受け持ち、どれを選ぶかは RadialSelector が決める。
## 色だけで区別しないよう、各項目に文字を書き、選択中は太い縁と「▶」を付ける。

const RADIUS: float = 120.0
const MAX_DRAG: float = 140.0

var offset: Vector2 = Vector2.ZERO
var current_mode: TriggerMode.Kind = TriggerMode.Kind.SINGLE_SHOT


func open(mode: TriggerMode.Kind) -> void:
	offset = Vector2.ZERO
	current_mode = mode
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func drag(relative: Vector2) -> void:
	offset = (offset + relative).limit_length(MAX_DRAG)
	queue_redraw()


## 今の位置で離したときに選ばれる方式。選ばない場合は -1。
func picked_index() -> int:
	return RadialSelector.pick(offset, RadialSelector.MODES.size())


func _draw() -> void:
	var center := size * 0.5
	var count := RadialSelector.MODES.size()
	var picked := picked_index()
	var outer := RADIUS + 30.0
	var inner := RadialSelector.DEADZONE + 8.0
	# 暗い半透明のリング。方式ごとに扇形の区画を描き、選ばれている区画を金で満たす
	draw_circle(center, outer + 2.0, Color(0, 0, 0, 0.25))
	for i in count:
		var mid := RadialSelector.option_angle(i, count)
		var span := TAU / count
		var arc := _sector(center, inner, outer, mid - span * 0.5 + 0.02, mid + span * 0.5 - 0.02)
		var supported := TriggerMode.is_supported(RadialSelector.MODES[i])
		var fill := UiTheme.SURFACE_SOLID
		if i == picked and supported:
			fill = Color(UiTheme.ACCENT, 0.85)
		elif i == picked:
			fill = Color(1, 1, 1, 0.12)
		draw_colored_polygon(arc, fill)
		var outline := arc.duplicate()
		outline.append(arc[0])
		draw_polyline(outline, UiTheme.LINE, 1.0, true)
	draw_circle(center, inner - 6.0, UiTheme.SURFACE_SOLID)
	draw_arc(center, inner - 6.0, 0, TAU, 48, UiTheme.LINE, 1.0, true)
	var title_font := UiTheme.font(700, 1)
	var small := UiTheme.font(500)
	for i in count:
		var mode := RadialSelector.MODES[i]
		var dir := Vector2.from_angle(RadialSelector.option_angle(i, count))
		var spot := center + dir * (inner + outer) * 0.5
		var supported := TriggerMode.is_supported(mode)
		var ink := UiTheme.TEXT
		if i == picked and supported:
			ink = Color("#1b1a17")
		elif not supported:
			ink = UiTheme.TEXT_FAINT
		draw_string(
			title_font,
			spot + Vector2(-60, 6),
			TriggerMode.label(mode),
			HORIZONTAL_ALIGNMENT_CENTER,
			120.0,
			20,
			ink
		)
		var note := ""
		if mode == current_mode:
			note = "使用中"
		if not supported:
			note = "P1 で追加"
		if not note.is_empty():
			draw_string(
				small,
				spot + Vector2(-60, 26),
				note,
				HORIZONTAL_ALIGNMENT_CENTER,
				120.0,
				12,
				Color(ink, 0.75)
			)
	# 中心: いま選ぼうとしている方式の説明
	var hint := "ドラッグして選ぶ"
	if picked >= 0:
		hint = _describe(RadialSelector.MODES[picked])
	draw_string(
		small,
		center + Vector2(-34, 5),
		hint,
		HORIZONTAL_ALIGNMENT_CENTER,
		68.0,
		11,
		UiTheme.TEXT_DIM
	)
	draw_line(center, center + offset, Color(UiTheme.ACCENT, 0.8), 1.5, true)
	draw_circle(center + offset, 4.0, UiTheme.ACCENT)


func _describe(mode: TriggerMode.Kind) -> String:
	match mode:
		TriggerMode.Kind.SINGLE_SHOT:
			return "キーで1回"
		TriggerMode.Kind.REPEAT:
			return "自動で反復"
		TriggerMode.Kind.SIGNAL:
			return "音で動く"
	return ""


func _sector(center: Vector2, r0: float, r1: float, a0: float, a1: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := 24
	for k in steps + 1:
		points.append(center + Vector2.from_angle(lerpf(a0, a1, float(k) / steps)) * r1)
	for k in range(steps, -1, -1):
		points.append(center + Vector2.from_angle(lerpf(a0, a1, float(k) / steps)) * r0)
	return points
