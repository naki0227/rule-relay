extends "res://tests/integration/world_coop.gd"
## ワールド 4 の新しいステージの協力の道（2 人のオンライン協力。ホスト＝0、参加者＝1）。
## 部品は world_coop.gd。どちらの人もプレイヤーと同じ操作だけで動く（瞬間移動しない）。


## 4-1: ホストが子どもに D を投げ渡し、切り株に上がったら参加者が「投げる」を投げ渡す。
func test_nut_toss_coop_two_throwers() -> void:
	await _start(World4Stages.NUT_TOSS_ID, 44100)
	assert_true(await _walk(0, Vector3(-1.5, 0.0, -1.6), 0.3))
	assert_true(await _walk(1, Vector3(0.5, 0.0, -1.6), 0.3))
	await _give(0, "kit", RIGHT, true)
	assert_true(await _wait_wish("kit"), "the kit is on its stump")
	await _give(1, "kit", THROW, true)
	assert_true(
		await party.until(func() -> bool: return _host().activated.has("nut_bell"), "the nut rang")
	)
	for i in 2:
		for p: Vector3 in [
			Vector3(-1.5, 0.0, 2.5), Vector3(-1.5, 1.0, 4.5), Vector3(-2.5, 2.0, 4.5)
		]:
			assert_true(await _walk(i, p))
	await _both_in_goal([Vector3(-5.5, 1.0, 5.0), Vector3(-4.0, 1.0, 5.0)])


## 4-2: 参加者がジャンプをホストへ渡す（×2）→ ホストが東の段へ跳び上がってグローブを取り、うさぎへ投げ渡す。
## 参加者がうさぎに D を渡す。ホストが段の上からジャンプを 2 つとも返し、参加者も ×2 で跳び上がる。
func test_creature_ladder_coop_pool_jumps_and_throw_the_gloves() -> void:
	await _start(World4Stages.LADDER_ID, 44200)
	assert_true(await _walk(0, Vector3(4.5, 0.0, -1.5), 0.3))
	assert_true(await _walk(1, Vector3(3.5, 0.0, -1.5), 0.3))
	await _give(1, 0, JUMP)
	assert_eq(_w(0).ledger.ability_count(JUMP, party.pid(0)), 2, "the host has jump x2")
	assert_true(await _walk(0, Vector3(4.5, 2.0, -3.5)), "jumped up the ledge with x2")
	await _pick(0, Vector3(7.5, 2.0, -3.5), CLIMB)
	assert_true(await _walk(0, Vector3(4.5, 2.0, -3.4), 0.3))
	await _give(0, "bunny", CLIMB, true)
	assert_true(await _walk(1, Vector3(-4.0, 0.0, -1.0), 0.4))
	await _give(1, "bunny", RIGHT)
	assert_true(await _wait_wish("bunny"), "the bunny climbed with the thrown gloves")
	assert_true(await _walk(1, Vector3(4.5, 0.0, -1.6), 0.3))
	await _give(0, 1, JUMP)
	await _give(0, 1, JUMP)
	assert_true(await _walk(1, Vector3(5.5, 2.0, -3.5)), "the client jumped up with x2")
	await _both_in_goal([Vector3(5.6, 1.0, -6.0), Vector3(7.4, 1.0, -6.0)])


## 4-4: ホストがおもりを持って原っぱの板に乗る（4 人分）→ 参加者がひつじにジャンプと A を渡して橋を渡り、
## 向こうの小さな板に乗る → ホストが板を降りて渡る。
func test_weight_plates_coop_hold_the_bridge_from_both_ends() -> void:
	await _start(World4Stages.PLATES_ID, 44300)
	await _pick(0, Vector3(-5.5, 1.0, 5.5), HEAVY)
	assert_true(await _walk(0, Vector3(-2.5, 1.0, 2.5), 0.2))
	assert_true(await _wait_door("plate_bridge", true), "a heavy host is 4 people's weight")
	assert_true(await _walk(1, Vector3(7.5, 1.0, 3.0), 0.4))
	await _give(1, "lamb", JUMP)
	await _give(1, "lamb", LEFT)
	assert_true(await _wait_wish("lamb"), "the lamb is on its dais")
	assert_true(await _walk(1, Vector3(0.0, 1.0, 0.6), 0.3))
	assert_true(await _walk(1, Vector3(0.0, 1.0, -10.5), 0.35, 400), "the client crossed")
	assert_true(await _walk(1, Vector3(3.5, 1.0, -10.5), 0.2))
	assert_true(await _walk(0, Vector3(0.0, 1.0, 0.6), 0.3))
	assert_true(_door_closed("plate_bridge"), "the client holds the far plate")
	assert_true(await _walk(0, Vector3(0.0, 1.0, -10.5), 0.35, 400), "the host crossed")
	for i in 2:
		assert_true(await _walk(i, Vector3(4.5, 1.0, -11.5)))
		assert_true(await _walk(i, Vector3(4.5, 1.0, -15.5)))
	await _both_in_goal([Vector3(-1.0, 0.0, -15.0), Vector3(1.0, 0.0, -15.0)])


