extends TestCase
## 信号方式と音源（企画書 5.2・5.4）: 音波が届いている間だけ発動し、途絶えると休止、再受信で再開。
## トークンは自動で戻らない（手動回収）。

const JUMP_SLOT := 4
const W_SLOT := 0

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


func max_height(block: RuleBlock, seconds: float) -> float:
	var top := block.global_position.y
	for i in int(seconds * 60.0):
		await tree.physics_frame
		top = maxf(top, block.global_position.y)
	return top


func test_receiving_block_acts_and_out_of_range_block_rests() -> void:
	var inside := island.row[0]
	var outside := island.mover
	assert_true(island.is_receiving_signal(inside.entity_id))
	assert_false(island.is_receiving_signal(outside.entity_id))
	var t := await lend_signal(inside, JUMP_SLOT)
	assert_gt(await max_height(inside, 3.0), 1.5, "jumps while the sound reaches it")
	assert_true(t.is_lent(), "signal never returns by itself")
	island.ledger.recall(t.id)
	await lend_signal(outside, JUMP_SLOT)
	assert_lt(await max_height(outside, 3.0), 0.6, "no sound, no action")
	assert_true(island.ledger.token(t.id).is_lent(), "paused but still lent")


func test_moving_the_source_pauses_and_resumes() -> void:
	var block := island.row[0]
	var t := await lend_signal(block, JUMP_SLOT)
	assert_gt(await max_height(block, 2.0), 1.5)
	# 音源を遠ざける（テストでは直接動かす）→ 休止。トークンは残る
	var home := island.sound_source.global_position
	island.sound_source.teleport(Vector3(-8.5, 0.5, 4.5), 0.0)  # 島の南西の端
	await wait_physics_frames(80)
	assert_false(island.is_receiving_signal(block.entity_id))
	assert_lt(await max_height(block, 3.0), 0.6, "paused")
	assert_true(t.is_lent())
	# 戻すと再開
	island.sound_source.teleport(home, 0.0)
	assert_gt(await max_height(block, 3.0), 1.5, "resumes when the sound returns")


func test_prohibition_still_wins_in_signal_mode() -> void:
	var middle := island.row[1]  # ジャンプ禁止のブロック（音波の中）
	assert_true(island.is_receiving_signal(middle.entity_id))
	await lend_signal(middle, JUMP_SLOT)
	assert_lt(await max_height(middle, 3.0), 0.6)


func test_signal_state_survives_checkpoint() -> void:
	var block := island.row[0]
	island.set_initial_checkpoint()
	var t := await lend_signal(block, JUMP_SLOT)
	island.player.global_position = island.checkpoint_center
	await wait_physics_frames(10)
	assert_true(island.save_checkpoint())
	island.ledger.recall(t.id)
	island.restore_checkpoint()
	assert_eq(island.ledger.token(t.id).mode, TriggerMode.Kind.SIGNAL)
	assert_true(island.ledger.token(t.id).holder_ids.has(block.entity_id))
