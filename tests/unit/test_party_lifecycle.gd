extends TestCase
## 死亡観戦・共通チェックポイント・全員復活・全員リセット投票・途中参加（2026-11-20 引き継ぎ仕様 4、
## 受け入れ候補 10〜15 のルール層）。世界の復元そのものは呼び出し側の責務なので、
## ここでは「台帳を動かさないこと」と「戻す指示（PartyResetDecision）の中身」を検査する。

const ACTIVE := PartyLifecycle.State.ACTIVE
const DEAD := PartyLifecycle.State.DEAD_SPECTATING
const WAITING := PartyLifecycle.State.WAITING_SPECTATOR
const DISCONNECTED := PartyLifecycle.State.DISCONNECTED
const MAJORITY := PartyResetDecision.Reason.MAJORITY
const SURVIVORS := PartyResetDecision.Reason.SURVIVORS_AGREED
const NO_ONE_ALIVE := PartyResetDecision.Reason.NO_ONE_ALIVE
const JUMP := RuleAction.Kind.JUMP
const FORWARD := RuleAction.Kind.FORWARD
const REPEAT := TriggerMode.Kind.REPEAT
const OK := RuleLedger.LendResult.OK
const A := RuleLedger.PLAYER_ID
const B := 2
const C := 3
const D := 4
const BLOCK := 10

var party: PartyLifecycle


func before_each() -> void:
	party = PartyLifecycle.new()


func _start(count: int) -> void:
	var ids := PackedInt32Array()
	for i: int in count:
		ids.append(A + i)
	party.start_stage(ids)


func _ids(values: Array[int]) -> PackedInt32Array:
	return PackedInt32Array(values)


# --- 11. 死亡: 貸与も手持ちも台帳はそのまま ---------------------------------------


func test_death_keeps_ledger_unchanged_and_spectates() -> void:
	var ledger := RuleLedger.new()
	ledger.register_player(B)
	ledger.register_entity(BLOCK, EntityKind.Kind.BLOCK)
	var to_b := ledger.give_player_item(JUMP, false, 0, A)
	var to_block := ledger.give_player_item(JUMP, false, 1, A)
	ledger.give_player_item(FORWARD, false, 2, A)
	assert_eq(ledger.give_to_player(to_b.token_id, A, B), OK)
	assert_eq(ledger.lend_token(to_block.token_id, A, _ids([BLOCK]), REPEAT), OK)
	var before := var_to_str(ledger.snapshot())
	_start(2)
	assert_true(party.die(A))
	assert_eq(party.state_of(A), DEAD)
	assert_eq(var_to_str(ledger.snapshot()), before, "death does not touch the ledger")
	assert_eq(ledger.ability_count(JUMP, B), 1, "jump lent to B stays with B")
	assert_true(ledger.can_initiate(BLOCK, JUMP), "jump lent to the block stays")
	assert_true(ledger.player_can(FORWARD, A), "A keeps what A was holding")
	assert_false(party.has_pending_reset(), "B is alive: no reset")


func test_only_active_players_can_die() -> void:
	_start(2)
	party.die(A)
	assert_false(party.die(A), "already dead")
	party.join(C)
	assert_false(party.die(C), "waiting spectator is not playing")


# --- 12. 共通チェックポイントと全員復活 ----------------------------------------------


func test_one_arrival_activates_shared_checkpoint() -> void:
	_start(4)
	assert_eq(party.latest_checkpoint(), PartyLifecycle.STAGE_START)
	assert_true(party.activate_checkpoint(C, "cp1"), "no majority needed; capture now")
	assert_eq(party.latest_checkpoint(), "cp1")
	assert_true(party.activate_checkpoint(A, "cp2"))
	assert_eq(party.activated_checkpoints(), PackedStringArray(["cp1", "cp2"]))


func test_reaching_activated_checkpoint_again_does_not_capture() -> void:
	_start(2)
	party.activate_checkpoint(A, "cp1")
	party.activate_checkpoint(A, "cp2")
	assert_false(party.activate_checkpoint(B, "cp1"), "no second snapshot")
	assert_eq(party.latest_checkpoint(), "cp2", "latest stays the newest activation")
	assert_eq(party.activated_checkpoints().size(), 2)


func test_dead_or_waiting_cannot_activate_checkpoint() -> void:
	_start(2)
	party.die(B)
	party.join(C)
	assert_false(party.activate_checkpoint(B, "cp1"))
	assert_false(party.activate_checkpoint(C, "cp1"))
	assert_false(party.activate_checkpoint(A, PartyLifecycle.STAGE_START))
	assert_eq(party.latest_checkpoint(), PartyLifecycle.STAGE_START)


