class_name HotbarSlot
extends Control
## ホットバーの1枠。暗い半透明の四角に細い線。選んでいる枠は金の縁と下線で、少し大きくなる。
## 貸出中はアイコンを薄くして「貸出」と書く。禁止は赤い角の印と「禁止」の文字（色だけに頼らない）。

const SIZE := Vector2(76, 76)

var slot_index: int = 0
var selected: bool = false
var token: RuleToken

var _grow: float = 0.0


func _ready() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = SIZE * 0.5


func show_token(new_token: RuleToken, is_selected: bool) -> void:
	token = new_token
	if is_selected != selected:
		selected = is_selected
		var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(self, "scale", Vector2.ONE * (1.08 if selected else 1.0), UiTheme.FAST)
	queue_redraw()


## 状態を文字で（テスト・読み上げ用）。
func describe() -> String:
	if token == null:
		return "%d: 空" % (slot_index + 1)
	var state := ""
	if token.is_lent():
		state = "・貸出中（%s）" % TriggerMode.label(token.mode)
	elif token.is_prohibition:
		state = "・適用中"
	return "%d: %s%s" % [slot_index + 1, item_name(), state]


func item_name() -> String:
	if token == null:
		return ""
	return ("%s禁止" if token.is_prohibition else "%s") % RuleAction.label(token.action)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, SIZE)
	var fill := Color(UiTheme.SURFACE, 0.86 if selected else 0.7)
	var border := UiTheme.ACCENT if selected else UiTheme.LINE
	var box := UiTheme.surface_box(fill, border, UiTheme.RADIUS, 0.0)
	box.set_border_width_all(2 if selected else 1)
	draw_style_box(box, rect)
	if selected:
		draw_rect(
			Rect2(Vector2(SIZE.x * 0.3, SIZE.y + 6), Vector2(SIZE.x * 0.4, 2)), UiTheme.ACCENT
		)
	draw_string(
		UiTheme.font(600),
		Vector2(7, 16),
		str(slot_index + 1),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		UiTheme.ACCENT if selected else UiTheme.TEXT_FAINT
	)
	if token == null:
		return
	var icon_rect := Rect2(Vector2((SIZE.x - 46) * 0.5, 12), Vector2(46, 46))
	var lent := token.is_lent()
	draw_texture_rect(
		ItemIcons.for_token(token), icon_rect, false, Color(1, 1, 1, 0.35 if lent else 1.0)
	)
	if lent:
		_draw_tag("貸出", UiTheme.ACCENT)
	elif token.is_prohibition:
		_draw_tag("禁止", UiTheme.ALERT)
		var corner := PackedVector2Array(
			[Vector2(SIZE.x - 14, 1), Vector2(SIZE.x - 1, 1), Vector2(SIZE.x - 1, 14)]
		)
		draw_colored_polygon(corner, UiTheme.ALERT)


func _draw_tag(text: String, color: Color) -> void:
	draw_string(
		UiTheme.font(700, 1),
		Vector2(0, SIZE.y - 6),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		SIZE.x,
		11,
		color
	)
