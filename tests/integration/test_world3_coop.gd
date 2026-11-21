extends "res://tests/integration/world_coop.gd"
## ワールド 3 の新しいステージの協力の道（2 人のオンライン協力。ホスト＝0、参加者＝1）。
## 部品は world_coop.gd。どちらの人もプレイヤーと同じ操作だけで動く（瞬間移動しない）。


## 3-1: ホストがうさぎを砂丘へ上げてダッシュを拾い、崖から幅 6 を越えてから、参加者へダッシュを投げ渡す。
func test_dash_beach_coop_pass_the_dash_back() -> void:
	await _start(World3Stages.DASH_BEACH_ID, 43100)
	assert_true(await _walk(0, Vector3(-1.0, 0.0, 2.5), 0.4))
	await _give(0, "bunny", RIGHT)
	await _give(0, "bunny", JUMP)
	assert_true(await _wait_wish("bunny"), "the bunny is on its dune")
	assert_true(await _walk(0, Vector3(-2.5, 0.0, 0.5), 0.3))
	await _interact(0, "bunny")
	await _pick(0, Vector3(1.5, 0.0, 2.5), DASH)
	assert_true(await _walk(0, Vector3(5.5, 1.0, 2.5)))
	assert_true(await _dash_jump(0, Vector3(5.5, 1.0, 0.3), Vector3(5.5, 0.0, -7.5)), "host over")
	assert_true(await _walk(1, Vector3(4.5, 1.0, 0.5), 0.3))
	await _give(0, 1, DASH, true)
	assert_eq(_w(1).ledger.ability_count(DASH, party.pid(1)), 1, "the client caught the dash")
	assert_true(await _dash_jump(1, Vector3(4.5, 1.0, 0.3), Vector3(4.5, 0.0, -7.5)), "client over")
	for i in 2:
		for p: Vector3 in [Vector3(7.5, 1.0, -8.5), Vector3(7.5, 2.0, -10.5)]:
			assert_true(await _walk(i, p))
	await _both_in_goal([Vector3(6.8, 1.0, -13.0), Vector3(8.2, 1.0, -13.0)])


## 3-2: ホストは西の足場を乗り継ぎ、参加者は東を回る。参加者がひつじに D を渡す。
func test_shuttle_cove_coop_both_sides_of_the_bay() -> void:
	await _start(World3Stages.SHUTTLE_COVE_ID, 43200)
	await _ride(
		0,
		"north_shuttle",
		Vector3(-3.5, 1.0, 2.6),
		Vector3i(-4, 0, 1),
		Vector3i(-4, 0, 0),
		Vector3(-3.5, 1.0, -1.5)
	)
	await _ride(
		1,
		"east_shuttle",
		Vector3(6.4, 1.0, 4.5),
		Vector3i(7, 0, 4),
		Vector3i(8, 0, 4),
		Vector3(9.5, 1.0, 4.5)
	)
	await _ride(
		0,
		"twin_south",
		Vector3(0.5, 1.0, -4.4),
		Vector3i(0, 0, -6),
		Vector3i(0, 0, -7),
		Vector3(0.5, 1.0, -7.5)
	)
	var north := _node(0, "twin_north") as RuleBlock
	await party.until(
		func() -> bool: return north.global_position.distance_to(Vector3(0.5, 0.5, -8.5)) < 0.05,
		"carried north"
	)
	assert_true(await _walk(0, Vector3(0.5, 1.0, -10.5), 0.35, 120))
	assert_true(await _walk(1, Vector3(9.6, 1.0, -10.5)))
	await _ride(
		1,
		"return_shuttle",
		Vector3(9.6, 1.0, -10.5),
		Vector3i(8, 0, -11),
		Vector3i(7, 0, -11),
		Vector3(5.5, 1.0, -10.5)
	)
	assert_true(await _walk(1, Vector3(5.5, 1.0, -12.5)))
	assert_true(await _walk(1, Vector3(3.5, 1.0, -13.5), 0.4))
	await _give(1, "lamb", RIGHT)
	assert_true(await _wait_wish("lamb"), "the lamb is on its rock")
	for p: Vector3 in [
		Vector3(5.5, 1.0, -10.5), Vector3(5.5, 1.0, -12.5), Vector3(3.5, 1.0, -14.5)
	]:
		assert_true(await _walk(0, p))
	await _both_in_goal([Vector3(-1.0, 0.0, -14.0), Vector3(1.0, 0.0, -14.0)])


