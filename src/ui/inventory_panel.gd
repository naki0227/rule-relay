class_name InventoryPanel
extends Control
## 持ち物の画面（E）。全画面で、後ろのゲームをぼかす。左に検索・種類のタブ・一覧、右に選んだ器の
## 詳しい説明、下に操作の案内（AAA のメニューの組み方。docs/ui-research.md）。
## 何を出すかは InventoryQuery が決め、ここは表示と選択だけを受け持つ（企画書 7 の UI 必須項目）。

var ledger: RuleLedger
var category: InventoryQuery.Category = InventoryQuery.Category.ALL

var _search: LineEdit
var _list: ItemList
var _count: Label
var _category_buttons: Array[Button] = []
var _ids: PackedInt32Array = PackedInt32Array()
var _entries: Array[InventoryQuery.Entry] = []
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_state: Label
var _detail_where: Label
var _detail_text: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func open() -> void:
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, UiTheme.FAST)
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
	_show_detail(index)
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
	_entries = InventoryQuery.search(ledger, _search.text, category)
	var name_width := 0.0
	for entry in _entries:
		name_width = maxf(name_width, _text_width(entry.label))
	for entry in _entries:
		# 名前の幅をそろえて、場所と状態の列を縦にそろえる（ItemList は列を持たないため）
		var text := (
			"%s%s%s · %s"
			% [
				entry.label,
				_pad(name_width + 48.0 - _text_width(entry.label)),
				InventoryQuery.location_text(entry),
				entry.state_text,
			]
		)
		var index := _list.add_item(text, ItemIcons.for_token(entry.token))
		if entry.state == InventoryQuery.State.LENT:
			_list.set_item_custom_fg_color(index, UiTheme.ACCENT)
		elif entry.state == InventoryQuery.State.STORED:
			_list.set_item_custom_fg_color(index, UiTheme.TEXT_FAINT)
		_ids.append(entry.vessel_id)
	var total := InventoryQuery.search(ledger, "", InventoryQuery.Category.ALL).size()
	_count.text = "%d / %d" % [_entries.size(), total]
	if _entries.is_empty():
		_count.text += "　該当なし"
	for i in _category_buttons.size():
		_category_buttons[i].button_pressed = i == int(category)
	if keep != -1 and select_vessel(keep):
		return
	if not _ids.is_empty():
		_list.select(0)
		_show_detail(0)
	else:
		_show_detail(-1)


func _text_width(text: String) -> float:
	return UiTheme.regular().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x


## およそ width ピクセル分の空白（全角スペースと半角スペースを組み合わせる）。
func _pad(width: float) -> String:
	var wide := _text_width("　")
	var narrow := maxf(_text_width(" "), 1.0)
	var count_wide := int(width / wide)
	var count_narrow := int(roundf((width - count_wide * wide) / narrow))
	return "　".repeat(count_wide) + " ".repeat(count_narrow)


func _show_detail(index: int) -> void:
	if index < 0 or index >= _entries.size():
		_detail_icon.texture = null
		_detail_name.text = "—"
		_detail_state.text = ""
		_detail_where.text = ""
		_detail_text.text = "条件に合う持ち物がありません。検索語や種類を変えてください。"
		return
	var entry := _entries[index]
	_detail_icon.texture = ItemIcons.for_token(entry.token)
	_detail_name.text = entry.label
	_detail_state.text = entry.state_text
	var state_color := UiTheme.TEXT
	if entry.state == InventoryQuery.State.LENT:
		state_color = UiTheme.ACCENT
	elif entry.state == InventoryQuery.State.PROHIBITION_APPLIED:
		state_color = UiTheme.ALERT
	elif entry.state == InventoryQuery.State.STORED:
		state_color = UiTheme.TEXT_DIM
	_detail_state.add_theme_color_override("font_color", state_color)
	_detail_where.text = InventoryQuery.location_text(entry)
	_detail_text.text = _explain(entry)


