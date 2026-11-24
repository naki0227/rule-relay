class_name Hud
extends CanvasLayer
## 画面表示（設計は docs/ui-design.md）。景色とキャラクターを主役にし、UI は生成りの札で静かに添える。
## - 普段: 照準、下中央のホットバー（生成りの台）、右に方式と届き方の印、左上に短い知らせ
## - 操作の案内: いまいちばん要る1つだけを、慣れるまで（同じ操作を3回するまで）照準の下に出す（TeachHints）
## - 重ねて出す画面: 円形 UI、持ち物（E）、一時停止（Esc）、到達のカード
## 状態は色だけでなく形（帯・印・輪）でも示す（企画書 8）。

## クリアのカードの見出し。
const GOAL_TITLE := "クリア！"

var world: GameWorld
var radial_menu: RadialMenu
var inventory: InventoryPanel
var pause_menu: PauseMenu
var toasts: ToastStack
var crosshair: Crosshair
## 願いの行き先が画面の外にあるときの矢印。
var wish_pointer: WishPointer
var hints: HintMemory = HintMemory.new()
## この島に来てからの秒数（一時停止中は数えない）。目安の時間を過ぎたら、やり直しの案内を出す。
var stage_seconds: float = 0.0
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
var _goal: PanelContainer
var _goal_note: Label
var _goal_title: Label
## クリアのカードの上の3つの印（順に弾んで出る）。
var _goal_marks: Array[Control] = []
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


func _process(delta: float) -> void:
	if not get_tree().paused:
		stage_seconds += delta


func is_inventory_open() -> bool:
	return inventory != null and inventory.visible


## メニュー（Esc・その上の「せってい」・持ち物）を開いているか。BGM を少し下げるのに使う。
func is_menu_open() -> bool:
	return is_inventory_open() or (pause_menu != null and pause_menu.is_open())


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
	var me := world.player.player_id if world.player != null else RuleLedger.PLAYER_ID
	var counted: Dictionary[int, bool] = {}
	for i in RuleLedger.HOTBAR_SIZE:
		var v := world.ledger.hotbar_vessel(i, me)
		var t: RuleToken = null if v == null else world.ledger.token(v.token_id)
		_slots[i].show_token(t, i == world.selected_slot, v)
		# 集めた同じ能力の数（×n）。2個以上のときだけ、その能力の最初の枠にだけ出す（ジャンプが 2 枠に
		# あると両方に「×2」と出て、4 つ持っているように見えた。2026-11-22 の通し）
		var key := -1 if t == null or t.is_prohibition else int(t.action)
		_slots[i].stack = (
			0 if key == -1 or counted.has(key) else world.ledger.ability_count(t.action, me)
		)
		if key != -1:
			counted[key] = true
		# 足もとのブロックの禁止で使えない能力は、枠を薄くして小さな禁止の印を付ける（FloorBans）
		_slots[i].floor_banned = (
			t != null
			and not t.is_prohibition
			and world.player != null
			and world.player.floor_blocks(t.action)
		)
	_badge.show_state(world.lend_mode, world.throw_mode)
	if world.selected_slot != _last_selected:
		# 島に来た最初の表示では名前を出さない（島を作った直後は能力を配る前なので、W があるのに
		# 「からっぽ」と出ていた。2026-11-22 の通し）。選び替えたときだけ出す
		if _last_selected != -1:
			if sounds != null:
				sounds.play_slot_select(world.selected_slot)
			_flash_item_name()
		_last_selected = world.selected_slot
	if int(world.lend_mode) != _last_mode or int(world.throw_mode) != _last_throw:
		if _last_mode != -1:
			_flash_badge_label()
		_last_mode = int(world.lend_mode)
		_last_throw = int(world.throw_mode)
	if inventory != null:
		inventory.refresh()
	if pause_menu != null:
		pause_menu.refresh()


## ホットバーの各枠に出している「×n」の数（出していなければ 0）。テスト用。
func hotbar_stacks() -> PackedInt32Array:
	var out := PackedInt32Array()
	for slot in _slots:
		out.append(slot.stack)
	return out


## ホットバーの各枠の状態（文字）。テスト用。
func hotbar_descriptions() -> PackedStringArray:
	var out := PackedStringArray()
	for slot in _slots:
		out.append(slot.describe())
	return out


