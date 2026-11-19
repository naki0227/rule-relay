class_name InventorySlot
extends Control
## 持ち物の画面の1枠（ホットバー・装備）。見た目は ItemPainter で、かばんのグリッドとそろえる。
## ホットバーの枠は、ドラッグの元にも先にもなる。装備の枠は、装備品（P2 で実装）だけを受け付ける。

signal clicked(slot: InventorySlot)
signal hovered(slot: InventorySlot)
signal dropped(slot: InventorySlot, vessel_id: int)
signal drag_started

enum Kind { HOTBAR, EQUIP }

const SIZE := Vector2(88, 88)

var kind: Kind = Kind.HOTBAR
var slot_index: int = 0
var vessel_id: int = -1
var token: RuleToken
var selected: bool = false
var dimmed: bool = false
## 装備の枠の名前（頭・体・手・足）。
var equip_label: String = ""

var _hover: bool = false
var _drop_hover: bool = false


func _ready() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)


func show_vessel(
	new_vessel_id: int, new_token: RuleToken, is_selected: bool, is_dimmed: bool
) -> void:
	vessel_id = new_vessel_id
	token = new_token
	selected = is_selected
	dimmed = is_dimmed
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var style := ItemPainter.Style.new()
	style.selected = selected
	style.hovered = _hover
	style.dimmed = dimmed
	style.drop_target = _drop_hover
	style.number = slot_index + 1 if kind == Kind.HOTBAR else -1
	style.show_active = kind == Kind.HOTBAR
	ItemPainter.draw_slot(self, rect, token, style)
	if kind == Kind.EQUIP and token == null:
		draw_string(
			UiTheme.bold(),
			Vector2(0, size.y * 0.5 + 8),
			equip_label,
			HORIZONTAL_ALIGNMENT_CENTER,
			size.x,
			UiTheme.SIZE_BODY,
			UiTheme.INK_FAINT
		)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if kind != Kind.HOTBAR or token == null:
		return null
	drag_started.emit()
	set_drag_preview(ItemGrid.drag_preview(token))
	return {"vessel_id": vessel_id, "from": "hotbar", "slot": slot_index}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var ok: bool = (
		kind == Kind.HOTBAR and data is Dictionary and (data as Dictionary).has("vessel_id")
	)
	if ok and int((data as Dictionary)["vessel_id"]) == vessel_id:
		ok = false
	_set_drop_hover(ok)
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_set_drop_hover(false)
	dropped.emit(self, int((data as Dictionary)["vessel_id"]))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_set_drop_hover(false)


func _set_drop_hover(on: bool) -> void:
	if on != _drop_hover:
		_drop_hover = on
		queue_redraw()


func _on_enter() -> void:
	_hover = true
	hovered.emit(self)
	queue_redraw()


func _on_exit() -> void:
	_hover = false
	queue_redraw()
