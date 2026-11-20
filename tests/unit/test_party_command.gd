extends TestCase
## ホストが参加者の依頼を検証して適用する（ホスト権威。docs/adr/0006）。通信なしで確かめる。

const JUMP := RuleAction.Kind.JUMP
const REPEAT := TriggerMode.Kind.REPEAT
const OK := PartyCommand.Result.OK
const INVALID := PartyCommand.Result.INVALID
const REFUSED := PartyCommand.Result.REFUSED
const A := RuleLedger.PLAYER_ID
const B := 2
const BLOCK := 10

var ledger: RuleLedger
var a_jump: RuleVessel
var b_jump: RuleVessel


func before_each() -> void:
	ledger = RuleLedger.new()
	ledger.register_player(B)
	ledger.register_entity(BLOCK, EntityKind.Kind.BLOCK)
	a_jump = ledger.give_player_item(JUMP, false, 0, A)
	b_jump = ledger.give_player_item(JUMP, false, 0, B)


func _result(player: int, command: Dictionary) -> int:
	return int(PartyCommand.apply(ledger, player, command)["result"])


func test_give_lend_recall_and_pickup() -> void:
	assert_eq(_result(B, PartyCommand.give(b_jump.token_id, A)), OK)
	assert_eq(ledger.ability_count(JUMP, A), 2)
	var lend := PartyCommand.lend(b_jump.token_id, PackedInt32Array([BLOCK]), REPEAT)
	assert_eq(_result(A, lend), OK)
	assert_eq(_result(B, PartyCommand.recall_entity(BLOCK)), OK, "B recalls with F")
	assert_eq(ledger.ability_count(JUMP, B), 1)
	assert_true(ledger.validate().is_empty(), str(ledger.validate()))


func test_identity_comes_from_the_sender_not_the_payload() -> void:
	# B が A の器のトークンを A へ渡す依頼を出しても、送り主は B なので「手元にない」で断られる
	var out := PartyCommand.apply(ledger, B, PartyCommand.give(a_jump.token_id, A))
	assert_eq(int(out["result"]), REFUSED)
	assert_eq(int(out["detail"]), RuleLedger.LendResult.NOT_HELD)
	assert_true(ledger.player_can(JUMP, A))


func test_malformed_commands_are_invalid() -> void:
	assert_eq(_result(B, {}), INVALID)
	assert_eq(_result(B, {"kind": 99}), INVALID)
	assert_eq(_result(B, {"kind": PartyCommand.Kind.GIVE, "token": "1", "to": A}), INVALID)
	var bad_targets := PartyCommand.lend(b_jump.token_id, PackedInt32Array([BLOCK]), REPEAT)
	bad_targets["targets"] = [BLOCK]
	assert_eq(_result(B, bad_targets), INVALID)
	var bad_range := PartyCommand.lend(b_jump.token_id, PackedInt32Array([BLOCK]), REPEAT)
	bad_range["range"] = {"center": "here"}
	assert_eq(_result(B, bad_range), INVALID)
	assert_eq(_result(7, PartyCommand.give(b_jump.token_id, A)), INVALID, "unknown player")
	assert_true(ledger.player_can(JUMP, B), "nothing changed")


func test_leave_marks_player_absent_but_host_cannot_leave() -> void:
	assert_eq(_result(A, PartyCommand.leave()), REFUSED, "host leaving is host migration (P5)")
	assert_eq(_result(B, PartyCommand.leave()), OK)
	assert_false(ledger.players().has(B))
	assert_eq(_result(B, PartyCommand.give(b_jump.token_id, A)), INVALID, "absent player")
