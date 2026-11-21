extends TestCase
## 風（docs/adr/0015）: 範囲の中のプレイヤー・ブロック・生き物・落ちている器を風下へ押す。重いものは押さない。
## 脈打つ風は拍子のとおりに吹き、止む。見た目は風上のかざぐるま（骨格の「spin」）と流れる木の葉。
##
## 試しの置き場所（このテストの中だけの小さな島）:
##   草の台 x -6〜6, z -3〜3（上面 y = 0）。東（+X）向きの風が x -6〜6, z -1〜1, 高さ 0〜2 に吹く。
##   東の端 x = 4 に高さ 2 の岩の壁（z -1〜1）。ブロックと器はこの壁の手前で止まる。

const HEAVY := RuleAction.Kind.HEAVY
const EAST := Vector3i(1, 0, 0)

var world: GameWorld
var layout: NatureLayout


func before_each() -> void:
	world = GameWorld.new()
	tree.root.add_child(world)
	(
		world
		. build_terrain(
			[
				[Vector3i(-6, -1, -3), Vector3i(6, -1, 3), "grass"],
				[Vector3i(4, 0, -1), Vector3i(4, 1, 1), "rock"],
			]
		)
	)
	layout = NatureLayout.new()
	layout.add_wind(Vector3i(-6, 0, -1), Vector3i(6, 2, 1), EAST)
	NatureBuilder.build(world, layout)
	world.spawn_player(Vector3(-4.5, 0.0, 0.5))
	await wait_physics_frames(5)


func after_each() -> void:
	world.queue_free()
	await tree.process_frame


func test_wind_pushes_a_player_standing_still() -> void:
	var start := world.player.global_position
	await wait_physics_frames(40)
	var moved := world.player.global_position.x - start.x
	assert_gt(moved, 1.2, "blown about 3 m/s downwind")
	assert_almost(world.player.global_position.z, start.z, 0.05, "only along the wind")


func test_a_heavy_player_stands_firm() -> void:
	world.ledger.give_player_item(HEAVY, false, 0)
	var start := world.player.global_position
	await wait_physics_frames(40)
	assert_almost(world.player.global_position.x, start.x, 0.05, "heavy is not blown")


func test_walking_upwind_is_slow_but_possible() -> void:
	world.ledger.give_player_item(RuleAction.Kind.LEFT, false, 0)
	world.player.global_position = Vector3(2.5, 0.0, 0.5)
	world.player.view_yaw = 0.0
	world.player.move_intent = Vector2(-1.0, 0.0)
	await wait_physics_frames(2)
	var start := world.player.global_position.x
	await wait_physics_frames(60)
	var moved := start - world.player.global_position.x
	assert_gt(moved, 1.0, "5 m/s against 3 m/s still makes way")
	assert_lt(moved, 3.0, "but slower than walking")


func test_outside_the_wind_nothing_happens() -> void:
	world.player.global_position = Vector3(-4.5, 0.0, 2.5)
	await wait_physics_frames(30)
	assert_almost(world.player.global_position.x, -4.5, 0.05)


func test_wind_carries_a_block_cell_by_cell_until_the_wall() -> void:
	var block := world.add_block(Vector3i(-1, 0, 0))
	# 1 マスごとに 0.9 秒待って 0.45 秒で動く。4 マスで約 5.4 秒
	await wait_physics_frames(420)
	assert_eq(block.cell(), Vector3i(3, 0, 0), "stopped by the rock wall")


func test_a_heavy_block_stays_put() -> void:
	var block := world.add_block(Vector3i(-1, 0, 0))
	world.ledger.place_on_entity(HEAVY, false, block.entity_id, TriggerMode.Kind.NONE)
	await wait_physics_frames(120)
	assert_eq(block.cell(), Vector3i(-1, 0, 0))


func test_lending_heavy_to_a_drifting_block_anchors_it() -> void:
	var block := world.add_block(Vector3i(-1, 0, 0))
	await wait_physics_frames(70)
	assert_gt(float(block.cell().x), -1.0, "drifting")
	var v := world.ledger.give_player_item(HEAVY, false, 0)
	world.ledger.lend(v.id, PackedInt32Array([block.entity_id]), TriggerMode.Kind.NONE)
	await wait_physics_frames(40)
	var cell := block.cell()
	await wait_physics_frames(120)
	assert_eq(block.cell(), cell, "heavy blocks ignore the wind")


func test_wind_carries_a_dropped_item_but_not_over_the_wall() -> void:
	var v := world.ledger.place_in_world(RuleAction.Kind.JUMP, false, Vector3(1.5, 0.0, 0.5))
	await wait_physics_frames(200)
	assert_almost(v.world_position.x, 3.5, 0.01, "rests against the wall")
	assert_almost(v.world_position.y, 0.0, 0.01)


func test_wind_pushes_creatures_unless_heavy() -> void:
	var creature := world.add_creature(Vector3(-2.5, 0.0, 0.5))
	await wait_physics_frames(3)
	assert_gt(creature.external_velocity.x, 2.0)
	world.ledger.place_on_entity(HEAVY, false, creature.entity_id, TriggerMode.Kind.NONE)
	await wait_physics_frames(3)
	assert_eq(creature.external_velocity, Vector3.ZERO)


func test_pulsing_wind_and_its_visuals() -> void:
	layout.winds[0].period = 2.0
	layout.winds[0].on_time = 0.5
	world.nature.clock = 1.0
	var visual := world.find_child("Wind", false, false) as WindVisual
	assert_true(visual != null, "a wind visual was built")
	assert_true(visual.fan.find_child("AnimationPlayer", true, false) != null, "rigged fan")
	var start := world.player.global_position.x
	await wait_physics_frames(30)
	assert_almost(world.player.global_position.x, start, 0.05, "calm between gusts")
	assert_false(visual.leaves.emitting, "no leaves while calm")
	world.nature.clock = 0.0
	await wait_physics_frames(20)
	assert_gt(world.player.global_position.x - start, 0.4, "a gust")
	assert_true(visual.leaves.emitting)


func test_checkpoint_keeps_the_wind_clock() -> void:
	world.nature.clock = 7.25
	var saved := WorldSnapshot.capture(world)
	world.nature.clock = 0.0
	world.nature.drift_timers[123] = 0.5
	WorldSnapshot.apply(world, saved)
	assert_almost(world.nature.clock, 7.25, 0.001)
	assert_false(world.nature.drift_timers.has(123))
