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
		world.lend_to(world.aimed_block(), false)
	elif event.is_action_pressed(&"lend_range"):
		world.begin_range_preview()
	elif event.is_action_released(&"lend_range"):
		if world.is_range_preview_active():
			world.commit_range_preview(world.aimed_block())
	elif event.is_action_pressed(&"radial_menu"):
		world.cancel_range_preview()
		if hud != null:
			hud.radial_menu.open(world.lend_mode)
	elif event.is_action_pressed(&"cycle_mode"):
		world.cycle_mode()
	elif event.is_action_pressed(&"toggle_reach"):
		world.toggle_reach()
	elif event.is_action_pressed(&"interact"):
		world.interact(world.aimed_block())
	elif event.is_action_pressed(&"restore_checkpoint"):
		# プレビュー中の Esc は取り消しだけにする（うっかり世界を戻さない）
		if world.is_range_preview_active():
			world.cancel_range_preview()
		else:
			world.restore_checkpoint()


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
			world.set_lend_mode(RadialSelector.MODES[index])
	elif event.is_action_pressed(&"restore_checkpoint"):
		hud.radial_menu.close()


func _handle_inventory(event: InputEvent) -> void:
	for i in RuleLedger.HOTBAR_SIZE:
		if event.is_action_pressed(StringName("slot_%d" % (i + 1))):
			hud.move_selected_inventory_item_to(i)
