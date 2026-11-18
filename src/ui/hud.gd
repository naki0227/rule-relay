class_name Hud
extends CanvasLayer
## 画面表示。方針は docs/ui-research.md（AAA タイトルの調査）、色と書体は UiTheme。
## - 普段の画面は最小限: 照準、ホットバー、知らせだけ。ホットバーは操作が無いと薄くなる
## - 操作の案内は常に並べず、狙ったものに応じて照準の下に出す（文脈の案内）
## - 知らせは画面左の1か所に、順に出して消す
## - 重ねて出す画面（持ち物・一時停止）は全画面で背景をぼかす
## 状態は色だけでなく文字・形（印・線）でも示す（企画書 8）。

const IDLE_FADE_AFTER: float = 4.0
const IDLE_ALPHA: float = 0.42

var world: GameWorld
var radial_menu: RadialMenu
var inventory: InventoryPanel
var pause_menu: PauseMenu
var toasts: ToastStack
var crosshair: Crosshair

var _root: Control
var _hotbar: Control
var _slots: Array[HotbarSlot] = []
var _item_name: Label
var _mode_value: Label
var _reach_value: Label
var _context: HBoxContainer
var _preview_label: Label
var _goal: Control
var _idle: float = 0.0
var _last_selected: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 一時停止中もメニューを動かす
	_build()
	if world != null:
		world.state_changed.connect(refresh)
		world.message_posted.connect(toasts.push)
		world.goal_reached.connect(_show_goal)
		world.checkpoint_changed.connect(refresh)
	refresh()


func _process(delta: float) -> void:
	_idle += delta
	var target := 1.0 if _idle < IDLE_FADE_AFTER else IDLE_ALPHA
	_hotbar.modulate.a = move_toward(_hotbar.modulate.a, target, delta * 2.5)


func is_inventory_open() -> bool:
	return inventory != null and inventory.visible


func toggle_inventory() -> bool:
	if inventory.visible:
		inventory.close()
	else:
		inventory.open()
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
	_mode_value.text = TriggerMode.label(world.lend_mode)
	_reach_value.text = "投げる" if world.throw_mode else "触る"
	_wake()
	if world.selected_slot != _last_selected:
		_last_selected = world.selected_slot
		_flash_item_name()
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
	if _preview_label == null:
		return
	_preview_label.visible = active
	if not active:
		return
	_wake()
	var ids := preview.get("ids", PackedInt32Array()) as PackedInt32Array
	var reason := String(preview.get("reason", ""))
	if not reason.is_empty():
		_preview_label.text = reason
		_preview_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	else:
		_preview_label.text = (
			"範囲に渡す　%d 個 · 半径 %.0f · 1層" % [ids.size(), float(preview.get("radius", 0.0))]
		)
		_preview_label.add_theme_color_override("font_color", UiTheme.ACCENT)


func set_aim(aim: Crosshair.Aim) -> void:
	if crosshair != null:
		crosshair.set_aim(aim)


## 照準の下の文脈の案内。狙っているもの・いる場所に応じて、使えるキーだけを出す。
func update_context(target: RuleBlock, in_reach: bool, on_checkpoint: bool) -> void:
	var prompts: Array[Array] = []
	if on_checkpoint:
		prompts.append(["F", "保存"])
	if target != null and in_reach:
		prompts.append(["左クリック", "渡す"])
		prompts.append(["右長押し", "範囲"])
		if world != null and not world.ledger.tokens_on(target.entity_id).is_empty():
			prompts.append(["F", "回収"])
	elif target != null:
		prompts.append(["C", "投げるに切り替え" if not world.throw_mode else "届かない"])
	var key := str(prompts)
	if _context.get_meta("key", "") == key:
		return
	_context.set_meta("key", key)
	for child in _context.get_children():
		child.queue_free()
	for p in prompts:
		_context.add_child(KeyPrompt.make(String(p[0]), String(p[1])))


func _set_world_hud_visible(on: bool) -> void:
	for node: CanvasItem in [crosshair, _context, _hotbar, toasts, _item_name]:
		node.visible = on


func _wake() -> void:
	_idle = 0.0


func _flash_item_name() -> void:
	var slot := _slots[world.selected_slot]
	_item_name.text = slot.item_name() if slot.token != null else "空き"
	_item_name.modulate.a = 1.0
	var tween := _item_name.create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(_item_name, "modulate:a", 0.0, 0.5)


func _show_goal() -> void:
	_goal.visible = true
	_goal.modulate.a = 0.0
	var tween := _goal.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_goal, "modulate:a", 1.0, 0.5)
	tween.tween_interval(4.5)
	tween.tween_property(_goal, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func() -> void: _goal.visible = false)


