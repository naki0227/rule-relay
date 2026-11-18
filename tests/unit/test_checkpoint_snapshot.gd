extends TestCase
## チェックポイント: 保存→変更→復元で所有状態が丸ごと戻り、トークンが増えない（受け入れテスト 6）。

const JUMP := RuleAction.Kind.JUMP


func test_restore_returns_ownership_without_duplication() -> void:
	var ledger := RuleLedger.new()
	ledger.register_entity(10, EntityKind.Kind.BLOCK)
	var jump := ledger.give_player_item(JUMP, false, 0)
	ledger.place_on_entity(JUMP, true, 10)
	var saved := ledger.snapshot()

	ledger.lend(jump.id, PackedInt32Array([10]), TriggerMode.Kind.REPEAT)
	ledger.recall_from_entity(10)  # 能力と禁止を両方回収 → 禁止を拾う
	assert_false(ledger.player_can(JUMP))

	ledger.restore(saved)
	assert_true(ledger.player_can(JUMP))
	assert_true(ledger.entity_prohibited(10, JUMP))
	assert_false(ledger.entity_has_ability(10, JUMP))
	assert_eq(ledger.inventory_vessels().size(), 0, "picked-up vessel is gone again")
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))


func test_snapshot_is_independent_of_later_changes() -> void:
	var ledger := RuleLedger.new()
	ledger.register_entity(10, EntityKind.Kind.BLOCK)
	var jump := ledger.give_player_item(JUMP, false, 0)
	var saved := ledger.snapshot()
	ledger.lend(jump.id, PackedInt32Array([10]), TriggerMode.Kind.REPEAT)
	ledger.restore(saved)
	ledger.lend(jump.id, PackedInt32Array([10]), TriggerMode.Kind.REPEAT)
	ledger.restore(saved)
	assert_true(ledger.player_can(JUMP), "restoring twice from the same snapshot works")


func test_ids_continue_after_restore() -> void:
	var ledger := RuleLedger.new()
	ledger.give_player_item(JUMP, false, 0)
	var saved := ledger.snapshot()
	var later := ledger.give_player_item(RuleAction.Kind.FORWARD, false, 1)
	ledger.restore(saved)
	var again := ledger.give_player_item(RuleAction.Kind.FORWARD, false, 1)
	assert_eq(again.id, later.id, "ids restart from the saved counter, so no collisions")
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))
