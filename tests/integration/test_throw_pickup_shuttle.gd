extends TestCase
## 「投げる」の切り替えと手放し、F で拾う、谷の往復足場を島の上で確かめる。

const THROW_SLOT := 5
const JUMP_SLOT := 4

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


func test_throw_starts_in_the_hotbar_and_extends_reach() -> void:
	assert_true(island.can_throw())
	assert_almost(island.reach(), Tuning.TOUCH_REACH, 0.001)
	island.toggle_reach()
	assert_true(island.throw_mode)
	assert_almost(island.reach(), Tuning.THROW_REACH, 0.001)


func test_lending_throw_allows_the_last_throw_then_falls_back_to_touch() -> void:
	var far := island.mover
	await place_player(far.global_position + Vector3(-8.0, -0.5, 0.0))
	island.toggle_reach()
	island.select_slot(THROW_SLOT)
	var result := island.lend_to(far, false)
	assert_eq(result, RuleLedger.LendResult.OK, "the throw itself can be thrown")
	assert_false(island.can_throw())
	assert_false(island.throw_mode, "back to touch")
	assert_almost(island.reach(), Tuning.TOUCH_REACH, 0.001)
	island.toggle_reach()
	assert_false(island.throw_mode, "C refuses while Throw is lent")
	island.select_slot(JUMP_SLOT)
	assert_eq(island.lend_to(far, false), RuleLedger.LendResult.NO_TARGETS, "too far to touch")


func test_recall_with_f_is_touch_range_even_while_throwing() -> void:
	var block := island.mover
	await place_player(block.global_position + Vector3(-8.0, -0.5, 0.0))
	island.toggle_reach()
	island.select_slot(JUMP_SLOT)
	island.lend_to(block, false)
	island.interact(block)
	assert_false(island.ledger.tokens_on(block.entity_id).is_empty(), "F does not reach 8 blocks")
	await place_player(block.global_position + Vector3(-1.6, -0.5, 0.0))
	island.interact(block)
	assert_true(island.ledger.tokens_on(block.entity_id).is_empty(), "F recalls up close")


func test_f_picks_up_a_world_item_into_the_bag() -> void:
	var spot := island.player.global_position + Vector3(1.0, 0.0, 0.0)
	var v := island.ledger.place_in_world(RuleAction.Kind.LEFT, false, spot)
	await wait_physics_frames(2)
	assert_eq(island.nearest_world_item(), v)
	island.interact(null)
	assert_eq(island.ledger.vessel(v.id).location, RuleVessel.Location.INVENTORY)
	assert_eq(island.nearest_world_item(), null)


func test_restoring_puts_a_picked_up_item_back_in_the_world() -> void:
	var spot := island.player.global_position + Vector3(1.0, 0.0, 0.0)
	var v := island.ledger.place_in_world(RuleAction.Kind.LEFT, false, spot)
	island.set_initial_checkpoint()
	island.interact(null)
	island.restore_checkpoint()
	await wait_physics_frames(2)
	assert_eq(island.ledger.vessel(v.id).location, RuleVessel.Location.WORLD)
	assert_eq(island.nearest_world_item().id, v.id)


func test_shuttle_goes_back_and_forth_across_the_valley() -> void:
	var shuttle := island.shuttle
	var cells: Dictionary = {}
	for i in int(Tuning.REPEAT_PERIOD * 60.0 * 5):
		await tree.physics_frame
		cells[shuttle.cell().z] = true
	assert_true(cells.has(9) and cells.has(10), "visits both cells: %s" % str(cells.keys()))
	assert_eq(shuttle.cell().y, -1, "stays on the valley floor")
