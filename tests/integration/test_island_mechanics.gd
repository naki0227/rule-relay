extends TestCase
## 島の物理を実際に進めて、ルールが物理世界で成立するかを確かめる結合テスト。
## キー入力の代わりに GameWorld の操作メソッドを呼ぶ。

const JUMP := RuleAction.Kind.JUMP
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


func place_player(at: Vector3) -> void:
	island.player.global_position = at
	island.player.velocity = Vector3.ZERO
	island.player.move_intent = Vector2.ZERO
	await wait_physics_frames(6)


## frames の間に node の高さが取った最大値。
func max_height_over(node: Node3D, frames: int) -> float:
	var top := node.global_position.y
	for i in frames:
		await tree.physics_frame
		top = maxf(top, node.global_position.y)
	return top


func test_blocks_rest_on_the_ground() -> void:
	for block: RuleBlock in island.blocks.values():
		var floor_y := -0.5 if block == island.shuttle else 0.5  # 往復の足場は谷底にいる
		assert_almost(block.global_position.y, floor_y, 0.02, block.name)
		assert_true(block.is_grounded(), block.name)


func test_single_shot_jump_lifts_rider_then_returns() -> void:
	var platform := island.row[0]
	await place_player(platform.global_position + Vector3(0.0, 0.5, 0.0))
	island.select_slot(JUMP_SLOT)
	var result := island.lend_to(platform, false)
	assert_eq(result, RuleLedger.LendResult.OK)
	assert_false(island.ledger.player_can(JUMP), "player gave the jump away")
	await wait_physics_frames(20)
	assert_almost(platform.global_position.y, 0.5, 0.02, "single shot does not fire by itself")

	island.press_action(JUMP)
	assert_true(island.ledger.player_can(JUMP), "returned once the block took off")
	var rider_top: float = await max_height_over(island.player, 40)
	assert_gt(rider_top, 3.0, "rider is carried above the plateau height")
	assert_almost(island.row[1].global_position.y, 0.5, 0.02, "neighbour did not move")
	await wait_physics_frames(60)
	assert_almost(platform.global_position.y, 0.5, 0.05, "block lands again")


func test_range_single_shot_skips_only_the_prohibited_block() -> void:
	await place_player(Vector3(4.5, 0.0, -2.5))
	island.select_slot(JUMP_SLOT)
	var result := island.lend_to(island.row[0], true)
	assert_eq(result, RuleLedger.LendResult.OK)
	var t := island.ledger.token(island.selected_vessel().token_id)
	assert_true(t.holder_ids.has(island.row[1].entity_id), "middle block is in range")
	island.press_action(JUMP)
	var tops := {}
	for i in 15:
		await tree.physics_frame
		for block: RuleBlock in [island.row[0], island.row[1], island.row[2], island.bouncer]:
			tops[block.name] = maxf(float(tops.get(block.name, 0.0)), block.global_position.y)
	assert_gt(float(tops[island.row[0].name]), 2.0, "left jumps")
	assert_gt(float(tops[island.row[2].name]), 2.0, "right jumps")
	assert_almost(float(tops[island.row[1].name]), 0.5, 0.02, "middle is prohibited")
	assert_almost(float(tops[island.bouncer.name]), 0.5, 0.02, "bouncer is prohibited too")
	assert_true(island.ledger.player_can(JUMP), "range single shot returned after success")


func test_prohibition_blocks_player_jump() -> void:
	await place_player(Vector3(0.5, 0.0, 2.5))
	island.ledger.give_player_item(JUMP, true)
	island.press_action(JUMP)
	var top: float = await max_height_over(island.player, 30)
	assert_almost(top, 0.0, 0.05, "player with the jump prohibition stays on the ground")


func test_solution_ride_the_bouncer_while_prohibited() -> void:
	await place_player(Vector3(0.5, 0.0, -6.0))
	island.interact(island.bouncer)  # 置かれていた「ジャンプ（繰り返し）」と「ジャンプ禁止」を全部回収
	# 跳ばなくなった足場へ、自分のジャンプを繰り返しで渡し直す（禁止中でも渡すことはできる）
	island.select_slot(JUMP_SLOT)
	island.set_lend_mode(TriggerMode.Kind.REPEAT)
	assert_eq(island.lend_to(island.bouncer, false), RuleLedger.LendResult.OK)
	assert_false(island.ledger.entity_prohibited(island.bouncer.entity_id, JUMP))
	assert_true(island.ledger.can_initiate(island.bouncer.entity_id, JUMP))
	assert_false(island.ledger.player_can(JUMP), "player now carries the prohibition")
	await place_player(island.bouncer.global_position + Vector3(0.0, 0.5, 0.0))
	var reached := false
	for i in 400:
		await tree.physics_frame
		# 最高点付近で東（高台の方向）へ歩く。view_yaw 0 で右 = +X = 東
		var high := island.player.global_position.y > 2.6
		island.player.move_intent = Vector2(1.0, 0.0) if high else Vector2.ZERO
		if island.goal_cleared:
			reached = true
			break
	assert_true(reached, "reached the plateau without jumping by itself")


