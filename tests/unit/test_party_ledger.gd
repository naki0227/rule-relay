extends TestCase
## 複数プレイヤーの能力の受け渡し・重ね合わせ・回収・単発返還（2026-11-20 引き継ぎ仕様 9 の 2〜9）。
## ルール層だけを検査する。ネットワーク・物理の倍率（ジャンプ×4 の高さなど）はまだ扱わない。

const JUMP := RuleAction.Kind.JUMP
const FORWARD := RuleAction.Kind.FORWARD
const THROW := RuleAction.Kind.THROW
const SINGLE := TriggerMode.Kind.SINGLE_SHOT
const REPEAT := TriggerMode.Kind.REPEAT
const OK := RuleLedger.LendResult.OK
const A := RuleLedger.PLAYER_ID
const B := 2
const C := 3
const D := 4
const BLOCK := 10
const CREATURE := 20
const SUCCESS: Array[BlockRules.Attempt] = [BlockRules.Attempt.SUCCESS]
const BLOCKED: Array[BlockRules.Attempt] = [BlockRules.Attempt.NOT_READY]

var ledger: RuleLedger
## プレイヤー → ホットバー 0 のジャンプの器
var jumps: Dictionary[int, RuleVessel] = {}


func before_each() -> void:
	ledger = RuleLedger.new()
	for p: int in [B, C, D]:
		ledger.register_player(p)
	ledger.register_entity(BLOCK, EntityKind.Kind.BLOCK)
	ledger.register_entity(CREATURE, EntityKind.Kind.CREATURE)
	jumps.clear()
	for p: int in [A, B, C, D]:
		jumps[p] = ledger.give_player_item(JUMP, false, 0, p)


func _jump_token(p: int) -> int:
	return jumps[p].token_id


func _valid() -> void:
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))


# --- 2. 2人で直接渡す ---------------------------------------------------------


func test_give_moves_ability_without_approval() -> void:
	assert_eq(ledger.give_to_player(_jump_token(A), A, B), OK)
	assert_false(ledger.player_can(JUMP, A), "A cannot jump after giving")
	assert_eq(ledger.ability_count(JUMP, B), 2, "B has jump x2")
	assert_true(ledger.player_can(JUMP, B))
	_valid()


func test_receiver_can_pass_it_on_to_player_and_block() -> void:
	ledger.give_to_player(_jump_token(A), A, B)
	assert_eq(ledger.give_to_player(_jump_token(A), B, C), OK, "B passes A's jump to C")
	assert_eq(ledger.ability_count(JUMP, C), 2)
	assert_eq(ledger.ability_count(JUMP, B), 1)
	var lent := ledger.lend_token(_jump_token(A), C, PackedInt32Array([BLOCK]), REPEAT)
	assert_eq(lent, OK, "C lends the received jump to a block")
	assert_true(ledger.can_initiate(BLOCK, JUMP))
	assert_eq(ledger.ability_count(JUMP, C), 1)
	_valid()


# --- 3. 4人分を1人に集める ------------------------------------------------------


func test_four_jumps_stack_on_one_player() -> void:
	for p: int in [A, C, D]:
		assert_eq(ledger.give_to_player(_jump_token(p), p, B), OK)
	assert_eq(ledger.ability_count(JUMP, B), 4, "B has jump x4")
	for p: int in [A, C, D]:
		assert_eq(ledger.ability_count(JUMP, p), 0, "empty vessels do not count")
	_valid()


func test_forward_and_throw_stack_separately() -> void:
	for p: int in [A, B, C, D]:
		ledger.give_player_item(FORWARD, false, 1, p)
		ledger.give_player_item(THROW, false, 2, p)
	for p: int in [A, C, D]:
		ledger.give_to_player(ledger.hotbar_vessel(1, p).token_id, p, B)
	assert_eq(ledger.ability_count(FORWARD, B), 4, "W x4")
	assert_eq(ledger.ability_count(THROW, B), 1, "throw is counted separately")
	ledger.give_to_player(ledger.hotbar_vessel(2, A).token_id, A, B)
	assert_eq(ledger.ability_count(THROW, B), 2)
	_valid()


