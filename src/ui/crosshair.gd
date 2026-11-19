class_name Crosshair
extends Control
## 照準: 普段は小さな生成りの点。届く距離のブロックを狙うと、夕日色の輪がふわっと開く。

enum Aim { NONE, OUT_OF_REACH, IN_REACH }

var aim: Aim = Aim.NONE
var _ring: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(48, 48)


func set_aim(value: Aim) -> void:
	if value == aim:
		return
	aim = value
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_method(_set_ring, _ring, 1.0 if aim == Aim.IN_REACH else 0.0, UiTheme.NORMAL)


func _set_ring(value: float) -> void:
	_ring = value
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var dot := UiTheme.INK_FAINT if aim == Aim.OUT_OF_REACH else UiTheme.INK
	draw_circle(center, 5.0, Color(UiTheme.CREAM, 0.95))
	draw_circle(center, 2.6, dot)
	if _ring > 0.01:
		var radius := lerpf(6.0, 15.0, _ring)
		draw_arc(center, radius, 0, TAU, 48, Color(UiTheme.CREAM, 0.9 * _ring), 5.0, true)
		draw_arc(center, radius, 0, TAU, 48, Color(UiTheme.SUN, _ring), 2.5, true)