func test_solution_push_block_to_ledge_and_climb() -> void:
	await place_player(Vector3(8.5, 0.0, 0.0))
	island.select_slot(W_SLOT)
	island.cycle_mode()
	assert_eq(island.lend_mode, TriggerMode.Kind.REPEAT)
	assert_eq(island.lend_to(island.mover, false), RuleLedger.LendResult.OK)
	await wait_physics_frames(int(60 * Tuning.REPEAT_PERIOD * 4.5))
	assert_eq(island.mover.cell(), Vector3i(8, 0, -5), "slid north until the ledge stopped it")

	await place_player(Vector3(8.5, 0.0, -3.0))
	island.interact(island.mover)
	assert_true(island.ledger.player_can(RuleAction.Kind.FORWARD), "W recalled")
	var reached := false
	var on_ledge := false
	for i in 600:
		await tree.physics_frame
		var p := island.player.global_position
		# 北へ登って岩棚（高さ2）に乗ったら、西の高台へ向かう
		if p.y > 1.9 and island.player.is_on_floor():
			on_ledge = true
		island.player.move_intent = Vector2(-1.0, 0.0) if on_ledge else Vector2(0.0, 1.0)
		if island.player.is_on_floor():
			island.press_action(JUMP)
		if island.goal_cleared:
			reached = true
			break
	assert_true(reached, "climbed mover -> ledge -> plateau")


func test_blocked_single_shot_move_returns_like_a_firing() -> void:
	await place_player(Vector3(9.5, 0.0, -3.5))
	island.mover.teleport(RuleBlock.cell_center(Vector3i(8, 0, -5)), 0.0)
	await wait_physics_frames(5)
	island.select_slot(W_SLOT)
	assert_eq(island.lend_to(island.mover, false), RuleLedger.LendResult.OK)
	island.press_action(RuleAction.Kind.FORWARD)
	await wait_physics_frames(30)
	assert_eq(island.mover.cell(), Vector3i(8, 0, -5), "the ledge blocks the move")
	assert_true(
		island.ledger.player_can(RuleAction.Kind.FORWARD), "could not move, but came back anyway"
	)


func test_checkpoint_restores_the_whole_world() -> void:
	await place_player(Vector3(4.5, 0.0, -3.0))
	island.select_slot(JUMP_SLOT)
	island.cycle_mode()
	island.lend_to(island.row[0], false)
	island.interact(island.row[1])  # 中央の禁止を拾う
	await wait_physics_frames(40)
	assert_false(island.ledger.player_can(JUMP))

	island.restore_checkpoint()
	await wait_physics_frames(3)
	assert_true(island.ledger.player_can(JUMP))
	assert_true(island.ledger.entity_prohibited(island.row[1].entity_id, JUMP))
	assert_eq(island.ledger.tokens_on(island.row[0].entity_id).size(), 0)
	assert_almost(island.row[0].global_position.y, 0.5, 0.05, "block back on the ground")
	assert_almost(island.player.global_position.distance_to(PrototypeIsland.SPAWN), 0.0, 0.1)
	assert_true(island.ledger.validate().is_empty(), str(island.ledger.validate()))


func test_falling_off_restores_checkpoint() -> void:
	await place_player(Vector3(0.5, 0.0, 12.0))  # 島の外（地面なし）
	await wait_physics_frames(90)
	assert_almost(island.player.global_position.distance_to(PrototypeIsland.SPAWN), 0.0, 0.5)


func test_solution_ride_a_row_block() -> void:
	var platform := island.row[2]
	await place_player(platform.global_position + Vector3(0.0, 0.5, 0.0))
	island.select_slot(JUMP_SLOT)
	island.lend_to(platform, false)
	island.press_action(JUMP)
	var reached := false
	for i in 200:
		await tree.physics_frame
		var high := island.player.global_position.y > 2.6
		island.player.move_intent = Vector2(0.0, 1.0) if high else Vector2.ZERO
		if island.goal_cleared:
			reached = true
			break
	assert_true(reached, "rode a row block onto the plateau")


func test_plateau_is_not_reachable_without_lending() -> void:
	# 自力のジャンプと歩行だけでは、壁に沿って跳び続けても高台にも岩棚にも上がれない
	for start: Vector3 in [
		Vector3(6.5, 0.0, -4.0), Vector3(1.0, 0.0, -9.5), Vector3(9.0, 0.0, -4.0)
	]:
		await place_player(start)
		var toward := Vector2(0.0, 1.0) if start.z > -5.0 else Vector2(1.0, 0.0)
		var highest := 0.0
		for i in 240:
			await tree.physics_frame
			island.player.move_intent = toward
			if island.player.is_on_floor():
				island.press_action(JUMP)
			if island.player.global_position.z > -5.0 or start.x < 2.0:
				highest = maxf(highest, island.player.global_position.y)
		assert_false(island.goal_cleared, "no goal from %s" % str(start))
		assert_lt(highest, 1.95, "never stood on a height-2 surface from %s" % str(start))


func test_prohibited_block_is_still_pushed_up_from_below() -> void:
	await place_player(Vector3(3.5, 0.0, -2.5))
	var lower := island.row[0]
	var upper := island.row[1]  # ジャンプ禁止
	upper.teleport(lower.global_position + Vector3(0.0, 1.0, 0.0), 0.0)
	await wait_physics_frames(5)
	island.select_slot(JUMP_SLOT)
	island.lend_to(lower, false)
	island.press_action(JUMP)
	var top: float = await max_height_over(upper, 40)
	assert_gt(top, 3.0, "external force lifts the prohibited block")
	assert_true(island.ledger.entity_prohibited(upper.entity_id, JUMP))
