extends TestCase
## 装備を島で使う: 拾う → 持ち物の画面で装備 → ジャンプブーツで岩棚へ、グローブで高台の壁を登る。

var island: PrototypeIsland
var panel: InventoryPanel


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	panel = InventoryPanel.new()
	panel.ledger = island.ledger
	tree.root.add_child(panel)
	await wait_physics_frames(10)


func after_each() -> void:
	island.queue_free()
	panel.queue_free()
	await tree.process_frame


func place_player(at: Vector3) -> void:
	island.player.global_position = at
	island.player.velocity = Vector3.ZERO
	island.player.move_intent = Vector2.ZERO
	island.player.view_yaw = 0.0
	await wait_physics_frames(6)


func pick_up_and_wear(at: Vector3, part: RuleVessel.Part) -> RuleVessel:
	await place_player(at)
	var item := island.nearest_world_item()
	island.interact(null)
	assert_eq(island.ledger.vessel(item.id).location, RuleVessel.Location.INVENTORY)
	panel.open()
	assert_true(panel.drop_on_equip(item.id, part), "dropped on the right slot")
	panel.close()
	return item


## 岩棚（高さ2）の南から、跳んで北へ進む。乗れたら最後の高さが 2 付近になる。
func jump_north_onto_ledge() -> float:
	await place_player(Vector3(8.5, 0.0, -4.2))
	island.player.request_jump()
	for i in 90:
		await tree.physics_frame
		island.player.move_intent = Vector2(0.0, 1.0) if i > 8 else Vector2.ZERO
	island.player.move_intent = Vector2.ZERO
	await wait_physics_frames(20)
	return island.player.global_position.y


func test_boots_must_be_worn_to_reach_the_ledge() -> void:
	assert_lt(await jump_north_onto_ledge(), 0.5, "a plain jump does not reach height 2")
	var boots := await pick_up_and_wear(island.BOOTS_AT, RuleVessel.Part.FEET)
	assert_false(panel.drop_on_equip(boots.id, RuleVessel.Part.HANDS), "wrong part is refused")
	assert_almost(island.player.jump_height(), Tuning.BOOTS_JUMP_HEIGHT, 0.001)
	assert_almost(await jump_north_onto_ledge(), 2.0, 0.1, "boots reach the ledge")


func test_boots_need_the_jump_itself() -> void:
	await pick_up_and_wear(island.BOOTS_AT, RuleVessel.Part.FEET)
	island.select_slot(4)
	var row := island.row[0]
	await place_player(row.global_position + Vector3(0.0, -0.5, 1.5))
	island.lend_to(row, false)
	assert_false(island.ledger.player_can(RuleAction.Kind.JUMP), "jump lent away")
	assert_lt(await jump_north_onto_ledge(), 0.5, "boots alone do not jump")


func test_gloves_climb_the_high_ground_wall() -> void:
	await pick_up_and_wear(island.GLOVES_AT, RuleVessel.Part.HANDS)
	await place_player(Vector3(6.5, 0.0, -4.3))
	var climbed := false
	for i in 240:
		island.player.move_intent = Vector2(0.0, 1.0)
		await tree.physics_frame
		climbed = climbed or island.player.climbing
		if island.player.is_on_floor() and island.player.global_position.y > 2.9:
			break  # 登りきったら少しだけ進んで止まる（歩き続けると北の端から落ちる）
	await wait_physics_frames(15)
	island.player.move_intent = Vector2.ZERO
	await wait_physics_frames(20)
	assert_true(climbed)
	assert_almost(island.player.global_position.y, 3.0, 0.1, "on top of the high ground")
	assert_true(island.goal_cleared, "any route counts")


func test_unworn_gloves_do_not_climb() -> void:
	await place_player(Vector3(6.5, 0.0, -4.3))
	for i in 120:
		island.player.move_intent = Vector2(0.0, 1.0)
		await tree.physics_frame
	assert_false(island.player.climbing)
	assert_lt(island.player.global_position.y, 0.5)
