extends "res://tests/integration/timed_bells_play.gd"
## 「鳴りつづける鐘」（2-5）の関所と詰みを、プレイヤーと同じ操作で壊しにいく試遊（2026-11-21）。
## 書き方は test_island_probes.gd と同じ。部品は timed_bells_play.gd。
## 関所は幅 10 の谷（z = -13〜-4）。時の鐘が鳴っている間だけ橋がせり上がる。鳴らさずに渡れないこと、
## 鐘 1 回では石も生き物も足りないこと、橋から落ちても・取り残されても詰まないことを確かめる。

## 北の台地の南の縁（z）。ここより北で台地の高さに立てたら「渡った」。
const FAR_EDGE_Z := -13.0
## 鐘の段の縁（z = -3）の手前で跳ぶ位置。
const JUMP_AT_EDGE := -2.85


## 鐘を鳴らさなければ橋は谷の底に沈んだまま。鐘の段の縁から全力で走って跳んでも（橋の列でも、ほかの列でも）
## 谷は越えない。
func test_gate_no_bell_no_bridge_and_the_chasm_is_not_a_running_jump() -> void:
	await _enter(STAGE_ID)
	await _climb_to_the_terrace()
	await wait_physics_frames(60)
	assert_true(_bridge_down(), "the bridge stays down without the bell")
	for x: float in [1.0, -4.5]:
		var farthest := await _leap_north(Vector3(x, 2.0, -0.5), JUMP_AT_EDGE)
		assert_gt(farthest, FAR_EDGE_Z + 0.5, "running jump at x = %.1f falls short" % x)
		await _wait_respawn()
		await _climb_to_the_terrace()
	assert_false(w.activated.has(BELL), "the bell never rang")


