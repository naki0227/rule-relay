class_name InventoryPanel
extends Control
## 持ち物の画面（E）。カテゴリのタブで切り替えるのをやめ、1つの画面を領域で分ける。
##   左: キャラクターと装備の枠（頭・体・手・足）
##   中央: かばん（通常インベントリ。容量無制限のスクロールするアイコングリッド）
##   右: 選んだ／指したアイテムの詳しい説明と、貸し出し中の一覧
##   下: ホットバー9枠（ここにある能力だけ自分に効く）
##   上: 目立ちすぎない検索欄と、小さな絞り込みのチップ
## 同じ器を複数の場所に出すとき（貸し出し中の一覧など）は、複製せず同じ器 ID を参照する。
## 何を出すかの判定は InventoryQuery、所有の変更は RuleLedger が受け持つ（企画書 7）。

const EQUIP_SLOTS: PackedStringArray = ["頭", "体", "手", "足"]
const EQUIP_PARTS: Array[RuleVessel.Part] = [
	RuleVessel.Part.HEAD, RuleVessel.Part.BODY, RuleVessel.Part.HANDS, RuleVessel.Part.FEET
]
const CHIPS: Array[InventoryQuery.Category] = [
	InventoryQuery.Category.ALL,
	InventoryQuery.Category.ABILITY,
	InventoryQuery.Category.PROHIBITION,
	InventoryQuery.Category.LENT,
]

var ledger: RuleLedger
## 持ち物を動かす窓口（参加者ならホストへの依頼になる）。空なら台帳を直接動かす。
var actions: LedgerActions
## この画面を見ているプレイヤー。
var player_id: int = RuleLedger.PLAYER_ID
## 効果音を鳴らす関数（Hud.play_ui）。無ければ鳴らさない。
var play_sound: Callable
var category: InventoryQuery.Category = InventoryQuery.Category.ALL

var _search: LineEdit
var _chips: Array[Button] = []
var _grid: ItemGrid
var _bag_count: Label
var _hotbar_slots: Array[InventorySlot] = []
var _equip_slots: Array[InventorySlot] = []
var _matches: Array[InventoryQuery.Entry] = []
var _selected_id: int = -1
var _hover_id: int = -1
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_state: Label
var _detail_where: Label
var _detail_text: Label
var _lent_list: VBoxContainer
var _equip_button: Button
var _book: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func open() -> void:
	visible = true
	modulate.a = 0.0
	_book.scale = Vector2.ONE * 0.97
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "modulate:a", 1.0, UiTheme.FAST)
	tween.parallel().tween_property(_book, "scale", Vector2.ONE, UiTheme.NORMAL)
	refresh()
	_search.grab_focus()


func close() -> void:
	_search.release_focus()
	_grid.release_focus()
	visible = false


func is_typing() -> bool:
	return _search.has_focus()


func set_query(text: String, new_category: InventoryQuery.Category) -> void:
	_search.text = text
	category = new_category
	refresh()


## 検索・絞り込みに合う器の ID（ホットバーの枠の順 → かばんの順）。
func visible_vessel_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	for entry in _matches:
		ids.append(entry.vessel_id)
	return ids


## かばんのグリッドに出ている器の ID（ホットバーの器は含まない）。
func bag_vessel_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	for entry in _grid.entries:
		ids.append(entry.vessel_id)
	return ids


func select_vessel(vessel_id: int) -> bool:
	if _find(vessel_id) == null:
		return false
	_selected_id = vessel_id
	_grid.select(vessel_id)
	_update_slots()
	_show_detail()
	return true


func selected_vessel_id() -> int:
	return _selected_id


## 選んでいる器をホットバーの slot へ（入っていた器と入れ替え）。
func move_selected_to_hotbar(slot: int) -> bool:
	var ok := _selected_id != -1 and _actions().move_to_hotbar(_selected_id, slot)
	_sound(&"ui_drop" if ok else &"ui_error")
	return ok


## 選んでいる器をかばん（通常インベントリ）へ。能力はかばんでは自分に効かない（禁止は効いたまま）。
func move_selected_to_inventory() -> bool:
	var ok := _selected_id != -1 and _actions().move_to_inventory(_selected_id)
	_sound(&"ui_drop" if ok else &"ui_error")
	return ok


