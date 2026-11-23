extends TestCase
## 4人（ホスト A＋参加者 B・C・D）の同時操作の競合（docs/requirements-status.md 22）。
## 参加者の操作は同じフレームに送る。ホストは届いた順に1つずつ台帳へ適用するので、勝つのは1人だけで、
## トークンは増えも減りもせず（validate が空）、全員の台帳の写しがホストの正本にそろうことを確かめる。
## 部屋の組み立ては net_party.gd。

const NetParty := preload("res://tests/integration/net_party.gd")
const JUMP := RuleAction.Kind.JUMP
const JUMP_SLOT := 4
const CLIENTS: Array[int] = [1, 2, 3]

var party: NetParty
var host: PartyDirector


func before_each() -> void:
	party = NetParty.new(self, 4, "zz_test_races")
	host = party.host()
	await party.open(StageCatalog.HUB_ID, 44000)
	await party.join_all()
	await party.enter(StageCatalog.INTRO_ID)


func after_each() -> void:
	await party.close()


func _lift_id() -> int:
	return int(host.world.entity_ids["lift"])


## ホストが持ち上げ台へジャンプを渡す（単発なので、ホストが押すまで台は動かない）。
func _host_lends_jump_to_lift() -> int:
	var lift := host.world.blocks[_lift_id()]
	await party.place(0, lift.global_position + Vector3(0.0, 0.6, 1.4))
	host.world.select_slot(JUMP_SLOT)
	host.world.set_lend_mode(TriggerMode.Kind.SINGLE_SHOT)
	assert_eq(host.world.lend_to(lift, false), RuleLedger.LendResult.OK)
	await party.until(party.converged, "the lend reaches everyone")
	for i in party.count():
		assert_true(party.world(i).ledger.can_initiate(_lift_id(), JUMP), "side %d sees it" % i)
	return _lift_id()


## 参加者 3人を、持ち上げ台に F が届く位置に置く。
func _gather_clients_near_lift() -> void:
	var spots: Array[Vector3] = [
		Vector3(-1.0, 0.1, -3.0), Vector3(2.0, 0.1, -3.0), Vector3(0.5, 0.1, -1.9)
	]
	for k in CLIENTS.size():
		await party.place(CLIENTS[k], spots[k])


## 参加者 3人を、地面の point のまわり（拾える距離の内側）に置く。
func _gather_clients_around(point: Vector3) -> void:
	var offsets: Array[Vector3] = [
		Vector3(0.9, 0.1, 0.0), Vector3(-0.9, 0.1, 0.0), Vector3(0, 0.1, 0.9)
	]
	for k in CLIENTS.size():
		await party.place(CLIENTS[k], point + offsets[k])


## 全員の台帳で、4人のジャンプの合計が4つのまま（増えも減りもしない）か。
func _assert_jumps_conserved(label: String) -> void:
	for i in party.count():
		var total := 0
		for p in party.count():
			total += party.world(i).ledger.ability_count(JUMP, party.pid(p))
		assert_eq(total, 4, "%s: side %d still has 4 jumps in total" % [label, i])


## ジャンプを n 個持っている参加者の側の番号。
func _clients_with_jumps(n: int) -> Array[int]:
	var found: Array[int] = []
	for i in CLIENTS:
		if host.world.ledger.ability_count(JUMP, party.pid(i)) == n:
			found.append(i)
	return found


