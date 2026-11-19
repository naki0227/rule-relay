extends TestCase
## 信号方式と鐘（企画書 5.2・5.4。2026-11-19 本人の判断: 音源は鐘で、F で鳴らす）。
## 鐘が鳴っている間だけ発動し、鳴りやむと休止、また鳴らすと再開。トークンは自動で戻らない（手動回収）。

const JUMP_SLOT := 4

var island: PrototypeIsland


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	await wait_physics_frames(10)


func after_each() -> void:
	island.queue_free()
	await tree.process_frame


func lend_signal(block: RuleBlock, slot: int) -> RuleToken:
	island.player.global_position = block.global_position + Vector3(-1.6, -0.5, 1.0)
	island.player.velocity = Vector3.ZERO
	await wait_physics_frames(4)
	island.select_slot(slot)
	assert_true(island.set_lend_mode(TriggerMode.Kind.SIGNAL))
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.OK)
	var t := island.ledger.token(island.selected_vessel().token_id)
	assert_eq(t.mode, TriggerMode.Kind.SIGNAL)
	return t


func ring_bell_with_f() -> void:
	island.player.global_position = island.bell.global_position + Vector3(0.0, 0.0, 1.6)
	island.player.velocity = Vector3.ZERO
	await wait_physics_frames(3)
	island.interact(island.bell)


func max_height(block: RuleBlock, seconds: float) -> float:
	var top := block.global_position.y
	for i in int(seconds * 60.0):
		await tree.physics_frame
		top = maxf(top, block.global_position.y)
	return top


func test_silent_bell_means_no_action() -> void:
	var block := island.row[0]
	var t := await lend_signal(block, JUMP_SLOT)
	assert_false(island.is_receiving_signal(block.entity_id))
	assert_lt(await max_height(block, 3.0), 0.6, "nothing rings yet")
	assert_true(t.is_lent())


func test_f_rings_the_bell_and_only_blocks_in_reach_act() -> void:
	var inside := island.row[0]
	var t := await lend_signal(inside, JUMP_SLOT)
	await ring_bell_with_f()
	assert_true(island.bell.is_ringing())
	assert_true(island.is_receiving_signal(inside.entity_id))
	assert_false(island.is_receiving_signal(island.mover.entity_id), "too far from the bell")
	assert_gt(await max_height(inside, 3.0), 1.5, "jumps while the bell rings")
	assert_true(t.is_lent(), "signal never returns by itself")


func test_pauses_when_the_bell_stops_and_resumes_when_rung_again() -> void:
	var block := island.row[0]
	var t := await lend_signal(block, JUMP_SLOT)
	await ring_bell_with_f()
	await wait_physics_frames(int(60 * (Tuning.BELL_RING_TIME + 1.0)))
	assert_false(island.bell.is_ringing())
	assert_lt(await max_height(block, 3.0), 0.6, "paused after the bell stopped")
	assert_true(t.is_lent(), "still lent while paused")
	await ring_bell_with_f()
	assert_gt(await max_height(block, 3.0), 1.5, "resumes when rung again")


func test_prohibition_still_wins_in_signal_mode() -> void:
	var middle := island.row[1]  # ジャンプ禁止のブロック（鐘の届く範囲）
	await lend_signal(middle, JUMP_SLOT)
	await ring_bell_with_f()
	assert_true(island.is_receiving_signal(middle.entity_id))
	assert_lt(await max_height(middle, 3.0), 0.6)


func test_bell_state_survives_checkpoint() -> void:
	island.set_initial_checkpoint()
	await ring_bell_with_f()
	island.player.global_position = island.checkpoint_center
	await wait_physics_frames(10)
	assert_true(island.save_checkpoint())
	var saved_left := island.bell.remaining
	await wait_physics_frames(int(60 * (Tuning.BELL_RING_TIME + 0.5)))
	assert_false(island.bell.is_ringing())
	island.restore_checkpoint()
	assert_almost(island.bell.remaining, saved_left, 0.05, "rings again from the saved moment")
