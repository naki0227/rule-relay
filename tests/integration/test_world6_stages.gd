extends "res://tests/integration/world56_play.gd"
## ワールド 6「霧の峰」の新しいステージ（6-1〜6-5）を、ひとりで最初から最後まで自動で遊ぶ。
## 操作はプレイヤーと同じ（move_intent・view_yaw・press_action と、渡す・回収・拾う・持ち物の入れ替え）で、
## 瞬間移動はしない（ワープの石が移すのは仕掛けの動き）。どのステージも、ひとりの道 2 通りと協力の近道
## 1 通り（仲間がくれた能力を台帳の普通の配り方で持たせる）を通す。
## 関所と詰みの試遊は test_world6_probes.gd、ゴールの視線は test_goal_sightlines_w56.gd。

# --- 6-1 ワープの石 --------------------------------------------------------------


## ひとりの道 1: 石に D を繰り返しで渡してワープで北の島へ送り、岩の脇の足場にする。
func test_warp_stones_send_the_crate_through_the_warp() -> void:
	await _enter(World6Stages.WARP_ID)
	await _walk_to(Vector3(-7.5, 0.0, 5.6), 0.3)
	_lend(_block("warp_crate"), _slot_of(RIGHT), TriggerMode.Kind.REPEAT)
	await _wait_block_at("warp_crate", Vector3i(-5, 0, -10))
	assert_true(await _step_on_warp(Vector3(-4.5, 0.0, 4.5)), "warped to the isle")
	await _walk_to(Vector3(-4.5, 1.0, -9.5))
	await _walk_to(Vector3(-3.5, 2.0, -9.5))
	assert_true(await _step_on_warp(Vector3(-2.5, 2.0, -9.5)), "the rock's stone sent me east")
	_lend(_creature("warp_bunny"), _slot_of(THROW), TriggerMode.Kind.NONE)
	assert_true(await _wait_until_rung("terrace_bell"), "the bunny rang the bell")
	await _walk_into_goal()
	assert_true(await _cleared(), "crate through the warp, then the one-way stone")


## ひとりの道 2: 塔の上の風船（浮く）で、東の高台へゆっくり落ちながら渡る。鐘は触って鳴らす。
func test_warp_stones_float_from_the_tower() -> void:
	await _enter(World6Stages.WARP_ID)
	for i in 4:
		await _walk_to(Vector3(1.5 + i, 1.0 + i, -0.5))
	await _walk_to(Vector3(5.5, 5.0, -1.5))
	await _pick_to_hotbar(Vector3(5.5, 5.0, -1.5), FLOAT)
	assert_true(
		await _leap_to(Vector3(6.6, 5.0, -1.5), Vector3(15.5, 2.0, -1.5)), "floated over the gap"
	)
	await _ring("terrace_bell")
	await _walk_into_goal()
	assert_true(await _cleared(), "the balloon carried me across")


## 協力の近道: ワープで北の島へ渡り、ジャンプ×2 で岩（2）へ直接（石を運ばない）。
func test_warp_stones_coop_double_jump_onto_the_rock() -> void:
	await _enter(World6Stages.WARP_ID)
	assert_true(await _step_on_warp(Vector3(-4.5, 0.0, 4.5)), "warped to the isle")
	_gift_from_teammate(JUMP)
	await _walk_to(Vector3(-3.5, 2.0, -9.5))
	assert_true(await _step_on_warp(Vector3(-2.5, 2.0, -9.5)), "on to the terrace")
	await _ring("terrace_bell")
	await _walk_into_goal()
	assert_true(await _cleared(), "jumped onto the rock with a teammate's jump")


# --- 6-2 霧の段丘 ----------------------------------------------------------------


func _door_is_open(key: String) -> bool:
	for door in MechanismSet.of(w).doors:
		if door.spec.key == key:
			return door.is_open()
	return false


## 門を抜けて、階段から段丘へ上がり、ゴールへ。
func _through_the_mist_gate() -> void:
	await _walk_to(Vector3(3.5, 0.0, -4.6), 0.35, 120)
	await _walk_to(Vector3(3.5, 1.0, -5.5))
	await _walk_to(Vector3(3.5, 2.0, -7.5))
	await _walk_into_goal()


## ひとりの道 1: 西の時の鐘を鳴らし、脇のワープの石で門の前へ移って、閉まる前に抜ける。
func test_misty_terraces_ring_and_warp() -> void:
	await _enter(World6Stages.MIST_ID)
	await _ring("mist_bell")
	assert_true(await _step_on_warp(Vector3(-21.5, 0.0, 6.5)), "warped to the gate")
	assert_true(_door_is_open("mist_gate"), "the gate is open while the bell rings")
	await _through_the_mist_gate()
	assert_true(await _cleared(), "rang, warped and slipped through")