## ドラッグ＆ドロップと同じ処理（テストからも呼ぶ）。
func drop_on_hotbar(vessel_id: int, slot: int) -> bool:
	_selected_id = vessel_id
	var ok := _actions().move_to_hotbar(vessel_id, slot)
	_sound(&"ui_drop" if ok else &"ui_error")
	return ok


func drop_into_bag(vessel_id: int) -> bool:
	_selected_id = vessel_id
	var ok := _actions().move_to_inventory(vessel_id)
	_sound(&"ui_drop" if ok else &"ui_error")
	return ok


## 装備の枠へ落とす（ドラッグ＆ドロップと同じ処理。テストからも呼ぶ）。部位が合う装備品だけ。
func drop_on_equip(vessel_id: int, part: RuleVessel.Part) -> bool:
	_selected_id = vessel_id
	var v := ledger.vessel(vessel_id)
	var ok := v != null and v.part == part and _actions().equip(vessel_id)
	_sound(&"ui_confirm" if ok else &"ui_error")
	return ok


## 選んでいる装備品をつける／外す（詳しい説明のボタンと同じ）。
func toggle_equip_selected() -> bool:
	var v := ledger.vessel(_selected_id)
	if v == null or not v.is_equipment():
		_sound(&"ui_error")
		return false
	var ok := false
	if v.location == RuleVessel.Location.EQUIPPED:
		ok = _actions().unequip(v.id)
	else:
		ok = _actions().equip(v.id)
	_sound(&"ui_confirm" if ok else &"ui_error")
	return ok


func _accepts_for_equip(vessel_id: int, part: RuleVessel.Part) -> bool:
	var v := ledger.vessel(vessel_id)
	return v != null and v.part == part


func _actions() -> LedgerActions:
	if actions == null or actions.ledger != ledger:
		actions = LedgerActions.new()
		actions.ledger = ledger
		actions.player_id = player_id
	return actions


func _sound(event: StringName) -> void:
	if play_sound.is_valid():
		play_sound.call(event)


## 右の詳しい説明に出ている名前（テスト用）。
func detail_title() -> String:
	return _detail_name.text


func refresh() -> void:
	if ledger == null or _grid == null or not visible:
		return
	_matches = InventoryQuery.search(ledger, _search.text, category, player_id)
	var bag: Array[InventoryQuery.Entry] = []
	for entry in _matches:
		if entry.location == RuleVessel.Location.INVENTORY:
			bag.append(entry)
	_grid.set_entries(bag)
	var bag_total := ledger.inventory_vessels(player_id).size()
	_bag_count.text = (
		"%d こ" % bag_total if bag.size() == bag_total else "%d / %d こ" % [bag.size(), bag_total]
	)
	for i in _chips.size():
		_chips[i].button_pressed = CHIPS[i] == category
	if _find(_selected_id) == null:
		_selected_id = -1 if _matches.is_empty() else _matches[0].vessel_id
	_grid.select(_selected_id)
	_update_slots()
	_update_lent_list()
	_show_detail()


func _find(vessel_id: int) -> InventoryQuery.Entry:
	for entry in _matches:
		if entry.vessel_id == vessel_id:
			return entry
	return null


func _update_slots() -> void:
	var filtering := (
		not _search.text.strip_edges().is_empty() or category != InventoryQuery.Category.ALL
	)
	for slot in _hotbar_slots:
		var v := ledger.hotbar_vessel(slot.slot_index, player_id)
		var id := -1 if v == null else v.id
		var t: RuleToken = null if v == null else ledger.token(v.token_id)
		var dim := filtering and t != null and _find(id) == null
		slot.show_vessel(id, t, id != -1 and id == _selected_id, dim)
	for i in _equip_slots.size():
		var ev := ledger.equipped_vessel(EQUIP_PARTS[i], player_id)
		var eid := -1 if ev == null else ev.id
		var et: RuleToken = null if ev == null else ledger.token(ev.token_id)
		var edim := filtering and et != null and _find(eid) == null
		_equip_slots[i].show_vessel(eid, et, eid != -1 and eid == _selected_id, edim)


