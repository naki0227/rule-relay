extends TestCase
## タイトルの「せってい」: Esc のメニューと同じ設定の画面を開き、ゲームパッドだけでも行き来できる。

const PATH := "user://zz_test_title_settings.cfg"

var title: TitleMenu


func before_each() -> void:
	title = TitleMenu.new()
	tree.root.add_child(title)
	title.settings_menu.settings = GameSettings.new(PATH)
	await tree.process_frame
	await tree.process_frame


func after_each() -> void:
	tree.root.content_scale_factor = 1.0
	KeyBindings.new().apply()
	InputMode.using_pad = false
	title.queue_free()
	for path: String in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	await tree.process_frame


func _settings_button() -> Button:
	for node: Node in title.menu_box().find_children("*", "Button", true, false):
		if (node as Button).text == "せってい":
			return node as Button
	return null


func _focused() -> Control:
	return title.get_viewport().gui_get_focus_owner()


## パッドのボタンを押して離す（Xbox 風の並び: A 決定・B もどる・十字キーで移動）。
func _tap(index: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = index
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await tree.process_frame


func test_settings_button_opens_the_same_settings_menu() -> void:
	var button := _settings_button()
	assert_ne(button, null, "the title has a せってい button")
	if button == null:
		return
	button.pressed.emit()
	assert_true(title.is_settings_open())
	assert_true(title.settings_menu is SettingsMenu, "the same screen as the pause menu")
	var focused := _focused()
	assert_ne(focused, null, "a control has focus so the d-pad can move around")
	assert_true(title.settings_menu.is_ancestor_of(focused), "focus is inside the settings")
	assert_false(title.menu_box().is_visible_in_tree(), "the title card cannot steal focus")


func test_gamepad_reaches_settings_and_comes_back() -> void:
	var button := _settings_button()
	assert_ne(button, null)
	if button == null:
		return
	button.grab_focus()
	await _tap(JOY_BUTTON_A)
	assert_true(title.is_settings_open(), "A on せってい opens the settings")
	await _tap(JOY_BUTTON_DPAD_DOWN)
	assert_true(title.settings_menu.is_ancestor_of(_focused()), "the d-pad stays in the settings")
	await _tap(JOY_BUTTON_B)
	assert_false(title.is_settings_open(), "B closes the settings")
	assert_true(title.menu_box().is_visible_in_tree())
	assert_eq(_focused(), button, "focus returns to せってい")


func test_changes_from_the_title_apply_and_save() -> void:
	_settings_button().pressed.emit()
	var menu := title.settings_menu
	menu.begin_capture(&"interact", KeyBindings.Slot.KEYBOARD)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	key.pressed = true
	assert_true(menu.capture(key))
	assert_eq(InputMode.key(&"interact"), "G")
	menu.close()
	var saved := GameSettings.new(PATH)
	saved.load_file()
	assert_eq(
		saved.bindings.get_descriptor(&"interact", KeyBindings.Slot.KEYBOARD), "key:%d" % KEY_G
	)