## ひとりの道 2: 門の前から、岩棚のうさぎに「投げる」を投げて渡す。木の実で岩棚の鐘が鳴る間に抜ける。
func test_misty_terraces_bunny_rings_the_shelf_bell() -> void:
	await _enter(World6Stages.MIST_ID)
	await _walk_to(Vector3(3.5, 0.0, 0.5), 0.3)
	await _lend_by_throwing(_creature("mist_bunny"), _slot_of(THROW))
	assert_true(await _wait_until_rung("shelf_bell"), "the bunny's nut rang the shelf bell")
	await _through_the_mist_gate()
	assert_true(await _cleared(), "the bunny's wish opened the gate")


## 協力の近道: 仲間の W で W×2 なら、西の鐘から門まで走って間に合う（ワープを使わない）。
func test_misty_terraces_coop_double_speed_dash_to_the_gate() -> void:
	await _enter(World6Stages.MIST_ID)
	_gift_from_teammate(FORWARD)
	await _ring("mist_bell")
	await _walk_to(Vector3(3.5, 0.0, -0.5), 0.4, 240)
	assert_true(_door_is_open("mist_gate"), "still open when I got there")
	await _through_the_mist_gate()
	assert_true(await _cleared(), "ran there with W x2")


# --- 6-3 峰の鐘 ------------------------------------------------------------------


## 尾根の持ち上げ台で峰へ上がり、峰の鐘を鳴らす。
func _up_to_the_peak() -> void:
	await _walk_to(Vector3(24.5, 2.0, -12.5))
	await _lift_up("peak_lift", Vector3(10.5, 2.0, -12.5), Vector3(7.5, 4.0, -12.5))
	await _ring("peak_bell")


## 峰の西の縁から尖塔へ渡り（浮く・W×2）、尖塔の鐘を鳴らして、片道の石で峰へ戻り、ゴールへ。
func _spire_and_home() -> void:
	assert_true(
		await _leap_to(Vector3(-7.6, 4.0, -14.5), Vector3(-15.5, 1.0, -14.5)), "reached the spire"
	)
	await _ring("spire_bell")
	assert_true(await _step_on_warp(Vector3(-17.5, 1.0, -15.5)), "the spire's stone took me back")
	await _walk_into_goal()


## ひとりの道 1: こだま石をワープで東の島へ送り、うさぎの木の実でこだまの鐘を鳴らして跳ねる石で高台へ。
## 風船で尖塔へ。
func test_peak_bells_echo_stone_and_the_balloon() -> void:
	await _enter(World6Stages.PEAK_ID)
	await _walk_to(Vector3(3.4, 0.0, 8.5), 0.3)
	_lend(_block("echo_stone"), _slot_of(RIGHT), TriggerMode.Kind.REPEAT)
	await _wait_block_at("echo_stone", Vector3i(22, 0, 0), 1500)
	assert_true(await _step_on_warp(Vector3(9.5, 0.0, 8.5)), "warped to the east isle")
	await _walk_to(Vector3(22.5, 1.0, 0.5))
	await _lend_by_throwing(_creature("echo_bunny"), _slot_of(THROW))
	for i in 400:
		var high := _me().global_position.y > 2.2
		_face(Vector3(25.0, 2.0, 0.5))
		_me().move_intent = Vector2(0.0, 1.0) if high else Vector2.ZERO
		if _me().global_position.x > 23.6 and _me().is_on_floor():
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_true(w.activated.has("echo_bell"), "the bunny rang the echo bell")
	assert_gt(_me().global_position.y, 1.8, "the echo stone bounced me up")
	await _pick_to_hotbar(Vector3(28.5, 2.0, -8.5), FLOAT)
	await _up_to_the_peak()
	await _spire_and_home()
	assert_true(await _cleared(), "three bells with the echo stone and the balloon")


## ひとりの道 2: ワープで東の島へ渡り、島のブーツで高台へ。こだまの鐘は触って鳴らす。
func test_peak_bells_boots_on_the_isle() -> void:
	await _enter(World6Stages.PEAK_ID)
	assert_true(await _step_on_warp(Vector3(9.5, 0.0, 8.5)), "warped to the east isle")
	await _pick_and_wear(Vector3(21.5, 0.0, -3.5), RuleVessel.Part.FEET)
	await _walk_to(Vector3(24.0, 2.0, -2.5))
	await _ring("echo_bell")
	await _pick_to_hotbar(Vector3(28.5, 2.0, -8.5), FLOAT)
	await _up_to_the_peak()
	await _spire_and_home()
	assert_true(await _cleared(), "three bells with the boots and the balloon")