func test_revive_all_revives_only_the_dead_and_keeps_world() -> void:
	var ledger := RuleLedger.new()
	ledger.register_player(B)
	ledger.register_player(C)
	var jump := ledger.give_player_item(JUMP, false, 0, A)
	ledger.give_to_player(jump.token_id, A, B)
	var before := var_to_str(ledger.snapshot())
	_start(3)
	party.activate_checkpoint(C, "cp1")
	party.die(A)
	party.die(B)
	assert_eq(party.revive_all(C, "cp1"), _ids([A, B]))
	assert_eq(party.players_in(ACTIVE), _ids([A, B, C]))
	assert_eq(var_to_str(ledger.snapshot()), before, "revive does not restore tokens")
	assert_false(party.has_pending_reset(), "revive is not a full reset")
	assert_eq(party.reset_count(), 0)


func test_revive_needs_alive_player_at_activated_checkpoint() -> void:
	_start(2)
	party.die(B)
	assert_eq(party.revive_all(A, "cp1").size(), 0, "cp1 is not activated")
	party.activate_checkpoint(A, "cp1")
	assert_eq(party.revive_all(B, "cp1").size(), 0, "the dead cannot revive themselves")
	assert_eq(party.revive_all(A, "cp1"), _ids([B]))


func test_revive_at_older_checkpoint_is_provisional_flag() -> void:
	_start(2)
	party.activate_checkpoint(A, "cp1")
	party.activate_checkpoint(A, "cp2")
	party.die(B)
	assert_true(party.can_revive_at(A, "cp1"), "仮 7-2: older checkpoints allowed")
	party.revive_at_older_checkpoints = false
	assert_false(party.can_revive_at(A, "cp1"))
	assert_true(party.can_revive_at(A, "cp2"))


# --- 13. 全員リセット票 -------------------------------------------------------------


func test_majority_table() -> void:
	assert_eq(PartyLifecycle.majority_of(1), 1)
	assert_eq(PartyLifecycle.majority_of(2), 2)
	assert_eq(PartyLifecycle.majority_of(3), 2)
	assert_eq(PartyLifecycle.majority_of(4), 3)


func test_vote_passes_exactly_at_majority() -> void:
	var needed: Dictionary[int, int] = {1: 1, 2: 2, 3: 2, 4: 3}
	for count: int in needed:
		party = PartyLifecycle.new()
		_start(count)
		party.activate_checkpoint(A, "cp1")
		for i: int in needed[count] - 1:
			party.vote_reset(A + i)
			assert_false(party.has_pending_reset(), "%d/%d must not pass" % [i + 1, count])
		party.vote_reset(A + needed[count] - 1)
		var d := party.take_pending_reset()
		assert_true(d != null, "%d/%d passes" % [needed[count], count])
		if d == null:
			continue
		assert_eq(d.reason, MAJORITY)
		assert_eq(d.checkpoint_id, "cp1", "restore to one snapshot")
		assert_eq(d.active_player_ids.size(), count)


func test_waiting_spectators_are_not_counted() -> void:
	_start(3)
	party.join(D)
	assert_eq(party.eligible_voters(), _ids([A, B, C]))
	assert_eq(party.required_votes(), 2)
	assert_false(party.vote_reset(D), "waiting spectator cannot vote")
	party.vote_reset(A)
	assert_false(party.has_pending_reset())


func test_left_and_disconnected_are_not_counted() -> void:
	_start(4)
	party.leave(D)
	party.disconnect_player(C)
	assert_eq(party.eligible_voters(), _ids([A, B]))
	assert_eq(party.required_votes(), 2)
	assert_false(party.vote_reset(C))
	assert_false(party.vote_reset(D))


func test_duplicate_votes_count_once() -> void:
	_start(4)
	assert_true(party.vote_reset(A), "proposal")
	assert_true(party.vote_reset(A), "repeat is accepted but not counted")
	party.vote_reset(A)
	assert_eq(party.yes_vote_count(), 1)
	party.vote_reset(B)
	assert_false(party.has_pending_reset(), "2 of 4 is not enough")
	party.vote_reset(C)
	assert_true(party.has_pending_reset())


