extends TestCase
## 部屋の参加者の対応表。peer ID が変わっても session_key で同じプレイヤーに戻る。

var ledger: RuleLedger
var roster: PartyRoster


func before_each() -> void:
	ledger = RuleLedger.new()
	roster = PartyRoster.new()
	roster.add_host("host", 1)


func test_new_players_get_ids_and_are_registered() -> void:
	assert_eq(roster.join(ledger, "bob", 100), 2)
	assert_eq(roster.join(ledger, "cat", 101), 3)
	assert_eq(ledger.players(), PackedInt32Array([1, 2, 3]))
	assert_eq(roster.player_of_peer(100), 2)


func test_reconnect_with_same_key_keeps_the_player_id() -> void:
	roster.join(ledger, "bob", 100)
	roster.disconnect_peer(100)
	assert_false(roster.is_connected_player(2))
	assert_true(ledger.players().has(2), "disconnect does not change the ledger")
	assert_eq(roster.join(ledger, "bob", 205), 2, "same player, new peer id")
	assert_eq(roster.player_of_peer(205), 2)
	assert_eq(roster.player_of_peer(100), -1)


func test_rejoin_after_leaving_marks_present_again() -> void:
	roster.join(ledger, "bob", 100)
	ledger.set_player_present(2, false)
	assert_eq(roster.join(ledger, "bob", 101), 2)
	assert_true(ledger.players().has(2))


func test_room_is_full_at_four() -> void:
	assert_eq(roster.join(ledger, "b", 100), 2)
	assert_eq(roster.join(ledger, "c", 101), 3)
	assert_eq(roster.join(ledger, "d", 102), 4)
	assert_eq(roster.join(ledger, "e", 103), -1, "fifth player is refused")
	assert_eq(roster.join(ledger, "", 104), -1, "empty key is refused")


func test_nobody_can_join_as_the_host() -> void:
	assert_eq(roster.join(ledger, "host", 300), -1)
	assert_eq(roster.player_of_peer(1), RuleLedger.PLAYER_ID, "host mapping is untouched")