## 3-4: ホストは追い風で跳び、参加者は横風が止んだ間に橋を渡る。ホストがうさぎを上げる。
func test_wind_path_coop_gust_and_bridge() -> void:
	await _start(World3Stages.WIND_PATH_ID, 43300)
	var gust := Vector3(-1.5, 0.5, -2.5)
	assert_true(await _walk(0, Vector3(-1.5, 0.0, 2.5), 0.25))
	await party.until(func() -> bool: return _host().nature.wind_at(gust).length() < 0.1, "calm")
	await party.until(func() -> bool: return _host().nature.wind_at(gust).length() > 0.1, "gust")
	_face(0, Vector3(-1.5, 0.0, -6.5))
	_me(0).move_intent = Vector2(0.0, 1.0)
	await party.until(func() -> bool: return _me(0).global_position.z < 0.25, "run up", 120)
	_w(0).press_action(JUMP)
	assert_true(await _walk(0, Vector3(-1.5, 0.0, -6.5), 0.6, 240), "the gust carried the host")
	var cross := Vector3(-9.0, 0.5, -3.0)
	assert_true(await _walk(1, Vector3(-9.0, 0.0, 0.6), 0.2))
	await party.until(func() -> bool: return _w(1).nature.wind_at(cross).length() > 0.1, "blows")
	await party.until(func() -> bool: return _w(1).nature.wind_at(cross).length() < 0.1, "stops")
	assert_true(await _walk(1, Vector3(-9.0, 0.0, -6.5), 0.35, 300), "the client crossed in a lull")
	assert_true(await _walk(0, Vector3(3.5, 0.0, -10.5), 0.4))
	await _give(0, "bunny", RIGHT)
	await _give(0, "bunny", JUMP)
	assert_true(await _wait_wish("bunny"), "the bunny is on its lookout")
	assert_true(await _walk(0, Vector3(5.5, 0.0, -10.5), 0.3))
	await _interact(0, "bunny")
	for i in 2:
		for p: Vector3 in [
			Vector3(-3.5, 0.0, -9.5), Vector3(-3.5, 1.0, -10.5), Vector3(-3.5, 2.0, -12.5)
		]:
			assert_true(await _walk(i, p))
	await _both_in_goal([Vector3(-3.6, 1.0, -14.0), Vector3(-2.4, 1.0, -14.0)])


## 3-5: 2 人で投げ渡しのリレー。参加者がひつじに D を投げ渡して見張り岩へ、ホストが「投げる」を投げ渡す
## → 木の実で鐘 → 6 秒の橋を 2 人で渡る。
func test_gap_relay_coop_two_throwers() -> void:
	await _start(World3Stages.GAP_RELAY_ID, 43400)
	assert_true(await _walk(1, Vector3(-0.4, 0.0, 0.6), 0.3))
	assert_true(await _walk(0, Vector3(0.4, 0.0, 0.6), 0.3))
	await _give(1, "lamb", RIGHT, true)
	assert_true(await _wait_wish("lamb"), "the lamb is on its rock")
	await _give(0, "lamb", THROW, true)
	assert_true(await _wait_door("relay_bridge", true), "the nut rang the bell and the bridge rose")
	for i in 2:
		assert_true(
			await _walk(i, Vector3(-0.4 + 0.8 * i, 0.0, -10.5), 0.35, 400), "side %d over" % i
		)
	for i in 2:
		for p: Vector3 in [
			Vector3(-4.5, 0.0, -12.5), Vector3(-4.5, 1.0, -13.5), Vector3(-4.5, 2.0, -15.5)
		]:
			assert_true(await _walk(i, p))
	await _both_in_goal([Vector3(-4.6, 1.0, -18.0), Vector3(-3.4, 1.0, -18.0)])


