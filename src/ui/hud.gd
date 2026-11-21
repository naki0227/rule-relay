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
var _last_selected: int = -1
var _last_mode: int = -1
var _last_throw: int = -1
## 入口の stage_id → ステージの名前（毎フレーム定義を作らないように覚えておく）。
var _stage_names: Dictionary[String, String] = {}


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
	for i in RuleLedger.HOTBAR_SIZE:
		var v := world.ledger.hotbar_vessel(i, me)
		var t: RuleToken = null if v == null else world.ledger.token(v.token_id)
		_slots[i].show_token(t, i == world.selected_slot)
		# 仲間から集めた同じ能力の数（×n）。2個以上のときだけ出す
		_slots[i].stack = 0 if t == null else world.ledger.ability_count(t.action, me)
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


## 願いの一文を出している生き物（focus）の行き先が画面の外なら、縁に矢印を出す。
func update_wish_pointer(focus: Creature) -> void:
	if wish_pointer == null or world == null or world.camera_rig == null:
		return
	if is_inventory_open():
		focus = null
	var target: Variant = null
	if focus != null and focus.wish_box.has_volume() and not focus.is_wish_met():
		target = focus.wish_box.get_center()
	wish_pointer.point_to(world.camera_rig.camera(), target)


func set_aim(aim: Crosshair.Aim) -> void:
	if crosshair != null:
		crosshair.set_aim(aim)


## 照準の下の案内。狙っているもの・いる場所・いまの状況に応じて、まだ慣れていない操作だけを出す。
## 初めての人には、必要になった順に1つずつ出す（docs/onboarding.md）: 歩く・見回す → 入口 →
## 能力を選ぶ・渡す → 貸した単発を使う → 回収 → （目安の時間を過ぎたら）やり直し・メニュー。
func update_context(target: Node3D, in_reach: bool, on_checkpoint: bool) -> void:
	if is_inventory_open():
		_context.visible = false
		_context.set_meta("key", "")
		return
	# [キーの表記, 動作, 表記をそのまま出すか（省略なら InputMode.label で置きかえる）]
	var prompts: Array[Array] = []
	_first_step_prompts(prompts)
	if on_checkpoint and hints.should_show("save"):
		prompts.append(["F", "ここで保存"])
	_place_prompts(prompts)
	if target is Bell and in_reach:
		prompts.append(["F", "鳴らす"])
	elif target != null and in_reach:
		_lend_prompts(prompts, target)
	elif target != null and hints.should_show("throw"):
		if world.throw_mode:
			prompts.append(["C", "遠すぎる"])
		elif world.can_throw():
			prompts.append(["C", "投げるで届く"])
	_fire_prompts(prompts)
	_retry_prompts(prompts)
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


## 歩く・見回す（初めて遊ぶ人の最初の数秒だけ。少し歩いて見回したら出なくなる）。
func _first_step_prompts(prompts: Array[Array]) -> void:
	if hints.should_show("move"):
		prompts.append([move_keys(), "歩く", true])
	if hints.should_show("look"):
		prompts.append([look_keys(), "見回す", true])


## 足もとの物・ハブの入口（慣れても出す。そこで何ができるかの案内）。
func _place_prompts(prompts: Array[Array]) -> void:
	if world == null or world.player == null:
		return
	if world.nearest_world_item() != null:
		prompts.append(["F", "拾う"])
	var stage_world := world as StageWorld
	if stage_world == null:
		return
	var entrance := stage_world.entrance_at(world.player.global_position)
	if entrance != "":
		prompts.append(["F", "「%s」へ" % _stage_name(entrance)])


## 手の届く相手を狙っているとき。選んでいる能力の名前を出す（何を渡すのかが分かるように）。
## 範囲（まとめて）は、1つずつ渡すのに慣れてから出す（一度にたくさん並べない）。
func _lend_prompts(prompts: Array[Array], target: Node3D) -> void:
	var token := _selected_token()
	# 地形にも渡せるが、初めのうちは足もとの地面に案内を出さない（まずブロックで覚える。
	# 地面に渡せることは、自分で試して気づく）
	var ground := target is TerrainCell
	if token == null:
		if not ground:
			prompts.append(["1〜9", "能力をえらぶ"])
	elif hints.should_show("lend"):
		if token.holder_ids.is_empty() and not ground:
			prompts.append(["左クリック", "%sを渡す" % token_label(token)])
		if hints.should_show("select") and not ground:
			prompts.append(["1〜9", "えらぶ"])
	elif hints.should_show("range"):
		prompts.append(["右クリック", "まとめて"])
	var creature := target as Creature
	if creature != null and not creature.can_walk() and hints.should_show("creature_move"):
		prompts.append(["左クリック", "移動の能力を渡すと歩き出す"])
	var id := int(target.get("entity_id"))
	var holds := world != null and not world.ledger.tokens_on(id).is_empty()
	if holds and hints.should_show("recall"):
		prompts.append(["F", "回収"])


## 単発で貸した能力があるとき: 自分のキーで、貸した先が1回だけ動く（どこを向いていても出す）。
func _fire_prompts(prompts: Array[Array]) -> void:
	if world == null or world.player == null or not hints.should_show("fire"):
		return
	var me := world.acting_id()
	for action_name: StringName in PlayerInput.ACTION_KEYS:
		var kind: RuleAction.Kind = PlayerInput.ACTION_KEYS[action_name]
		if not world.ledger.pending_single_shots(kind, me).is_empty():
			var text := "貸した%sを使う" % RuleAction.label(kind)
			prompts.append([InputMode.key(action_name), text, true])


## ステージで目安の時間を過ぎたら、やり直しとメニューの場所をそっと出す（使ったら出なくなる）。
func _retry_prompts(prompts: Array[Array]) -> void:
	var stage_world := world as StageWorld
	if stage_world == null or stage_world.def == null or stage_world.def.is_hub():
		return
	if stage_seconds < stage_world.def.target_minutes * 60.0:
		return
	if hints.should_show("vote"):
		prompts.append(["V", "長押しでやり直し"])
	if hints.should_show("menu"):
		prompts.append(["Esc", "メニュー"])


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


func _selected_token() -> RuleToken:
	if world == null:
		return null
	var v := world.selected_vessel()
	return null if v == null else world.ledger.token(v.token_id)


func _stage_name(stage_id: String) -> String:
	if not _stage_names.has(stage_id):
		var stage := StageCatalog.by_id(stage_id)
		_stage_names[stage_id] = stage.display_name if stage != null else stage_id
	return _stage_names[stage_id]


func _set_world_hud_visible(on: bool) -> void:
	for node: CanvasItem in [crosshair, _hotbar, toasts]:
		node.visible = on
	if not on:
		_context.visible = false
		wish_pointer.visible = false


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
