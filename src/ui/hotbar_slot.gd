class_name HotbarSlot
extends Control
## HUD のホットバーの1枠。見た目は ItemPainter で、持ち物の画面とそろえる。
## 選んでいる枠は少し大きく浮き上がり、夕日色の縁になる。ほかの枠は控えめにする。

const SIZE := Vector2(80, 80)

var slot_index: int = 0
var selected: bool = false
var token: RuleToken
## 装備品なら、その名前（例: ジャンプブーツ）。装備の姿で描く。普通の器は空。
var equipment_name: String = ""
## 同じ能力をいくつ持っているか（2以上なら「×n」を出す）。
var stack: int = 0:
	set(value):
		if value != stack:
			stack = value
			queue_redraw()

## 足もとのブロックの禁止で、いまは使えない（乗っている間だけ。薄くして小さな禁止の印を付ける）。
var floor_banned: bool = false:
	set(value):
		if value != floor_banned:
			floor_banned = value
			queue_redraw()


func _ready() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = Vector2(SIZE.x * 0.5, SIZE.y)


func show_token(new_token: RuleToken, is_selected: bool, item: RuleVessel = null) -> void:
	token = new_token
	equipment_name = ""
	if item != null and item.is_equipment():
		equipment_name = item.item_name if item.item_name != "" else RuleAction.label(token.action)
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
	if equipment_name != "":
		state = "・空（中の能力を貸出中）" if not token.is_in_vessel() else "・装備していない"
	elif not token.is_in_vessel():
		state = "・貸出中（%s）" % TriggerMode.label(token.mode)
	elif token.is_prohibition:
		state = "・適用中"
	if floor_banned:
		state += "・足もとの禁止で使えない"
	return "%d: %s%s" % [slot_index + 1, item_name(), state]


func item_name() -> String:
	if token == null:
		return ""
	if equipment_name != "":
		return equipment_name
	return ("%s禁止" if token.is_prohibition else "%s") % RuleAction.label(token.action)


## 枠を選んだときに一瞬出す名前。装備品は、ホットバーでは効かないことと、つけ方を短く添える。
func flash_text() -> String:
	if token == null:
		return "からっぽ"
	if equipment_name == "":
		return item_name()
	if not token.is_in_vessel():
		return "%s（空。%s で中の能力を回収）" % [equipment_name, InputMode.key(&"interact")]
	return "%s（つけると効く。%s →「そうびする」）" % [equipment_name, InputMode.key(&"inventory")]


func _draw() -> void:
	var style := ItemPainter.Style.new()
	style.selected = selected
	style.number = slot_index + 1
	style.compact = true
	style.equipment = equipment_name != ""
	ItemPainter.draw_slot(self, Rect2(Vector2.ZERO, SIZE), token, style)
	if floor_banned:
		# 控えめに: 枠全体を紙の色で薄く覆い、左下に小さな禁止の印
		draw_rect(Rect2(Vector2(4, 4), SIZE - Vector2(8, 8)), Color(UiTheme.CREAM, 0.55))
		UiGlyphs.draw_ban(self, Vector2(17, SIZE.y - 17), 18.0)
	if stack >= 2:
		var font := UiTheme.font(800)
		var at := Vector2(SIZE.x - 34, SIZE.y - 8)
		draw_string_outline(
			font, at, "×%d" % stack, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 6, UiTheme.CREAM
		)
		draw_string(font, at, "×%d" % stack, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTheme.INK)
