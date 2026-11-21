extends TestCase
## スイッチの仕掛け（重さの板・スイッチの扉・レバー・時の鐘・ワープの石。docs/adr/0014）を、
## 見本の配置（switch_demo.gd）で 1 人用の PartyDirector から確かめる。
## 板・石に乗せる準備は位置を置くだけ（歩き方は別のテストが確かめる）。扉を通れるかは歩いて確かめる。

const Demo := preload("res://tests/integration/switch_demo.gd")
const PROFILE := "zz_test_switches"
const JUMP_SLOT := 4

var director: PartyDirector
var w: StageWorld
var m: MechanismSet


func before_each() -> void:
	ProgressStore.new().delete(PROFILE)
	Demo.register()
	director = PartyDirector.new()
	director.profile = PROFILE
	tree.root.add_child(director)
	director.enter_stage(Demo.ID)
	w = director.world
	m = MechanismSet.of(w)
	await wait_physics_frames(10)


func after_each() -> void:
	director.queue_free()
	Demo.unregister()
	await tree.process_frame
	ProgressStore.new().delete(PROFILE)


func _me() -> PlayerAvatar:
	return w.player


func _place(at: Vector3) -> void:
	_me().global_position = at + Vector3(0.0, 0.05, 0.0)
	_me().velocity = Vector3.ZERO
	await wait_physics_frames(4)


func _block(key: String) -> RuleBlock:
	return w.blocks[int(w.entity_ids[key])]


func _door(key: String) -> SwitchDoor:
	for door in m.doors:
		if door.spec.key == key:
			return door
	return null


func _plate(key: String) -> PressurePlate:
	for plate in m.plates:
		if plate.spec.key == key:
			return plate
	return null


func _put_block(key: String, at: Vector3) -> RuleBlock:
	var block := _block(key)
	block.teleport(Vector3(floorf(at.x) + 0.5, 0.5, floorf(at.z) + 0.5), 0.0)
	await wait_physics_frames(4)
	return block


## 条件が真になるまで物理フレームを進める（来なければ失敗）。
func _until(condition: Callable, what: String, frames: int = 240) -> bool:
	for f in frames:
		if condition.call():
			return true
		await tree.physics_frame
	fail("timed out: %s" % what)
	return false


## target へ歩く（水平の距離 0.3 以内）。着けなければ false（失敗にはしない）。
func _try_walk(target: Vector3, frames: int = 300) -> bool:
	for f in frames:
		var flat := Vector3(
			target.x - _me().global_position.x, 0.0, target.z - _me().global_position.z
		)
		if flat.length() <= 0.3:
			_me().move_intent = Vector2.ZERO
			return true
		_me().view_yaw = atan2(-flat.x, -flat.z)
		_me().move_intent = Vector2(0.0, 1.0)
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	return false


func test_the_demo_layout_is_a_valid_stage() -> void:
	assert_eq(Demo.build().problems(), PackedStringArray())
	assert_ne(m, null, "the stage built its mechanisms")
	assert_eq(m.plates.size(), 5)
	assert_eq(m.doors.size(), 5)
	assert_eq(m.warps.size(), 4)
	assert_true(w.bells_by_key.has("clock"), "a timed bell is a bell of the stage")
	assert_true(w.bells.has(m.timed_bells[0]))


# --- 重さの板とスイッチの扉 --------------------------------------------------------


func test_a_player_on_the_plate_opens_the_held_door_and_leaving_closes_it() -> void:
	var gate := _door("gate")
	assert_true(gate.is_closed())
	await _place(Demo.PLATE_A)
	assert_true(_plate("plate_a").pressed, "standing on the plate presses it")
	assert_true(await _until(gate.is_open, "the door opens"))
	await _place(Demo.PLATE_A + Vector3(0.0, 0.0, 3.0))
	assert_false(_plate("plate_a").pressed, "stepping off releases it")
	assert_true(await _until(gate.is_closed, "the door closes again"))


func test_a_block_or_a_creature_weighs_the_plate_down_too() -> void:
	var gate := _door("gate")
	await _put_block("crate", Demo.PLATE_A)
	assert_true(await _until(gate.is_open, "the crate holds the door open"))
	await _put_block("crate", Vector3(2.5, 0.0, 2.5))
	assert_true(await _until(gate.is_closed, "closes without the crate"))
	var critter := w.creatures[int(w.entity_ids["critter"])]
	critter.restore_state({"position": Demo.PLATE_A, "velocity": Vector3.ZERO})
	critter.set_physics_process(false)  # 歩き出さないように止める
	await wait_physics_frames(3)
	assert_true(_plate("plate_a").pressed, "a creature presses it as well")


