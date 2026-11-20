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


func test_footsteps_rotate_through_four_variants() -> void:
	# 足音は 4 種を順番に鳴らす（2026-11-20 の本人の判断。同じ音が続かない）
	assert_eq(sounds.variant_count(&"footstep"), 4)
	assert_eq(sounds.variant_count(&"ui_select"), 0)
	var order := []
	for i in 8:
		sounds._last_played.clear()  # 35ms の連打よけを外して、続けて鳴らす
		assert_true(sounds.play_at(&"footstep", Vector3.ZERO))
		order.append(sounds.last_variant)
	assert_eq(order, [1, 2, 3, 4, 1, 2, 3, 4])
	sounds._last_played.clear()
	assert_true(sounds.play_slot_select(8))
	assert_eq(sounds.last_variant, 0, "an event without variants uses its single file")


func test_lend_jump_and_land_make_sounds() -> void:
	island.player.global_position = Vector3(3.5, 0.0, -3.0)
	await wait_physics_frames(3)
	island.select_slot(4)
	island.lend_to(island.row[0], false)
	island.press_action(RuleAction.Kind.JUMP)
	await wait_physics_frames(70)
	assert_true(heard.has(&"lend@9"), "the rule tone at Jump's pitch: %s" % str(heard))
	assert_true(heard.has(&"receive_wood"), "the wooden block answers in its own voice")
	assert_true(heard.has(&"block_jump"))
	assert_true(heard.has(&"block_land"))


func test_each_ability_has_its_own_pitch_and_materials_answer() -> void:
	assert_eq(RuleAction.motif_semitone(RuleAction.Kind.FORWARD), 0)
	assert_eq(RuleAction.motif_semitone(RuleAction.Kind.JUMP), 9)
	assert_true(sounds.play_at(&"lend@7", Vector3.ZERO), "pitched variant of a known event")
	assert_eq(sounds.last_event, &"lend")
	assert_eq(WorldQueries.receive_sound(island.creature), &"receive_creature")
	assert_eq(WorldQueries.receive_sound(island.row[0]), &"receive_wood")
	var cell := TerrainPromotion.promote(island, Vector3i(-3, -1, 1))
	assert_eq(WorldQueries.receive_sound(cell), &"receive_grass")
	var rock := TerrainPromotion.promote(island, Vector3i(4, 2, -6))
	assert_eq(WorldQueries.receive_sound(rock), &"receive_stone")


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
