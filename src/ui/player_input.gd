class_name PlayerInput
extends Node
## キーボード・マウス・ゲームパッドの入力を GameWorld の操作に変換する。ルールの判定はここに書かない。
## キー割当は project.godot の Input Map（企画書 8 の操作表）。ゲームパッドは Xbox 風の並び
## （Steam Deck と同じ）: 左スティック 移動・右スティック カメラ・A ジャンプ・X F（回収など）・
## Y 触る／投げる・RT 渡す・LT まとめて渡す（押している間プレビュー）・LB/RB ホットバー・
## 十字↑ 方式の切り替え・十字↓ 長押し 全員リセットの投票・View 持ち物・Start メニュー・右スティック押し込み 円形メニュー。

const ACTION_KEYS: Dictionary[StringName, RuleAction.Kind] = {
	&"move_forward": RuleAction.Kind.FORWARD,
	&"move_left": RuleAction.Kind.LEFT,
	&"move_back": RuleAction.Kind.BACK,
	&"move_right": RuleAction.Kind.RIGHT,
	&"jump": RuleAction.Kind.JUMP,
	&"dash": RuleAction.Kind.DASH,
}

## 右スティックでカメラを回す速さ（マウスの移動量に換算して 1 秒あたり。仮値）。
## 遊ぶ人は設定画面の「視点の速さ（パッド）」で倍率を変えられる（GameSettings.pad_sensitivity）。
const PAD_LOOK_SPEED: float = 800.0
## 操作の案内「歩く」「見回す」を慣れたことにする量（1回分。HintMemory.LEARN_AFTER 回で消える）。
const WALK_SECONDS_PER_USE: float = 1.0
const LOOK_RADIANS_PER_USE: float = 0.8

var world: GameWorld
var hud: Hud
## 全員リセットの投票を受け取る（GameRoot）。無ければ無視する。
var party: Node
## V（十字↓）は長押しで投票する（誤操作を防ぐ）。
var _vote_hold := HoldAction.new()
var _walked: float = 0.0
var _turned: float = 0.0
var _last_yaw: float = NAN


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if world == null or world.player == null:
		return
	var blocked := hud != null and hud.is_inventory_open()
	var intent := Vector2.ZERO
	if not blocked:
		intent = Vector2(
			Input.get_axis(&"move_left", &"move_right"),
			Input.get_axis(&"move_back", &"move_forward")
		)
	world.player.move_intent = intent
	_hold_vote(blocked, delta)
	_look_with_stick(delta)
	_note_first_steps(intent, delta)
	world.player.view_yaw = world.camera_rig.yaw
	var aimed := world.aimed_block()
	world.update_highlight(aimed)
	# 願いの一文は、狙っているか近くにいる生き物1匹だけに出す（にぎやかにしない）
	var focus := WorldQueries.wish_focus(world, aimed)
	for creature: Creature in world.creatures.values():
		creature.show_wish(creature == focus)
	if hud != null:
		hud.update_wish_pointer(focus)
	if hud != null:
		var in_reach := world.is_within_reach(aimed)
		var aim := Crosshair.Aim.NONE
		if aimed != null:
			aim = Crosshair.Aim.IN_REACH if in_reach else Crosshair.Aim.OUT_OF_REACH
		hud.set_aim(aim)
		hud.update_context(aimed, in_reach, world.is_on_checkpoint())
	# 範囲のプレビューは円と円板だけで示す（文字の札は出さない。2026-11-21 本人）
	world.update_range_preview(aimed)