## 受け入れた重ね跳び（足もとのセルの上昇＋自分のジャンプ）でも、谷の幅 10 は越えない（同じ高さへ約 8.4 m、
## 向こうは 2 段高い）。
func test_gate_stacked_jump_falls_short_of_the_far_plateau() -> void:
	await _enter(STAGE_ID)
	await _climb_to_the_terrace()
	await _walk_to(Vector3(-4.5, 2.0, -2.5), 0.2)
	_lend(w.terrain_target(Vector3i(-5, 1, -3)), _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	var pressed := false
	var farthest := 0.0
	for i in 300:
		if not pressed and w.ledger.player_can(JUMP, _me().player_id) and _me().is_on_floor():
			if _me().global_position.y > 2.05:
				w.press_action(JUMP)
				pressed = true
		_me().view_yaw = 0.0
		_me().move_intent = Vector2(0.0, 1.0) if _me().global_position.y > 2.3 else Vector2.ZERO
		if _me().global_position.y > 1.5:
			farthest = minf(farthest, _me().global_position.z)
		if _me().global_position.y < -3.0:
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	print(
		(
			"    timed_bells: stacked jump reached z = %.2f (far plateau at %.1f)"
			% [farthest, FAR_EDGE_Z]
		)
	)
	assert_true(pressed, "jumped on the rising cell")
	assert_gt(farthest, FAR_EDGE_Z + 0.5, "short of the far plateau")
	await _wait_respawn()
	assert_false(w.activated.has(BELL), "the bell never rang")


## 鐘 1 回（5 秒）では、石は 3 マスしか歩かず、生き物が探す 8 マスにも入らない。生き物は浜で待つ。
func test_gate_one_ring_is_not_enough_for_the_stone() -> void:
	await _enter(STAGE_ID)
	await _give_kit_a_move()
	await _climb_to_the_terrace()
	await _walk_to(BY_THE_BELL, 0.3)
	await _ring_here()
	await wait_physics_frames(420)
	assert_false(_bell().is_ringing(), "the bell went quiet")
	assert_eq(_block("walking_stone").cell(), Vector3i(2, 0, 1), "three steps in one ring")
	assert_lt(await _creature_top("kit", 180), 0.6, "the kit is still waiting on the shore")


## 発射台が最初の列のままでは、玉は時の鐘に当たらない。
func test_gate_launcher_misses_from_its_starting_spot() -> void:
	await _enter(STAGE_ID)
	await _climb_to_the_terrace()
	var launcher := _block("launcher")
	await _walk_to(launcher.global_position + Vector3(-1.5, -0.5, 0.0), 0.3)
	_lend(launcher, _slot_of(THROW), TriggerMode.Kind.NONE)
	assert_false(await _wait_until_rung(BELL, 360), "the shots miss the timed bell")
	assert_true(_bridge_down(), "so the bridge stays down")


## 詰みの試し: 鐘 1 回だけで生き物を橋に乗せると、渡りきる前に橋が沈んで落ちる。生き物は元の場所に戻され、
## 渡した移動は手元に戻る（もう一度やり直せる）。
func test_softlock_the_kit_falls_from_a_short_ring_and_comes_home() -> void:
	await _enter(STAGE_ID)
	var kit := _creature("kit")
	var home := kit.global_position
	await _give_kit_a_move()
	await _push_the_stone_by_hand()
	for i in 900:
		if kit.global_position.y > 1.9 and kit.is_on_floor():
			break
		await tree.physics_frame
	assert_gt(kit.global_position.y, 1.9, "the kit climbed the stone onto the bell terrace")
	await _climb_to_the_terrace()
	await _walk_to(BY_THE_BELL, 0.3)
	await _ring_here()
	var deepest := kit.global_position.y
	var farthest := kit.global_position.z
	for i in 900:
		deepest = minf(deepest, kit.global_position.y)
		farthest = minf(farthest, kit.global_position.z)
		if deepest < -5.0 and kit.global_position.distance_to(home) < 0.5:
			break
		await tree.physics_frame
	print("    timed_bells: the kit got to z = %.2f on one ring" % farthest)
	assert_lt(deepest, -5.0, "the kit fell when the bridge sank")
	assert_gt(farthest, FAR_EDGE_Z, "it never reached the far plateau")
	assert_lt(kit.global_position.distance_to(home), 0.5, "the kit was put back home")
	assert_ne(_ready_slot(RIGHT), -1, "my move came back to me")
	assert_eq(_block("walking_stone").cell(), STONE_REST, "the stone is still in place")


## 詰みの試し: 橋の上で鳴りやむと、橋といっしょに谷へ落ちる。谷の底には立てず、南で復活する。
func test_softlock_standing_on_the_bridge_when_it_sinks_respawns_south() -> void:
	await _enter(STAGE_ID)
	await _climb_to_the_terrace()
	await _walk_to(BRIDGE_FOOT, 0.3)
	await _ring_here()
	for i in 120:
		if _bridge_up():
			break
		await tree.physics_frame
	await _walk_to(Vector3(1.0, 3.0, -9.0), 0.4)
	var lowest := _me().global_position.y
	for i in 600:
		lowest = minf(lowest, _me().global_position.y)
		if lowest < -3.0:
			break
		await tree.physics_frame
	assert_lt(lowest, -3.0, "fell with the sinking bridge")
	await _wait_respawn()
	assert_gt(_me().global_position.z, -3.0, "back on the south side")


## 生き物を連れずに走って渡っても、クリアにならない。北に取り残されても、谷へ降りれば南で復活する
## （北にチェックポイントは無い）。
func test_softlock_alone_on_the_far_side_is_no_clear_and_the_chasm_brings_you_back() -> void:
	await _enter(STAGE_ID)
	await _climb_to_the_terrace()
	await _race_across()
	await _walk_into_goal()
	assert_false(await _cleared(120), "everyone at the goal, but the kit is not home")
	for i in 600:
		if _bridge_down():
			break
		await tree.physics_frame
	await _walk_to(Vector3(1.0, 4.0, -13.5), 0.3)
	_me().view_yaw = PI
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(60)
	_me().move_intent = Vector2.ZERO
	await _wait_respawn()
	assert_gt(_me().global_position.z, -3.0, "respawned on the south side")


## 石を繰り返しで押して島の外へ落としても、元の場所へ戻される。信号の能力も付いたまま（詰まない）。
func test_softlock_stone_pushed_off_the_island_comes_back() -> void:
	await _enter(STAGE_ID)
	var stone := _block("walking_stone")
	var start := stone.cell()
	# 石の東に立つ（南に立つと、自分が石の行く手をふさぐ）
	await _walk_to(stone.global_position + Vector3(1.5, -0.5, 0.0), 0.3)
	_lend(stone, _slot_of(BACK), TriggerMode.Kind.REPEAT)
	var lowest := stone.global_position.y
	for i in 1200:
		lowest = minf(lowest, stone.global_position.y)
		if lowest < -2.0 and stone.cell() == start:
			break
		await tree.physics_frame
	assert_lt(lowest, -2.0, "slid off the south edge")
	assert_eq(stone.cell(), start, "put back where it started")
	assert_eq(w.ledger.tokens_on(stone.entity_id).size(), 1, "its signal is still on it")
	assert_ne(_slot_of(BACK), -1, "my S came back to me")


## 鐘の段から北へ全力で走り、縁（z = -3）の手前 jump_at で跳ぶ。地面より上にいた間の最も北の z を返す。
func _leap_north(start: Vector3, jump_at: float) -> float:
	await _walk_to(start, 0.25)
	_me().view_yaw = 0.0
	_me().move_intent = Vector2(0.0, 1.0)
	var farthest := _me().global_position.z
	var jumped := false
	for i in 300:
		if not jumped and _me().global_position.z <= jump_at and _me().is_on_floor():
			w.press_action(JUMP)
			jumped = true
		if _me().global_position.y > 1.5:
			farthest = minf(farthest, _me().global_position.z)
		if _me().global_position.y < -3.0:
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	return farthest
