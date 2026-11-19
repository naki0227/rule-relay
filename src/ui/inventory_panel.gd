class_name InventoryPanel
extends PanelContainer
## 持ち物の画面（E）。検索欄・種類の絞り込み・状態表示つきの一覧（企画書 7 の UI 必須項目）。
## 何を出すかは InventoryQuery が決め、ここは表示と選択だけを受け持つ。
## 操作: 文字を入力して検索 → Enter で一覧へ → 1〜9 でそのスロットへ（入れ替え）、X で通常インベントリへ。

var ledger: RuleLedger
var category: InventoryQuery.Category = InventoryQuery.Category.ALL

var _search: LineEdit
var _list: ItemList
var _count: Label
var _category_buttons: Array[Button] = []
var _ids: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	_build()


func open() -> void:
	visible = true
	refresh()
	_search.grab_focus()


func close() -> void:
	_search.release_focus()
	_list.release_focus()
	visible = false


func is_typing() -> bool:
	return _search.has_focus()


func set_query(text: String, new_category: InventoryQuery.Category) -> void:
	_search.text = text
	category = new_category
	refresh()


## いま一覧に出ている器の ID（表示順）。
func visible_vessel_ids() -> PackedInt32Array:
	return _ids


func select_vessel(vessel_id: int) -> bool:
	var index := _ids.find(vessel_id)
	if index < 0:
		return false
	_list.select(index)
	return true


func selected_vessel_id() -> int:
	var selected := _list.get_selected_items()
	return -1 if selected.is_empty() else _ids[selected[0]]


## 選んでいる器をホットバーの slot へ（入っていた器と入れ替え）。
func move_selected_to_hotbar(slot: int) -> bool:
	var id := selected_vessel_id()
	return id != -1 and ledger.move_to_hotbar(id, slot)


## 選んでいる器を通常インベントリへ。能力はここでは本人に効かなくなる（禁止は効いたまま）。
func move_selected_to_inventory() -> bool:
	var id := selected_vessel_id()
	return id != -1 and ledger.move_to_inventory(id)


func refresh() -> void:
	if ledger == null or _list == null or not visible:
		return
	var keep := selected_vessel_id()
	_list.clear()
	_ids = PackedInt32Array()
	var entries := InventoryQuery.search(ledger, _search.text, category)
	for entry in entries:
		var text := (
			"%s　｜%s｜%s" % [entry.label, InventoryQuery.location_text(entry), entry.state_text]
		)
		var index := _list.add_item(text, ItemIcons.for_token(entry.token))
		_list.set_item_tooltip(index, text)
		if entry.state == InventoryQuery.State.LENT:
			_list.set_item_custom_fg_color(index, Color(1.0, 0.7, 0.55))
		_ids.append(entry.vessel_id)
	var total := InventoryQuery.search(ledger, "", InventoryQuery.Category.ALL).size()
	_count.text = "%d / %d 件" % [entries.size(), total]
	if entries.is_empty():
		_count.text += "（該当なし）"
	for i in _category_buttons.size():
		_category_buttons[i].button_pressed = i == int(category)
	if keep != -1:
		select_vessel(keep)
	elif not _ids.is_empty():
		_list.select(0)


func _on_category(value: int) -> void:
	category = value as InventoryQuery.Category
	refresh()


func _on_submit(_text: String) -> void:
	_list.grab_focus()
	if not _ids.is_empty() and _list.get_selected_items().is_empty():
		_list.select(0)


func _build() -> void:
	custom_minimum_size = Vector2(560, 420)
	# 背景の世界が透けて文字が読みにくくならないよう、不透明に近い背景と余白を付ける
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.13, 0.96)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(16)
	style.border_color = Color(0.85, 0.7, 0.35)
	style.set_border_width_all(2)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var title := Label.new()
	title.text = "持ち物（ホットバー9枠＋通常インベントリ）"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	_search = LineEdit.new()
	_search.placeholder_text = "検索: 名前・キー・状態（例: ジャンプ、W、禁止、貸出中、ホットバー）"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: refresh())
	_search.text_submitted.connect(_on_submit)
	box.add_child(_search)

	var tabs := HBoxContainer.new()
	var group := ButtonGroup.new()
	for c: InventoryQuery.Category in [
		InventoryQuery.Category.ALL,
		InventoryQuery.Category.ABILITY,
		InventoryQuery.Category.PROHIBITION,
		InventoryQuery.Category.EQUIPMENT,
	]:
		var button := Button.new()
		button.text = InventoryQuery.category_label(c)
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_category.bind(int(c)))
		tabs.add_child(button)
		_category_buttons.append(button)
	_count = Label.new()
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tabs.add_child(_count)
	box.add_child(tabs)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(540, 260)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(40, 40)
	_list.allow_search = false
	box.add_child(_list)

	var help := Label.new()
	help.text = (
		"Enter で一覧へ → 1〜9: そのホットバー枠へ（入れ替え）　X: 通常インベントリへ　Esc: 閉じる\n"
		+ "能力はホットバーに置いたときだけ自分に効く。禁止はどこに置いても効く。"
	)
	help.add_theme_font_size_override("font_size", 14)
	box.add_child(help)