## 協力の近道: 仲間の W で W×2 なら、東の島へも尖塔へも走って跳べる（ワープと風船を使わない）。
func test_peak_bells_coop_double_speed_leaps() -> void:
	await _enter(World6Stages.PEAK_ID)
	_gift_from_teammate(FORWARD)
	assert_true(
		await _run_and_jump(
			Vector3(9.5, 0.0, 3.5), Vector3(12.9, 0.0, 3.5), Vector3(18.8, 0.0, 3.5)
		),
		"leapt to the east isle"
	)
	await _walk_to(Vector3(21.5, 0.0, 2.5))  # 島のワープの石（x 19）を踏まないように回る
	await _pick_and_wear(Vector3(21.5, 0.0, -3.5), RuleVessel.Part.FEET)
	await _walk_to(Vector3(24.0, 2.0, -2.5))
	await _ring("echo_bell")
	await _up_to_the_peak()
	await _spire_and_home()
	assert_true(await _cleared(), "leapt the gaps with W x2")


# --- 6-4 流れる川 ----------------------------------------------------------------


## 南の岸から、台地のうさぎへ「投げる」を投げて渡す（川越しに鐘を鳴らす）。
func _bunny_rings_across_the_river() -> void:
	await _walk_to(Vector3(-6.5, 0.0, 3.6), 0.3)
	await _lend_by_throwing(_creature("river_bunny"), _slot_of(THROW))
	assert_true(await _wait_until_rung("river_bell"), "the bunny rang the bell across the river")


## 船着き場から階段で台地へ上がり、ゴールへ。
func _landing_to_the_goal() -> void:
	await _walk_to(Vector3(9.5, 0.0, -5.5))
	await _walk_to(Vector3(9.5, 1.0, -6.5))
	await _walk_to(Vector3(9.5, 2.0, -8.5))
	await _walk_into_goal()


## ひとりの道 1: 足ひれ（泳ぐ）で川に入り、流されながら北へ泳いで船着き場へ。
func test_river_run_swim_with_the_current() -> void:
	await _enter(World6Stages.RIVER_ID)
	await _bunny_rings_across_the_river()
	await _pick_to_hotbar(Vector3(-8.5, 0.0, 6.5), SWIM)
	await _walk_to(Vector3(3.5, 0.0, 3.4), 0.3)
	assert_true(await _swim_to(Vector3(10.5, 0.0, -4.0)), "swam over to the landing")
	await _landing_to_the_goal()
	assert_true(await _cleared(), "swam the river")


