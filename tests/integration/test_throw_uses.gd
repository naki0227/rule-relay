extends TestCase
## 「投げる」の使い道（2026-11-19 本人の判断）: 発射台は投げるが来ないと撃たない。
## 何かを持っている生き物は、投げるがあると投げる。玉が鐘に当たると鐘が鳴る。

const THROW_SLOT := 5

var island: PrototypeIsland


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	await wait_physics_frames(10)


func after_each() -> void:
	island.queue_free()
	await tree.process_frame


func lend_throw_to(target: Node3D) -> void:
	island.player.global_position = target.global_position + Vector3(0.0, -0.5, 1.6)
	island.player.velocity = Vector3.ZERO
	await wait_physics_frames(4)
	island.select_slot(THROW_SLOT)
	assert_eq(island.lend_to(target, false), RuleLedger.LendResult.OK)


func balls() -> int:
	return tree.get_nodes_in_group(&"thrown_balls").size()


func test_launcher_does_nothing_without_throw() -> void:
	await wait_physics_frames(int(60 * Tuning.REPEAT_PERIOD * 3))
	assert_eq(balls(), 0)
	assert_false(island.bell.is_ringing())


func test_launcher_with_throw_rings_the_bell_from_afar() -> void:
	await lend_throw_to(island.launcher)
	island.player.global_position = Vector3(0.5, 0.0, 4.5)  # 鐘から離れる
	var fired := false
	for i in 120:
		await tree.physics_frame
		fired = fired or balls() > 0
		if island.bell.is_ringing():
			break
	assert_true(fired, "it fired a ball")
	assert_true(island.bell.is_ringing(), "the ball hit the bell")


func test_launcher_stops_when_throw_is_recalled() -> void:
	await lend_throw_to(island.launcher)
	await wait_physics_frames(30)
	island.interact(island.launcher)
	assert_false(island.ledger.can_initiate(island.launcher.entity_id, RuleAction.Kind.THROW))
	await wait_physics_frames(int(60 * 1.2))
	var before := balls()
	await wait_physics_frames(int(60 * Tuning.REPEAT_PERIOD * 2))
	assert_eq(balls(), 0, "no new balls (was %d)" % before)


func test_creature_throws_what_it_holds_only_with_throw() -> void:
	var creature := island.creature
	assert_eq(creature.held_item, "木の実")
	await wait_physics_frames(90)
	assert_eq(creature.held_item, "木の実", "no throw: keeps holding it")
	await lend_throw_to(creature)
	var thrown := false
	for i in 120:
		await tree.physics_frame
		thrown = thrown or balls() > 0
	assert_true(thrown, "threw the nut")
	assert_eq(creature.held_item, "", "hands are empty now")


func test_bells_are_not_lending_targets() -> void:
	island.player.global_position = island.bell.global_position + Vector3(0.0, 0.0, 1.6)
	await wait_physics_frames(3)
	island.select_slot(4)
	assert_ne(island.lend_to(island.bell, false), RuleLedger.LendResult.OK)
	assert_true(island.ledger.player_can(RuleAction.Kind.JUMP))
