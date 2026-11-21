extends TestCase
## ブロックの W/A/S/D の予約（2026-11-21 本人の判断「W とかの単発がシビア。1マス進ませて。繰り返しの時も予約に」。
## docs/adr/0003「横移動の予約」）。空中・移動中に起動した W/A/S/D は、動けるようになった瞬間に1マスだけ動く。
## 着地して進む先が塞がれていれば失敗として使い切り、単発は戻る。禁止は動く瞬間に判定する。

const W := RuleAction.Kind.FORWARD
const A := RuleAction.Kind.LEFT
const JUMP := RuleAction.Kind.JUMP
const W_SLOT := 0
const A_SLOT := 1
const JUMP_SLOT := 4
const SINGLE := TriggerMode.Kind.SINGLE_SHOT

var island: PrototypeIsland
var block: RuleBlock


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	block = island.mover  # (8, 0, -2)。北（W）の (8, 0, -3) は空いている
	await wait_physics_frames(10)


func after_each() -> void:
	island.queue_free()
	await tree.process_frame


## x の列で、block の北に高さ height の段を積む。
func build_ledge(x: int, height: int) -> void:
	for y in height:
		island.add_block(Vector3i(x, y, -3))
	await wait_physics_frames(10)


## ホットバーの枠の能力を、単発で targets へ貸す（範囲なら range_spec を渡す）。
func lend_single(slot: int, targets: Array[RuleBlock], range_spec: Dictionary = {}) -> void:
	var ids := PackedInt32Array()
	for b in targets:
		ids.append(b.entity_id)
	var v := island.ledger.hotbar_vessel(slot)
	assert_eq(island.ledger.lend(v.id, ids, SINGLE, range_spec), RuleLedger.LendResult.OK)


func jump_then_w() -> void:
	island.press_action(JUMP)
	await wait_physics_frames(2)
	island.press_action(W)


func test_jump_then_w_climbs_a_ledge_of_height_1() -> void:
	await build_ledge(8, 1)
	lend_single(JUMP_SLOT, [block])
	lend_single(W_SLOT, [block])
	await jump_then_w()
	assert_eq(island.move_buffer.pending_action(block.entity_id), W, "W waits for the edge")
	assert_false(island.ledger.player_can(W), "not returned while it waits")
	await wait_physics_frames(90)
	assert_eq(block.cell(), Vector3i(8, 1, -3), "on top of the 1-high ledge")
	assert_false(island.move_buffer.has_pending(block.entity_id))
	assert_true(island.ledger.player_can(W), "W came back after it moved")
	assert_almost(block.global_position.x, 8.5, 0.01, "exactly one cell, on the grid")


func test_jump_then_w_climbs_a_ledge_of_height_2() -> void:
	await build_ledge(8, 2)
	lend_single(JUMP_SLOT, [block])
	lend_single(W_SLOT, [block])
	await jump_then_w()
	await wait_physics_frames(90)
	assert_eq(block.cell(), Vector3i(8, 2, -3), "jump 2.5 clears a 2-high ledge")
	assert_true(island.ledger.player_can(W))


func test_a_wall_still_there_on_landing_fails_and_returns_the_single_shot() -> void:
	await build_ledge(8, 3)  # 跳んでも越えられない
	lend_single(JUMP_SLOT, [block])
	lend_single(W_SLOT, [block])
	await jump_then_w()
	assert_true(island.move_buffer.has_pending(block.entity_id))
	await wait_physics_frames(90)
	assert_eq(block.cell(), Vector3i(8, 0, -2), "landed where it jumped")
	assert_false(island.move_buffer.has_pending(block.entity_id), "consumed on landing")
	assert_true(island.ledger.player_can(W), "the single shot returned anyway")
	await wait_physics_frames(30)
	assert_eq(block.cell(), Vector3i(8, 0, -2), "it does not move later on its own")


func test_w_in_the_air_with_a_free_cell_moves_at_once() -> void:
	lend_single(JUMP_SLOT, [block])
	lend_single(W_SLOT, [block])
	await jump_then_w()
	assert_true(block.is_moving_horizontally(), "free at this height: no need to wait")
	await wait_physics_frames(90)
	assert_eq(block.cell(), Vector3i(8, 0, -3))