## 3人が同じフレームに、同じ持ち上げ台へ F（回収）を押す。回収できるのは1人だけ。
func test_three_clients_recall_the_same_block_in_the_same_frame() -> void:
	var lift_id := await _host_lends_jump_to_lift()
	await _gather_clients_near_lift()
	var tokens := party.token_count(0)
	var refused: Array[int] = []
	for i in CLIENTS:
		party.world(i).message_posted.connect(
			func(text: String) -> void:
				if text.contains("回収できるものがありません"):
					refused.append(i)
		)
	for i in CLIENTS:
		party.world(i).interact(party.world(i).blocks[lift_id])
	await party.until(
		func() -> bool: return host.world.ledger.tokens_on(lift_id).is_empty(), "someone recalls"
	)
	await party.until(func() -> bool: return refused.size() == 2, "the host answers the other two")
	await wait_physics_frames(20)
	await party.assert_consistent("recall race")
	assert_eq(_clients_with_jumps(2).size(), 1, "exactly one client got the jump")
	assert_eq(_clients_with_jumps(1).size(), 2, "the other two keep only their own")
	assert_false(host.world.ledger.player_can(JUMP, 1), "the host's jump went to the winner")
	_assert_jumps_conserved("recall race")
	for i in party.count():
		assert_eq(party.token_count(i), tokens, "side %d: no token appeared or vanished" % i)
		assert_true(party.world(i).ledger.tokens_on(lift_id).is_empty(), "side %d: lift empty" % i)


## 依頼の層でも同じ: 3人が同じトークンの回収（RECALL_TOKEN）を同時に送る。OK が返るのは1人だけ。
func test_three_clients_send_the_same_recall_command_at_once() -> void:
	var lift_id := await _host_lends_jump_to_lift()
	var token_id := host.world.ledger.tokens_on(lift_id)[0].id
	var winners: Array[int] = []
	for i in CLIENTS:
		party.nets[i].session.result_received.connect(
			func(_seq: int, result: Dictionary) -> void:
				if result["result"] == PartyCommand.Result.OK:
					winners.append(i)
		)
	for i in CLIENTS:
		party.nets[i].session.send(PartyCommand.recall_token(token_id))
	await party.until(func() -> bool: return winners.size() >= 1, "a recall result arrives")
	await wait_physics_frames(20)
	await party.assert_consistent("recall command race")
	assert_eq(winners.size(), 1, "only one recall was applied")
	assert_eq(_clients_with_jumps(2), winners, "the one who got OK holds the jump")
	_assert_jumps_conserved("recall command race")


## 地面に落ちている器（世界の器）を、3人が同じフレームに F で拾う。拾えるのは1人だけ。
func test_three_clients_pick_up_the_same_world_vessel() -> void:
	var at := Vector3(-2.5, 0.0, 2.0)
	var v := host.world.ledger.place_in_world(JUMP, false, at)
	await party.until(party.converged, "the vessel reaches everyone")
	await _gather_clients_around(at)
	var vessels := host.world.ledger.all_vessels().size()
	for i in CLIENTS:
		party.world(i).interact(null)
	await party.until(
		func() -> bool: return v.location != RuleVessel.Location.WORLD, "someone picks it up"
	)
	await wait_physics_frames(20)
	await party.assert_consistent("vessel pickup race")
	var owners: Array[int] = []
	for i in CLIENTS:
		var held := carried(party.world(i).ledger, party.pid(i))
		if held.any(func(x: RuleVessel) -> bool: return x.id == v.id):
			owners.append(i)
	assert_eq(owners.size(), 1, "exactly one client has the vessel")
	for i in party.count():
		var copy := party.world(i).ledger.vessel(v.id)
		# 拾った器はホットバーの空きへ入る（2026-11-23）。どの画面でも同じ場所
		assert_eq(copy.location, RuleVessel.Location.HOTBAR, "side %d: on a hotbar" % i)
		assert_eq(party.world(i).ledger.all_vessels().size(), vessels, "side %d: no copy" % i)