## 器ごとの説明: 行動の意味と、いまの状態で何が起きているか。
static func _explain(entry: InventoryQuery.Entry) -> String:
	var t := entry.token
	var action := ""
	match t.action:
		RuleAction.Kind.FORWARD:
			action = "前へ進む。ブロックに渡すと、北へ1マス動く。"
		RuleAction.Kind.LEFT:
			action = "左へ進む。ブロックに渡すと、西へ1マス動く。"
		RuleAction.Kind.BACK:
			action = "後ろへ進む。ブロックに渡すと、南へ1マス動く。"
		RuleAction.Kind.RIGHT:
			action = "右へ進む。ブロックに渡すと、東へ1マス動く。"
		RuleAction.Kind.JUMP:
			action = "跳ぶ。ブロックに渡すと、そのブロックが跳ねる。"
	if t.is_prohibition:
		return (
			"「%s」を自分から始められなくする禁止。\n\n" % RuleAction.label(t.action)
			+ "禁止は、ホットバーでも通常インベントリでも自分に効く。ブロックに渡すと、"
			+ "そのブロックが禁止される。外から押されて動くことまでは止めない。"
		)
	match entry.state:
		InventoryQuery.State.ACTIVE:
			return action + "\n\nホットバーにあるので自分に効いている。渡すと、回収するまで自分は使えない。"
		InventoryQuery.State.STORED:
			return action + "\n\n通常インベントリでは自分に効かない。1〜9 でホットバーに置くと効く。"
		InventoryQuery.State.LENT:
			return action + "\n\n貸出中。回収するまで、自分は使えず、別の対象に渡すこともできない。" + "対象に近づいて F で回収する。"
	return action


func _on_category(value: int) -> void:
	category = value as InventoryQuery.Category
	refresh()


func _on_submit(_text: String) -> void:
	_list.grab_focus()
	if not _ids.is_empty() and _list.get_selected_items().is_empty():
		_list.select(0)
		_show_detail(0)


func _build() -> void:
	add_child(ScreenBlur.new())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_right", 120)
	margin.add_theme_constant_override("margin_top", 84)
	margin.add_theme_constant_override("margin_bottom", 56)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 24)
	margin.add_child(page)

	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	var kicker := Label.new()
	kicker.text = "INVENTORY"
	kicker.theme_type_variation = &"Kicker"
	header.add_child(kicker)
	var title := Label.new()
	title.text = "持ち物"
	title.theme_type_variation = &"HeaderLarge"
	header.add_child(title)
	page.add_child(header)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 56)
	page.add_child(body)
	body.add_child(_build_list_column())
	var divider := ColorRect.new()
	divider.color = UiTheme.LINE
	divider.custom_minimum_size = Vector2(1, 0)
	body.add_child(divider)
	body.add_child(_build_detail_column())

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 28)
	for pair: Array in [
		["文字", "検索"],
		["Enter", "一覧へ"],
		["1〜9", "ホットバーへ（入れ替え）"],
		["X", "通常インベントリへ"],
		["Esc", "閉じる"],
	]:
		footer.add_child(KeyPrompt.make(String(pair[0]), String(pair[1]), true))
	var rule := ColorRect.new()
	rule.color = UiTheme.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	page.add_child(rule)
	page.add_child(footer)


func _build_list_column() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.5
	column.add_theme_constant_override("separation", 14)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 28)
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
		button.theme_type_variation = &"Tab"
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_category.bind(int(c)))
		tabs.add_child(button)
		_category_buttons.append(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(spacer)
	_count = Label.new()
	_count.theme_type_variation = &"Caption"
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tabs.add_child(_count)
	column.add_child(tabs)

	_search = LineEdit.new()
	_search.placeholder_text = "検索　名前・キー・状態（例: ジャンプ、W、禁止、貸出中、ホットバー）"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: refresh())
	_search.text_submitted.connect(_on_submit)
	column.add_child(_search)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.fixed_icon_size = Vector2i(48, 48)
	_list.allow_search = false
	_list.item_selected.connect(_show_detail)
	column.add_child(_list)
	return column


func _build_detail_column() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	_detail_icon = TextureRect.new()
	_detail_icon.custom_minimum_size = Vector2(128, 128)
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_detail_icon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(_detail_icon)
	_detail_name = Label.new()
	_detail_name.theme_type_variation = &"HeaderLarge"
	column.add_child(_detail_name)
	_detail_state = Label.new()
	_detail_state.theme_type_variation = &"Strong"
	column.add_child(_detail_state)
	_detail_where = Label.new()
	_detail_where.theme_type_variation = &"Caption"
	column.add_child(_detail_where)
	var rule := ColorRect.new()
	rule.color = UiTheme.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	column.add_child(rule)
	_detail_text = Label.new()
	_detail_text.theme_type_variation = &"Caption"
	_detail_text.add_theme_font_size_override("font_size", 17)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.custom_minimum_size = Vector2(420, 0)
	column.add_child(_detail_text)
	return column
