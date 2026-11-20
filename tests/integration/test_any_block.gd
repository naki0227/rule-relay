extends TestCase
## どのブロックにも渡せる（2026-11-19 本人の判断）: 地面・高台・岩棚などの地形のセルも、
## 能力を渡すとそのセルが動くブロックになって受け取る。範囲付与なら範囲内の地形のセルも全部受け取る。
## チェックポイントに戻ると、ブロックにしたセルは地形へ戻る。

const JUMP := RuleAction.Kind.JUMP
const JUMP_SLOT := 4

var island: PrototypeIsland


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	await wait_physics_frames(10)


func after_each() -> void:
	island.queue_free()
	await tree.process_frame


func stand_near(cell: Vector3i) -> void:
	island.player.global_position = Vector3(cell.x + 0.5, cell.y + 1.0, cell.z + 2.0)
	island.player.velocity = Vector3.ZERO
	await wait_physics_frames(6)


func test_a_ground_cell_takes_a_single_shot_jump() -> void:
	var cell := Vector3i(-3, -1, 1)
	assert_true(island.terrain.has_cell(cell))
	await stand_near(cell)
	island.select_slot(JUMP_SLOT)
	assert_eq(island.lend_to(island.terrain_target(cell), false), RuleLedger.LendResult.OK)
	assert_false(island.terrain.has_cell(cell), "the cell left the terrain")
	var block := island.blocks[island.promoted[cell]]
	assert_true(island.ledger.can_initiate(block.entity_id, JUMP))
	island.press_action(JUMP)
	var top := block.global_position.y
	for i in 40:
		await tree.physics_frame
		top = maxf(top, block.global_position.y)
	assert_gt(top, 1.0, "the ground itself jumped")
	assert_true(island.ledger.player_can(JUMP), "single shot came back")
	await wait_physics_frames(60)
	assert_almost(block.global_position.y, -0.5, 0.05, "lands back in its hole (bedrock below)")


func test_a_high_ground_cell_moves_out_with_repeat() -> void:
	var cell := Vector3i(4, 2, -6)  # 高台のいちばん上の層、南の端
	await stand_near(Vector3i(4, 0, -5))
	island.player.global_position = Vector3(4.5, 0.0, -2.5)
	await wait_physics_frames(4)
	island.toggle_reach()
	island.select_slot(2)  # S
	island.set_lend_mode(TriggerMode.Kind.REPEAT)
	assert_eq(island.lend_to(island.terrain_target(cell), false), RuleLedger.LendResult.OK)
	var block := island.blocks[island.promoted[cell]]
	await wait_physics_frames(int(60 * Tuning.REPEAT_PERIOD * 1.5))
	assert_ne(block.cell(), cell, "it moved south out of the high ground")


func test_range_on_the_ground_layer_reaches_every_ground_cell_in_the_circle() -> void:
	var center := Vector3i(-3, -1, 2)
	await stand_near(center)
	island.select_slot(JUMP_SLOT)
	island.set_lend_mode(TriggerMode.Kind.REPEAT)
	var selection := island.range_selection(island.terrain_target(center))
	var cells := selection["cells"] as Array
	assert_gt(cells.size(), 40, "a radius-5 circle of ground")
	assert_eq(island.lend_to(island.terrain_target(center), true), RuleLedger.LendResult.OK)
	var t := island.ledger.token(island.selected_vessel().token_id)
	assert_eq(t.holder_ids.size(), cells.size() + (selection["ids"] as PackedInt32Array).size())
	assert_eq(t.mode, TriggerMode.Kind.REPEAT, "still one token")


func test_checkpoint_puts_promoted_cells_back_into_the_terrain() -> void:
	var cell := Vector3i(-3, -1, 1)
	await stand_near(cell)
	island.select_slot(JUMP_SLOT)
	island.set_lend_mode(TriggerMode.Kind.REPEAT)
	island.lend_to(island.terrain_target(cell), false)
	var id := island.promoted[cell]
	await wait_physics_frames(60)
	island.restart_island()
	await wait_physics_frames(3)
	assert_true(island.terrain.has_cell(cell), "back in the terrain")
	assert_false(island.promoted.has(cell))
	assert_false(island.blocks.has(id))
	assert_false(island.ledger.has_entity(id))
	assert_true(island.ledger.player_can(JUMP))
	assert_true(island.ledger.validate().is_empty())


func test_restoring_a_save_with_a_promoted_cell_promotes_it_again() -> void:
	var cell := Vector3i(-3, -1, 1)
	# 自分のジャンプを全部貸したままだと保存できない（F8）ので、手元にもう1つ持っておく
	for slot in RuleLedger.HOTBAR_SIZE:
		if island.ledger.hotbar_vessel(slot) == null:
			island.ledger.give_player_item(JUMP, false, slot)
			break
	await stand_near(cell)
	island.select_slot(JUMP_SLOT)
	island.set_lend_mode(TriggerMode.Kind.REPEAT)
	island.lend_to(island.terrain_target(cell), false)
	island.player.global_position = island.checkpoint_center
	await wait_physics_frames(10)
	assert_true(island.save_checkpoint())
	TerrainPromotion.demote(island, cell)  # 何かで地形に戻った状態から、保存へ戻る
	await wait_physics_frames(3)
	assert_true(island.terrain.has_cell(cell))
	island.restore_checkpoint()
	await wait_physics_frames(3)
	assert_false(island.terrain.has_cell(cell))
	var id := island.promoted[cell]
	assert_true(island.ledger.can_initiate(id, JUMP), "the saved repeat jump is on it again")
