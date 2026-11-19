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
	world.update_highlight(world.aimed_block())


func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		world.camera_rig.rotate_by(motion.relative)
		return
	if event.is_action_pressed(&"release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event.is_action_pressed(&"inventory") and hud != null:
		var open := hud.toggle_inventory()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
		return
	if hud != null and hud.is_inventory_open():
		_handle_inventory(event)
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and event is InputEventMouseButton:
		# 最初のクリックはマウスを捕まえるだけにする（誤って付与しない）
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
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
		world.lend_to(world.aimed_block(), true)
	elif event.is_action_pressed(&"cycle_mode"):
		world.cycle_mode()
	elif event.is_action_pressed(&"toggle_reach"):
		world.toggle_reach()
	elif event.is_action_pressed(&"interact"):
		world.interact(world.aimed_block())
	elif event.is_action_pressed(&"restore_checkpoint"):
		world.restore_checkpoint()


func _handle_inventory(event: InputEvent) -> void:
	for i in RuleLedger.HOTBAR_SIZE:
		if event.is_action_pressed(StringName("slot_%d" % (i + 1))):
			hud.move_selected_inventory_item_to(i)
