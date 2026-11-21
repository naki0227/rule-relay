extends TestCase
## 氷（docs/adr/0015）: 地形の種類 "ice" のセル。上に立つと止まれず曲がれない（勢いが残る）。
## ブロックは氷の上で動き終えると同じ向きにもう 1 マスすべり、塞がれるか氷が終わるまで続く。
##
## 試しの置き場所: 草の台 x -6〜7, z -3〜3（上面 y = 0）。その一部 x -2〜3, z -1〜1 が氷。
## 東の x = 6 に高さ 2 の岩の壁（z -1〜1）。

const RIGHT := RuleAction.Kind.RIGHT
const EAST := Vector3i(1, 0, 0)

var world: GameWorld


func before_each() -> void:
	world = GameWorld.new()
	tree.root.add_child(world)
	(
		world
		. build_terrain(
			[
				[Vector3i(-6, -1, -3), Vector3i(7, -1, 3), "grass"],
				[Vector3i(-2, -1, -1), Vector3i(3, -1, 1), "ice"],
				[Vector3i(6, 0, -1), Vector3i(6, 1, 1), "rock"],
			]
		)
	)
	NatureBuilder.build(world, NatureLayout.new())
	world.spawn_player(Vector3(-4.5, 0.0, 0.5))
	await wait_physics_frames(5)


func after_each() -> void:
	world.queue_free()
	await tree.process_frame


func _walk_east_then_stop(start: Vector3, frames: int) -> float:
	world.ledger.give_player_item(RIGHT, false, 0)
	world.player.global_position = start
	world.player.view_yaw = 0.0
	world.player.move_intent = Vector2(1.0, 0.0)
	await wait_physics_frames(frames)
	world.player.move_intent = Vector2.ZERO
	var released := world.player.global_position.x
	await wait_physics_frames(30)
	return world.player.global_position.x - released


func test_ice_cells_are_ice() -> void:
	assert_true(world.nature.is_ice(Vector3i(0, -1, 0)))
	assert_false(world.nature.is_ice(Vector3i(-4, -1, 0)))
	assert_true(world.nature.is_ice_under(Vector3(0.5, 0.0, 0.5)))


func test_on_grass_a_player_stops_at_once() -> void:
	var drift := await _walk_east_then_stop(Vector3(-5.5, 0.0, 2.5), 20)
	assert_lt(drift, 0.15, "grass grips")


func test_on_ice_a_player_keeps_sliding() -> void:
	# 草の上で勢いをつけて氷へ入り、氷の上で手を離す
	var drift := await _walk_east_then_stop(Vector3(-4.5, 0.0, 0.5), 40)
	assert_gt(drift, 1.5, "ice keeps the momentum after letting go")


func test_ice_is_slow_to_get_going() -> void:
	world.ledger.give_player_item(RIGHT, false, 0)
	world.player.global_position = Vector3(-1.5, 0.0, 0.5)
	world.player.view_yaw = 0.0
	await wait_physics_frames(3)
	world.player.move_intent = Vector2(1.0, 0.0)
	await wait_physics_frames(10)
	var speed := world.player.get_real_velocity().x
	assert_lt(speed, 2.0, "cannot reach walking speed at once on ice")
	assert_gt(speed, 0.0)


func test_a_block_slides_across_the_ice_and_stops_on_grass() -> void:
	var block := world.add_block(Vector3i(-1, 0, 0))
	await wait_physics_frames(5)
	assert_true(block.push(EAST))
	await wait_physics_frames(150)
	assert_eq(block.cell(), Vector3i(4, 0, 0), "slid to the first cell without ice under it")


func test_a_block_on_ice_slides_until_it_hits_something() -> void:
	world.add_block(Vector3i(2, 0, 0)).name = "Stopper"
	var block := world.add_block(Vector3i(-2, 0, 0))
	await wait_physics_frames(5)
	assert_true(block.is_ready_for(RIGHT))
	block.perform(RIGHT)
	await wait_physics_frames(120)
	assert_eq(block.cell(), Vector3i(1, 0, 0), "stopped against the other block")


func test_an_ice_cell_turned_into_a_block_is_still_ice() -> void:
	var frost := world.find_child("IceFrost", false, false) as IceFrost
	assert_eq(frost.plate_count(), 18, "frost on every ice top")
	var block := TerrainPromotion.promote(world, Vector3i(0, -1, 0))
	assert_true(block.is_ice(), "the moving cell keeps the ice look and grip")
	assert_true(world.nature.is_ice(Vector3i(0, -1, 0)))
	frost.refresh()
	assert_eq(frost.plate_count(), 17, "the moved cell carries its own frost")


func test_restoring_a_checkpoint_clears_the_slide() -> void:
	var saved := WorldSnapshot.capture(world)
	world.player.slide = Vector2(3.0, 0.0)
	WorldSnapshot.apply(world, saved)
	assert_eq(world.player.slide, Vector2.ZERO)
