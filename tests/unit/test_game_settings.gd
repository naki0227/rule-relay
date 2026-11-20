extends TestCase
## 設定（文字の大きさ・視点の速さ・音の大きさ・キー割り当て）を user://settings.cfg の形で保存し、起動時に反映すること。

const PATH := "user://zz_test_settings.cfg"


func before_each() -> void:
	_clean()


func after_each() -> void:
	_clean()
	tree.root.content_scale_factor = 1.0
	KeyBindings.new().apply()
	GameSettings.new().apply_volumes()
	GameSettings.current = null


func _clean() -> void:
	for path: String in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func test_round_trip_through_the_file() -> void:
	var settings := GameSettings.new(PATH)
	settings.set_scale_step(3)
	settings.set_mouse_sensitivity(1.7)
	settings.set_pad_sensitivity(0.6)
	settings.set_music_volume(35)
	settings.set_sfx_volume(0)
	settings.bindings.assign(&"jump", KeyBindings.Slot.KEYBOARD, "key:%d" % KEY_J)
	assert_eq(settings.save_file(), OK)
	var loaded := GameSettings.new(PATH)
	assert_eq(loaded.load_file(), OK)
	assert_eq(loaded.scale_step, 3)
	assert_almost(loaded.mouse_sensitivity, 1.7, 0.001)
	assert_almost(loaded.pad_sensitivity, 0.6, 0.001)
	assert_eq(loaded.music_volume, 35)
	assert_eq(loaded.sfx_volume, 0)
	assert_eq(loaded.bindings.get_descriptor(&"jump", KeyBindings.Slot.KEYBOARD), "key:%d" % KEY_J)


func test_load_and_apply_at_startup() -> void:
	var settings := GameSettings.new(PATH)
	settings.set_scale_step(2)
	settings.set_music_volume(50)
	settings.set_sfx_volume(0)
	settings.bindings.assign(&"interact", KeyBindings.Slot.KEYBOARD, "key:%d" % KEY_G)
	settings.save_file()
	var started := GameSettings.load_and_apply(tree, PATH)
	assert_eq(GameSettings.get_current(), started)
	assert_almost(tree.root.content_scale_factor, GameSettings.SCALES[2], 0.001)
	assert_eq(InputMode.key(&"interact"), "G")
	var music := AudioServer.get_bus_index(AudioBuses.MUSIC)
	assert_almost(AudioServer.get_bus_volume_db(music), linear_to_db(0.5), 0.01, "BGM at 50%")
	assert_false(AudioServer.is_bus_mute(music))
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioBuses.SFX)), "0% is silent")


func test_values_are_clamped_and_missing_file_uses_defaults() -> void:
	var settings := GameSettings.new(PATH)
	assert_eq(settings.load_file(), ERR_FILE_NOT_FOUND)
	assert_eq(settings.scale_step, GameSettings.DEFAULT_SCALE_STEP)
	settings.set_scale_step(99)
	settings.set_mouse_sensitivity(50.0)
	settings.set_pad_sensitivity(-1.0)
	assert_eq(settings.scale_step, GameSettings.SCALES.size() - 1)
	assert_eq(settings.mouse_sensitivity, GameSettings.SENSITIVITY_MAX)
	assert_eq(settings.pad_sensitivity, GameSettings.SENSITIVITY_MIN)
	assert_gt(GameSettings.SCALES.size(), 2.0, "at least 3 text sizes")
	assert_eq(settings.music_volume, 70, "BGM starts a little quieter than the sounds")
	assert_eq(settings.sfx_volume, 100)
	settings.set_music_volume(150)
	settings.set_sfx_volume(-5)
	assert_eq(settings.music_volume, 100)
	assert_eq(settings.sfx_volume, 0)


func test_hand_edited_garbage_falls_back() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "scale_step", "huge")
	config.set_value("look", "mouse", 99.0)
	config.set_value("audio", "music", "loud")
	config.set_value("audio", "sfx", 250)
	config.set_value("input", "jump", ["key:%d" % KEY_C])
	config.save(PATH)
	var settings := GameSettings.new(PATH)
	assert_eq(settings.load_file(), OK)
	assert_eq(settings.scale_step, GameSettings.DEFAULT_SCALE_STEP)
	assert_eq(settings.mouse_sensitivity, GameSettings.SENSITIVITY_MAX)
	assert_eq(settings.music_volume, GameSettings.DEFAULT_MUSIC_VOLUME)
	assert_eq(settings.sfx_volume, 100)
	assert_true(settings.bindings.is_default(), "C belongs to 触る／投げる, so it is ignored")


func test_newer_version_is_not_read() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "version", GameSettings.VERSION + 1)
	config.set_value("display", "scale_step", 0)
	config.save(PATH)
	var settings := GameSettings.new(PATH)
	assert_eq(settings.load_file(), ERR_FILE_UNRECOGNIZED)
	assert_eq(settings.scale_step, GameSettings.DEFAULT_SCALE_STEP)
