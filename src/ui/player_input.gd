class_name PlayerInput
extends Node
## キーボード・マウスの入力を GameWorld の操作に変換する。ルールの判定はここに書かない。
## キー割当は project.godot の Input Map（企画書 8 の操作表）。

const ACTION_KEYS: Dictionary[StringName, RuleAction.Kind] = {
	&"move_forward": RuleAction.Kind.FORWARD,
	&"move_left": RuleAction.Kind.LEFT,
	&"move_back": RuleAction.Kind.BACK,
	&"move_right": RuleAction.Kind.RIGHT,
	&"jump": RuleAction.Kind.JUMP,
}

var world: GameWorld
var hud: Hud
## 投票・相棒ボットへの頼みごとを受け取る（GameRoot）。無ければ無視する。
var party: Node


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
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
	world.player.view_yaw = world.camera_rig.yaw
	var aimed := world.aimed_block()
	world.update_highlight(aimed)
	if hud != null:
		var in_reach := world.is_within_reach(aimed)
		var aim := Crosshair.Aim.NONE
		if aimed != null:
			aim = Crosshair.Aim.IN_REACH if in_reach else Crosshair.Aim.OUT_OF_REACH
		hud.set_aim(aim)
		hud.update_context(aimed, in_reach, world.is_on_checkpoint())
	var preview := world.update_range_preview(aimed)
	if hud != null:
		hud.show_range_preview(world.is_range_preview_active(), preview)


func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return
	var motion := event as InputEventMouseMotion
	if _radial_open():
		_handle_radial(event)
	elif motion != null:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			world.camera_rig.rotate_by(motion.relative)
	elif event.is_action_pressed(&"release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed(&"inventory") and hud != null:
		world.cancel_range_preview()
		var open := hud.toggle_inventory()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
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
			world.press_action(ACTION_KEYS[action_name])
	for i in RuleLedger.HOTBAR_SIZE:
		if event.is_action_pressed(StringName("slot_%d" % (i + 1))):
			world.select_slot(i)
	if event.is_action_pressed(&"lend_single"):
		if world.lend_to(world.aimed_block(), false) == RuleLedger.LendResult.OK and hud != null:
			hud.hints.used("lend")
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
		if hud != null:
			hud.hints.used("save" if world.is_on_checkpoint() else "recall")
		world.interact(world.aimed_block())
	elif _party_action(event):
		pass
	elif event.is_action_pressed(&"restore_checkpoint"):
		# プレビュー中の Esc は取り消しだけにする。それ以外はメニューを開く（戻る操作はメニューから）
		if world.is_range_preview_active():
			world.cancel_range_preview()
		elif hud != null:
			hud.pause_menu.open()


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
func _handle_inventory(event: InputEvent) -> void:
	for i in RuleLedger.HOTBAR_SIZE:
		if event.is_action_pressed(StringName("slot_%d" % (i + 1))):
			hud.inventory.move_selected_to_hotbar(i)
	if event.is_action_pressed(&"store_item"):
		hud.inventory.move_selected_to_inventory()


## Esc は検索欄に入力中でも持ち物画面を閉じる（世界は戻さない）。GUI より先に受け取る。
func _input(event: InputEvent) -> void:
	if hud == null or not hud.is_inventory_open():
		return
	if event.is_action_pressed(&"restore_checkpoint"):
		hud.toggle_inventory()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


## V（全員リセットの投票）と G/H/R（相棒ボット）。押されたら true。
func _party_action(event: InputEvent) -> bool:
	if party == null:
		return false
	for action: StringName in [&"vote_reset", &"bot_follow", &"bot_give", &"bot_recall"]:
		if event.is_action_pressed(action):
			party.call(&"handle_party_action", action)
			return true
	return false
