extends TestCase
## 持ち物の画面を開いたまま番号キー・Esc を押す（PlayerInput を通す）。番号キーは指している器を動かすだけで、
## ホットバーの選択やほかの操作には使わない。Esc は、持ち上げていればそれをやめ、もう一度で閉じる。

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
	for node: Node in [input, hud, island]:
		node.queue_free()
	await tree.process_frame


func _press(code: Key) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	await tree.process_frame
	key = key.duplicate() as InputEventKey
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	await tree.process_frame


func test_number_keys_move_the_hovered_item_without_changing_the_selection() -> void:
	var stored := island.ledger.give_player_item(RuleAction.Kind.CLIMB, false)
	island.select_slot(4)
	assert_true(hud.toggle_inventory(), "opened")
	assert_false(hud.inventory.is_typing(), "the search box is not focused")
	hud.inventory.hover(stored.id)
	await _press(KEY_3)
	assert_eq(island.ledger.hotbar_vessel(2), stored, "the hovered item went to hotbar 3")
	assert_eq(island.selected_slot, 4, "the hotbar selection did not change")
	hud.inventory.hover(-1)
	hud.inventory.click_hotbar(2)
	assert_true(hud.inventory.is_holding())
	await _press(KEY_ESCAPE)
	assert_false(hud.inventory.is_holding(), "Esc cancels the pick first")
	assert_true(hud.is_inventory_open(), "and keeps the inventory open")
	await _press(KEY_ESCAPE)
	assert_false(hud.is_inventory_open(), "a second Esc closes it")
