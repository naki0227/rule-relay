extends TestCase
## 効果音: 全部の音が読み込め、ゲームの出来事で正しい音が鳴る。音の中身の基準は tools/sfx/test_sfx.py。

var island: PrototypeIsland
var sounds: SoundBank
var heard: Array[StringName] = []


func before_each() -> void:
	heard.clear()
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	sounds = SoundBank.new()
	tree.root.add_child(sounds)
	island.sound_requested.connect(
		func(event: StringName, _at: Vector3, _positional: bool) -> void: heard.append(event)
	)
	await wait_physics_frames(10)


func after_each() -> void:
	island.queue_free()
	sounds.queue_free()
	await tree.process_frame


func test_every_event_has_a_sound_file() -> void:
	for event: StringName in SoundBank.EVENTS:
		assert_true(sounds.has_event(event), String(event))
	assert_false(sounds.has_event(&"nope"))


func test_buses_exist() -> void:
	assert_ne(AudioServer.get_bus_index(SoundBank.BUS_UI), -1)
	assert_ne(AudioServer.get_bus_index(SoundBank.BUS_WORLD), -1)


func test_play_and_rapid_repeat_guard() -> void:
	assert_true(sounds.play_ui(&"ui_hover"))
	assert_false(sounds.play_ui(&"ui_hover"), "too soon: skipped")
	assert_true(sounds.play_at(&"block_land", Vector3.ZERO))
	assert_true(sounds.play_slot_select(8))


func test_lend_jump_and_land_make_sounds() -> void:
	island.player.global_position = Vector3(3.5, 0.0, -3.0)
	await wait_physics_frames(3)
	island.select_slot(4)
	island.lend_to(island.row[0], false)
	island.press_action(RuleAction.Kind.JUMP)
	await wait_physics_frames(70)
	assert_true(heard.has(&"lend"))
	assert_true(heard.has(&"block_jump"))
	assert_true(heard.has(&"block_land"))


func test_failures_use_soft_error_sounds() -> void:
	island.player.global_position = Vector3(0.5, 0.0, 6.0)
	await wait_physics_frames(3)
	island.lend_to(island.row[0], false)  # 遠すぎる
	assert_eq(heard[-1], &"ui_error")
	island.player.global_position = island.row[1].global_position + Vector3(0.0, -0.5, 1.5)
	await wait_physics_frames(3)
	island.interact(island.row[1])  # 3つ並びの中央に置かれていた禁止だけを拾う
	assert_eq(heard[-1], &"prohibit")


func test_player_steps_and_jumps() -> void:
	island.player.move_intent = Vector2(0, 1)
	await wait_physics_frames(60)
	island.press_action(RuleAction.Kind.JUMP)
	await wait_physics_frames(60)
	assert_true(heard.has(&"footstep"))
	assert_true(heard.has(&"player_jump"))
	assert_true(heard.has(&"player_land"))