func test_w_pressed_mid_step_runs_right_after_the_step() -> void:
	lend_single(A_SLOT, [block])
	lend_single(W_SLOT, [block])
	island.press_action(A)
	await wait_physics_frames(6)
	assert_true(block.is_moving_horizontally())
	island.press_action(W)
	assert_eq(island.move_buffer.pending_action(block.entity_id), W)
	assert_true(island.ledger.player_can(A), "A finished and returned")
	await wait_physics_frames(int(60 * Tuning.BLOCK_STEP_DURATION) + 4)
	assert_true(block.is_moving_horizontally(), "W started as soon as A ended")
	await wait_physics_frames(60)
	assert_eq(block.cell(), Vector3i(7, 0, -3), "one west, then one north")
	assert_true(island.ledger.player_can(W))


func test_pressing_again_while_reserved_does_not_fire_twice() -> void:
	await build_ledge(8, 1)
	lend_single(JUMP_SLOT, [block])
	lend_single(W_SLOT, [block])
	await jump_then_w()
	island.press_action(W)
	await wait_physics_frames(90)
	assert_eq(block.cell(), Vector3i(8, 1, -3), "still exactly one cell")


func test_repeat_buffers_its_cycle_while_airborne() -> void:
	await build_ledge(8, 1)
	island.ledger.place_on_entity(W, false, block.entity_id, TriggerMode.Kind.REPEAT)
	lend_single(JUMP_SLOT, [block])
	island._repeat_timers[block.entity_id] = 0.0
	await wait_physics_frames(2)
	island.press_action(JUMP)
	# 繰り返しの周期が、跳んだ直後（まだ段より低い空中）に来る
	island._repeat_timers[block.entity_id] = Tuning.REPEAT_PERIOD - 0.03
	await wait_physics_frames(3)
	assert_eq(island.move_buffer.pending_action(block.entity_id), W, "the cycle is reserved")
	await wait_physics_frames(60)
	assert_eq(block.cell(), Vector3i(8, 1, -3), "it climbed instead of skipping the turn")


func test_a_ban_added_while_reserved_stops_the_move() -> void:
	await build_ledge(8, 1)
	lend_single(JUMP_SLOT, [block])
	lend_single(W_SLOT, [block])
	await jump_then_w()
	assert_true(island.move_buffer.has_pending(block.entity_id))
	island.ledger.place_on_entity(W, true, block.entity_id)
	await wait_physics_frames(90)
	assert_eq(block.cell(), Vector3i(8, 0, -2), "the ban wins: no move")
	assert_false(island.move_buffer.has_pending(block.entity_id))
	assert_true(island.ledger.player_can(W), "the single shot returned")


func test_recalling_a_reserved_single_shot_cancels_it() -> void:
	await build_ledge(8, 1)
	lend_single(JUMP_SLOT, [block])
	lend_single(W_SLOT, [block])
	await jump_then_w()
	island.ledger.recall_from_entity(block.entity_id)
	await wait_physics_frames(90)
	assert_eq(block.cell(), Vector3i(8, 0, -2))
	assert_false(island.move_buffer.has_pending(block.entity_id))
	assert_true(island.ledger.player_can(W))


func test_range_single_shot_reserves_each_block_on_its_own() -> void:
	var other := island.add_block(Vector3i(10, 0, -2))
	await build_ledge(8, 2)
	await build_ledge(10, 1)
	var spec := {"center": Vector3(9.0, 0.5, -1.5), "radius": 5.0, "layer": 0}
	lend_single(JUMP_SLOT, [block, other], spec)
	lend_single(W_SLOT, [block, other], spec)
	await jump_then_w()
	assert_true(island.move_buffer.has_pending(block.entity_id))
	assert_true(island.move_buffer.has_pending(other.entity_id))
	await wait_physics_frames(90)
	assert_eq(block.cell(), Vector3i(8, 2, -3), "the 2-high side")
	assert_eq(other.cell(), Vector3i(10, 1, -3), "the 1-high side")
	assert_true(island.ledger.player_can(W), "returned once both moved")
	assert_true(island.ledger.validate().is_empty())


func test_restoring_a_checkpoint_clears_reservations() -> void:
	await build_ledge(8, 1)
	lend_single(JUMP_SLOT, [block])
	lend_single(W_SLOT, [block])
	await jump_then_w()
	assert_true(island.move_buffer.has_pending(block.entity_id))
	island.restore_checkpoint()
	await wait_physics_frames(3)
	assert_false(island.move_buffer.has_pending(block.entity_id))
	assert_false(island.move_buffer.is_tracking(island.ledger.hotbar_vessel(W_SLOT).token_id))
	assert_true(island.ledger.validate().is_empty())
