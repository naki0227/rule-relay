class_name ModeBadge
extends Control
## ホットバーの右に置く、いまの発動方式と届き方の小さな印（記号だけ。切り替えた直後だけ名前を出す）。

var mode: TriggerMode.Kind = TriggerMode.Kind.SINGLE_SHOT
var throw_mode: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(124, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_state(new_mode: TriggerMode.Kind, new_throw: bool) -> void:
	mode = new_mode
	throw_mode = new_throw
	queue_redraw()


func _draw() -> void:
	var box := UiTheme.pill_box(Color(UiTheme.CREAM, 0.92), UiTheme.EDGE)
	draw_style_box(box, Rect2(Vector2.ZERO, size))
	var left := Vector2(size.x * 0.28, size.y * 0.5)
	var right := Vector2(size.x * 0.72, size.y * 0.5)
	UiGlyphs.draw_mode(self, left, 30.0, mode, UiTheme.INK)
	UiGlyphs.draw_reach(self, right, 30.0, throw_mode, UiTheme.INK)
	draw_line(
		Vector2(size.x * 0.5, 16), Vector2(size.x * 0.5, size.y - 16), UiTheme.EDGE, UiTheme.LINE
	)