## ひとりの道 2: 筏を川へ押し出して乗り、W を単発で渡して押すたびに 1 マス北へ。流されながら
## 船着き場の脇（堰の手前）まで行き、降りる。
func test_river_run_steer_the_raft() -> void:
	await _enter(World6Stages.RIVER_ID)
	await _bunny_rings_across_the_river()
	var raft := _block("raft")
	await _walk_to(Vector3(-3.5, 0.0, 5.0), 0.3)
	_lend(raft, _slot_of(FORWARD), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(FORWARD)
	await wait_physics_frames(90)
	assert_true(raft.afloat, "the raft floats")
	assert_true(await _board(raft), "stepped onto the raft")
	for i in 900:
		if raft.cell().z <= -2:
			break
		if not raft.is_moving_horizontally() and _slot_of(FORWARD) != -1:
			_lend(raft, _slot_of(FORWARD), TriggerMode.Kind.SINGLE_SHOT)
			w.press_action(FORWARD)
		await tree.physics_frame
	for i in 1800:
		if raft.cell().x >= 8:
			break
		await tree.physics_frame
	assert_gt(raft.cell().x, 7, "drifted alongside the landing")
	assert_true(w.ledger.player_can(FORWARD, _me().player_id), "the single shots came back")
	await _walk_to(Vector3(raft.global_position.x, 0.0, -3.6), 0.3)
	await _landing_to_the_goal()
	assert_true(await _cleared(), "rode the raft across")


## 協力の近道: 仲間の W で W×2 なら、川（幅 5）を船着き場へ走って跳べる。
func test_river_run_coop_double_speed_leap() -> void:
	await _enter(World6Stages.RIVER_ID)
	await _bunny_rings_across_the_river()
	_gift_from_teammate(FORWARD)
	assert_true(
		await _run_and_jump(
			Vector3(10.5, 0.0, 7.5), Vector3(10.5, 0.0, 3.1), Vector3(10.5, 0.0, -4.0)
		),
		"leapt the river"
	)
	await _landing_to_the_goal()
	assert_true(await _cleared(), "leapt over with W x2")


# --- 6-5 長い尾根 ----------------------------------------------------------------


func _gusts_blowing() -> bool:
	return w.nature.layout.winds[0].is_blowing(w.nature.clock)


## 風が止むのを待ってから、次の区間を歩く（止んでいる 2 秒の間に渡りきる）。
func _cross_in_the_lull(to: Vector3) -> void:
	for i in 600:
		if _gusts_blowing():
			break
		await tree.physics_frame
	for i in 600:
		if not _gusts_blowing():
			break
		await tree.physics_frame
	await _walk_to(to, 0.35, 150)


## 池の上の筏へ跳び移り、向こう岸へ跳ぶ。
func _hop_the_raft() -> void:
	await _jump_across(Vector3(0.5, 0.0, 8.3), Vector3(0.5, 0.0, 5.5))
	await _jump_across(Vector3(0.5, 0.0, 5.2), Vector3(0.5, 0.0, 1.6))


func _up_the_lookout() -> void:
	await _walk_to(Vector3(0.5, 1.0, -0.5))
	await _walk_to(Vector3(0.5, 2.0, -1.5))
	await _walk_to(Vector3(0.5, 3.0, -2.6))


func _ridge_finish(with_lift: bool) -> void:
	if with_lift:
		await _lift_up("ridge_lift", Vector3(1.5, 0.0, -14.5), Vector3(0.5, 2.0, -17.5))
	else:
		await _walk_to(Vector3(0.5, 2.0, -17.5))
	await _ring("ridge_bell")
	await _walk_into_goal()


## ひとりの道 1（持ち回り）: 重いで風の尾根を歩き、重いを外して泳いで池を渡り、風船で谷を越える。
func test_long_ridge_carry_the_gear() -> void:
	await _enter(World6Stages.RIDGE_ID)
	await _pick_to_hotbar(Vector3(-3.5, 0.0, 32.5), HEAVY)
	await _pick_up_here(Vector3(3.5, 0.0, 32.5))
	await _pick_up_here(Vector3(-3.5, 0.0, 36.5))
	await _walk_to(Vector3(0.5, 0.0, 29.6))
	await _walk_to(Vector3(0.5, 0.0, 13.0))
	assert_true(BodyTraits.is_heavy(w.ledger, _me().player_id), "heavy all along the ridge")
	_to_inventory(HEAVY)
	_to_hotbar(SWIM)
	await _walk_to(Vector3(0.5, 0.0, 8.3))
	assert_true(await _swim_to(Vector3(0.5, 0.0, 1.5)), "swam the pond")
	await _up_the_lookout()
	_to_inventory(SWIM)
	_to_hotbar(FLOAT)
	assert_true(
		await _leap_to(Vector3(0.5, 3.0, -3.7), Vector3(0.5, 0.0, -13.5)), "floated over the gap"
	)
	await _ridge_finish(true)
	assert_true(await _cleared(), "swapped the gear section by section")


## ひとりの道 2（何も持たない）: 風の止む間に尾根を渡り、筏を跳び移り、追い風で谷を越える。
func test_long_ridge_lulls_raft_and_tailwind() -> void:
	await _enter(World6Stages.RIDGE_ID)
	await _walk_to(Vector3(0.5, 0.0, 29.6))
	await _cross_in_the_lull(Vector3(0.5, 0.0, 21.5))
	await _cross_in_the_lull(Vector3(0.5, 0.0, 13.0))
	await _hop_the_raft()
	await _up_the_lookout()
	assert_true(
		await _leap_to(Vector3(0.5, 3.0, -3.7), Vector3(0.5, 0.0, -13.5)), "the tailwind carried me"
	)
	await _ridge_finish(true)
	assert_true(await _cleared(), "timed the gusts and rode the tailwind")


## 協力の近道: 重いで尾根を歩き、外して筏と追い風で進み、ジャンプ×2 で最後の台地へ直接。
func test_long_ridge_coop_double_jump_at_the_end() -> void:
	await _enter(World6Stages.RIDGE_ID)
	await _pick_to_hotbar(Vector3(-3.5, 0.0, 32.5), HEAVY)
	await _walk_to(Vector3(0.5, 0.0, 29.6))
	await _walk_to(Vector3(0.5, 0.0, 13.0))
	_to_inventory(HEAVY)
	await _hop_the_raft()
	await _up_the_lookout()
	assert_true(
		await _leap_to(Vector3(0.5, 3.0, -3.7), Vector3(0.5, 0.0, -13.5)), "the tailwind carried me"
	)
	_gift_from_teammate(JUMP)
	await _ridge_finish(false)
	assert_true(await _cleared(), "a teammate's jump skipped the lift")
