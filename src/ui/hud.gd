class_name Hud
extends CanvasLayer
## 画面表示（設計は docs/ui-design.md）。景色とキャラクターを主役にし、UI は生成りの札で静かに添える。
## - 普段: 照準、下中央のホットバー（生成りの台）、右に方式と届き方の印、左上に短い知らせ
## - 操作の案内: 対象を狙ったとき、慣れるまで（同じ操作を3回するまで）照準の下に出す
## - 重ねて出す画面: 円形 UI、持ち物（E）、一時停止（Esc）、到達のカード
## 状態は色だけでなく形（帯・印・輪）でも示す（企画書 8）。

var world: GameWorld
var radial_menu: RadialMenu
var inventory: InventoryPanel
var pause_menu: PauseMenu
var toasts: ToastStack
var crosshair: Crosshair
var hints: HintMemory = HintMemory.new()
## 効果音（無くても動く。テストでは入れない）。
var sounds: SoundBank

var _root: Control
var _hotbar: Control
var _slots: Array[HotbarSlot] = []
var _item_name: PanelContainer
var _item_name_label: Label
var _badge: ModeBadge
var _badge_label: PanelContainer
var _badge_text: Label
var _context: PanelContainer
var _context_row: HBoxContainer
var _preview: PanelContainer
var _preview_label: Label
var _goal: PanelContainer
var _last_selected: int = -1
var _last_mode: int = -1
var _last_throw: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 一時停止中もメニューを動かす
	_build()
	if world != null:
		world.state_changed.connect(refresh)
		world.message_posted.connect(toasts.push)
		world.goal_reached.connect(_show_goal)
		world.checkpoint_changed.connect(refresh)
	refresh()


func is_inventory_open() -> bool:
	return inventory != null and inventory.visible


func toggle_inventory() -> bool:
	if inventory.visible:
		inventory.close()
		play_ui(&"ui_close")
	else:
		inventory.open()
		play_ui(&"ui_open")
	_set_world_hud_visible(not inventory.visible)
	return inventory.visible


func refresh() -> void:
	if world == null or _slots.is_empty():
		return
	for i in RuleLedger.HOTBAR_SIZE:
		var v := world.ledger.hotbar_vessel(i)
		_slots[i].show_token(
			null if v == null else world.ledger.token(v.token_id), i == world.selected_slot
		)
	_badge.show_state(world.lend_mode, world.throw_mode)
	if world.selected_slot != _last_selected:
		if _last_selected != -1 and sounds != null:
			sounds.play_slot_select(world.selected_slot)
		_last_selected = world.selected_slot
		_flash_item_name()
	if int(world.lend_mode) != _last_mode or int(world.throw_mode) != _last_throw:
		if _last_mode != -1:
			_flash_badge_label()
		_last_mode = int(world.lend_mode)
		_last_throw = int(world.throw_mode)
	if inventory != null:
		inventory.refresh()
	if pause_menu != null:
		pause_menu.refresh()


## ホットバーの各枠の状態（文字）。テスト用。
func hotbar_descriptions() -> PackedStringArray:
	var out := PackedStringArray()
	for slot in _slots:
		out.append(slot.describe())
	return out


## 右クリックを押している間の範囲プレビューの説明。
func show_range_preview(active: bool, preview: Dictionary) -> void:
	if _preview == null:
		return
	_preview.visible = active
	if not active:
		return
	var ids := preview.get("ids", PackedInt32Array()) as PackedInt32Array
	var reason := String(preview.get("reason", ""))
	if not reason.is_empty():
		_preview_label.text = reason
	else:
		_preview_label.text = "範囲に渡す　%d こ" % ids.size()


func set_aim(aim: Crosshair.Aim) -> void:
	if crosshair != null:
		crosshair.set_aim(aim)


