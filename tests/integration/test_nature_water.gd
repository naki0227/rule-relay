extends TestCase
## 水と流れ、浮く・泳ぐ・重い（docs/adr/0015）。
## - 水は底なし。泳げない人・重い人は沈み、島から落ちたのと同じになる（死亡→観戦の流れをそのまま使う）。
## - 浮く人・泳げる人は水面に浮かぶ。泳げる人だけが自分で進め、流れには誰でも運ばれる。
## - 浮くブロックは水に浮いて筏になる（上面が岸の地面とそろう）。浮かないブロックは沈んで元の位置へ戻る。
## - 浮く人・ブロックは空中でゆっくり落ちる（×n で n 倍ゆっくり）。
##
## 試しの置き場所: 西の岸 x -6〜-1・東の岸 x 4〜8（z -3〜3、上面 y = 0）。その間 x 0〜3 が水
## （セル y -2〜-1、水面 y = -0.2。下には何も無い）。流れは各テストで向きを決める。

const SWIM := RuleAction.Kind.SWIM
const FLOAT := RuleAction.Kind.FLOAT
const HEAVY := RuleAction.Kind.HEAVY
const SOUTH := Vector3i(0, 0, 1)
const EAST := Vector3i(1, 0, 0)

var world: GameWorld


func before_each() -> void:
	world = GameWorld.new()
	world.networked = true  # 1人用の「落ちたら保存へ戻る」を止め、沈んだ先まで見る
	tree.root.add_child(world)
	(
		world
		. build_terrain(
			[
				[Vector3i(-6, -1, -3), Vector3i(-1, -1, 3), "grass"],
				[Vector3i(4, -1, -3), Vector3i(8, -1, 3), "grass"],
			]
		)
	)
	world.spawn_player(Vector3(-3.5, 0.0, 0.5))
	await wait_physics_frames(3)


func after_each() -> void:
	world.queue_free()
	await tree.process_frame


func _water(direction: Vector3i = Vector3i.ZERO, speed: float = NatureTuning.CURRENT_SPEED) -> void:
	var layout := NatureLayout.new()
	if direction == Vector3i.ZERO:
		layout.add_water(Vector3i(0, -2, -3), Vector3i(3, -1, 3))
	else:
		layout.add_current(Vector3i(0, -2, -3), Vector3i(3, -1, 3), direction, speed)
	NatureBuilder.build(world, layout)


func _drop_in(at: Vector3 = Vector3(1.5, -0.3, 0.5)) -> void:
	world.player.global_position = at
	world.player.velocity = Vector3.ZERO
	await wait_physics_frames(60)


func test_without_swim_a_player_sinks_like_falling_off() -> void:
	_water()
	world.player.global_position = Vector3(1.5, -0.3, 0.5)
	await wait_physics_frames(150)
	assert_lt(world.player.global_position.y, Tuning.FALL_LIMIT_Y, "sank below the fall line")


func test_a_swimmer_floats_at_the_surface() -> void:
	_water()
	world.ledger.give_player_item(SWIM, false, 0)
	await _drop_in()
	var feet := world.player.global_position.y
	assert_almost(feet, -0.2 - NatureTuning.AFLOAT_DEPTH, 0.12, "head above the water")
	assert_true(world.player.afloat)


func test_a_swimmer_moves_at_swim_speed() -> void:
	_water()
	world.ledger.give_player_item(SWIM, false, 0)
	world.ledger.give_player_item(RuleAction.Kind.FORWARD, false, 1)
	await _drop_in(Vector3(1.5, -0.3, 2.5))
	world.player.view_yaw = 0.0
	world.player.move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(2)
	var start := world.player.global_position.z
	await wait_physics_frames(30)
	var speed := (start - world.player.global_position.z) * 2.0
	assert_almost(speed, NatureTuning.SWIM_SPEED, 0.4, "slower than walking")


func test_float_keeps_you_up_but_does_not_swim() -> void:
	_water()
	world.ledger.give_player_item(FLOAT, false, 0)
	world.ledger.give_player_item(RuleAction.Kind.RIGHT, false, 1)
	await _drop_in()
	world.player.view_yaw = 0.0
	world.player.move_intent = Vector2(1.0, 0.0)
	await wait_physics_frames(30)
	assert_gt(world.player.global_position.y, -1.0, "still afloat")
	assert_almost(world.player.global_position.x, 1.5, 0.1, "cannot paddle without SWIM")


func test_heavy_sinks_even_a_swimmer() -> void:
	_water()
	world.ledger.give_player_item(SWIM, false, 0)
	world.ledger.give_player_item(HEAVY, false, 1)
	world.player.global_position = Vector3(1.5, -0.3, 0.5)
	await wait_physics_frames(150)
	assert_lt(world.player.global_position.y, Tuning.FALL_LIMIT_Y, "heavy sinks")


