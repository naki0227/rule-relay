extends TestCase
## 「投げる」の能力トークンと、世界に落ちている器（F で拾う）の台帳ルール（企画書 5.1・7）。

const THROW := RuleAction.Kind.THROW
const JUMP := RuleAction.Kind.JUMP
const BLOCK := 100

var ledger: RuleLedger


func before_each() -> void:
	ledger = RuleLedger.new()
	ledger.register_entity(BLOCK, EntityKind.Kind.BLOCK)


func test_throw_is_an_ability_that_can_be_lent_away() -> void:
	var v := ledger.give_player_item(THROW, false, 5)
	assert_true(ledger.player_can(THROW))
	var result := ledger.lend(v.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.NONE)
	assert_eq(result, RuleLedger.LendResult.OK)
	assert_false(ledger.player_can(THROW), "lent away: no long-range lending")
	assert_eq(ledger.token(v.token_id).mode, TriggerMode.Kind.NONE, "held, not triggered")
	assert_eq(ledger.vessel(v.id).slot, 5, "the vessel stays in its slot")
	assert_true(ledger.recall(v.token_id))
	assert_true(ledger.player_can(THROW))


func test_held_abilities_ignore_the_trigger_mode() -> void:
	var v := ledger.give_player_item(THROW, false, 0)
	ledger.lend(v.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.SINGLE_SHOT)
	assert_eq(ledger.token(v.token_id).mode, TriggerMode.Kind.NONE)
	assert_true(ledger.pending_single_shots(THROW).is_empty())


func test_world_item_has_no_effect_until_picked_up() -> void:
	var v := ledger.place_in_world(JUMP, true, Vector3(1, 0, 2))
	assert_false(ledger.player_prohibited(JUMP), "a prohibition lying in the world does not bind")
	assert_eq(ledger.world_vessels().size(), 1)
	assert_true(ledger.pickup(v.id))
	assert_eq(ledger.vessel(v.id).location, RuleVessel.Location.INVENTORY, "F puts it in the bag")
	assert_true(ledger.player_prohibited(JUMP), "now carried: binds from the bag")
	assert_true(ledger.world_vessels().is_empty())
	assert_false(ledger.pickup(v.id), "cannot pick up twice")
	assert_true(ledger.validate().is_empty())


func test_world_item_cannot_skip_the_bag() -> void:
	var v := ledger.place_in_world(JUMP, false, Vector3.ZERO)
	assert_false(ledger.move_to_hotbar(v.id, 0))
	assert_false(ledger.move_to_inventory(v.id))
	assert_eq(
		ledger.lend(v.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.REPEAT),
		RuleLedger.LendResult.NOT_IN_HOTBAR
	)


func test_world_items_survive_snapshot_and_restore() -> void:
	var v := ledger.place_in_world(JUMP, false, Vector3(3, 0, 4))
	var saved := ledger.snapshot()
	ledger.pickup(v.id)
	ledger.restore(saved)
	assert_eq(ledger.vessel(v.id).location, RuleVessel.Location.WORLD)
	assert_eq(ledger.vessel(v.id).world_position, Vector3(3, 0, 4))
	assert_eq(ledger.world_vessels().size(), 1)