func test_withdraw_and_cancel_vote() -> void:
	_start(3)
	party.vote_reset(A)
	assert_true(party.is_vote_open())
	assert_true(party.withdraw_vote(A))
	assert_false(party.is_vote_open(), "no supporters left")
	party.vote_reset(A)
	party.cancel_vote()
	assert_eq(party.yes_vote_count(), 0)
	party.vote_reset(B)
	assert_false(party.has_pending_reset(), "cancelled vote is gone")


func test_leaving_voter_loses_vote_and_smaller_party_can_pass() -> void:
	_start(4)
	party.vote_reset(A)
	party.vote_reset(D)
	party.leave(D)
	assert_eq(party.yes_vote_count(), 1)
	party.vote_reset(B)
	assert_true(party.has_pending_reset(), "2 of 3 passes")


func test_full_reset_makes_everyone_active_and_clears_vote() -> void:
	_start(3)
	party.activate_checkpoint(A, "cp1")
	party.die(C)
	party.vote_reset(A)
	party.vote_reset(C)
	var d := party.take_pending_reset()
	assert_eq(d.reason, MAJORITY, "dead may vote (仮 7-3)")
	assert_eq(party.players_in(ACTIVE), _ids([A, B, C]))
	assert_false(party.is_vote_open())
	assert_eq(d.generation, 1)
	assert_eq(party.reset_count(), 1)
	assert_true(party.take_pending_reset() == null, "taken once")


# --- 14. 生存者合意による早期リセット ------------------------------------------------


func test_all_survivors_agree_resets_even_without_majority() -> void:
	_start(4)
	party.activate_checkpoint(A, "cp1")
	party.die(C)
	party.die(D)
	party.vote_reset(A)
	assert_false(party.has_pending_reset())
	party.vote_reset(B)
	var d := party.take_pending_reset()
	assert_true(d != null, "2 of 4 is not majority, but all survivors agreed")
	if d != null:
		assert_eq(d.reason, SURVIVORS)
		assert_eq(d.checkpoint_id, "cp1")


func test_last_survivor_alone_can_reset() -> void:
	_start(4)
	for p: int in [B, C, D]:
		party.die(p)
	party.vote_reset(A)
	var d := party.take_pending_reset()
	assert_true(d != null and d.reason == SURVIVORS)


func test_survivor_path_needs_dead_spectators_and_can_be_disabled() -> void:
	_start(2)
	party.vote_reset(A)
	assert_false(party.has_pending_reset(), "no dead: survivors path does not apply")
	party.cancel_vote()
	party.survivors_can_reset_early = false
	party.die(B)
	party.vote_reset(A)
	assert_false(party.has_pending_reset(), "1 of 2 without the survivors path")


func test_dead_can_vote_flag_changes_the_count() -> void:
	_start(4)
	party.survivors_can_reset_early = false
	party.dead_can_vote = false
	party.die(D)
	assert_eq(party.eligible_voters(), _ids([A, B, C]))
	party.vote_reset(D)
	assert_eq(party.yes_vote_count(), 0, "dead vote ignored")
	party.vote_reset(A)
	party.vote_reset(B)
	assert_true(party.has_pending_reset(), "2 of 3 alive")


# --- 全員死亡・ソロの死亡は自動で戻す ------------------------------------------------


func test_all_dead_resets_to_latest_checkpoint_automatically() -> void:
	_start(3)
	party.activate_checkpoint(A, "cp1")
	party.activate_checkpoint(B, "cp2")
	party.die(A)
	party.die(B)
	assert_false(party.has_pending_reset())
	party.die(C)
	var d := party.take_pending_reset()
	assert_true(d != null)
	if d != null:
		assert_eq(d.reason, NO_ONE_ALIVE)
		assert_eq(d.checkpoint_id, "cp2")
	assert_eq(party.players_in(ACTIVE), _ids([A, B, C]))


func test_solo_death_never_leaves_permanent_spectate() -> void:
	_start(1)
	party.die(A)
	var d := party.take_pending_reset()
	assert_true(d != null)
	if d != null:
		assert_eq(d.checkpoint_id, PartyLifecycle.STAGE_START, "no checkpoint yet")
		assert_eq(d.reason, NO_ONE_ALIVE)
	assert_eq(party.state_of(A), ACTIVE)
	party.activate_checkpoint(A, "cp1")
	party.die(A)
	assert_eq(party.take_pending_reset().checkpoint_id, "cp1")


func test_last_alive_disconnecting_resets_the_dead() -> void:
	_start(2)
	party.die(B)
	party.disconnect_player(A)
	var d := party.take_pending_reset()
	assert_true(d != null, "no one left to play")
	assert_eq(party.state_of(B), ACTIVE)
	assert_true(party.reconnect(A))
	assert_eq(party.state_of(A), ACTIVE, "returns alive after the reset")