func test_the_closed_door_is_a_wall_and_the_open_door_lets_you_through() -> void:
	await _place(Vector3(0.5, 0.0, Demo.SOUTH_Z))
	assert_false(await _try_walk(Vector3(0.5, 0.0, Demo.NORTH_Z), 150), "the closed door blocks")
	assert_gt(_me().global_position.z, -3.4, "stopped south of the wall")
	# 解き方は自由: ブロックを板に置けば、自分は扉を抜けられる
	await _put_block("crate", Demo.PLATE_A)
	assert_true(await _until(_door("gate").is_open, "open"))
	assert_true(await _try_walk(Vector3(0.5, 0.0, Demo.NORTH_Z)), "walked through the open door")


func test_the_door_waits_for_whoever_stands_in_the_doorway() -> void:
	var gate := _door("gate")
	await _put_block("crate", Demo.PLATE_A)
	assert_true(await _until(gate.is_open, "open"))
	await _place(Vector3(0.5, 0.0, -3.5))
	await _put_block("crate", Vector3(2.5, 0.0, 2.5))
	await wait_physics_frames(60)
	assert_true(gate.is_open(), "never closes on someone in the doorway")
	await _place(Vector3(0.5, 0.0, -1.0))
	assert_true(await _until(gate.is_closed, "closes once the doorway is clear"))


func test_the_two_plate_door_needs_both_plates() -> void:
	var duo := _door("duo_gate")
	await _place(Demo.PLATE_L)
	await wait_physics_frames(40)
	assert_true(duo.is_closed(), "one plate is not enough")
	await _put_block("crate", Demo.PLATE_R)
	assert_true(await _until(duo.is_open, "both plates open it"))


func test_a_plate_with_a_radius_is_a_held_bell_for_signal_blocks() -> void:
	var pusher := _block("pusher")
	await _place(pusher.global_position + Vector3(0.0, -0.5, 1.6))
	w.select_slot(JUMP_SLOT)
	assert_true(w.set_lend_mode(TriggerMode.Kind.SIGNAL))
	assert_eq(w.lend_to(pusher, false), RuleLedger.LendResult.OK)
	await _place(Vector3(-2.5, 0.0, 6.5))
	assert_false(w.is_receiving_signal(pusher.entity_id), "silent while nobody is on the plate")
	await _place(Demo.PULSE_PLATE)
	assert_true(w.is_receiving_signal(pusher.entity_id), "the pressed plate reaches the block")
	var top := 0.0
	for i in 150:
		await tree.physics_frame
		top = maxf(top, pusher.global_position.y)
	assert_gt(top, 1.5, "the signal block jumps while the plate is held")
	assert_false(w.is_receiving_signal(_block("chime").entity_id), "too far from the plate")


# --- レバー ---------------------------------------------------------------------


func test_the_lever_stays_where_it_was_put_and_its_door_follows() -> void:
	var door := _door("lever_gate")
	await _place(Demo.LEVER + Vector3(0.0, 0.0, 0.8))
	w.interact(null)
	assert_true(m.levers[0].on, "F next to the lever flips it")
	assert_true(await _until(door.is_open, "the door opens"))
	await _place(Vector3(7.5, 0.0, 2.5))
	await wait_physics_frames(60)
	assert_true(door.is_open(), "stays open after walking away")
	await _place(Demo.LEVER + Vector3(0.0, 0.0, 0.8))
	w.interact(null)
	assert_false(m.levers[0].on)
	assert_true(await _until(door.is_closed, "flipping it back closes it"))


func test_the_toggle_door_flips_each_time_the_plate_is_pressed() -> void:
	var door := _door("toggle_gate")
	await _place(Demo.PLATE_T)
	assert_true(await _until(door.is_open, "the first press opens it"))
	await _place(Demo.PLATE_T + Vector3(2.0, 0.0, 0.0))
	await wait_physics_frames(60)
	assert_true(door.is_open(), "stays open after stepping off")
	await _place(Demo.PLATE_T)
	assert_true(await _until(door.is_closed, "the next press closes it"))
	await _place(Demo.PLATE_T + Vector3(2.0, 0.0, 0.0))
	await wait_physics_frames(60)
	assert_true(door.is_closed(), "and it stays closed")


# --- 時の鐘 ---------------------------------------------------------------------


func test_the_timed_bell_rings_for_its_own_time_and_holds_its_door() -> void:
	var bell := m.timed_bells[0]
	var door := _door("bell_gate")
	assert_almost(bell.ring_time, Demo.CLOCK_TIME, 0.001)
	await _place(Demo.CLOCK + Vector3(0.0, 0.0, 1.4))
	w.interact(bell)
	assert_true(bell.is_ringing())
	assert_true(w.activated.has("clock"), "counts as activated like any bell")
	assert_true(await _until(door.is_open, "the door opens while it rings"))
	await wait_physics_frames(20)
	assert_lt(bell.remaining_fraction(), 0.9, "the countdown shrinks")
	assert_true(await _until(func() -> bool: return not bell.is_ringing(), "stops", 180))
	assert_true(await _until(door.is_closed, "the door closes when the bell stops"))