## 4-5: ホストが門の板に乗り、参加者が 3 匹に A・S・D を渡す。3 匹が秤に乗ったら 2 人で橋を渡る。
func test_herd_path_coop_one_holds_the_gate() -> void:
	await _start(World4Stages.HERD_ID, 44400)
	assert_true(await _walk(0, Vector3(7.5, 1.0, 4.5), 0.2))
	var gifts: Array[RuleAction.Kind] = [LEFT, BACK, RIGHT]
	for k in World4Stages.HERD.size():
		var key := World4Stages.HERD[k]
		assert_true(await _walk(1, _node(1, key).global_position + Vector3(0.0, 0.0, 1.6), 0.4))
		await _give(1, key, gifts[k])
	for key in World4Stages.HERD:
		assert_true(await _wait_in(key, World4Stages.PASTURE), "%s is in the pasture" % key)
	assert_true(await _wait_door("herd_bridge", true), "the herd raised the bridge")
	for i in 2:
		assert_true(await _walk(i, Vector3(8.6, 1.0, 5.2 + 0.6 * i), 0.3))
		assert_true(
			await _walk(i, Vector3(18.5, 1.0, 5.2 + 0.6 * i), 0.35, 400), "side %d over" % i
		)
		assert_true(await _walk(i, Vector3(19.5, 1.0, 0.5)))
		assert_true(await _walk(i, Vector3(21.5, 1.0, 0.5)))
	await _both_in_goal([Vector3(22.5, 0.0, 3.0), Vector3(22.5, 0.0, 5.0)])


## 4-6: ホストが子どもに D と「投げる」を投げ渡して檻を開け、参加者がおもりを取って石の板に乗る（橋）。
## ホストが願いの動物にジャンプと A を渡して台へ上げ、取り戻して渡り、向こうの小さな板で参加者を待つ。
func test_deep_forest_coop_cage_weight_and_far_plate() -> void:
	await _start(DeepForest.ID, 44500)
	assert_true(await _walk(0, Vector3(-3.5, 1.0, 0.6), 0.3))
	await _give(0, "kit", RIGHT, true)
	assert_true(await _wait_in("kit", AABB(Vector3(-6.0, 1.5, -12.0), Vector3(1.0, 2.0, 1.0))))
	assert_true(await _walk(1, Vector3(-3.6, 1.0, 2.5), 0.3))
	await _give(0, "kit", THROW, true)
	assert_true(await _wait_door("cage_door", false), "the nut opened the cage")
	await _pick(1, DeepForest.HEAVY_AT, HEAVY)
	assert_true(await _walk(1, Vector3(-3.5, 1.0, 2.5), 0.3))
	assert_true(await _walk(1, Vector3(2.5, 1.0, 6.5), 0.2))
	assert_true(await _wait_door("forest_bridge", true), "the heavy client holds the bridge")
	assert_true(await _walk(0, Vector3(3.5, 1.0, 2.5), 0.4))
	await _give(0, "forest_wish", JUMP)
	await _give(0, "forest_wish", LEFT)
	assert_true(await _wait_wish("forest_wish"), "the creature is on its dais")
	await _interact(0, "forest_wish")
	assert_true(await _walk(0, Vector3(8.6, 1.0, 6.0), 0.3))
	assert_true(await _walk(0, Vector3(19.5, 1.0, 6.0), 0.35, 400), "the host crossed")
	assert_true(await _walk(0, Vector3(20.5, 1.0, 9.5), 0.2))
	assert_true(await _walk(1, Vector3(8.6, 1.0, 5.6), 0.3))
	assert_true(await _walk(1, Vector3(19.5, 1.0, 5.6), 0.35, 400), "the client crossed")
	assert_true(await _walk(1, Vector3(19.5, 1.0, 1.5)))
	assert_true(await _walk(1, Vector3(22.5, 1.0, 1.5)))
	assert_true(await _walk(0, Vector3(22.5, 1.0, 1.5)))
	await _both_in_goal([Vector3(23.5, 0.0, 5.0), Vector3(23.5, 0.0, 6.5)])
