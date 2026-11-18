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
	draw_circle(center, RADIUS + 34.0, Color(0.05, 0.05, 0.08, 0.72))
	draw_arc(center, RadialSelector.DEADZONE, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0)
	var picked := picked_index()
	var font := get_theme_default_font()
	var count := RadialSelector.MODES.size()
	for i in count:
		var mode := RadialSelector.MODES[i]
		var dir := Vector2.from_angle(RadialSelector.option_angle(i, count))
		var spot := center + dir * RADIUS * 0.72
		var supported := TriggerMode.is_supported(mode)
		var fill := Color(0.8, 0.15, 0.15, 0.9) if i == picked else Color(0.25, 0.25, 0.3, 0.9)
		if not supported:
			fill = fill.darkened(0.5)
		draw_circle(spot, 48.0, fill)
		if mode == current_mode:
			draw_arc(spot, 50.0, 0.0, TAU, 32, Color(1.0, 0.9, 0.4), 4.0)
		var text := TriggerMode.label(mode)
		if i == picked:
			text = "▶" + text
		if not supported:
			text += "\n(P1)"
		draw_multiline_string(
			font, spot + Vector2(-50, -2), text, HORIZONTAL_ALIGNMENT_CENTER, 100.0, 16
		)
	draw_line(center, center + offset, Color(1, 1, 1, 0.8), 3.0)
	draw_circle(center + offset, 6.0, Color.WHITE)