## 願いの一文を出している生き物（focus）の行き先が画面の外なら、縁に矢印を出す。
func update_wish_pointer(focus: Creature) -> void:
	if wish_pointer == null or world == null or world.camera_rig == null:
		return
	if is_inventory_open():
		focus = null
	var target: Variant = null
	var tint := WishPointer.FILL
	if focus != null and focus.wish_box.has_volume() and not focus.is_wish_met():
		target = focus.wish_box.get_center()
		tint = focus.nest_tint
	wish_pointer.point_to(world.camera_rig.camera(), target, tint)


func set_aim(aim: Crosshair.Aim) -> void:
	if crosshair != null:
		crosshair.set_aim(aim)


## 照準の下の案内。いまいちばん要る操作を 1 つだけ、キーの絵と数文字で出す（TeachHints。docs/w1-teaching.md）。
## 初めての人には、必要になった順に1つずつ出る（docs/onboarding.md）: 歩く → 見回す → 入口 →
## 能力を選ぶ・渡す → 貸した単発を使う → 取り戻す → …（目安の時間を過ぎたら）やり直し・メニュー。
func update_context(target: Node3D, in_reach: bool, on_checkpoint: bool) -> void:
	if is_inventory_open():
		_context.visible = false
		_context.set_meta("key", "")
		return
	# [キーの表記, 動作, 表記をそのまま出すか（省略なら InputMode.label で置きかえる）]
	var prompts: Array[Array] = []
	var picked := TeachHints.pick(self, target, in_reach, on_checkpoint)
	if not picked.is_empty():
		prompts.append(picked)
	# 狙っている相手の名前（照準の補助で何が選ばれたかが分かるように。地形のセルには出さない）
	var target_name := (
		"" if target == null or world == null else WorldQueries.target_name(world, target)
	)
	var key := str(prompts) + target_name + str(InputMode.using_pad) + str(KeyBindings.revision)
	if _context.get_meta("key", "") == key:
		return
	_context.set_meta("key", key)
	for child in _context_row.get_children():
		child.queue_free()
	if target_name != "":
		var name_label := Label.new()
		name_label.text = target_name
		name_label.theme_type_variation = &"Strong"
		name_label.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL + 1)
		_context_row.add_child(name_label)
	for p in prompts:
		var literal := p.size() > 2 and bool(p[2])
		var text := String(p[1])
		_context_row.add_child(
			(
				KeyPrompt.make_literal(String(p[0]), text)
				if literal
				else KeyPrompt.make(String(p[0]), text)
			)
		)
	_context.visible = not prompts.is_empty() or target_name != ""


## いま照準の下に出ている案内のキーの表記（テスト用）。
func context_keys() -> PackedStringArray:
	var out := PackedStringArray()
	if not _context.visible:
		return out
	for prompt in _context_row.get_children():
		if prompt is KeyPrompt and not prompt.is_queued_for_deletion():
			var cap := prompt.get_child(0) as PanelContainer
			out.append((cap.get_child(0) as Label).text)
	return out


## いま照準の下に出ている、狙っている相手の名前（テスト用。無ければ空）。
func context_target_name() -> String:
	if not _context.visible:
		return ""
	for child in _context_row.get_children():
		if child is Label and not child.is_queued_for_deletion():
			return (child as Label).text
	return ""


## いま照準の下に出ている案内の動作（テスト用）。
func context_actions() -> PackedStringArray:
	var out := PackedStringArray()
	if not _context.visible:
		return out
	for prompt in _context_row.get_children():
		if prompt is KeyPrompt and not prompt.is_queued_for_deletion():
			out.append((prompt.get_child(1) as Label).text)
	return out


func play_ui(event: StringName) -> void:
	if sounds != null:
		sounds.play_ui(event)


