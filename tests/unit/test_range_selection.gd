extends TestCase
## 範囲付与: 水平円・1層のみ・ブロックだけ・トークンは1つ（企画書 5.3、受け入れテスト 2, 3）。

const JUMP := RuleAction.Kind.JUMP


func test_selects_only_same_layer_inside_circle() -> void:
	var candidates := {
		1 + 10: Vector3i(0, 1, 0),
		2 + 10: Vector3i(4, 1, 0),  # 中心から4ブロック → 内側
		3 + 10: Vector3i(5, 1, 0),  # 5ブロック → 境界上で内側
		4 + 10: Vector3i(6, 1, 0),  # 6ブロック → 外側
		5 + 10: Vector3i(0, 2, 0),  # 上の層
		6 + 10: Vector3i(0, 0, 0),  # 下の層
		7 + 10: Vector3i(4, 1, 4),  # 斜め約5.66 → 外側
	}
	var center := Vector3(0.5, 1.0, 0.5)
	var selected := BlockRules.select_in_range(center, 5.0, 1, candidates)
	assert_eq(selected, PackedInt32Array([11, 12, 13]))


func test_range_lend_shares_one_token_and_respects_individual_ban() -> void:
	var ledger := RuleLedger.new()
	for id: int in [10, 11, 12]:
		ledger.register_entity(id, EntityKind.Kind.BLOCK)
	ledger.place_on_entity(JUMP, true, 11)  # 中央だけジャンプ禁止
	var jump := ledger.give_player_item(JUMP, false, 0)
	var spec := {"center": Vector3(1.5, 0, 0.5), "radius": 5.0, "layer": 0}
	var result := ledger.lend(
		jump.id, PackedInt32Array([10, 11, 12]), TriggerMode.Kind.SINGLE_SHOT, spec
	)
	assert_eq(result, RuleLedger.LendResult.OK)
	var attempts: Array[BlockRules.Attempt] = []
	for id: int in [10, 11, 12]:
		attempts.append(BlockRules.attempt(ledger, id, JUMP, true))
	assert_eq(
		attempts,
		(
			[BlockRules.Attempt.SUCCESS, BlockRules.Attempt.PROHIBITED, BlockRules.Attempt.SUCCESS]
			as Array[BlockRules.Attempt]
		),
		"left and right jump, middle does not"
	)
	assert_eq(ledger.pending_single_shots(JUMP).size(), 1, "one token, not three")
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))


func test_range_rejects_creatures_and_prohibitions() -> void:
	var ledger := RuleLedger.new()
	ledger.register_entity(10, EntityKind.Kind.BLOCK)
	ledger.register_entity(20, EntityKind.Kind.CREATURE)
	var jump := ledger.give_player_item(JUMP, false, 0)
	var ban := ledger.give_player_item(JUMP, true, 1)
	var spec := {"center": Vector3.ZERO, "radius": 5.0, "layer": 0}
	assert_eq(
		ledger.lend(jump.id, PackedInt32Array([10, 20]), TriggerMode.Kind.REPEAT, spec),
		RuleLedger.LendResult.RANGE_ONLY_FOR_BLOCKS
	)
	assert_eq(
		ledger.lend(ban.id, PackedInt32Array([10]), TriggerMode.Kind.NONE, spec),
		RuleLedger.LendResult.RANGE_PROHIBITION_UNSUPPORTED
	)


func test_range_recall_from_anywhere_inside() -> void:
	var ledger := RuleLedger.new()
	for id: int in [10, 11]:
		ledger.register_entity(id, EntityKind.Kind.BLOCK)
	var jump := ledger.give_player_item(JUMP, false, 0)
	var spec := {"center": Vector3(0, 0, 0), "radius": 5.0, "layer": 0}
	ledger.lend(jump.id, PackedInt32Array([10, 11]), TriggerMode.Kind.REPEAT, spec)
	assert_eq(ledger.range_tokens_at(Vector3(4.0, 1.0, 0.0)).size(), 1, "inside")
	assert_eq(ledger.range_tokens_at(Vector3(6.0, 1.0, 0.0)).size(), 0, "outside")
	var token_id := ledger.range_tokens_at(Vector3(3.0, 1.0, 3.0))[0].id
	assert_true(ledger.recall(token_id))
	assert_false(ledger.can_initiate(10, JUMP))
	assert_false(ledger.can_initiate(11, JUMP))
	assert_true(ledger.player_can(JUMP))
