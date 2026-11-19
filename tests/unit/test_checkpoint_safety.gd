extends TestCase
## 詰み防止: 保存の条件と、直前の保存・開始時点への戻り先（企画書 9）。


func snap(n: int) -> Dictionary:
	return {"n": n}


func test_latest_falls_back_to_initial() -> void:
	var history := CheckpointHistory.new()
	history.set_initial(snap(0))
	assert_eq(history.latest(), snap(0))
	assert_false(history.can_discard_latest())
	history.push(snap(1))
	assert_eq(history.latest(), snap(1))


func test_discard_latest_steps_back_one_save_at_a_time() -> void:
	var history := CheckpointHistory.new()
	history.set_initial(snap(0))
	history.push(snap(1))
	history.push(snap(2))
	assert_eq(history.discard_latest(), snap(1), "the save before the bad one")
	assert_eq(history.latest(), snap(1), "the discarded save is gone for good")
	assert_eq(history.discard_latest(), snap(0), "then the island start")
	assert_eq(history.discard_latest(), snap(0), "the start is always there")


func test_capacity_drops_oldest_but_keeps_initial() -> void:
	var history := CheckpointHistory.new()
	history.set_initial(snap(0))
	for i in range(1, 6):
		history.push(snap(i))
	assert_eq(history.save_count(), CheckpointHistory.CAPACITY)
	assert_eq(history.latest(), snap(5))
	history.discard_latest()
	history.discard_latest()
	assert_eq(history.latest(), snap(3))
	assert_eq(history.discard_latest(), snap(0), "oldest saves dropped, start kept")


func test_reset_to_initial() -> void:
	var history := CheckpointHistory.new()
	history.set_initial(snap(0))
	history.push(snap(1))
	assert_eq(history.reset_to_initial(), snap(0))
	assert_eq(history.save_count(), 0)


func make_ledger() -> RuleLedger:
	var ledger := RuleLedger.new()
	for action: RuleAction.Kind in RuleAction.ALL:
		ledger.give_player_item(action, false, int(action))
	return ledger


func test_policy_allows_a_normal_save() -> void:
	assert_eq(CheckpointPolicy.save_blockers(make_ledger(), true, 0).size(), 0)


func test_policy_refuses_mid_air_and_falling_blocks() -> void:
	var blockers := CheckpointPolicy.save_blockers(make_ledger(), false, 2)
	assert_true(blockers.has(CheckpointPolicy.Blocker.AIRBORNE))
	assert_true(blockers.has(CheckpointPolicy.Blocker.FALLING_BLOCK))


func test_policy_refuses_when_player_cannot_walk_at_all() -> void:
	var ledger := make_ledger()
	for action: RuleAction.Kind in CheckpointPolicy.MOVE_ACTIONS:
		ledger.move_to_inventory(ledger.hotbar_vessel(int(action)).id)
	var blockers := CheckpointPolicy.save_blockers(ledger, true, 0)
	assert_eq(blockers, [CheckpointPolicy.Blocker.CANNOT_MOVE] as Array[CheckpointPolicy.Blocker])
	ledger.move_to_hotbar(ledger.inventory_vessels()[0].id, 0)
	assert_eq(CheckpointPolicy.save_blockers(ledger, true, 0).size(), 0, "one direction is enough")


func test_policy_counts_prohibited_directions_as_unusable() -> void:
	var ledger := make_ledger()
	for action: RuleAction.Kind in CheckpointPolicy.MOVE_ACTIONS:
		ledger.give_player_item(action, true)
	assert_false(CheckpointPolicy.player_can_move(ledger))


func test_every_blocker_has_a_message() -> void:
	for b: int in CheckpointPolicy.Blocker.values():
		assert_ne(CheckpointPolicy.describe(b as CheckpointPolicy.Blocker), "?")
