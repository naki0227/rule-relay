extends TestCase
## 願いを持つ生き物（企画書 6）を島で確かめる: 願いへ向かう・待つ・禁止優先・環境変化で再挑戦、
## 単体だけで受け取り範囲からは受け取らない、F で回収、チェックポイントで戻る。

const JUMP_SLOT := 4

var island: PrototypeIsland
var creature: Creature


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	creature = island.creature
	await wait_physics_frames(30)


func after_each() -> void:
	island.queue_free()
	await tree.process_frame


func near_creature() -> void:
	island.player.global_position = creature.global_position + Vector3(-1.5, 0.0, 0.0)
	island.player.velocity = Vector3.ZERO
	await wait_physics_frames(4)


func run_seconds(seconds: float) -> float:
	var top := creature.global_position.y
	for i in int(seconds * 60.0):
		await tree.physics_frame
		top = maxf(top, creature.global_position.y)
	return top


func test_waits_on_the_ground_without_jump() -> void:
	assert_eq(creature.stage, CreatureMind.Stage.WAIT, "no route to anything higher")
	assert_lt(await run_seconds(2.0), 0.3)


func test_heads_for_higher_ground_once_it_has_jump() -> void:
	await near_creature()
	island.select_slot(JUMP_SLOT)
	assert_eq(island.lend_to(creature, false), RuleLedger.LendResult.OK)
	var token := island.ledger.token(island.selected_vessel().token_id)
	assert_eq(token.mode, TriggerMode.Kind.NONE, "creatures take no trigger mode")
	assert_false(island.ledger.player_can(RuleAction.Kind.JUMP), "the player lost the jump")
	await wait_physics_frames(3)
	assert_eq(creature.stage, CreatureMind.Stage.SEEK, "re-plans when its abilities change")
	assert_gt(await run_seconds(8.0), 0.9, "it jumped up onto something higher by itself")


func test_prohibition_wins_over_the_wish() -> void:
	island.ledger.place_on_entity(RuleAction.Kind.JUMP, true, creature.entity_id)
	await near_creature()
	island.select_slot(JUMP_SLOT)
	island.lend_to(creature, false)
	assert_lt(await run_seconds(4.0), 0.3, "has jump but also a jump prohibition: does not jump")
	assert_eq(creature.stage, CreatureMind.Stage.WAIT)


func test_range_lending_never_reaches_creatures() -> void:
	await near_creature()
	island.select_slot(JUMP_SLOT)
	assert_eq(island.lend_to(creature, true), RuleLedger.LendResult.RANGE_ONLY_FOR_BLOCKS)
	var preview := island.preview_range(creature)
	assert_ne(String(preview["reason"]), "")
	var selection := island.range_selection(island.mover)
	assert_false((selection["ids"] as PackedInt32Array).has(creature.entity_id))


func test_f_recalls_everything_on_the_creature() -> void:
	await near_creature()
	island.select_slot(JUMP_SLOT)
	island.lend_to(creature, false)
	await wait_physics_frames(2)
	await near_creature()
	island.interact(creature)
	assert_true(island.ledger.player_can(RuleAction.Kind.JUMP), "the player's own jump came back")
	assert_eq(island.ledger.tokens_on(creature.entity_id).size(), 0, "one F takes everything")
	assert_eq(island.ledger.inventory_vessels().size(), 4, "its W/A/S/D went into the bag")


func test_checkpoint_restores_the_creature() -> void:
	var start := creature.global_position
	await near_creature()
	island.select_slot(JUMP_SLOT)
	island.lend_to(creature, false)
	await run_seconds(6.0)
	assert_gt(creature.global_position.distance_to(start), 0.5, "it moved")
	island.restart_island()
	await wait_physics_frames(2)
	assert_lt(creature.global_position.distance_to(start), 0.1)
	assert_true(island.ledger.player_can(RuleAction.Kind.JUMP))