## 貸し出し中の一覧。器はホットバーかかばんに残ったままで、ここは同じ器への参照。
func _update_lent_list() -> void:
	for child in _lent_list.get_children():
		child.queue_free()
	var lent := InventoryQuery.search(ledger, "", InventoryQuery.Category.LENT)
	if lent.is_empty():
		var none := Label.new()
		none.text = "いまは何も貸していません"
		none.theme_type_variation = &"Note"
		_lent_list.add_child(none)
		return
	for entry in lent:
		var row := Button.new()
		row.theme_type_variation = &"Chip"
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.icon = ItemIcons.for_token(entry.token)
		row.expand_icon = true
		row.custom_minimum_size = Vector2(0, 44)
		row.add_theme_constant_override("icon_max_width", 30)
		var target := "範囲 %d こ" % entry.token.holder_ids.size() if entry.token.is_range else "1つ"
		row.text = "%s　%s · %s" % [entry.label, target, TriggerMode.label(entry.token.mode)]
		row.focus_mode = Control.FOCUS_NONE
		row.pressed.connect(_on_lent_pressed.bind(entry.vessel_id))
		_lent_list.add_child(row)


func _on_lent_pressed(vessel_id: int) -> void:
	if _find(vessel_id) == null:
		set_query("", InventoryQuery.Category.ALL)
	select_vessel(vessel_id)


func _show_detail() -> void:
	var id := _hover_id if _hover_id != -1 else _selected_id
	var entry := _find(id)
	if entry == null and id != -1:
		entry = _describe_any(id)
	if entry == null:
		_detail_icon.texture = null
		_detail_state.visible = false
		_detail_where.text = ""
		_equip_button.visible = false
		var searching := not _search.text.strip_edges().is_empty()
		_detail_name.text = "見つかりません" if searching else "からっぽ"
		_detail_text.text = "ことばや絞り込みを変えてみてください。" if searching else ""
		return
	_detail_icon.texture = ItemIcons.for_token(entry.token)
	_detail_name.text = entry.label
	_detail_state.visible = true
	_detail_state.text = entry.state_text.replace("通常インベントリ", "かばん")
	_style_state(entry.state)
	_detail_where.text = InventoryQuery.location_text(entry).replace("通常インベントリ", "かばん")
	_detail_text.text = _explain(entry)
	_equip_button.visible = entry.is_equipment and entry.vessel_id == _selected_id
	var worn := entry.location == RuleVessel.Location.EQUIPPED
	_equip_button.text = "はずす" if worn else "そうびする"


func _describe_any(vessel_id: int) -> InventoryQuery.Entry:
	var v := ledger.vessel(vessel_id)
	return null if v == null else InventoryQuery.describe(ledger, v)


func _style_state(state: InventoryQuery.State) -> void:
	var fill := UiTheme.LEAF_SOFT
	var edge := UiTheme.LEAF
	match state:
		InventoryQuery.State.STORED:
			fill = UiTheme.CREAM_DEEP
			edge = UiTheme.EDGE_DEEP
		InventoryQuery.State.LENT:
			fill = UiTheme.HONEY_SOFT
			edge = UiTheme.HONEY
		InventoryQuery.State.PROHIBITION_APPLIED:
			fill = UiTheme.BAN_SOFT
			edge = UiTheme.BAN
	var box := UiTheme.pill_box(fill, edge)
	box.shadow_size = 0
	box.content_margin_top = 2
	box.content_margin_bottom = 3
	_detail_state.add_theme_stylebox_override("normal", box)


## 器ごとの説明: 行動の意味と、いまの状態で何が起きているか（短く）。
static func _explain(entry: InventoryQuery.Entry) -> String:
	var t := entry.token
	var action := ""
	match t.action:
		RuleAction.Kind.FORWARD:
			action = "前へ進む力。ブロックに渡すと北へ1マス動く。"
		RuleAction.Kind.LEFT:
			action = "左へ進む力。ブロックに渡すと西へ1マス動く。"
		RuleAction.Kind.BACK:
			action = "後ろへ進む力。ブロックに渡すと南へ1マス動く。"
		RuleAction.Kind.RIGHT:
			action = "右へ進む力。ブロックに渡すと東へ1マス動く。"
		RuleAction.Kind.JUMP:
			action = "跳ぶ力。ブロックに渡すと、そのブロックが跳ねる。"
		RuleAction.Kind.THROW:
			action = "投げて遠くへ渡す力（C で切り替え）。手放すと「触る」の距離だけになるが、F の回収は残る。"
		RuleAction.Kind.HIGH_JUMP:
			action = "いつもより高く跳ぶ力（約2ブロック）。装備しているときだけ自分に効く。"
		RuleAction.Kind.DASH:
			action = "向いている方へ、まっすぐ3マス突進する力（Shift）。途中に穴があっても落ちずに抜けられる。ブロックに渡すと北へ突進する。"
		RuleAction.Kind.CLIMB:
			action = "壁を登る力。装備しているときだけ自分に効く。ブロックに渡すと、隣でいちばん高い所の高さまで登ってつかまる。"
	if t.is_prohibition:
		var lent_note := "\n\nいまは貸し出し中なので、自分には効いていない。" if not t.is_in_vessel() else ""
		return (
			("「%s」を自分から始められなくする禁止。ホットバーでも、かばんでも、持っている限り自分に効く。" % RuleAction.label(t.action))
			+ lent_note
		)
	match entry.state:
		InventoryQuery.State.ACTIVE:
			return action + "\n\nホットバーにあるので、自分に効いている。"
		InventoryQuery.State.STORED:
			return action + "\n\nかばんの中では自分に効かない。ホットバーに置くと効く。"
		InventoryQuery.State.LENT:
			return action + "\n\n貸し出し中。回収するまで自分は使えない。相手に近づいて F で回収できる。"
	return action