## 照準の下の案内。狙っているもの・いる場所に応じて、まだ慣れていない操作だけを出す。
func update_context(target: Node3D, in_reach: bool, on_checkpoint: bool) -> void:
	var prompts: Array[Array] = []
	if on_checkpoint and hints.should_show("save"):
		prompts.append(["F", "ここで保存"])
	if world != null and world.player != null and world.nearest_world_item() != null:
		prompts.append(["F", "拾う"])
	if target is Bell and in_reach:
		prompts.append(["F", "鳴らす"])
	elif target != null and in_reach:
		if hints.should_show("lend"):
			prompts.append(["左クリック", "渡す"])
		if hints.should_show("range"):
			prompts.append(["右クリック", "まとめて"])
		var id := int(target.get("entity_id"))
		var holds := world != null and not world.ledger.tokens_on(id).is_empty()
		if holds and hints.should_show("recall"):
			prompts.append(["F", "回収"])
	elif target != null and hints.should_show("throw"):
		if world.throw_mode:
			prompts.append(["C", "遠すぎる"])
		elif world.can_throw():
			prompts.append(["C", "投げるで届く"])
	var key := str(prompts)
	if _context.get_meta("key", "") == key:
		return
	_context.set_meta("key", key)
	for child in _context_row.get_children():
		child.queue_free()
	for p in prompts:
		_context_row.add_child(KeyPrompt.make(String(p[0]), String(p[1])))
	_context.visible = not prompts.is_empty()


## いま照準の下に出ている案内の動作（テスト用）。
func context_actions() -> PackedStringArray:
	var out := PackedStringArray()
	if not _context.visible:
		return out
	for prompt in _context_row.get_children():
		if not prompt.is_queued_for_deletion():
			out.append((prompt.get_child(1) as Label).text)
	return out


func play_ui(event: StringName) -> void:
	if sounds != null:
		sounds.play_ui(event)


func _set_world_hud_visible(on: bool) -> void:
	for node: CanvasItem in [crosshair, _hotbar, toasts]:
		node.visible = on
	if not on:
		_context.visible = false


func _flash_item_name() -> void:
	var slot := _slots[world.selected_slot]
	_item_name_label.text = slot.item_name() if slot.token != null else "からっぽ"
	_item_name.modulate.a = 1.0
	var tween := _item_name.create_tween()
	tween.tween_interval(1.4)
	tween.tween_property(_item_name, "modulate:a", 0.0, 0.4)


func _flash_badge_label() -> void:
	_badge_text.text = (
		"%s · %s" % [TriggerMode.label(world.lend_mode), "投げる" if world.throw_mode else "触る"]
	)
	_badge_label.modulate.a = 1.0
	var tween := _badge_label.create_tween()
	tween.tween_interval(1.4)
	tween.tween_property(_badge_label, "modulate:a", 0.0, 0.4)


func _show_goal() -> void:
	_goal.visible = true
	_goal.modulate.a = 0.0
	_goal.pivot_offset = _goal.size * 0.5
	_goal.scale = Vector2.ONE * 0.9
	var tween := _goal.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_goal, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(_goal, "scale", Vector2.ONE, 0.4)
	tween.tween_interval(3.6)
	tween.tween_property(_goal, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func() -> void: _goal.visible = false)


func _build() -> void:
	_root = Control.new()
	_root.theme = UiTheme.get_theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-24, -24)
	crosshair.size = Vector2(48, 48)
	_root.add_child(crosshair)

	_context = _bubble()
	# 照準の右下に出す（肩越しのカメラで、キャラクターは照準の左にいる）
	_context.set_anchors_preset(Control.PRESET_CENTER)
	_context.position = Vector2(36, 22)
	_context.visible = false
	_context_row = HBoxContainer.new()
	_context_row.add_theme_constant_override("separation", 20)
	_context.add_child(_context_row)
	_root.add_child(_context)

	toasts = ToastStack.new()
	toasts.position = Vector2(UiTheme.SAFE_MARGIN, UiTheme.SAFE_MARGIN)
	toasts.size = Vector2(760, 200)
	_root.add_child(toasts)

	_build_hotbar()

	_preview = _bubble(UiTheme.SUN_SOFT, UiTheme.SUN)
	_preview_label = Label.new()
	_preview_label.theme_type_variation = &"Strong"
	_preview.add_child(_preview_label)
	_preview.visible = false
	_center_band(_preview, UiTheme.SAFE_MARGIN + HotbarSlot.SIZE.y + 80, true)

	_build_goal_card()

	radial_menu = RadialMenu.new()
	radial_menu.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	radial_menu.custom_minimum_size = Vector2(340, 340)
	radial_menu.size = Vector2(340, 340)
	radial_menu.position = Vector2(-340 - UiTheme.SAFE_MARGIN * 2.0, -170)
	radial_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radial_menu.visible = false
	_root.add_child(radial_menu)

	inventory = InventoryPanel.new()
	inventory.ledger = world.ledger if world != null else null
	inventory.play_sound = play_ui
	inventory.visible = false
	_root.add_child(inventory)

	pause_menu = PauseMenu.new()
	pause_menu.world = world
	pause_menu.play_sound = play_ui
	_root.add_child(pause_menu)


