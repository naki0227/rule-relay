extends TestCase
## 設定の画面（Esc のメニューの「せってい」）: 開く・割り当てる・衝突・はじめにもどす・閉じる。
## 和文の折り返しの設定（説明文が単語の途中で改行されない）もここで確かめる。

const PATH := "user://zz_test_settings_menu.cfg"

var island: PrototypeIsland
var hud: Hud
var menu: SettingsMenu


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	hud = Hud.new()
	hud.world = island
	tree.root.add_child(hud)
	menu = hud.pause_menu.settings_menu
	menu.settings = GameSettings.new(PATH)
	await wait_physics_frames(5)


func after_each() -> void:
	tree.paused = false
	tree.root.content_scale_factor = 1.0
	KeyBindings.new().apply()
	GameSettings.new().apply_volumes()
	InputMode.using_pad = false
	hud.queue_free()
	island.queue_free()
	for path: String in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	await tree.process_frame


func _key(code: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.pressed = true
	return key


func _open_settings() -> void:
	hud.pause_menu.open()
	hud.pause_menu.choose("settings")


func test_reachable_from_the_pause_menu_with_focus_for_gamepads() -> void:
	_open_settings()
	assert_true(menu.is_open())
	assert_true(tree.paused, "the game stays paused")
	var focused := menu.get_viewport().gui_get_focus_owner()
	assert_ne(focused, null, "a control has focus so the d-pad can move around")
	assert_true(menu.is_ancestor_of(focused))
	menu.close()
	assert_true(hud.pause_menu.is_open(), "closing settings goes back to the pause card")


func test_rebinding_updates_prompts_and_saves() -> void:
	_open_settings()
	menu.begin_capture(&"interact", KeyBindings.Slot.KEYBOARD)
	assert_true(menu.is_capturing())
	assert_true(menu.capture(_key(KEY_G)))
	assert_false(menu.is_capturing())
	assert_eq(InputMode.label("F"), "G")
	hud.update_context(island.row[1], true, false)  # ジャンプ禁止が置かれている
	var prompt := _prompt_for("回収")
	assert_ne(prompt, null)
	assert_eq(((prompt.get_child(0) as Control).get_child(0) as Label).text, "G")
	var saved := GameSettings.new(PATH)
	saved.load_file()
	assert_eq(
		saved.bindings.get_descriptor(&"interact", KeyBindings.Slot.KEYBOARD), "key:%d" % KEY_G
	)


func test_conflicts_swap_or_refuse() -> void:
	_open_settings()
	menu.begin_capture(&"jump", KeyBindings.Slot.KEYBOARD)
	menu.capture(_key(KEY_F))
	assert_eq(InputMode.key(&"jump"), "F")
	assert_eq(InputMode.key(&"interact"), "Space", "swapped, so interact is still reachable")
	menu.begin_capture(&"dash", KeyBindings.Slot.KEYBOARD)
	menu.capture(_key(KEY_Q))
	assert_eq(InputMode.key(&"dash"), "Shift", "Q is 方式の切り替え, so it is refused")


func test_pad_slot_takes_only_pad_input() -> void:
	_open_settings()
	menu.begin_capture(&"jump", KeyBindings.Slot.PAD)
	menu.capture(_key(KEY_J))
	assert_true(menu.is_capturing(), "a key does not end a pad capture")
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_LEFT_STICK
	button.pressed = true
	assert_true(menu.capture(button))
	InputMode.using_pad = true
	assert_eq(InputMode.key(&"jump"), "左スティック押し")


func test_text_size_and_reset_to_defaults() -> void:
	_open_settings()
	menu.choose_scale(3)
	assert_almost(tree.root.content_scale_factor, GameSettings.SCALES[3], 0.001)
	assert_lt(hud.inventory.fit_scale(), 1.0, "the bag shrinks to fit when text is very large")
	menu.begin_capture(&"jump", KeyBindings.Slot.KEYBOARD)
	menu.capture(_key(KEY_J))
	menu.choose_reset()
	assert_eq(InputMode.key(&"jump"), "J", "the first press only arms the reset")
	menu.choose_reset()
	assert_eq(InputMode.key(&"jump"), "Space")
	assert_almost(tree.root.content_scale_factor, 1.0, 0.001)
	assert_true(menu.settings.bindings.is_default())
	assert_eq(menu.settings.music_volume, GameSettings.DEFAULT_MUSIC_VOLUME)


func test_volume_sliders_apply_to_buses_and_persist() -> void:
	_open_settings()
	assert_eq(menu._music_slider.value, 70.0, "BGM starts at 70%")
	menu.choose_music_volume(40)
	menu.choose_sfx_volume(0)
	var music := AudioServer.get_bus_index(AudioBuses.MUSIC)
	assert_almost(AudioServer.get_bus_volume_db(music), linear_to_db(0.4), 0.01)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioBuses.SFX)))
	assert_eq(menu._music_value.text, "40%")
	menu.close()
	var saved := GameSettings.new(PATH)
	saved.load_file()
	assert_eq(saved.music_volume, 40)
	assert_eq(saved.sfx_volume, 0)