func _build() -> void:
	_root = Control.new()
	_root.theme = UiTheme.get_theme()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# 文字が集まる所だけ、画面の端から薄い暗がりを敷く（文字の影より読みやすく、箱より軽い）
	_root.add_child(
		_scrim(Control.PRESET_BOTTOM_WIDE, Vector2(0, -300), Vector2(0, 300), true, 0.5)
	)
	_root.add_child(_scrim(Control.PRESET_LEFT_WIDE, Vector2.ZERO, Vector2(820, 0), false, 0.32))

	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-24, -24)
	crosshair.size = Vector2(48, 48)
	_root.add_child(crosshair)

	_context = HBoxContainer.new()
	_context.set_anchors_preset(Control.PRESET_CENTER)
	_context.position = Vector2(-300, 40)
	_context.size = Vector2(600, 30)
	_context.alignment = BoxContainer.ALIGNMENT_CENTER
	_context.add_theme_constant_override("separation", 22)
	_context.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_context.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_context)

	toasts = ToastStack.new()
	toasts.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	toasts.position = Vector2(UiTheme.SAFE_MARGIN, -220)
	toasts.size = Vector2(760, 150)
	_root.add_child(toasts)

	_build_hotbar()

	_preview_label = Label.new()
	_preview_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_preview_label.position = Vector2(-400, -190)
	_preview_label.size = Vector2(800, 30)
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_label.theme_type_variation = &"Strong"
	_preview_label.add_theme_font_size_override("font_size", 19)
	_preview_label.visible = false
	_root.add_child(_preview_label)

	_build_goal_banner()

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
	inventory.visible = false
	_root.add_child(inventory)

	pause_menu = PauseMenu.new()
	pause_menu.world = world
	_root.add_child(pause_menu)


func _build_hotbar() -> void:
	_hotbar = Control.new()
	_hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar.position = Vector2(0, -UiTheme.SAFE_MARGIN)
	_root.add_child(_hotbar)
	var gap := 10.0
	var width := RuleLedger.HOTBAR_SIZE * HotbarSlot.SIZE.x + (RuleLedger.HOTBAR_SIZE - 1) * gap
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", int(gap))
	bar.position = Vector2(-width * 0.5, -HotbarSlot.SIZE.y)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in RuleLedger.HOTBAR_SIZE:
		var slot := HotbarSlot.new()
		slot.slot_index = i
		bar.add_child(slot)
		_slots.append(slot)
	_hotbar.add_child(bar)

	# ホットバーの右: 付与方式と届き方（切り替えのキーつき）
	var status := VBoxContainer.new()
	status.position = Vector2(width * 0.5 + 32, -HotbarSlot.SIZE.y + 2)
	status.add_theme_constant_override("separation", 6)
	_mode_value = _status_row(status, "方式", "Q")
	_reach_value = _status_row(status, "届き方", "C")
	_hotbar.add_child(status)

	_item_name = Label.new()
	_item_name.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_item_name.position = Vector2(-200, -UiTheme.SAFE_MARGIN - HotbarSlot.SIZE.y - 46)
	_item_name.size = Vector2(400, 28)
	_item_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_name.theme_type_variation = &"Strong"
	_item_name.add_theme_font_size_override("font_size", 20)
	_item_name.modulate.a = 0.0
	_root.add_child(_item_name)


func _status_row(parent: VBoxContainer, caption: String, key: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var cap := PanelContainer.new()
	cap.theme_type_variation = &"KeyCap"
	var key_label := Label.new()
	key_label.text = key
	key_label.theme_type_variation = &"KeyLabel"
	cap.add_child(key_label)
	row.add_child(cap)
	var label := Label.new()
	label.text = caption
	label.theme_type_variation = &"Caption"
	label.add_theme_font_size_override("font_size", 14)
	label.custom_minimum_size = Vector2(52, 0)
	row.add_child(label)
	var value := Label.new()
	value.theme_type_variation = &"Strong"
	value.add_theme_font_size_override("font_size", 16)
	row.add_child(value)
	parent.add_child(row)
	return value


## 到達の演出: 箱を使わず、画面の帯に大きな文字と左右に伸びる細い線（映画のテロップのように）。
func _build_goal_banner() -> void:
	_goal = Control.new()
	_goal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_goal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goal.visible = false
	_root.add_child(_goal)
	var band := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0, 0, 0, 0))
	gradient.add_point(0.5, Color(0, 0, 0, 0.55))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	band.texture = texture
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.set_anchors_preset(Control.PRESET_CENTER_TOP)
	band.position = Vector2(-1200, 230)
	band.size = Vector2(2400, 200)
	_goal.add_child(band)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-500, 262)
	box.size = Vector2(1000, 140)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	_goal.add_child(box)
	var kicker := Label.new()
	kicker.text = "REACHED"
	kicker.theme_type_variation = &"Kicker"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kicker)
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 28)
	box.add_child(title_row)
	title_row.add_child(_rule_line())
	var title := Label.new()
	title.text = "高台に到達しました"
	title.theme_type_variation = &"Display"
	title_row.add_child(title)
	title_row.add_child(_rule_line())
	var note := Label.new()
	note.text = "法則どおりなら、どの順番で着いても到達です（仮のゴール）"
	note.theme_type_variation = &"Caption"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(note)


## 端から伸びる薄い暗がり。vertical なら下から上へ、そうでなければ左から右へ薄くなる。
func _scrim(
	preset: Control.LayoutPreset, offset: Vector2, extent: Vector2, vertical: bool, strength: float
) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, strength if not vertical else 0.0))
	gradient.set_color(1, Color(0, 0, 0, 0.0 if not vertical else strength))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(preset)
	if vertical:
		rect.offset_top = offset.y
	else:
		rect.offset_right = extent.x
	return rect


func _rule_line() -> Control:
	var line := ColorRect.new()
	line.color = Color(UiTheme.ACCENT, 0.7)
	line.custom_minimum_size = Vector2(120, 1)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return line