# --- 15. 途中入室と人数別補助（10 のフック） -----------------------------------------


func test_mid_stage_join_waits_and_joins_only_at_full_reset() -> void:
	_start(3)
	party.activate_checkpoint(A, "cp1")
	assert_true(party.join(D))
	assert_eq(party.state_of(D), WAITING)
	assert_false(party.has_pending_reset(), "joining does not rewind the game")
	assert_eq(party.headcount(), 3, "helpers do not change mid-stage")
	assert_false(party.reward_eligible_players().has(D))
	party.vote_reset(A)
	party.vote_reset(B)
	var d := party.take_pending_reset()
	assert_eq(d.joined_player_ids, _ids([D]))
	assert_eq(d.active_player_ids, _ids([A, B, C, D]))
	assert_eq(d.previous_headcount, 3)
	assert_eq(d.headcount, 4)
	assert_true(d.headcount_changed(), "rebuild helpers for 4")
	assert_eq(party.headcount(), 4)
	assert_true(party.reward_eligible_players().has(D))


func test_revive_does_not_change_headcount_or_join_waiting() -> void:
	_start(2)
	party.activate_checkpoint(A, "cp1")
	party.join(C)
	party.die(B)
	party.revive_all(A, "cp1")
	assert_eq(party.state_of(C), WAITING)
	assert_eq(party.headcount(), 2)


func test_only_waiting_left_joins_by_reset() -> void:
	_start(1)
	party.join(B)
	party.leave(A)
	var d := party.take_pending_reset()
	assert_true(d != null, "仮: waiting spectators are not stuck")
	if d != null:
		assert_eq(d.active_player_ids, _ids([B]))
		assert_eq(d.headcount, 1)
		assert_false(d.headcount_changed())


# --- 報酬資格・切断 ------------------------------------------------------------------


func test_reward_eligibility_truth_table() -> void:
	_start(4)
	party.die(B)
	party.disconnect_player(C)
	party.leave(D)
	party.join(5)
	assert_eq(party.reward_eligible_players(), _ids([A, B, C]))


func test_disconnect_keeps_death_and_is_distinct_from_leave() -> void:
	_start(3)
	party.die(B)
	party.disconnect_player(B)
	assert_eq(party.state_of(B), DISCONNECTED)
	assert_false(party.join(B), "reconnect, not a new join")
	assert_true(party.reconnect(B))
	assert_eq(party.state_of(B), DEAD)
	party.leave(B)
	assert_false(party.reconnect(B), "an explicit leave is not a disconnect")
	assert_true(party.join(B), "coming back after leaving means waiting")
	assert_eq(party.state_of(B), WAITING)


func test_waiting_spectator_disconnect_is_forgotten() -> void:
	_start(2)
	party.join(C)
	assert_true(party.disconnect_player(C))
	assert_false(party.has_player(C))
	assert_false(party.reward_eligible_players().has(C))


# --- 保存（ホスト移譲用） -------------------------------------------------------------


func test_serialization_round_trip() -> void:
	_start(4)
	party.activate_checkpoint(A, "cp1")
	party.activate_checkpoint(B, "cp2")
	party.die(B)
	party.disconnect_player(B)
	party.join(5)
	party.leave(D)
	party.vote_reset(A)
	var data := party.to_dict()
	var copy := PartyLifecycle.from_dict(str_to_var(var_to_str(data)) as Dictionary)
	assert_eq(var_to_str(copy.to_dict()), var_to_str(data))
	assert_eq(copy.state_of(B), DISCONNECTED)
	assert_true(copy.reconnect(B))
	assert_eq(copy.state_of(B), DEAD, "pre-disconnect state survives")
	assert_eq(copy.yes_vote_count(), 1, "open vote survives")
	copy.vote_reset(C)
	var d := copy.take_pending_reset()
	assert_true(d != null, "A and C are 2 of 3 (B dead, D left)")
	if d != null:
		assert_eq(d.checkpoint_id, "cp2")
		assert_eq(d.joined_player_ids, _ids([5]))


func test_serialization_keeps_pending_reset() -> void:
	_start(1)
	party.die(A)
	var copy := PartyLifecycle.from_dict(party.to_dict())
	var d := copy.take_pending_reset()
	assert_true(d != null)
	if d != null:
		assert_eq(d.generation, 1)
		assert_eq(d.reason, NO_ONE_ALIVE)
	assert_eq(copy.headcount(), 1)
