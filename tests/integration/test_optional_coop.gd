extends TestCase
## 寄り道のステージを 2 人のオンライン協力で遊ぶ（協力で解き方が変わるところ）。部屋は net_party.gd。
## O1-2 時計じかけの回廊の扉 A: ひとりでは箱を戸口に入れて開けておくが、2 人なら W を集めて速さ 2 倍にし、
## 鐘を鳴らしてから走って間に合う。先に渡った人は、閉じた扉越しに W を 2 つとも渡し返し、残りの人も
## 同じように渡る（箱は使わない）。操作は move_intent・view_yaw・press_action と、渡す・F だけ。

const NetParty := preload("res://tests/integration/net_party.gd")
const W := RuleAction.Kind.FORWARD
const LEFT := RuleAction.Kind.LEFT
const JUMP := RuleAction.Kind.JUMP
const BELL := Vector3(-7.5, 0.0, 17.5)
const FOOT := Vector3(-0.5, 0.0, 4.5)
const SOUTH := Vector3(-0.5, 0.0, 1.5)
const NORTH := Vector3(-0.5, 0.0, -0.8)

var party: NetParty


func before_each() -> void:
	party = NetParty.new(self, 2, "zz_test_optional_coop")
	await party.open(StageCatalog.HUB_ID, 38000)
	await party.join_all()
	await party.enter("o1_2")


func after_each() -> void:
	await party.close()


## i 番目が target へ走る（W が無ければ A で）。着いたら true（着かなくても失敗にしない）。
func _run(i: int, target: Vector3, frames: int = 600) -> bool:
	var w := party.world(i)
	var me := w.player
	for f in frames:
		var flat := Vector3(target.x - me.global_position.x, 0.0, target.z - me.global_position.z)
		if flat.length() <= 0.4 and absf(me.global_position.y - target.y) < 0.7:
			me.move_intent = Vector2.ZERO
			return true
		var dir := flat.normalized()
		if w.ledger.player_can(W, party.pid(i)):
			me.view_yaw = atan2(-dir.x, -dir.z)
			me.move_intent = Vector2(0.0, 1.0)
		else:
			me.view_yaw = atan2(dir.z, -dir.x)
			me.move_intent = Vector2(-1.0, 0.0)
		await tree.physics_frame
	me.move_intent = Vector2.ZERO
	return false


func _slot(i: int, action: RuleAction.Kind) -> int:
	var w := party.world(i)
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, party.pid(i))
		if v != null and w.ledger.token(v.token_id).action == action:
			return slot
	return -1


## i 番目が j 番目へ W を 1 つ渡す（届いたら true）。
func _give_w(i: int, j: int) -> bool:
	await party.settle(i)
	await party.settle(j)
	var w := party.world(i)
	var before := party.world(j).ledger.ability_count(W, party.pid(j))
	var slot := _slot(i, W)
	w.select_slot(slot if slot != -1 else 0)
	w.lend_to(w.avatars[party.pid(j)], false)
	var arrived := await party.until(
		func() -> bool: return party.world(j).ledger.ability_count(W, party.pid(j)) > before,
		"side %d gives a W to side %d" % [i, j],
		240
	)
	await party.until(party.converged, "after giving")
	return arrived


## i 番目が鐘を鳴らしてから、土手の入口を通って扉 A の北へ走る。扉が閉じる前に抜けたら true。
func _ring_and_run(i: int) -> bool:
	assert_true(await _run(i, BELL + Vector3(1.0, 0.0, -1.0)), "side %d reached the bell" % i)
	await party.settle(i)
	party.world(i).interact(party.world(i).bells_by_key["clock_a"])
	assert_true(
		await party.until(func() -> bool: return party.host().world.activated.has("clock_a")),
		"the bell rang"
	)
	await _run(i, FOOT, 200)
	return await _run(i, NORTH, 120)


func test_o1_2_two_players_pool_w_and_run_through_gate_a() -> void:
	# 1 人目は A を拾う（W を手放しても歩けるように）。2 人目は扉 A のすぐ南で待つ
	assert_true(await _run(0, Vector3(6.5, 0.0, 15.5)), "host walks to the A")
	party.world(0).interact(null)
	await wait_physics_frames(2)
	var host := party.world(0)
	for v in host.ledger.inventory_vessels(party.pid(0)):
		if host.ledger.token(v.token_id).action == LEFT:
			assert_true(host.ledger_actions.move_to_hotbar(v.id, 2), "A on the hotbar")
	assert_true(host.ledger.player_can(LEFT, party.pid(0)), "picked A")
	assert_true(await _run(1, FOOT), "client walks to the causeway")
	assert_true(await _run(1, SOUTH), "client waits south of gate A")
	assert_true(await _run(0, SOUTH + Vector3(0.0, 0.0, 1.0)), "host comes over")
	assert_true(await _give_w(1, 0), "the client gives its W to the host (W x2)")
	assert_eq(party.world(0).ledger.ability_count(W, party.pid(0)), 2, "host has W x2")
	assert_true(await _ring_and_run(0), "W x2 rang the bell and made it through gate A")
	# 閉じた扉越しに W を 2 つとも渡し返す
	await party.until(func() -> bool: return not _gate_open(), "gate A shut again")
	assert_true(await _give_w(0, 1), "first W back through the closed gate")
	assert_true(await _give_w(0, 1), "second W back")
	assert_eq(party.world(1).ledger.ability_count(W, party.pid(1)), 2, "client has W x2")
	assert_true(await _ring_and_run(1), "the client made it through too")
	var crate := party.host().world.blocks[int(party.host().world.entity_ids["cog_a"])]
	assert_eq(crate.cell(), Vector3i(0, 0, 2), "the crate never moved (co-op did not need it)")


func _gate_open() -> bool:
	for door in MechanismSet.of(party.host().world).doors:
		if door.spec.key == "gate_a":
			return door.is_open() or door.heading_open
	return false