func test_stacking_does_not_override_prohibition() -> void:
	for p: int in [A, C, D]:
		ledger.give_to_player(_jump_token(p), p, B)
	ledger.give_player_item(JUMP, true, -1, B)
	assert_eq(ledger.ability_count(JUMP, B), 4)
	assert_false(ledger.player_can(JUMP, B), "prohibition wins over jump x4")


# --- 4. 器は残り、トークンは1つ -------------------------------------------------


func test_vessel_stays_with_its_owner() -> void:
	ledger.give_to_player(_jump_token(A), A, B)
	assert_eq(ledger.hotbar_vessel(0, A), jumps[A], "A keeps the empty vessel in its slot")
	assert_eq(ledger.hotbar_vessel(0, B), jumps[B])
	assert_eq(PartyQuery.carried_tokens(ledger, B).size(), 1)
	assert_eq(PartyQuery.origin_owner(ledger, _jump_token(A)), A, "origin stays A")
	var again := ledger.give_to_player(_jump_token(A), A, C)
	assert_eq(again, RuleLedger.LendResult.ALREADY_LENT, "A cannot give it twice")
	var lend := ledger.lend(jumps[A].id, PackedInt32Array([BLOCK]), SINGLE)
	assert_eq(lend, RuleLedger.LendResult.ALREADY_LENT, "empty vessel cannot lend")
	assert_false(ledger.can_initiate(BLOCK, JUMP), "no duplicate token")
	_valid()


func test_cannot_give_what_you_do_not_hold() -> void:
	var result := ledger.give_to_player(_jump_token(A), B, C)
	assert_eq(result, RuleLedger.LendResult.NOT_HELD, "B cannot give A's vessel")
	assert_eq(ledger.give_to_player(_jump_token(A), A, A), RuleLedger.LendResult.UNKNOWN_TARGET)
	assert_eq(ledger.give_to_player(_jump_token(A), A, BLOCK), RuleLedger.LendResult.UNKNOWN_TARGET)
	var stored := ledger.give_player_item(FORWARD, false, -1, A)
	var from_inventory := ledger.give_to_player(stored.token_id, A, B)
	assert_eq(from_inventory, RuleLedger.LendResult.NOT_IN_HOTBAR)
	var ban := ledger.give_player_item(FORWARD, true, 3, A)
	var ban_result := ledger.give_to_player(ban.token_id, A, B)
	assert_eq(ban_result, RuleLedger.LendResult.PROHIBITION_TO_PLAYER, "undecided: not allowed")


func test_lend_still_refuses_player_targets() -> void:
	var result := ledger.lend(jumps[A].id, PackedInt32Array([B]), SINGLE)
	assert_eq(result, RuleLedger.LendResult.CANNOT_TARGET_PLAYER, "players use give_to_player")


func test_range_lend_of_received_token_is_for_blocks() -> void:
	ledger.give_to_player(_jump_token(A), A, B)
	var spec := {"center": Vector3.ZERO, "radius": 2.0, "layer": 0}
	var targets := PackedInt32Array([BLOCK, CREATURE])
	var result := ledger.lend_token(_jump_token(A), B, targets, SINGLE, spec)
	assert_eq(result, RuleLedger.LendResult.RANGE_ONLY_FOR_BLOCKS)


# --- 5. F で回収した人が受け取る -----------------------------------------------


func test_recall_goes_to_the_player_who_pressed_f() -> void:
	ledger.lend(jumps[A].id, PackedInt32Array([BLOCK]), REPEAT)
	var recalled := ledger.recall_from_entity(BLOCK, B)
	assert_eq(recalled.size(), 1)
	assert_eq(ledger.ability_count(JUMP, B), 2, "B receives it")
	assert_false(ledger.player_can(JUMP, A), "not returned to A")
	_valid()


func test_owner_recalling_puts_it_back_in_the_vessel() -> void:
	ledger.lend(jumps[A].id, PackedInt32Array([BLOCK]), REPEAT)
	ledger.recall_from_entity(BLOCK, A)
	assert_true(ledger.token(_jump_token(A)).is_in_vessel())
	assert_true(ledger.player_can(JUMP, A))