## 落ちている能力（器なし。単発の付与者が抜けたときなど）を、3人が同じフレームに F で拾う。
func test_three_clients_pick_up_the_same_dropped_token() -> void:
	var at := Vector3(2.5, 0.0, 2.0)
	# 器のないトークンを落ちている状態にする（準備だけ台帳を直接さわる。ホストが全員へ配る）
	var t := host.world.ledger.place_on_entity(JUMP, false, _lift_id())
	t.holder_ids = PackedInt32Array()
	t.dropped = true
	t.drop_position = at
	host.world.ledger.changed.emit()
	await party.until(party.converged, "the dropped token reaches everyone")
	assert_eq(host.world.ledger.validate(), PackedStringArray())
	await _gather_clients_around(at)
	var tokens := party.token_count(0)
	for i in CLIENTS:
		party.world(i).interact(null)
	await party.until(func() -> bool: return not t.dropped, "someone picks it up")
	await wait_physics_frames(20)
	await party.assert_consistent("dropped token race")
	var owners: Array[int] = []
	for i in CLIENTS:
		var held := host.world.ledger.inventory_vessels(party.pid(i))
		if held.any(func(x: RuleVessel) -> bool: return x.token_id == t.id):
			owners.append(i)
	assert_eq(owners.size(), 1, "exactly one client picked it up")
	for i in party.count():
		var made := party.world(i).ledger.all_vessels().filter(
			func(x: RuleVessel) -> bool: return x.token_id == t.id
		)
		assert_eq(made.size(), 1, "side %d: the token got exactly one vessel" % i)
		assert_eq(party.token_count(i), tokens, "side %d: no token appeared or vanished" % i)


## 借りているジャンプ（A の器のもの。B が持っている）を、同じフレームに何人もが渡そうとする。
## 持っている B だけが渡せる（B が2人へ続けて送っても、渡るのは最初の1回）。A（元の持ち主）と D は断られる。
func test_two_players_give_the_same_carried_token_at_once() -> void:
	var token_id := host.world.ledger.hotbar_vessel(JUMP_SLOT, 1).token_id
	assert_eq(host.world.ledger.give_to_player(token_id, 1, 2), RuleLedger.LendResult.OK)
	await party.until(party.converged, "B carries A's jump everywhere")
	var applied: Array[String] = []
	for i in CLIENTS:
		party.nets[i].session.result_received.connect(
			func(seq: int, result: Dictionary) -> void:
				if result["result"] == PartyCommand.Result.OK:
					applied.append("%d#%d" % [i, seq])
		)
	party.nets[1].session.send(PartyCommand.give(token_id, 3))
	party.nets[1].session.send(PartyCommand.give(token_id, 4))
	party.nets[3].session.send(PartyCommand.give(token_id, 2))
	var by_owner := host.world.ledger.give_to_player(token_id, 1, 4)
	assert_eq(by_owner, RuleLedger.LendResult.ALREADY_LENT, "the original owner cannot give it")
	await party.until(func() -> bool: return applied.size() >= 1, "a give result arrives")
	await wait_physics_frames(20)
	await party.assert_consistent("give race")
	assert_eq(applied, ["1#1"] as Array[String], "only B's first give was applied")
	for i in party.count():
		var t := party.world(i).ledger.token(token_id)
		assert_eq(t.carrier_id, 3, "side %d: C carries it, nobody else" % i)
	_assert_jumps_conserved("give race")


## 4人が同じフレームに全員リセットへ投票する。リセットは1回だけで、余った票で次の投票が開かない。
func test_four_votes_in_the_same_frame_reset_once() -> void:
	for i in party.count():
		party.directors[i].request_vote()
	await party.until(func() -> bool: return host.lifecycle.reset_count() >= 1, "the reset passes")
	await wait_physics_frames(30)
	assert_eq(host.lifecycle.reset_count(), 1, "exactly one reset")
	assert_false(host.lifecycle.is_vote_open(), "no leftover vote is open")
	for i in party.count():
		var lc := party.directors[i].lifecycle
		assert_eq(lc.reset_count(), 1, "side %d sees one reset" % i)
		assert_false(lc.is_vote_open(), "side %d sees no open vote" % i)
		assert_eq(lc.players_in(PartyLifecycle.State.ACTIVE).size(), 4, "side %d: all alive" % i)
	await party.assert_consistent("vote race")