## 画面の横幅いっぱいの帯に child を置き、横方向の中央にそろえる。y は上端（bottom なら下端）からの距離。
func _center_band(child: Control, y: float, from_bottom: bool) -> void:
	var band := CenterContainer.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_WIDE if from_bottom else Control.PRESET_TOP_WIDE
	)
	if from_bottom:
		band.offset_top = -y - 60
		band.offset_bottom = -y
	else:
		band.offset_top = y
		band.offset_bottom = y + 200
	band.use_top_left = false
	band.add_child(child)
	_root.add_child(band)


func _bubble(fill: Color = UiTheme.CREAM, edge: Color = UiTheme.EDGE) -> PanelContainer:
	var bubble := PanelContainer.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiTheme.pill_box(Color(fill, 0.94), edge)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 8
	box.content_margin_bottom = 9
	bubble.add_theme_stylebox_override("panel", box)
	return bubble


func _build_hotbar() -> void:
	var gap := 10
	var width := RuleLedger.HOTBAR_SIZE * HotbarSlot.SIZE.x + (RuleLedger.HOTBAR_SIZE - 1) * gap
	_hotbar = Control.new()
	_hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar.position = Vector2(0, -UiTheme.SAFE_MARGIN)
	_root.add_child(_hotbar)
	# 生成りの台（景色が少し透ける）
	var tray := Panel.new()
	tray.add_theme_stylebox_override(
		"panel", UiTheme.panel_box(Color(UiTheme.CREAM, 0.72), 26, 0.0)
	)
	tray.position = Vector2(-width * 0.5 - 14, -HotbarSlot.SIZE.y - 14)
	tray.size = Vector2(width + 28, HotbarSlot.SIZE.y + 28)
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar.add_child(tray)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", gap)
	bar.position = Vector2(-width * 0.5, -HotbarSlot.SIZE.y)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in RuleLedger.HOTBAR_SIZE:
		var slot := HotbarSlot.new()
		slot.slot_index = i
		bar.add_child(slot)
		_slots.append(slot)
	_hotbar.add_child(bar)

	_badge = ModeBadge.new()
	_badge.position = Vector2(width * 0.5 + 32, -HotbarSlot.SIZE.y + 8)
	_badge.size = Vector2(124, 64)
	_hotbar.add_child(_badge)
	_badge_label = _bubble()
	_badge_label.position = Vector2(width * 0.5 + 24, -HotbarSlot.SIZE.y - 54)
	_badge_text = Label.new()
	_badge_text.theme_type_variation = &"Strong"
	_badge_text.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	_badge_label.add_child(_badge_text)
	_badge_label.modulate.a = 0.0
	_hotbar.add_child(_badge_label)

	_item_name = _bubble()
	_item_name_label = Label.new()
	_item_name_label.theme_type_variation = &"Strong"
	_item_name.add_child(_item_name_label)
	_item_name.modulate.a = 0.0
	_center_band(_item_name, UiTheme.SAFE_MARGIN + HotbarSlot.SIZE.y + 24, true)


## 到達のカード: 画面の上に、生成りの札が小さく降りてきて、少ししたら消える。
func _build_goal_card() -> void:
	_goal = PanelContainer.new()
	_goal.custom_minimum_size = Vector2(460, 0)
	_goal.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.CREAM, 26, 22.0))
	_goal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goal.visible = false
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	_goal.add_child(box)
	var stars := HBoxContainer.new()
	stars.alignment = BoxContainer.ALIGNMENT_CENTER
	stars.add_theme_constant_override("separation", 10)
	for i in 3:
		var leaf := ColorRect.new()
		leaf.color = UiTheme.LEAF if i != 1 else UiTheme.SUN
		leaf.custom_minimum_size = Vector2(8, 8)
		leaf.rotation = PI * 0.25
		stars.add_child(leaf)
	box.add_child(stars)
	var title := Label.new()
	title.text = "高台に到達しました"
	title.theme_type_variation = &"Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var note := Label.new()
	note.text = "どの順番でたどり着いても正解（仮のゴール）"
	note.theme_type_variation = &"Note"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)
	_center_band(_goal, 96.0, false)
