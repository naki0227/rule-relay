extends TestCase
## 単発・繰り返しと入力の宛先（企画書 5.2、受け入れテスト 4）。

const JUMP := RuleAction.Kind.JUMP
const FORWARD := RuleAction.Kind.FORWARD
const BACK := RuleAction.Kind.BACK
const SUCCESS := BlockRules.Attempt.SUCCESS
const PROHIBITED := BlockRules.Attempt.PROHIBITED
const NOT_READY := BlockRules.Attempt.NOT_READY
const BLOCK := 10

var ledger: RuleLedger
var jump_vessel: RuleVessel


func before_each() -> void:
	ledger = RuleLedger.new()
	ledger.register_entity(BLOCK, EntityKind.Kind.BLOCK)
	jump_vessel = ledger.give_player_item(JUMP, false, 4)


func test_space_jumps_player_when_ability_is_home() -> void:
	var route := InputRouter.route_press(ledger, JUMP)
	assert_true(route.player_acts)
	assert_eq(route.single_shot_token_ids.size(), 0)


func test_space_triggers_lent_single_shot_not_player() -> void:
	ledger.lend(jump_vessel.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.SINGLE_SHOT)
	var route := InputRouter.route_press(ledger, JUMP)
	assert_false(route.player_acts)
	assert_eq(route.single_shot_token_ids, PackedInt32Array([jump_vessel.token_id]))


func test_single_shot_is_not_triggered_by_other_keys() -> void:
	ledger.lend(jump_vessel.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.SINGLE_SHOT)
	assert_eq(InputRouter.route_press(ledger, FORWARD).single_shot_token_ids.size(), 0)


func test_repeat_is_not_triggered_by_key() -> void:
	ledger.lend(jump_vessel.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.REPEAT)
	var route := InputRouter.route_press(ledger, JUMP)
	assert_false(route.player_acts)
	assert_eq(route.single_shot_token_ids.size(), 0)


func test_single_shot_returns_after_one_try_even_when_it_failed() -> void:
	var token_id := jump_vessel.token_id
	ledger.lend(jump_vessel.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.SINGLE_SHOT)
	var ok: Array[BlockRules.Attempt] = [SUCCESS]
	assert_true(ledger.complete_single_shot(token_id, ok))
	assert_true(ledger.player_can(JUMP), "auto-returned to the vessel")
	assert_false(ledger.can_initiate(BLOCK, JUMP))
	# 発動できなかったときも、発動したのと同じ扱いで戻る（2026-11-19 本人の判断）
	for failure: BlockRules.Attempt in [NOT_READY, BlockRules.Attempt.PROHIBITED]:
		ledger.lend(jump_vessel.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.SINGLE_SHOT)
		var failed: Array[BlockRules.Attempt] = [failure]
		assert_true(ledger.complete_single_shot(token_id, failed), "returned like a firing")
		assert_true(ledger.player_can(JUMP))


func test_repeat_never_auto_returns() -> void:
	ledger.lend(jump_vessel.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.REPEAT)
	var ok: Array[BlockRules.Attempt] = [SUCCESS]
	assert_false(ledger.complete_single_shot(jump_vessel.token_id, ok))
	assert_true(ledger.can_initiate(BLOCK, JUMP))


func test_success_check_for_messages() -> void:
	var results: Array[BlockRules.Attempt] = [SUCCESS, PROHIBITED, SUCCESS]
	assert_true(BlockRules.single_shot_succeeded(results))
	var all_blocked: Array[BlockRules.Attempt] = [PROHIBITED, PROHIBITED]
	assert_false(BlockRules.single_shot_succeeded(all_blocked))
	var empty: Array[BlockRules.Attempt] = []
	assert_false(BlockRules.single_shot_succeeded(empty))


func test_attempt_checks_prohibition_before_ability_and_physics() -> void:
	assert_eq(BlockRules.attempt(ledger, BLOCK, JUMP, true), BlockRules.Attempt.NO_ABILITY)
	ledger.lend(jump_vessel.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.REPEAT)
	assert_eq(BlockRules.attempt(ledger, BLOCK, JUMP, false), NOT_READY)
	assert_eq(BlockRules.attempt(ledger, BLOCK, JUMP, true), SUCCESS)
	ledger.place_on_entity(JUMP, true, BLOCK)
	assert_eq(BlockRules.attempt(ledger, BLOCK, JUMP, true), PROHIBITED)
	assert_eq(BlockRules.attempt(ledger, BLOCK, JUMP, false), PROHIBITED)


func test_repeat_alternates_and_skips_prohibited_turn() -> void:
	var w := ledger.give_player_item(FORWARD, false, 0)
	var s := ledger.give_player_item(BACK, false, 1)
	ledger.lend(w.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.REPEAT)
	ledger.lend(s.id, PackedInt32Array([BLOCK]), TriggerMode.Kind.REPEAT)
	ledger.place_on_entity(FORWARD, true, BLOCK)
	var cursor := RepeatCursor.new()
	var outcomes: Array[String] = []
	for i in 4:
		var action := cursor.next_action(ledger.repeat_actions(BLOCK)) as RuleAction.Kind
		var result := BlockRules.attempt(ledger, BLOCK, action, true)
		outcomes.append("%s:%s" % [RuleAction.label(action), result == SUCCESS])
	assert_eq(outcomes, ["W:false", "S:true", "W:false", "S:true"] as Array[String])


func test_repeat_cursor_empty() -> void:
	var cursor := RepeatCursor.new()
	var none: Array[RuleAction.Kind] = []
	assert_eq(cursor.next_action(none), -1)