func test_volume_slider_moves_with_the_d_pad() -> void:
	_open_settings()
	var slider := menu._music_slider
	slider.grab_focus()
	await tree.process_frame
	assert_eq(menu.get_viewport().gui_get_focus_owner(), slider)
	for pressed: bool in [true, false]:
		var right := InputEventJoypadButton.new()
		right.button_index = JOY_BUTTON_DPAD_RIGHT
		right.pressed = pressed
		Input.parse_input_event(right)
		Input.flush_buffered_events()
		await tree.process_frame
	assert_eq(slider.value, 75.0, "one step of 5% to the right")
	assert_eq(menu.settings.music_volume, 75)


func test_capture_times_out() -> void:
	_open_settings()
	menu.begin_capture(&"jump", KeyBindings.Slot.KEYBOARD)
	menu._process(SettingsMenu.CAPTURE_SECONDS + 0.1)
	assert_false(menu.is_capturing())
	assert_eq(InputMode.key(&"jump"), "Space")


func test_long_texts_wrap_at_japanese_phrase_boundaries() -> void:
	var detail := hud.inventory.find_children("*", "Label", true, false).filter(
		func(node: Node) -> bool: return (node as Label).autowrap_mode != TextServer.AUTOWRAP_OFF
	)
	assert_gt(detail.size(), 0.0)
	for label: Node in detail:
		assert_eq((label as Label).language, UiTheme.WRAP_LANGUAGE, label.name)
		assert_eq((label as Label).autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	var text := "その向きへまっすぐ3マス突進する力（後ろへは無し）。途中の穴も抜ける。ジャンプブーツを装備すると、高く跳べる。"
	for width: int in [230, 250, 290, 330]:
		for line: String in _wrapped(text, width):
			assert_false(line.ends_with("装"), "「装備」is not split at width %d" % width)
			assert_false(line.ends_with("突"), "「突進」is not split at width %d" % width)
			for head: String in ["。", "、", "）", "ー", "ャ"]:
				assert_false(_wrapped_head(line, head, text), "no line starts with %s" % head)


func _wrapped(text: String, width: int) -> PackedStringArray:
	var paragraph := TextParagraph.new()
	paragraph.width = width
	paragraph.break_flags = (
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	)
	paragraph.add_string(text, UiTheme.medium(), UiTheme.SIZE_BODY, UiTheme.WRAP_LANGUAGE)
	var lines := PackedStringArray()
	for i in paragraph.get_line_count():
		var span := paragraph.get_line_range(i)
		lines.append(text.substr(span.x, span.y - span.x))
	return lines


func _wrapped_head(line: String, head: String, text: String) -> bool:
	return line.begins_with(head) and not text.begins_with(line)


func _prompt_for(action_text: String) -> KeyPrompt:
	for child in hud.find_children("*", "HBoxContainer", true, false):
		var prompt := child as KeyPrompt
		if prompt == null or prompt.is_queued_for_deletion():
			continue
		if (prompt.get_child(1) as Label).text == action_text:
			return prompt
	return null
