extends TestCase
## ブロックの「登る」（2026-11-19 本人の判断）: 東西南北の隣でいちばん高い上面まで、
## 自分の上面がそろう高さへ登ってつかまる。両側の高さにはならない。回収すると落ちる。

var island: PrototypeIsland


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	await wait_physics_frames(10)


func after_each() -> void:
	island.queue_free()
	await tree.process_frame


func give_climb(block: RuleBlock) -> RuleToken:
	var gloves := island.ledger.place_in_world(
		RuleAction.Kind.CLIMB, false, Vector3.ZERO, RuleVessel.Part.HANDS, "グローブ"
	)
	island.ledger.pickup(gloves.id)
	island.ledger.move_to_hotbar(gloves.id, 7)
	island.player.global_position = block.global_position + Vector3(-1.5, -0.5, 1.5)
	await wait_physics_frames(4)
	island.select_slot(7)
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.OK)
	return island.ledger.token(gloves.token_id)


## 高さ 1・3・[1]・2 の並びを作る: [1] は青緑（地面の上、高さ1）、西に高さ3の柱、東に高さ2の柱。
func test_climbs_to_the_taller_neighbour_only() -> void:
	var block := island.mover  # (8, 0, -2)
	var west := Vector3i(7, 0, -2)
	var east := Vector3i(9, 0, -2)
	for y in 3:
		island.add_block(Vector3i(west.x, y, west.z))
	for y in 2:
		island.add_block(Vector3i(east.x, y, east.z))
	await wait_physics_frames(20)
	var t := await give_climb(block)
	assert_eq(t.mode, TriggerMode.Kind.NONE, "climb is held, not triggered")
	await wait_physics_frames(120)
	var block_top := block.global_position.y + RuleBlock.SIZE * 0.5
	assert_almost(block_top, 3.0, 0.05, "up to the west column's 3, not the east's 2")
	await wait_physics_frames(60)
	assert_almost(block.global_position.y + 0.5, 3.0, 0.05, "and it holds on there")
	island.ledger.recall(t.id)
	await wait_physics_frames(120)
	assert_almost(block.global_position.y, 0.5, 0.05, "recalled: falls back to the ground")


func test_climbs_the_high_ground_wall_and_a_rider_can_use_it() -> void:
	var block := island.row[0]  # 高台（高さ3）の南に接している
	await give_climb(block)
	await wait_physics_frames(120)
	assert_almost(block.global_position.y + 0.5, 3.0, 0.05, "flush with the high ground")


func test_nothing_taller_means_no_climbing() -> void:
	var block := island.shuttle  # 谷底（上面 0）。両側の谷の壁と小島も上面 0
	await give_climb(block)
	await wait_physics_frames(60)
	assert_lt(block.global_position.y, 0.6, "valley walls are only as high as its top")


func test_climb_prohibition_wins() -> void:
	var block := island.row[0]
	island.ledger.place_on_entity(RuleAction.Kind.CLIMB, true, block.entity_id)
	await give_climb(block)
	await wait_physics_frames(90)
	assert_almost(block.global_position.y, 0.5, 0.05)