func test_recalled_placed_token_gets_a_vessel_for_the_recaller() -> void:
	var placed := ledger.place_on_entity(FORWARD, false, BLOCK, REPEAT)
	ledger.recall(placed.id, C)
	var v := ledger.vessel(placed.vessel_id)
	assert_eq(v.owner_id, C)
	assert_eq(ledger.inventory_vessels(C).size(), 1)
	assert_eq(ledger.inventory_vessels(C)[0], v)
	assert_eq(ledger.inventory_vessels(A).size(), 0)
	_valid()


# --- 6. 単発は直前の付与者へ戻る -------------------------------------------------


func test_single_shot_returns_to_last_lender() -> void:
	ledger.give_to_player(_jump_token(A), A, B)
	ledger.lend_token(_jump_token(A), B, PackedInt32Array([BLOCK]), SINGLE)
	assert_eq(ledger.pending_single_shots(JUMP, B).size(), 1, "B's key fires it")
	assert_eq(ledger.pending_single_shots(JUMP, A).size(), 0, "A's key does not")
	assert_true(ledger.complete_single_shot(_jump_token(A), SUCCESS))
	assert_eq(ledger.ability_count(JUMP, B), 2, "returned to B, not to A")
	assert_eq(ledger.ability_count(JUMP, A), 0)
	_valid()


func test_four_bundled_single_shots_all_return_to_lender() -> void:
	for p: int in [A, C, D]:
		ledger.give_to_player(_jump_token(p), p, B)
	for p: int in [A, B, C, D]:
		ledger.lend_token(_jump_token(p), B, PackedInt32Array([BLOCK]), SINGLE)
	var shots := ledger.pending_single_shots(JUMP, B)
	assert_eq(shots.size(), 4)
	var ids := {}
	for t in shots:
		ids[t.id] = true
		ledger.complete_single_shot(t.id, SUCCESS)
	assert_eq(ids.size(), 4, "each token keeps its own id")
	assert_eq(ledger.ability_count(JUMP, B), 4)
	assert_true(
		ledger.token(_jump_token(B)).is_in_vessel(), "B's own token goes back to its vessel"
	)
	_valid()


func test_failed_single_shot_also_returns_to_lender() -> void:
	ledger.give_to_player(_jump_token(A), A, B)
	ledger.lend_token(_jump_token(A), B, PackedInt32Array([BLOCK]), SINGLE)
	assert_true(ledger.complete_single_shot(_jump_token(A), BLOCKED))
	assert_eq(ledger.ability_count(JUMP, B), 2)


func test_single_key_routes_per_player() -> void:
	ledger.lend(jumps[C].id, PackedInt32Array([BLOCK]), SINGLE)
	assert_eq(InputRouter.route_press(ledger, JUMP, C).single_shot_token_ids.size(), 1)
	assert_eq(InputRouter.route_press(ledger, JUMP, A).single_shot_token_ids.size(), 0)


# --- 7. 退出しても付与は残る ---------------------------------------------------


func test_lent_ability_survives_lender_leaving() -> void:
	ledger.lend(jumps[A].id, PackedInt32Array([BLOCK]), REPEAT)
	ledger.set_player_present(A, false)
	assert_true(ledger.can_initiate(BLOCK, JUMP), "still on the block")
	ledger.recall_from_entity(BLOCK, B)
	assert_eq(ledger.ability_count(JUMP, B), 2, "B can recall it")
	assert_eq(PartyQuery.origin_owner(ledger, _jump_token(A)), A, "origin is kept")
	assert_false(ledger.players().has(A))
	_valid()


func test_absent_player_cannot_give_or_lend() -> void:
	ledger.set_player_present(C, false)
	assert_eq(ledger.give_to_player(_jump_token(C), C, B), RuleLedger.LendResult.NOT_HELD)
	assert_eq(ledger.give_to_player(_jump_token(B), B, C), RuleLedger.LendResult.UNKNOWN_TARGET)


# --- 8. 付与者が退出していたら単発成功で落ちる -------------------------------------


