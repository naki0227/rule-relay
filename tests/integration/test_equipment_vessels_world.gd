extends TestCase
## 装備は入れ物（docs/adr/0018）を島で: ホットバーのブーツから触って・投げて渡すと中の能力だけが移り、
## 入れ物は枠に残る。F で入れ物へ戻り、身につけていれば効き目も戻る。チェックポイントは両方を別々に戻す。

const BOOTS := RuleAction.Kind.HIGH_JUMP
const BOOTS_SLOT := 7

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


## 島に落ちているジャンプブーツを F で拾い、ホットバーの BOOTS_SLOT へ置く（身につけない）。
func boots_on_hotbar() -> RuleVessel:
	await place_player(island.BOOTS_AT)
	var boots := island.nearest_world_item()
	island.interact(null)
	assert_true(island.ledger_actions.move_to_hotbar(boots.id, BOOTS_SLOT))
	island.select_slot(BOOTS_SLOT)
	return boots


func test_only_worn_boots_raise_the_jump() -> void:
	var boots := await boots_on_hotbar()
	assert_almost(island.player.jump_height(), Tuning.PLAYER_JUMP_HEIGHT, 0.001, "hotbar: none")
	island.ledger_actions.equip(boots.id)
	assert_almost(island.player.jump_height(), Tuning.BOOTS_JUMP_HEIGHT, 0.001, "worn: higher")


func test_touch_lend_from_hotbar_boots_then_f_brings_it_home() -> void:
	var boots := await boots_on_hotbar()
	var block := island.mover
	await place_player(block.global_position + Vector3(-1.6, -0.5, 1.0))
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.OK)
	assert_eq(island.ledger.hotbar_vessel(BOOTS_SLOT), boots, "the boots stay in the slot")
	assert_true(
		island.ledger.entity_has_ability(block.entity_id, BOOTS), "the block got the ability"
	)
	island.ledger_actions.equip(boots.id)
	assert_almost(island.player.jump_height(), Tuning.PLAYER_JUMP_HEIGHT, 0.001, "empty boots")
	island.interact(block)
	assert_true(island.ledger.token(boots.token_id).is_in_vessel(), "F: back in the boots")
	assert_eq(island.ledger.equipped_vessel(RuleVessel.Part.FEET), boots)
	assert_almost(island.player.jump_height(), Tuning.BOOTS_JUMP_HEIGHT, 0.001, "worn and full")
	assert_true(island.ledger.validate().is_empty())


func test_throwing_from_hotbar_boots_sends_only_a_medal() -> void:
	var boots := await boots_on_hotbar()
	var block := island.mover
	var at := block.global_position
	await place_player(Vector3(at.x - 8.0, 0.0, at.z))
	island.toggle_reach()
	assert_true(island.throw_mode, "throw reach is on")
	island.select_slot(BOOTS_SLOT)
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.OK, "thrown")
	await wait_physics_frames(int(60 * MedalThrow.RELEASE_DELAY) + 4)
	var flying := MedalThrow.flying(island)
	assert_eq(flying.size(), 1)
	if flying.size() == 1:
		assert_eq(flying[0].find_children("*", "MedalVisual", true, false).size(), 1, "a medal")
		assert_eq(island.find_children("*", "WorldItem", true, false).size(), 1, "gloves only")
	assert_true(await wait_throws(island), "the medal lands")
	assert_true(island.ledger.entity_has_ability(block.entity_id, BOOTS), "only the ability moved")
	assert_eq(island.ledger.hotbar_vessel(BOOTS_SLOT), boots, "the shell never left the slot")
	var entry := InventoryQuery.describe(island.ledger, boots)
	assert_true(entry.state_text.begins_with("空"), entry.state_text)


func test_checkpoint_restores_the_shell_and_the_ability_apart() -> void:
	var boots := await boots_on_hotbar()
	var block := island.mover
	await place_player(block.global_position + Vector3(-1.6, -0.5, 1.0))
	island.lend_to(block, false)
	assert_true(island.save_checkpoint(), "saved with the ability on the block")
	island.interact(block)
	island.ledger_actions.equip(boots.id)
	assert_true(island.player.ledger.player_can(BOOTS))
	island.restore_checkpoint()
	await wait_physics_frames(2)
	var shell := island.ledger.vessel(boots.id)
	assert_eq(shell.location, RuleVessel.Location.HOTBAR, "the empty shell is back on the hotbar")
	assert_eq(shell.slot, BOOTS_SLOT)
	assert_true(
		island.ledger.entity_has_ability(block.entity_id, BOOTS), "the ability is on the block"
	)
	assert_false(island.ledger.player_can(BOOTS))
	island.interact(block)
	assert_true(island.ledger.token(boots.token_id).is_in_vessel(), "F still finds the shell")


func test_range_lend_from_hotbar_boots_moves_only_the_ability() -> void:
	var boots := await boots_on_hotbar()
	await place_player(Vector3(4.5, 0.0, -2.5))
	island.select_slot(BOOTS_SLOT)
	assert_eq(island.lend_to(island.row[0], true), RuleLedger.LendResult.OK, "range lend")
	var t := island.ledger.token(boots.token_id)
	assert_true(t.is_range, "lent as a range")
	assert_gt(t.holder_ids.size(), 1, "several blocks hold it")
	for b in island.row:
		assert_true(island.ledger.entity_has_ability(b.entity_id, BOOTS), "every block in the row")
	assert_eq(island.ledger.hotbar_vessel(BOOTS_SLOT), boots, "the shell stays in the slot")
	island.interact(island.row[0])
	assert_true(t.is_in_vessel(), "F brings the range back into the shell")
	for b in island.row:
		assert_false(island.ledger.entity_has_ability(b.entity_id, BOOTS))
	assert_true(island.ledger.validate().is_empty())
