extends TestCase
## プレイヤーの移動・段差補助（企画書 4-1, 4-6）。島に依存しない最小の世界で確かめる。

var world: GameWorld


func before_each() -> void:
	world = GameWorld.new()
	tree.root.add_child(world)
	TerrainBuilder.add_box(world, Vector3i(-5, -1, -5), Vector3i(5, -1, 5), Color.GRAY)
	for action: RuleAction.Kind in RuleAction.ALL:
		world.ledger.give_player_item(action, false, int(action))
	world.spawn_player(Vector3(0.5, 0.0, 2.5))
	await wait_physics_frames(5)


func after_each() -> void:
	world.queue_free()
	await tree.process_frame


func add_slab(height: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Tuning.LAYER_TERRAIN
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, height, 6.0)
	shape.shape = box
	shape.position = Vector3(0.5, height * 0.5, -3.0)
	body.add_child(shape)
	world.add_child(body)


func walk_north(frames: int) -> void:
	world.player.move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(frames)
	world.player.move_intent = Vector2.ZERO


func test_walks_relative_to_camera() -> void:
	world.player.view_yaw = PI * 0.5  # カメラが西を向く → 前進は西（-X）
	world.player.move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(30)
	assert_lt(world.player.global_position.x, -1.5)
	assert_almost(world.player.global_position.z, 2.5, 0.05)


func test_lost_w_still_allows_turning_and_using_a() -> void:
	var w := world.ledger.hotbar_vessel(int(RuleAction.Kind.FORWARD))
	world.ledger.move_to_inventory(w.id)
	world.player.move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(20)
	assert_almost(world.player.global_position.z, 2.5, 0.05, "W is gone")
	world.player.view_yaw = -PI * 0.5  # 右を向くと、A（左）で元の北へ進める（許容する抜け道）
	world.player.move_intent = Vector2(-1.0, 0.0)
	await wait_physics_frames(20)
	assert_lt(world.player.global_position.z, 1.5)


func test_step_assist_climbs_low_step() -> void:
	add_slab(0.35)
	await walk_north(60)
	assert_almost(world.player.global_position.y, 0.35, 0.05, "0.35 step is walkable")


func test_step_assist_does_not_climb_high_step() -> void:
	add_slab(0.6)
	await walk_north(60)
	assert_almost(world.player.global_position.y, 0.0, 0.05, "0.6 step needs a jump")


func test_no_step_assist_without_move_input() -> void:
	add_slab(0.35)
	world.player.global_position = Vector3(0.5, 0.0, 0.31)
	await wait_physics_frames(30)
	assert_almost(world.player.global_position.y, 0.0, 0.05)


func test_no_step_assist_in_mid_air() -> void:
	# 跳躍の頂点（約1.3）から0.4以内の壁の上面（1.6）へ、空中の段差補助で登れてはいけない
	add_slab(1.6)
	world.player.move_intent = Vector2(0.0, 1.0)
	var highest := 0.0
	for i in 90:
		await tree.physics_frame
		if world.player.is_on_floor():
			world.press_action(RuleAction.Kind.JUMP)
		highest = maxf(highest, world.player.global_position.y)
	assert_lt(highest, 1.45, "only the jump height itself, no climbing")
	assert_lt(world.player.global_position.y, 1.5, "did not end up on top of the wall")
