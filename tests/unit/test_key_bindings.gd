extends TestCase
## キー割り当て: 初期値は project.godot、衝突は入れかえるか断る、保存して読み直せる、案内に反映される。


func after_each() -> void:
	# Input Map は全テストで共有なので、必ず初期の割り当てへもどす
	KeyBindings.new().apply()
	InputMode.using_pad = false


func test_defaults_come_from_the_project() -> void:
	var bindings := KeyBindings.new()
	assert_eq(bindings.get_descriptor(&"interact", KeyBindings.Slot.KEYBOARD), "key:%d" % KEY_F)
	assert_eq(bindings.get_descriptor(&"interact", KeyBindings.Slot.PAD), "joy:%d" % JOY_BUTTON_X)
	assert_eq(bindings.get_descriptor(&"lend_single", KeyBindings.Slot.KEYBOARD), "mouse:1")
	assert_eq(bindings.get_descriptor(&"move_forward", KeyBindings.Slot.PAD), "axis:1:-")
	assert_true(bindings.is_default())


func test_every_rebindable_action_has_both_slots() -> void:
	var bindings := KeyBindings.new()
	for action: StringName in KeyBindings.ACTIONS:
		assert_true(InputMap.has_action(action), String(action))
		for slot: KeyBindings.Slot in [KeyBindings.Slot.KEYBOARD, KeyBindings.Slot.PAD]:
			assert_ne(bindings.get_descriptor(action, slot), "", "%s %d" % [action, slot])


func test_conflict_with_another_main_action_swaps() -> void:
	var bindings := KeyBindings.new()
	var result := bindings.assign(&"jump", KeyBindings.Slot.KEYBOARD, "key:%d" % KEY_F)
	assert_true(result.ok)
	assert_eq(result.swapped_with, &"interact")
	assert_eq(bindings.get_descriptor(&"jump", KeyBindings.Slot.KEYBOARD), "key:%d" % KEY_F)
	assert_eq(
		bindings.get_descriptor(&"interact", KeyBindings.Slot.KEYBOARD),
		"key:%d" % KEY_SPACE,
		"interact takes jump's old key, so nothing is left unbound"
	)
	assert_false(bindings.is_default())


func test_conflict_with_a_fixed_action_is_refused() -> void:
	var bindings := KeyBindings.new()
	var result := bindings.assign(&"jump", KeyBindings.Slot.KEYBOARD, "key:%d" % KEY_C)
	assert_false(result.ok)
	assert_eq(result.blocked_by, &"toggle_reach")
	assert_eq(bindings.get_descriptor(&"jump", KeyBindings.Slot.KEYBOARD), "key:%d" % KEY_SPACE)
	result = bindings.assign(&"dash", KeyBindings.Slot.PAD, "joy:%d" % JOY_BUTTON_DPAD_UP)
	assert_eq(result.blocked_by, &"cycle_mode", "pad buttons are checked too")


func test_wrong_kind_of_input_is_refused() -> void:
	var bindings := KeyBindings.new()
	assert_false(bindings.assign(&"jump", KeyBindings.Slot.PAD, "key:%d" % KEY_J).ok)
	assert_false(bindings.assign(&"jump", KeyBindings.Slot.KEYBOARD, "joy:3").ok)
	assert_false(bindings.assign(&"jump", KeyBindings.Slot.KEYBOARD, "broken").ok)
	assert_false(bindings.assign(&"slot_1", KeyBindings.Slot.KEYBOARD, "key:%d" % KEY_J).ok)


func test_save_and_load_round_trip() -> void:
	var bindings := KeyBindings.new()
	bindings.assign(&"jump", KeyBindings.Slot.KEYBOARD, "key:%d" % KEY_J)
	bindings.assign(&"vote_reset", KeyBindings.Slot.PAD, "joy:%d" % JOY_BUTTON_LEFT_STICK)
	var config := ConfigFile.new()
	bindings.save_to(config, "input")
	var loaded := KeyBindings.new()
	loaded.load_from(config, "input")
	assert_eq(loaded.get_descriptor(&"jump", KeyBindings.Slot.KEYBOARD), "key:%d" % KEY_J)
	assert_eq(
		loaded.get_descriptor(&"vote_reset", KeyBindings.Slot.PAD), "joy:%d" % JOY_BUTTON_LEFT_STICK
	)


func test_broken_saved_values_keep_defaults() -> void:
	var config := ConfigFile.new()
	config.set_value("input", "jump", "not an array")
	config.set_value("input", "dash", ["key:%d" % KEY_C, 42])
	var loaded := KeyBindings.new()
	loaded.load_from(config, "input")
	assert_true(loaded.is_default(), "garbage and conflicts with fixed actions are ignored")


func test_apply_changes_input_map_and_prompts() -> void:
	var bindings := KeyBindings.new()
	bindings.assign(&"interact", KeyBindings.Slot.KEYBOARD, "key:%d" % KEY_G)
	assert_eq(
		bindings.assign(&"interact", KeyBindings.Slot.PAD, "joy:%d" % JOY_BUTTON_Y).blocked_by,
		&"toggle_reach",
		"Y is 触る／投げる on the pad"
	)
	bindings.assign(&"interact", KeyBindings.Slot.PAD, "joy:%d" % JOY_BUTTON_LEFT_STICK)
	bindings.apply()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	key.pressed = true
	assert_true(key.is_action_pressed(&"interact"))
	assert_eq(InputMode.label("F"), "G", "prompts written as F follow the new key")
	InputMode.using_pad = true
	assert_eq(InputMode.label("F"), "左スティック押し")
	assert_eq(InputMode.key(&"lend_single"), "RT")


func test_vote_reset_keeps_its_hold_behaviour_on_a_new_key() -> void:
	var bindings := KeyBindings.new()
	bindings.assign(&"vote_reset", KeyBindings.Slot.KEYBOARD, "key:%d" % KEY_B)
	bindings.apply()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	var hold := HoldAction.new(0.8)
	var fired := 0
	for i in 60:
		if hold.update(Input.is_action_pressed(&"vote_reset"), 1.0 / 60.0):
			fired += 1
	var release := key.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	assert_eq(fired, 1, "holding the rebound key fires the vote once")


func test_names_are_readable() -> void:
	assert_eq(InputNames.text(InputNames.decode("key:%d" % KEY_ESCAPE)), "Esc")
	assert_eq(InputNames.text(InputNames.decode("mouse:2")), "右クリック")
	assert_eq(InputNames.text(InputNames.decode("joy:%d" % JOY_BUTTON_START)), "Start")
	assert_eq(InputNames.text(InputNames.decode("axis:5:+")), "RT")
	assert_eq(InputNames.text(InputNames.decode("axis:0:-")), "左スティック←")
	assert_eq(InputNames.decode("axis:1:?"), null)
	assert_eq(InputNames.decode("key:-3"), null)
