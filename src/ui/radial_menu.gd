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


## ゲームパッドの右スティック: 倒した向き（長さ 0〜1）をそのまま選ぶ位置にする。
func point(direction: Vector2) -> void:
	offset = direction.limit_length(1.0) * MAX_DRAG
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
	# 生成りの丸い札を3つの区画に分け、選ぼうとしている区画を夕日色にする
	draw_circle(center + Vector2(0, 6), outer + 4.0, UiTheme.SHADOW)
	draw_circle(center, outer + 4.0, UiTheme.EDGE)
	for i in count:
		var mid := RadialSelector.option_angle(i, count)
		var span := TAU / count
		var arc := _sector(center, inner, outer, mid - span * 0.5 + 0.03, mid + span * 0.5 - 0.03)
		var supported := TriggerMode.is_supported(RadialSelector.MODES[i])
		var fill := UiTheme.CREAM
		if i == picked and supported:
			fill = UiTheme.SUN_SOFT
		elif not supported:
			fill = UiTheme.CREAM_DEEP
		draw_colored_polygon(arc, fill)
		if i == picked and supported:
			var outline := arc.duplicate()
			outline.append(arc[0])
			draw_polyline(outline, UiTheme.SUN, 3.0, true)
	draw_circle(center, inner - 4.0, UiTheme.CREAM)
	draw_arc(center, inner - 4.0, 0, TAU, 48, UiTheme.EDGE, UiTheme.LINE, true)
	for i in count:
		var mode := RadialSelector.MODES[i]
		var dir := Vector2.from_angle(RadialSelector.option_angle(i, count))
		var spot := center + dir * (inner + outer) * 0.5
		var supported := TriggerMode.is_supported(mode)
		var ink := UiTheme.INK if supported else UiTheme.INK_FAINT
		UiGlyphs.draw_mode(self, spot + Vector2(0, -14), 34.0, mode, ink)
		var label := TriggerMode.label(mode) if supported else "%s（まだ）" % TriggerMode.label(mode)
		draw_string(
			UiTheme.bold(),
			spot + Vector2(-70, 28),
			label,
			HORIZONTAL_ALIGNMENT_CENTER,
			140.0,
			UiTheme.SIZE_SMALL,
			ink
		)
		if mode == current_mode:
			draw_circle(spot + Vector2(0, -42), 5.0, UiTheme.LEAF)
	draw_line(center, center + offset, Color(UiTheme.SUN, 0.9), 3.0, true)
	draw_circle(center + offset, 6.0, UiTheme.SUN)


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
