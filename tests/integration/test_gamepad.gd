extends TestCase
## ゲームパッド（Xbox 風の並び。Steam Deck も同じ）で遊べること。
## Input.parse_input_event でボタン・スティックの入力を流し、島・HUD・入力の組み合わせで確かめる。

const JUMP_SLOT := 4

var island: PrototypeIsland
var hud: Hud
var input: PlayerInput


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	hud = Hud.new()
	hud.world = island
	tree.root.add_child(hud)
	input = PlayerInput.new()
	input.world = island
	input.hud = hud
	tree.root.add_child(input)
	await wait_physics_frames(10)


func after_each() -> void:
	for axis: int in [0, 1, 2, 3, 4, 5]:
		_stick(axis, 0.0)
	InputMode.using_pad = false
	for node: Node in [input, hud, island]:
		node.queue_free()
	await tree.process_frame


func _button(index: int, pressed: bool = true) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = index as JoyButton
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap(index: int) -> void:
	_button(index, true)
	await tree.process_frame
	_button(index, false)
	await tree.process_frame


func _stick(axis: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis as JoyAxis
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func test_prompts_switch_to_pad_labels() -> void:
	await _tap(JOY_BUTTON_RIGHT_SHOULDER)
	assert_true(InputMode.using_pad)
	assert_eq(InputMode.label("F"), "X")
	assert_eq(InputMode.label("左クリック"), "RT")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	InputMode.observe(key)
	assert_eq(InputMode.label("F"), "F", "back to keyboard labels")


func test_shoulder_buttons_step_the_hotbar() -> void:
	island.select_slot(0)
	await _tap(JOY_BUTTON_RIGHT_SHOULDER)
	assert_eq(island.selected_slot, 1)
	await _tap(JOY_BUTTON_LEFT_SHOULDER)
	await _tap(JOY_BUTTON_LEFT_SHOULDER)
	assert_eq(island.selected_slot, RuleLedger.HOTBAR_SIZE - 1, "wraps around")


func test_left_stick_walks_and_a_jumps() -> void:
	var start := island.player.global_position
	_stick(JOY_AXIS_LEFT_Y, -1.0)
	await wait_physics_frames(20)
	_stick(JOY_AXIS_LEFT_Y, 0.0)
	assert_gt(island.player.global_position.distance_to(start), 0.5, "walked forward")
	await wait_physics_frames(10)
	await _tap(JOY_BUTTON_A)
	await wait_physics_frames(6)
	assert_gt(island.player.velocity.y, 0.5, "A jumps")


func test_right_stick_turns_the_camera() -> void:
	var yaw := island.camera_rig.yaw
	_stick(JOY_AXIS_RIGHT_X, 1.0)
	await wait_physics_frames(15)
	_stick(JOY_AXIS_RIGHT_X, 0.0)
	assert_lt(island.camera_rig.yaw, yaw - 0.1, "camera turned")


func test_inventory_with_the_pad() -> void:
	var stored := island.ledger.give_player_item(RuleAction.Kind.CLIMB, false)
	island.select_slot(8)
	await _tap(JOY_BUTTON_BACK)
	assert_true(hud.is_inventory_open(), "View opens the inventory")
	var ids := hud.inventory.visible_vessel_ids()
	for i in ids.size():
		if hud.inventory.selected_vessel_id() == stored.id:
			break
		await _tap(JOY_BUTTON_DPAD_RIGHT)
	assert_eq(hud.inventory.selected_vessel_id(), stored.id, "D-pad picks the item")
	await _tap(JOY_BUTTON_A)
	assert_true(hud.inventory.is_holding(), "A picks it up")
	assert_eq(island.ledger.hotbar_vessel(8), null, "not placed yet")
	await _tap(JOY_BUTTON_A)
	assert_eq(island.ledger.hotbar_vessel(8), stored, "A again puts it on the selected hotbar slot")
	assert_false(hud.inventory.is_holding())
	await _tap(JOY_BUTTON_START)
	assert_false(hud.is_inventory_open(), "Start closes it")