func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return
	var motion := event as InputEventMouseMotion
	if _radial_open():
		_handle_radial(event)
	elif motion != null:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var mouse_scale := GameSettings.get_current().mouse_sensitivity
			world.camera_rig.rotate_by(motion.relative * mouse_scale)
	elif event.is_action_pressed(&"release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed(&"inventory") and hud != null:
		world.cancel_range_preview()
		if hud.needs_bag_prompt():
			_note(&"bag")
		var open := hud.toggle_inventory()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
		if open and event is InputEventJoypadButton:
			# ゲームパッドでは検索欄に文字を打たないので、十字キーと A を持ち物の操作に回す
			get_viewport().gui_release_focus()
	elif hud != null and hud.is_inventory_open():
		_handle_inventory(event)
	elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and event is InputEventMouseButton:
		# 最初のクリックはマウスを捕まえるだけにする（誤って付与しない）
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_handle_gameplay(event)


func _handle_gameplay(event: InputEvent) -> void:
	for action_name: StringName in ACTION_KEYS:
		if event.is_action_pressed(action_name):
			var kind := ACTION_KEYS[action_name]
			if (
				hud != null
				and not world.ledger.pending_single_shots(kind, world.acting_id()).is_empty()
			):
				hud.hints.used("fire")
			world.press_action(kind)
	for i in RuleLedger.HOTBAR_SIZE:
		if event.is_action_pressed(StringName("slot_%d" % (i + 1))):
			world.select_slot(i)
			_note(&"select")
	if _step_hotbar(event):
		_note(&"select")
	if event.is_action_pressed(&"lend_single"):
		var target := world.aimed_block()
		if world.lend_to(target, false) == RuleLedger.LendResult.OK and hud != null:
			hud.hints.used("lend")
			if target is Creature and (target as Creature).can_walk():
				hud.hints.used("creature_move")
	elif event.is_action_pressed(&"lend_range"):
		world.begin_range_preview()
	elif event.is_action_released(&"lend_range"):
		if world.is_range_preview_active():
			var result := world.commit_range_preview(world.aimed_block())
			if result == RuleLedger.LendResult.OK and hud != null:
				hud.hints.used("range")
	elif event.is_action_pressed(&"radial_menu"):
		world.cancel_range_preview()
		if hud != null:
			hud.radial_menu.open(world.lend_mode)
			hud.play_ui(&"radial_open")
	elif event.is_action_pressed(&"cycle_mode"):
		world.cycle_mode()
		hud.play_ui(&"ui_select")
	elif event.is_action_pressed(&"toggle_reach"):
		world.toggle_reach()
		hud.play_ui(&"ui_select")
		if hud != null:
			hud.hints.used("throw")
	elif event.is_action_pressed(&"interact"):
		_note_interact(world.aimed_block())
		world.interact(world.aimed_block())
	elif event.is_action_pressed(&"restore_checkpoint"):
		# プレビュー中の Esc は取り消しだけにする。それ以外はメニューを開く（戻る操作はメニューから）
		if world.is_range_preview_active():
			world.cancel_range_preview()
		elif hud != null:
			hud.pause_menu.open()
			# 同じ Esc を、開いたばかりのメニュー（「Esc で閉じる」）に渡さない。HUD が入力より先に
			# 木にあるゲーム本体（GameRoot）では、渡すと開いた直後に閉じてしまっていた
			get_viewport().set_input_as_handled()
			_note(&"menu")
			_restart_retry_timer()


func _radial_open() -> bool:
	return hud != null and hud.radial_menu.visible


## 円形 UI を開いている間: マウスの移動は選択に使い、カメラは回さない。
## ホイールを離すと決定、Esc で何も変えずに閉じる。
func _handle_radial(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		hud.radial_menu.drag(motion.relative)
	elif event.is_action_released(&"radial_menu"):
		var index := hud.radial_menu.picked_index()
		hud.radial_menu.close()
		if index >= 0:
			var ok := world.set_lend_mode(RadialSelector.MODES[index])
			hud.play_ui(&"ui_confirm" if ok else &"ui_error")
		else:
			hud.play_ui(&"ui_cancel")
	elif event.is_action_pressed(&"restore_checkpoint"):
		hud.radial_menu.close()


## 持ち物画面を開いている間（検索欄に入力中のキーは検索欄が受け取るので、ここには来ない）。
## 1〜9 は、マウスが指している器をその番号のホットバーへ（入っていた器と入れ替え）。ホットバーの選択は変えない。
## ゲームパッド: 十字←→ で持ち物を選び、A で持ち上げ、LB/RB で入れる枠を選んで A で置く。X でかばんへ、Y で装備。
func _handle_inventory(event: InputEvent) -> void:
	var panel := hud.inventory
	for i in RuleLedger.HOTBAR_SIZE:
		if event.is_action_pressed(StringName("slot_%d" % (i + 1))):
			panel.number_key(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"store_item"):
		if panel.is_holding():
			panel.click_bag(-1)
		else:
			panel.move_selected_to_inventory()
	if not event is InputEventJoypadButton:
		return
	_step_hotbar(event)
	if event.is_action_pressed(&"ui_left"):
		_step_inventory(-1)
	elif event.is_action_pressed(&"ui_right"):
		_step_inventory(1)
	elif event.is_action_pressed(&"jump"):
		if panel.is_holding():
			panel.click_hotbar(world.selected_slot)
		else:
			panel.pick(panel.selected_vessel_id())
	elif event.is_action_pressed(&"interact"):
		if panel.is_holding():
			panel.click_bag(-1)
		else:
			panel.move_selected_to_inventory()
	elif event.is_action_pressed(&"toggle_reach"):
		panel.toggle_equip_selected()


## LB/RB: ホットバーの枠を1つ前・後ろへ（端で反対側へ回る）。選び替えたら true。
func _step_hotbar(event: InputEvent) -> bool:
	var step := 0
	if event.is_action_pressed(&"hotbar_prev"):
		step = -1
	elif event.is_action_pressed(&"hotbar_next"):
		step = 1
	if step != 0:
		world.select_slot(posmod(world.selected_slot + step, RuleLedger.HOTBAR_SIZE))
	return step != 0


## 持ち物画面で、見えている持ち物を1つ前・後ろへ選ぶ。
func _step_inventory(step: int) -> void:
	var ids := hud.inventory.visible_vessel_ids()
	if ids.is_empty():
		return
	var at := ids.find(hud.inventory.selected_vessel_id())
	hud.inventory.select_vessel(ids[posmod(at + step, ids.size())])


## 右スティック: カメラを回す。円形メニューを開いている間は、倒した向きで方式を選ぶ。
func _look_with_stick(delta: float) -> void:
	var look := Input.get_vector(&"camera_left", &"camera_right", &"camera_up", &"camera_down")
	if _radial_open():
		if look.length() > 0.3:
			hud.radial_menu.point(look)
	elif look != Vector2.ZERO and not (hud != null and hud.is_inventory_open()):
		var speed := PAD_LOOK_SPEED * GameSettings.get_current().pad_sensitivity
		world.camera_rig.rotate_by(look * speed * delta)


## Esc: 検索欄に入力中ならそこから出るだけ、持ち上げていればやめるだけ。どちらでもなければ持ち物画面を閉じる
## （世界は戻さない）。GUI より先に受け取る。
func _input(event: InputEvent) -> void:
	InputMode.observe(event)
	if hud == null or not hud.is_inventory_open():
		return
	if event.is_action_pressed(&"restore_checkpoint"):
		get_viewport().set_input_as_handled()
		if hud.inventory.handle_escape():
			return
		hud.toggle_inventory()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## V 長押し（十字↓ 長押し）で全員リセットの投票。持ち物画面を開いている間は数えない。
func _hold_vote(blocked: bool, delta: float) -> void:
	var pressed := party != null and not blocked and Input.is_action_pressed(&"vote_reset")
	if _vote_hold.update(pressed, delta):
		party.call(&"handle_party_action", &"vote_reset")
		_note(&"vote")
		_restart_retry_timer()


## 操作の案内に「1回使った」と記録する（HUD が無ければ何もしない）。
func _note(hint: StringName) -> void:
	if hud != null:
		hud.hints.used(String(hint))


## やり直し・メニューを使ったら、次に「やり直し」の案内を出すのは、また目安の時間がたってから。
func _restart_retry_timer() -> void:
	if hud != null:
		hud.stage_seconds = 0.0


## F を押したとき: 案内が出ていた操作（保存・回収）を本当にしたときだけ数える
## （入口に入る・鐘を鳴らすなどで「回収」に慣れたことにしない）。
func _note_interact(target: Node3D) -> void:
	if world.is_on_checkpoint():
		_note(&"save")
	elif target != null and world.is_within_reach(target) and not target is Bell:
		if not world.ledger.tokens_on(int(target.get("entity_id"))).is_empty():
			_note(&"recall")


## 歩いた時間と、カメラを回した角度を数える（「歩く」「見回す」の案内を慣れたら消すため）。
func _note_first_steps(intent: Vector2, delta: float) -> void:
	if intent.length() > 0.1:
		_walked += delta
		if _walked >= WALK_SECONDS_PER_USE:
			_walked -= WALK_SECONDS_PER_USE
			_note(&"move")
	var yaw := world.camera_rig.yaw
	if not is_nan(_last_yaw):
		_turned += absf(angle_difference(_last_yaw, yaw))
		if _turned >= LOOK_RADIANS_PER_USE:
			_turned -= LOOK_RADIANS_PER_USE
			_note(&"look")
	_last_yaw = yaw