func test_the_timed_bell_drives_a_signal_block_only_for_its_time() -> void:
	var chime := _block("chime")
	await _place(chime.global_position + Vector3(-1.6, -0.5, 1.0))
	w.select_slot(JUMP_SLOT)
	assert_true(w.set_lend_mode(TriggerMode.Kind.SIGNAL))
	assert_eq(w.lend_to(chime, false), RuleLedger.LendResult.OK)
	await _place(Demo.CLOCK + Vector3(0.0, 0.0, 1.4))
	w.interact(m.timed_bells[0])
	assert_true(w.is_receiving_signal(chime.entity_id))
	await wait_physics_frames(int(60 * (Demo.CLOCK_TIME + 1.5)))
	assert_false(w.is_receiving_signal(chime.entity_id), "silent after the short ring")
	var top := chime.global_position.y
	for i in 120:
		await tree.physics_frame
		top = maxf(top, chime.global_position.y)
	assert_lt(top, 0.6, "paused once the time ran out")


# --- ワープの石 -------------------------------------------------------------------


func test_a_player_warps_to_the_partner_and_does_not_bounce_back() -> void:
	await _place(Demo.WARP_A)
	await wait_physics_frames(3)
	assert_almost(_me().global_position.x, Demo.WARP_B.x, 0.05)
	assert_almost(_me().global_position.z, Demo.WARP_B.z, 0.05, "moved to the partner stone")
	await wait_physics_frames(60)
	assert_almost(_me().global_position.z, Demo.WARP_B.z, 0.3, "stays until stepping off")
	await _place(Demo.WARP_B + Vector3(0.0, 0.0, -1.5))
	await wait_physics_frames(3)
	await _place(Demo.WARP_B)
	await wait_physics_frames(3)
	assert_almost(_me().global_position.z, Demo.WARP_A.z, 0.05, "stepping on again goes back")


func test_a_block_warps_with_its_tokens_and_does_not_bounce() -> void:
	var crate := _block("crate")
	await _place(crate.global_position + Vector3(0.0, -0.5, 1.6))
	w.select_slot(JUMP_SLOT)
	assert_true(w.set_lend_mode(TriggerMode.Kind.SINGLE_SHOT))
	assert_eq(w.lend_to(crate, false), RuleLedger.LendResult.OK)
	await _put_block("crate", Demo.WARP_A)
	assert_true(
		await _until(
			func() -> bool: return absf(crate.global_position.z - Demo.WARP_B.z) < 0.05, "warps"
		)
	)
	assert_eq(w.ledger.tokens_on(crate.entity_id).size(), 1, "the lent jump came along")
	await wait_physics_frames(60)
	assert_almost(crate.global_position.z, Demo.WARP_B.z, 0.05, "no bounce for blocks either")


func test_nobody_warps_onto_an_occupied_stone() -> void:
	await _put_block("crate", Demo.WARP_EXIT)
	await _place(Demo.WARP_ONE)
	await wait_physics_frames(30)
	assert_almost(_me().global_position.z, Demo.WARP_ONE.z, 0.05, "waits while the exit is taken")
	await _put_block("crate", Demo.WARP_EXIT + Vector3(-2.0, 0.0, 0.0))
	assert_true(
		await _until(
			func() -> bool: return absf(_me().global_position.z - Demo.WARP_EXIT.z) < 0.05,
			"warps once the exit is clear"
		)
	)


func test_the_one_way_stone_has_no_way_back() -> void:
	await _place(Demo.WARP_ONE)
	await wait_physics_frames(3)
	assert_almost(_me().global_position.z, Demo.WARP_EXIT.z, 0.05, "the one-way stone sends you")
	await _place(Demo.WARP_EXIT + Vector3(-1.5, 0.0, 0.0))
	await _place(Demo.WARP_EXIT)
	await wait_physics_frames(10)
	assert_almost(_me().global_position.z, Demo.WARP_EXIT.z, 0.05, "the exit stone sends nowhere")


# --- 記録と復元 -------------------------------------------------------------------


func test_checkpoint_and_reset_bring_the_mechanisms_back() -> void:
	var snapshot := WorldSnapshot.capture(w)
	await _place(Demo.LEVER + Vector3(0.0, 0.0, 0.8))
	w.interact(null)
	await _put_block("crate", Demo.PLATE_A)
	assert_true(await _until(func() -> bool: return _door("lever_gate").is_open(), "open"))
	await _place(Demo.WARP_A)
	await wait_physics_frames(3)
	var saved := WorldSnapshot.capture(w)
	WorldSnapshot.apply(w, snapshot)
	assert_false(m.levers[0].on, "the lever is back")
	assert_true(_door("lever_gate").is_closed(), "the toggle door is back")
	assert_true(_door("gate").is_closed(), "the held door is back")
	WorldSnapshot.apply(w, saved)
	assert_true(m.levers[0].on)
	assert_true(_door("lever_gate").is_open())
	await wait_physics_frames(30)
	assert_almost(
		_me().global_position.z, Demo.WARP_B.z, 0.3, "the arrival mark came back: no bounce"
	)