func test_a_swimmer_can_jump_out_onto_the_bank() -> void:
	_water()
	world.ledger.give_player_item(SWIM, false, 0)
	world.ledger.give_player_item(RuleAction.Kind.RIGHT, false, 1)
	world.ledger.give_player_item(RuleAction.Kind.JUMP, false, 2)
	await _drop_in(Vector3(3.2, -0.3, 0.5))
	world.player.view_yaw = 0.0
	world.player.move_intent = Vector2(1.0, 0.0)
	world.press_action(RuleAction.Kind.JUMP)
	await wait_physics_frames(60)
	assert_gt(world.player.global_position.x, 4.0, "on the east bank")
	assert_almost(world.player.global_position.y, 0.0, 0.1, "standing on the grass")


func test_the_current_carries_a_floating_player() -> void:
	_water(SOUTH)
	world.ledger.give_player_item(FLOAT, false, 0)
	await _drop_in(Vector3(1.5, -0.3, -2.5))
	assert_gt(world.player.global_position.z, -1.0, "carried south")


func test_one_swim_cannot_beat_the_current_but_two_can() -> void:
	_water(SOUTH)
	world.ledger.give_player_item(SWIM, false, 0)
	world.ledger.give_player_item(RuleAction.Kind.FORWARD, false, 1)
	await _drop_in(Vector3(1.5, -0.3, 0.5))
	world.player.global_position = Vector3(1.5, -0.65, 0.5)
	world.player.view_yaw = 0.0
	world.player.move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(30)
	assert_gt(world.player.global_position.z, 0.6, "x1 (2.5 m/s) loses to 3 m/s")
	world.ledger.give_player_item(SWIM, false, 2)
	world.player.global_position = Vector3(1.5, -0.65, 0.5)
	await wait_physics_frames(30)
	assert_lt(world.player.global_position.z, 0.0, "x2 (5 m/s) goes upstream")


func test_float_slows_falling_and_stacks() -> void:
	world.ledger.give_player_item(FLOAT, false, 0)
	world.player.global_position = Vector3(-3.5, 8.0, 0.5)
	await wait_physics_frames(30)
	assert_almost(world.player.velocity.y, -NatureTuning.FLOAT_FALL_SPEED, 0.05)
	world.ledger.give_player_item(FLOAT, false, 1)
	await wait_physics_frames(5)
	assert_almost(world.player.velocity.y, -NatureTuning.FLOAT_FALL_SPEED / 2.0, 0.05)


func test_a_plain_block_sinks_and_comes_home() -> void:
	_water()
	var block := world.add_block(Vector3i(-1, 0, 0))
	await wait_physics_frames(5)
	assert_true(block.push(EAST))
	var sank := false
	for i in 400:
		await tree.physics_frame
		sank = sank or block.global_position.y < -3.0
		if sank and block.cell() == Vector3i(-1, 0, 0):
			break
	assert_true(sank, "it went under")
	assert_eq(block.cell(), Vector3i(-1, 0, 0), "rescued back to where it started")


func test_a_floating_block_is_a_raft() -> void:
	_water()
	var block := world.add_block(Vector3i(-1, 0, 0))
	world.ledger.place_on_entity(FLOAT, false, block.entity_id, TriggerMode.Kind.NONE)
	await wait_physics_frames(5)
	assert_true(block.push(EAST))
	await wait_physics_frames(120)
	assert_true(block.afloat, "floating")
	assert_almost(block.global_position.y, -0.5, 0.05, "top meets the banks")
	assert_eq(block.cell(), Vector3i(0, -1, 0))
	world.player.global_position = Vector3(0.5, 0.3, 0.5)
	await wait_physics_frames(30)
	assert_almost(world.player.global_position.y, 0.0, 0.05, "you can stand on it")
	assert_true(block.is_ready_for(RuleAction.Kind.RIGHT), "a raft can take its own steps")


func test_the_current_carries_a_raft_to_the_bank() -> void:
	_water(EAST)
	var block := world.add_block(Vector3i(-1, 0, 0))
	world.ledger.place_on_entity(FLOAT, false, block.entity_id, TriggerMode.Kind.NONE)
	await wait_physics_frames(5)
	block.push(EAST)
	await wait_physics_frames(480)
	assert_eq(block.cell(), Vector3i(3, -1, 0), "stopped by the east bank")


func test_the_current_carries_dropped_items() -> void:
	_water(SOUTH)
	var v := world.ledger.place_in_world(RuleAction.Kind.JUMP, false, Vector3(1.5, -0.2, -2.5))
	await wait_physics_frames(130)
	assert_gt(v.world_position.z, -1.0, "floated downstream")
	assert_almost(v.world_position.y, -0.2, 0.01, "on the surface")


func test_water_visuals_are_built() -> void:
	_water(SOUTH)
	var water := world.find_child("Water", false, false) as WaterVisual
	assert_true(water != null)
	assert_true(water.foam != null, "a current shows drifting foam")