func _on_grid_selected(vessel_id: int) -> void:
	_sound(&"ui_pick")
	_selected_id = vessel_id
	_update_slots()
	_show_detail()


func _on_hovered(vessel_id: int) -> void:
	if vessel_id != -1 and vessel_id != _hover_id:
		_sound(&"ui_hover")
	_hover_id = vessel_id
	_show_detail()


func _on_slot_clicked(slot: InventorySlot) -> void:
	if slot.vessel_id != -1:
		select_vessel(slot.vessel_id)


func _on_slot_hovered(slot: InventorySlot) -> void:
	_on_hovered(slot.vessel_id)


func _on_slot_dropped(slot: InventorySlot, vessel_id: int) -> void:
	drop_on_hotbar(vessel_id, slot.slot_index)


func _on_dropped_into_bag(vessel_id: int) -> void:
	drop_into_bag(vessel_id)


func _on_chip(index: int) -> void:
	_sound(&"ui_hover")
	category = CHIPS[index]
	refresh()


func _on_submit(_text: String) -> void:
	_grid.grab_focus()


func _build() -> void:
	var blur := ScreenBlur.new()
	blur.soft = true
	add_child(blur)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_book = PanelContainer.new()
	_book.custom_minimum_size = Vector2(1640, 0)
	_book.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.CREAM, 28, 32.0))
	_book.resized.connect(func() -> void: _book.pivot_offset = _book.size * 0.5)
	center.add_child(_book)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 22)
	_book.add_child(page)
	page.add_child(_build_header())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 36)
	body.custom_minimum_size = Vector2(0, 520)
	page.add_child(body)
	body.add_child(_build_character_column())
	body.add_child(_build_bag_column())
	body.add_child(_build_detail_column())
	page.add_child(_build_hotbar_row())


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "持ち物"
	title.theme_type_variation = &"Title"
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	for i in CHIPS.size():
		var chip := Button.new()
		chip.text = InventoryQuery.category_label(CHIPS[i])
		chip.theme_type_variation = &"Chip"
		chip.toggle_mode = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.pressed.connect(_on_chip.bind(i))
		header.add_child(chip)
		_chips.append(chip)
	_search = LineEdit.new()
	_search.placeholder_text = "さがす（ジャンプ、W、禁止 など）"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(380, 0)
	_search.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_search.text_changed.connect(func(_t: String) -> void: refresh())
	_search.text_submitted.connect(_on_submit)
	header.add_child(_search)
	return header


func _build_character_column() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(300, 0)
	column.add_theme_constant_override("separation", 12)
	var stage := PanelContainer.new()
	var stage_box := UiTheme.panel_box(UiTheme.CREAM_DEEP, 20, 0.0)
	stage_box.shadow_size = 0
	stage.add_theme_stylebox_override("panel", stage_box)
	stage.custom_minimum_size = Vector2(300, 300)
	stage.add_child(CharacterPreview.new())
	column.add_child(stage)
	column.add_child(_section("そうび", ""))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	for i in EQUIP_SLOTS.size():
		var slot := InventorySlot.new()
		slot.kind = InventorySlot.Kind.EQUIP
		slot.slot_index = i
		slot.equip_label = EQUIP_SLOTS[i]
		slot.custom_minimum_size = Vector2(62, 62)
		slot.tooltip_text = "装備品は、つけているときだけ効く。部位が合うものをここへ"
		slot.accepts = _accepts_for_equip.bind(EQUIP_PARTS[i])
		slot.clicked.connect(_on_slot_clicked)
		slot.hovered.connect(_on_slot_hovered)
		slot.dropped.connect(
			func(_s: InventorySlot, vessel_id: int) -> void:
				drop_on_equip(vessel_id, EQUIP_PARTS[i])
				refresh()
		)
		grid.add_child(slot)
		_equip_slots.append(slot)
	column.add_child(grid)
	var note := Label.new()
	note.text = "つけているときだけ効く"
	note.theme_type_variation = &"Note"
	column.add_child(note)
	return column


