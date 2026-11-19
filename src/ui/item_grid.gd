class_name ItemGrid
extends Control
## かばん（通常インベントリ）のアイコングリッド。容量は無制限なので、枠ごとにノードを作らず、
## 1つの Control が「見えている行だけ」を描く（数千個でも描画と操作が重くならない）。
## ScrollContainer の子として使う。マウスのホバー・クリック・ドラッグ＆ドロップ、
## フォーカス中は矢印キーで選択を動かせる。

signal item_selected(vessel_id: int)
signal item_hovered(vessel_id: int)
## ホットバーなどからかばんへ落とされた。
signal dropped_into_bag(vessel_id: int)
signal drag_started

const CELL: float = 88.0
const GAP: float = 10.0
const MIN_ROWS: int = 5

var columns: int = 7
var entries: Array[InventoryQuery.Entry] = []
var selected_id: int = -1

var _hover_index: int = -1
var _drop_hover: bool = false


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scroll := get_parent() as ScrollContainer
	if scroll != null:
		scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: queue_redraw())
	mouse_exited.connect(_on_mouse_exited)


func set_entries(new_entries: Array[InventoryQuery.Entry]) -> void:
	entries = new_entries
	var rows := maxi(MIN_ROWS, ceili(float(entries.size()) / columns))
	custom_minimum_size = Vector2(columns * (CELL + GAP) - GAP, rows * (CELL + GAP) - GAP)
	queue_redraw()


func select(vessel_id: int) -> void:
	selected_id = vessel_id
	_scroll_into_view(index_of(vessel_id))
	queue_redraw()


func index_of(vessel_id: int) -> int:
	for i in entries.size():
		if entries[i].vessel_id == vessel_id:
			return i
	return -1


func cell_rect(index: int) -> Rect2:
	var col := index % columns
	var row := index / columns
	return Rect2(Vector2(col * (CELL + GAP), row * (CELL + GAP)), Vector2(CELL, CELL))


func index_at(local: Vector2) -> int:
	var col := int(local.x / (CELL + GAP))
	var row := int(local.y / (CELL + GAP))
	if col < 0 or col >= columns or row < 0:
		return -1
	var index := row * columns + col
	if not cell_rect(index).has_point(local):
		return -1
	return index


## いま画面に見えている行の範囲（描画はこの範囲だけ）。
func visible_rows() -> Vector2i:
	var top := 0.0
	var height := size.y
	var scroll := get_parent() as ScrollContainer
	if scroll != null:
		top = scroll.scroll_vertical
		height = scroll.size.y
	var first := maxi(0, int(top / (CELL + GAP)))
	var last := int((top + height) / (CELL + GAP)) + 1
	return Vector2i(first, last)


func _draw() -> void:
	var rows := visible_rows()
	var style := ItemPainter.Style.new()
	for row in range(rows.x, rows.y + 1):
		for col in columns:
			var index := row * columns + col
			var rect := cell_rect(index)
			if rect.position.y > size.y:
				return
			style.selected = false
			style.hovered = index == _hover_index
			style.drop_target = false
			if index < entries.size():
				var entry := entries[index]
				style.selected = entry.vessel_id == selected_id
				ItemPainter.draw_slot(self, rect, entry.token, style)
			else:
				_draw_empty(rect)
	if _drop_hover:
		var box := StyleBoxFlat.new()
		box.draw_center = false
		box.border_color = UiTheme.LEAF
		box.set_border_width_all(3)
		box.set_corner_radius_all(UiTheme.RADIUS_SLOT)
		draw_style_box(box, Rect2(Vector2(-6, -6), size + Vector2(12, 12)))


func _draw_empty(rect: Rect2) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UiTheme.CREAM_DEEP, 0.45)
	box.border_color = Color(UiTheme.EDGE, 0.6)
	box.set_border_width_all(UiTheme.LINE)
	box.set_corner_radius_all(UiTheme.RADIUS_SLOT)
	box.anti_aliasing = true
	draw_style_box(box, rect)


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		var index := index_at(motion.position)
		if index >= entries.size():
			index = -1
		if index != _hover_index:
			_hover_index = index
			item_hovered.emit(entries[index].vessel_id if index >= 0 else -1)
			queue_redraw()
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		var index := index_at(button.position)
		if index >= 0 and index < entries.size():
			grab_focus()
			_choose(index)
			accept_event()
		return
	if not has_focus() or entries.is_empty():
		return
	var current := maxi(0, index_of(selected_id))
	var moved := current
	if event.is_action_pressed(&"ui_right"):
		moved = mini(current + 1, entries.size() - 1)
	elif event.is_action_pressed(&"ui_left"):
		moved = maxi(current - 1, 0)
	elif event.is_action_pressed(&"ui_down"):
		moved = mini(current + columns, entries.size() - 1)
	elif event.is_action_pressed(&"ui_up"):
		moved = maxi(current - columns, 0)
	else:
		return
	_choose(moved)
	accept_event()


func _choose(index: int) -> void:
	selected_id = entries[index].vessel_id
	_scroll_into_view(index)
	item_selected.emit(selected_id)
	queue_redraw()


func _scroll_into_view(index: int) -> void:
	var scroll := get_parent() as ScrollContainer
	if scroll == null or index < 0:
		return
	var rect := cell_rect(index)
	if rect.position.y < scroll.scroll_vertical:
		scroll.scroll_vertical = int(rect.position.y)
	elif rect.end.y > scroll.scroll_vertical + scroll.size.y:
		scroll.scroll_vertical = int(rect.end.y - scroll.size.y)


func _on_mouse_exited() -> void:
	_hover_index = -1
	_drop_hover = false
	item_hovered.emit(-1)
	queue_redraw()


# --- ドラッグ＆ドロップ ---


func _get_drag_data(at_position: Vector2) -> Variant:
	var index := index_at(at_position)
	if index < 0 or index >= entries.size():
		return null
	var entry := entries[index]
	drag_started.emit()
	set_drag_preview(drag_preview(entry.token))
	return {"vessel_id": entry.vessel_id, "from": "bag"}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var ok: bool = data is Dictionary and (data as Dictionary).get("from", "") == "hotbar"
	if ok != _drop_hover:
		_drop_hover = ok
		queue_redraw()
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_drop_hover = false
	queue_redraw()
	dropped_into_bag.emit(int((data as Dictionary)["vessel_id"]))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drop_hover:
		_drop_hover = false
		queue_redraw()


## ドラッグ中にカーソルについてくるアイコン。
static func drag_preview(token: RuleToken) -> Control:
	var icon := TextureRect.new()
	icon.texture = ItemIcons.for_token(token)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size = Vector2(64, 64)
	icon.position = Vector2(-32, -32)
	icon.modulate = Color(1, 1, 1, 0.9)
	var holder := Control.new()
	holder.add_child(icon)
	return holder