## 3-6: ホストは港の鐘で信号の往復足場を乗り継ぎ、グローブを拾って往復足場で鐘の雲へ。参加者はダッシュで
## 東を回って鐘の雲へ渡り、発射台を S で押して「投げる」を渡す（橋が架かったまま）。ホストが動物に
## グローブと D を渡し、2 人で橋を渡る。
func test_cloud_corridor_coop_shuttles_and_dashes() -> void:
	await _start(CloudCorridor.ID, 43500)
	await _pick(1, Vector3(3.5, 1.0, 6.5), DASH)
	await _ring(0, "harbor_bell")
	await _ride(
		0,
		"harbor_south",
		Vector3(-2.5, 1.0, 4.4),
		Vector3i(-3, 0, 3),
		Vector3i(-3, 0, 2),
		Vector3(-2.5, 1.0, 1.5)
	)
	var north := _node(0, "harbor_north") as RuleBlock
	await party.until(
		func() -> bool: return north.global_position.distance_to(Vector3(-2.5, 0.5, 0.5)) < 0.05,
		"carried to the cloud"
	)
	assert_true(await _walk(0, Vector3(-2.5, 1.0, -1.5), 0.35, 120))
	assert_true(await _ground_dash(1, Vector3(6.6, 1.0, 6.5), Vector3(9.5, 1.0, 6.5)), "east cloud")
	assert_true(await _walk(1, Vector3(9.4, 1.0, -2.5), 0.2))
	assert_true(await _ground_dash(1, Vector3(9.3, 1.0, -2.5), Vector3(5.5, 1.0, -2.5)), "cloud")
	await _pick(0, Vector3(-4.5, 1.0, -3.5), CLIMB)
	await _ride(
		0,
		"cloud_shuttle",
		Vector3(3.5, 1.0, -5.4),
		Vector3i(3, 0, -7),
		Vector3i(3, 0, -8),
		Vector3(3.5, 1.0, -9.5)
	)
	assert_true(
		await _ground_dash(1, Vector3(-0.5, 1.0, -5.7), Vector3(-0.5, 1.0, -9.5)), "bell cloud"
	)
	assert_true(await _walk(1, Vector3(4.5, 1.0, -10.6), 0.3))
	await _give(1, "launcher", BACK, false, TriggerMode.Kind.SINGLE_SHOT)
	await _fire(1, BACK)
	assert_true(await _walk(1, Vector3(4.5, 1.0, -10.6), 0.3))
	await _give(1, "launcher", THROW)
	assert_true(await _wait_door("sky_bridge", true), "the launcher keeps the sky bridge up")
	assert_true(await _walk(0, Vector3(-5.5, 1.0, -12.4), 0.4))
	await _give(0, "cloud_wish", CLIMB)
	await _give(0, "cloud_wish", RIGHT)
	assert_true(await _wait_wish("cloud_wish"), "the creature climbed its rock")
	for i in 2:
		assert_true(await _walk(i, Vector3(1.6 + 0.8 * i, 1.0, -13.6), 0.3))
		assert_true(
			await _walk(i, Vector3(1.6 + 0.8 * i, 1.0, -25.5), 0.35, 400), "side %d over" % i
		)
		assert_true(await _walk(i, Vector3(4.5, 1.0, -26.5)))
		assert_true(await _walk(i, Vector3(4.5, 1.0, -28.5)))
	await _both_in_goal([Vector3(-1.0, 0.0, -28.5), Vector3(1.0, 0.0, -28.5)])