func test_single_shot_drops_when_lender_left() -> void:
	ledger.lend(jumps[A].id, PackedInt32Array([BLOCK]), SINGLE)
	ledger.set_player_present(A, false)
	var where := Vector3(1, 2, 3)
	assert_true(ledger.complete_single_shot(_jump_token(A), SUCCESS, where))
	var dropped := PartyQuery.dropped_tokens(ledger)
	assert_eq(dropped.size(), 1)
	assert_eq(dropped[0].drop_position, where)
	assert_false(ledger.can_initiate(BLOCK, JUMP))
	_valid()
	assert_true(ledger.pickup_token(_jump_token(A), B))
	assert_eq(ledger.ability_count(JUMP, B), 2, "B picks up the same token")
	assert_eq(PartyQuery.dropped_tokens(ledger).size(), 0)
	assert_false(ledger.pickup_token(_jump_token(A), C), "cannot pick up twice")
	_valid()


func test_failed_single_shot_stays_on_block_when_lender_left() -> void:
	# 未決（引き継ぎ仕様 7-6）: 落とさず、ブロックに残す。F で回収はできる
	ledger.lend(jumps[A].id, PackedInt32Array([BLOCK]), SINGLE)
	ledger.set_player_present(A, false)
	assert_false(ledger.complete_single_shot(_jump_token(A), BLOCKED))
	assert_true(ledger.can_initiate(BLOCK, JUMP))
	assert_eq(PartyQuery.dropped_tokens(ledger).size(), 0)
	_valid()


func test_rejoined_lender_gets_the_return() -> void:
	ledger.lend(jumps[A].id, PackedInt32Array([BLOCK]), SINGLE)
	ledger.set_player_present(A, false)
	ledger.set_player_present(A, true)
	ledger.complete_single_shot(_jump_token(A), SUCCESS)
	assert_true(ledger.player_can(JUMP, A))


# --- 9. 循環譲渡 -------------------------------------------------------------


func test_circular_giving_keeps_origins() -> void:
	assert_eq(ledger.give_to_player(_jump_token(A), A, B), OK)
	assert_eq(ledger.give_to_player(_jump_token(B), B, C), OK)
	assert_eq(ledger.give_to_player(_jump_token(C), C, A), OK)
	for p: int in [A, B, C]:
		assert_eq(ledger.ability_count(JUMP, p), 1, "everyone still has one")
	assert_eq(PartyQuery.origin_owner(ledger, _jump_token(A)), A)
	assert_eq(PartyQuery.origin_owner(ledger, _jump_token(B)), B)
	assert_eq(PartyQuery.origin_owner(ledger, _jump_token(C)), C)
	assert_eq(ledger.token(_jump_token(C)).carrier_id, A, "C's jump is carried by A")
	assert_false(ledger.token(_jump_token(A)).is_in_vessel(), "no re-basing to the holder")
	_valid()


func test_giving_back_to_origin_refills_the_vessel() -> void:
	ledger.give_to_player(_jump_token(A), A, B)
	ledger.give_to_player(_jump_token(A), B, A)
	assert_true(ledger.token(_jump_token(A)).is_in_vessel())
	assert_eq(ledger.ability_count(JUMP, A), 1)
	_valid()


# --- 保存と復元 ----------------------------------------------------------------


func test_snapshot_restores_carriers_drops_and_presence() -> void:
	ledger.give_to_player(_jump_token(A), A, B)
	ledger.lend(jumps[C].id, PackedInt32Array([BLOCK]), SINGLE)
	ledger.set_player_present(C, false)
	ledger.complete_single_shot(_jump_token(C), SUCCESS, Vector3.ONE)
	var saved := ledger.snapshot()
	ledger.give_to_player(_jump_token(A), B, D)
	ledger.pickup_token(_jump_token(C), D)
	ledger.set_player_present(C, true)
	ledger.restore(saved)
	assert_eq(ledger.token(_jump_token(A)).carrier_id, B)
	assert_true(ledger.token(_jump_token(C)).dropped)
	assert_false(ledger.players().has(C))
	assert_eq(ledger.ability_count(JUMP, B), 2)
	_valid()