## かばんからホットバーへ移す案内を出す状況か（TeachHints が使う。テスト用にも使う）。
## 本当にかばんに使える能力があって、ホットバーに空きがあるときだけ（ステージの中）。
## 2026-11-23 から、拾った・F で取った能力は空きがあればホットバーへ入るので、かばんに入るのはホットバーが
## いっぱいだったとき・開始時にかばんへ置かれた能力だけ（その後に空きができたら出す）。
func needs_bag_prompt() -> bool:
	var stage_world := world as StageWorld
	if stage_world == null or stage_world.def == null or stage_world.def.is_hub():
		return false
	if not hints.should_show("bag"):
		return false
	var me := world.acting_id()
	var free := false
	for slot in RuleLedger.HOTBAR_SIZE:
		if world.ledger.hotbar_vessel(slot, me) == null:
			free = true
			break
	if not free:
		return false
	for v in world.ledger.inventory_vessels(me):
		var t := world.ledger.token(v.token_id)
		if (
			t != null
			and not v.is_equipment()
			and not t.is_prohibition
			and t.is_in_vessel()
			and RuleAction.is_triggered(t.action)
		):
			return true
	return false


## 移動キーの表記（割り当て直したキーとゲームパッドに合わせる）。
static func move_keys() -> String:
	var keys := PackedStringArray()
	for action: StringName in [&"move_forward", &"move_left", &"move_back", &"move_right"]:
		keys.append(InputMode.key(action))
	if Array(keys).all(func(k: String) -> bool: return k.begins_with("左スティック")):
		return "左スティック"
	return "/".join(keys)


static func look_keys() -> String:
	return "右スティック" if InputMode.using_pad else "マウス"


## 案内に出す能力の名前（ホットバーの名前と同じ）。
static func token_label(token: RuleToken) -> String:
	return ("%s禁止" if token.is_prohibition else "%s") % RuleAction.label(token.action)


func _set_world_hud_visible(on: bool) -> void:
	for node: CanvasItem in [crosshair, _hotbar, toasts]:
		node.visible = on
	if not on:
		_context.visible = false
		wish_pointer.visible = false


func _flash_item_name() -> void:
	var slot := _slots[world.selected_slot]
	_item_name_label.text = slot.flash_text()
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
	var stage_world := world as StageWorld
	_goal_note.text = (
		stage_world.def.display_name if stage_world != null and stage_world.def != null else ""
	)
	_goal_note.visible = _goal_note.text != ""
	_goal.visible = true
	_goal.modulate.a = 0.0
	_goal.pivot_offset = _goal.size * 0.5
	_goal.scale = Vector2.ONE * 0.6
	# カードが弾んで出て、上の印が1つずつ弾み、見出しが小さく跳ねる（見せて伝える。文字は増やさない）
	var tween := _goal.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_goal, "modulate:a", 1.0, 0.22)
	tween.parallel().tween_property(_goal, "scale", Vector2.ONE, 0.45)
	for i in _goal_marks.size():
		var mark := _goal_marks[i]
		mark.scale = Vector2.ZERO
		var pop := mark.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		pop.tween_interval(0.25 + 0.12 * i)
		pop.tween_property(mark, "scale", Vector2.ONE * 1.5, 0.16)
		pop.tween_property(mark, "scale", Vector2.ONE, 0.18)
	if _goal_title != null:
		_goal_title.pivot_offset = _goal_title.size * 0.5
		var hop := _goal_title.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		hop.tween_interval(0.55)
		hop.tween_property(_goal_title, "scale", Vector2(1.08, 0.94), 0.08)
		hop.tween_property(_goal_title, "scale", Vector2(0.96, 1.06), 0.1)
		hop.tween_property(_goal_title, "scale", Vector2.ONE, 0.16)
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

	wish_pointer = WishPointer.new()
	wish_pointer.name = "WishPointer"
	_root.add_child(wish_pointer)

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
	if world != null and world.player != null:
		inventory.player_id = world.player.player_id
		inventory.actions = world.ledger_actions
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
		leaf.pivot_offset = Vector2(4, 4)
		stars.add_child(leaf)
		_goal_marks.append(leaf)
	box.add_child(stars)
	var title := Label.new()
	_goal_title = title
	title.text = GOAL_TITLE
	title.theme_type_variation = &"Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	# 下の小さな行はステージの名前（「高台に到達しました・仮のゴール」は試作の島の言い方のままだった）
	_goal_note = Label.new()
	_goal_note.theme_type_variation = &"Note"
	_goal_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_goal_note)
	_center_band(_goal, 96.0, false)