func _build_bag_column() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_child(_section("かばん", "ここの能力は自分に効かない"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_bag_count = Label.new()
	_bag_count.theme_type_variation = &"Note"
	head.add_child(_bag_count)
	column.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(7 * (ItemGrid.CELL + ItemGrid.GAP) + 14, 0)
	column.add_child(scroll)
	_grid = ItemGrid.new()
	_grid.columns = 7
	_grid.item_selected.connect(_on_grid_selected)
	_grid.item_hovered.connect(_on_hovered)
	_grid.dropped_into_bag.connect(_on_dropped_into_bag)
	_grid.drag_started.connect(func() -> void: _sound(&"ui_pick"))
	scroll.add_child(_grid)
	return column


func _build_detail_column() -> Control:
	var card := PanelContainer.new()
	var box := UiTheme.panel_box(Color.WHITE, 20, 24.0)
	box.shadow_size = 0
	card.add_theme_stylebox_override("panel", box)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	_detail_icon = TextureRect.new()
	_detail_icon.custom_minimum_size = Vector2(96, 96)
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	top.add_child(_detail_icon)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 6)
	_detail_name = Label.new()
	_detail_name.theme_type_variation = &"Heading"
	names.add_child(_detail_name)
	_detail_state = Label.new()
	_detail_state.theme_type_variation = &"Strong"
	_detail_state.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	_detail_state.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	names.add_child(_detail_state)
	_detail_where = Label.new()
	_detail_where.theme_type_variation = &"Note"
	names.add_child(_detail_where)
	top.add_child(names)
	column.add_child(top)
	_detail_text = Label.new()
	_detail_text.theme_type_variation = &"Body"
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.custom_minimum_size = Vector2(360, 140)
	column.add_child(_detail_text)
	_equip_button = Button.new()
	_equip_button.text = "そうびする"
	_equip_button.custom_minimum_size = Vector2(0, 48)
	_equip_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_equip_button.visible = false
	_equip_button.pressed.connect(
		func() -> void:
			toggle_equip_selected()
			refresh()
	)
	column.add_child(_equip_button)
	column.add_child(_section("貸し出し中", ""))
	_lent_list = VBoxContainer.new()
	_lent_list.add_theme_constant_override("separation", 6)
	column.add_child(_lent_list)
	return card


func _build_hotbar_row() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_child(_section("ホットバー", "ここにある能力だけ自分に効く"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var how := Label.new()
	how.text = "ドラッグで入れかえ　·　1〜9 でホットバーへ　·　X でかばんへ"
	how.theme_type_variation = &"Note"
	head.add_child(how)
	column.add_child(head)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	for i in RuleLedger.HOTBAR_SIZE:
		var slot := InventorySlot.new()
		slot.kind = InventorySlot.Kind.HOTBAR
		slot.slot_index = i
		slot.clicked.connect(_on_slot_clicked)
		slot.hovered.connect(_on_slot_hovered)
		slot.mouse_exited.connect(_on_hovered.bind(-1))
		slot.dropped.connect(_on_slot_dropped)
		slot.drag_started.connect(func() -> void: _sound(&"ui_pick"))
		row.add_child(slot)
		_hotbar_slots.append(slot)
	column.add_child(row)
	return column


func _section(title: String, note: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var dot := ColorRect.new()
	dot.color = UiTheme.LEAF
	dot.custom_minimum_size = Vector2(6, 18)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var label := Label.new()
	label.text = title
	label.theme_type_variation = &"Strong"
	row.add_child(label)
	if not note.is_empty():
		var hint := Label.new()
		hint.text = note
		hint.theme_type_variation = &"Note"
		row.add_child(hint)
	return row
