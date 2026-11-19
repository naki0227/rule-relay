class_name HotbarSlot
extends Control
## HUD のホットバーの1枠。見た目は ItemPainter で、持ち物の画面とそろえる。
## 選んでいる枠は少し大きく浮き上がり、夕日色の縁になる。ほかの枠は控えめにする。

const SIZE := Vector2(80, 80)

var slot_index: int = 0
var selected: bool = false
var token: RuleToken


func _ready() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = Vector2(SIZE.x * 0.5, SIZE.y)


func show_token(new_token: RuleToken, is_selected: bool) -> void:
	token = new_token
	if is_selected != selected:
		selected = is_selected
		var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(
			self, "scale", Vector2.ONE * (1.12 if selected else 1.0), UiTheme.NORMAL
		)
	modulate.a = 1.0 if selected else 0.86
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
	var style := ItemPainter.Style.new()
	style.selected = selected
	style.number = slot_index + 1
	style.compact = true
	ItemPainter.draw_slot(self, Rect2(Vector2.ZERO, SIZE), token, style)
