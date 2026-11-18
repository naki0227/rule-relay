class_name Crosshair
extends Control
## 照準: 普段は小さな点だけ。届く距離のブロックを狙うと金の輪が開き、操作できることが分かる。
## 届かないブロックでは点が薄くなる。

enum Aim { NONE, OUT_OF_REACH, IN_REACH }

var aim: Aim = Aim.NONE
var _ring: float = 0.0  # 0 = 輪なし、1 = 開いた輪


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(48, 48)


func set_aim(value: Aim) -> void:
	if value == aim:
		return
	aim = value
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(_set_ring, _ring, 1.0 if aim == Aim.IN_REACH else 0.0, UiTheme.FAST)


func _set_ring(value: float) -> void:
	_ring = value
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var dot := UiTheme.TEXT_FAINT if aim == Aim.OUT_OF_REACH else UiTheme.TEXT
	draw_circle(center, 3.4, UiTheme.TEXT_SHADOW)
	draw_circle(center, 2.2, dot)
	if _ring > 0.01:
		var radius := lerpf(6.0, 13.0, _ring)
		var color := Color(UiTheme.ACCENT, _ring)
		draw_arc(center, radius, 0, TAU, 48, Color(0, 0, 0, 0.35 * _ring), 3.5, true)
		draw_arc(center, radius, 0, TAU, 48, color, 1.5, true)
