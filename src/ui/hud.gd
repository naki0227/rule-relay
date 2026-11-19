class_name Hud
extends CanvasLayer
## 画面表示: 下中央のホットバー9枠、付与方式・届き方、メッセージ、照準、簡易インベントリ。
## 状態は色だけでなく文字（貸出中・禁止・単発など）でも示す（企画書 8）。

const MESSAGE_LINES: int = 5

var world: GameWorld
var radial_menu: RadialMenu

var _slots: Array[Label] = []
var _status: Label
var _messages: Label
var _message_log: PackedStringArray = PackedStringArray()
var _inventory_panel: PanelContainer
var _inventory_list: ItemList
var _inventory_ids: PackedInt32Array = PackedInt32Array()
var _goal_banner: Label
var _preview_label: Label


func _ready() -> void:
	_build()
	if world != null:
		world.state_changed.connect(refresh)
		world.message_posted.connect(_on_message)
		world.goal_reached.connect(_on_goal)
	refresh()


func is_inventory_open() -> bool:
	return _inventory_panel != null and _inventory_panel.visible


func toggle_inventory() -> bool:
	_inventory_panel.visible = not _inventory_panel.visible
	refresh()
	return _inventory_panel.visible


func move_selected_inventory_item_to(slot: int) -> void:
	var selected := _inventory_list.get_selected_items()
	if selected.is_empty():
		return
	world.ledger.move_to_hotbar(_inventory_ids[selected[0]], slot)


func refresh() -> void:
	if world == null or _slots.is_empty():
		return
	var ledger := world.ledger
	for i in RuleLedger.HOTBAR_SIZE:
		var v := ledger.hotbar_vessel(i)
		var text := "%d\n" % (i + 1)
		if v != null:
			text += _vessel_text(ledger.token(v.token_id))
		var marker := "▶ " if i == world.selected_slot else ""
		_slots[i].text = marker + text
		_slots[i].modulate = Color(1, 1, 0.6) if i == world.selected_slot else Color.WHITE
	_status.text = (
		"付与方式: %s（ホイール押し込み＋ドラッグ／Q）   届き方: %s（C）   左クリック=単体  右クリック長押し=範囲  F=回収/保存  E=持ち物  Esc=戻る"
		% [TriggerMode.label(world.lend_mode), "投げる" if world.throw_mode else "触る"]
	)
	_refresh_inventory()


## 右クリックを押している間の範囲プレビューの説明。
func show_range_preview(active: bool, preview: Dictionary) -> void:
	if _preview_label == null:
		return
	_preview_label.visible = active
	if not active:
		return
	var ids := preview.get("ids", PackedInt32Array()) as PackedInt32Array
	var reason := String(preview.get("reason", ""))
	if not reason.is_empty():
		_preview_label.text = "範囲付与: %s（Esc で取り消し）" % reason
	else:
		_preview_label.text = (
			"範囲付与: 対象 %d 個・半径 %.0f・1層（右クリックを離すと付与／Esc で取り消し）"
			% [ids.size(), float(preview.get("radius", 0.0))]
		)


func _vessel_text(t: RuleToken) -> String:
	var text := ("⛔%s禁止" if t.is_prohibition else "%s") % RuleAction.label(t.action)
	if t.is_lent():
		text += "\n[貸出中:%s]" % TriggerMode.label(t.mode)
	elif t.is_prohibition:
		text += "\n[適用中]"
	return text


func _refresh_inventory() -> void:
	if _inventory_list == null or not _inventory_panel.visible:
		return
	_inventory_list.clear()
	_inventory_ids = PackedInt32Array()
	for v in world.ledger.inventory_vessels():
		var t := world.ledger.token(v.token_id)
		_inventory_list.add_item(_vessel_text(t).replace("\n", " "))
		_inventory_ids.append(v.id)


func _on_message(text: String) -> void:
	_message_log.append(text)
	if _message_log.size() > MESSAGE_LINES:
		_message_log.remove_at(0)
	_messages.text = "\n".join(_message_log)


func _on_goal() -> void:
	_goal_banner.visible = true


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.add_theme_font_size_override("font_size", 28)
	root.add_child(crosshair)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.position = Vector2(-450, -110)
	bar.add_theme_constant_override("separation", 6)
	root.add_child(bar)
	for i in RuleLedger.HOTBAR_SIZE:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(94, 90)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(label)
		bar.add_child(panel)
		_slots.append(label)

	_status = Label.new()
	_status.position = Vector2(16, 12)
	root.add_child(_status)

	_messages = Label.new()
	_messages.position = Vector2(16, 44)
	root.add_child(_messages)

	_goal_banner = Label.new()
	_goal_banner.text = "高台に到達！（仮のゴール）"
	_goal_banner.add_theme_font_size_override("font_size", 40)
	_goal_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_goal_banner.position = Vector2(-220, 80)
	_goal_banner.visible = false
	root.add_child(_goal_banner)

	_preview_label = Label.new()
	_preview_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_preview_label.position = Vector2(-330, -150)
	_preview_label.add_theme_font_size_override("font_size", 20)
	_preview_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_preview_label.add_theme_constant_override("outline_size", 6)
	_preview_label.visible = false
	root.add_child(_preview_label)

	radial_menu = RadialMenu.new()
	radial_menu.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	radial_menu.custom_minimum_size = Vector2(320, 320)
	radial_menu.size = Vector2(320, 320)
	radial_menu.position = Vector2(-360, -160)
	radial_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radial_menu.visible = false
	root.add_child(radial_menu)

	_inventory_panel = PanelContainer.new()
	_inventory_panel.set_anchors_preset(Control.PRESET_CENTER)
	_inventory_panel.position = Vector2(-220, -160)
	_inventory_panel.custom_minimum_size = Vector2(440, 300)
	_inventory_panel.visible = false
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "通常インベントリ（選んで 1〜9 でホットバーへ。E で閉じる）"
	box.add_child(title)
	_inventory_list = ItemList.new()
	_inventory_list.custom_minimum_size = Vector2(420, 240)
	box.add_child(_inventory_list)
	_inventory_panel.add_child(box)
	root.add_child(_inventory_panel)
