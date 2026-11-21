extends "res://tests/integration/optional_playthrough.gd"
## 寄り道 O3「ひみつの温室」の抜け道と詰みを、プレイヤーと同じ操作で壊しにいく（敵対的な試遊）。
## - test_gate_*: 守られている関所 / test_accepted_*: 残してよい技 / test_finding_*: いまはそのままの挙動

const SINGLE := TriggerMode.Kind.SINGLE_SHOT
const REPEAT := TriggerMode.Kind.REPEAT


## 苗の箱を板の方（西）へ押すと、板を通りすぎて柱まですべる（すぐ隣でも止まらない）。札があると西へは押せない。
func test_gate_o3_1_the_obvious_push_slides_past_the_plate() -> void:
	await _enter("o3_1")
	await _walk_route([Vector3(9.5, 1.0, -1.5), Vector3(7.5, 1.0, -8.5)])
	var box := _block("seed_box")
	_give(box, LEFT, SINGLE)
	w.press_action(LEFT)
	await wait_physics_frames(60)
	assert_eq(box.cell(), Vector3i(5, 0, -9), "the A ban keeps it in place")
	await _recall_all_from("seed_box")
	await _walk_to(Vector3(7.5, 1.0, -10.6), 0.3)
	_hand_off_ban(LEFT, _creature("bunny"))
	await _walk_to(Vector3(7.5, 1.0, -8.5), 0.3)
	_give(box, LEFT, SINGLE)
	w.press_action(LEFT)
	await _wait(func() -> bool: return not box.is_moving_horizontally(), 30)
	await wait_physics_frames(60)
	assert_ne(box.cell(), Vector3i(4, 0, -9), "it slid past the plate")
	assert_false(_door("garden_gate").is_open(), "the gate stays shut")


## ジャンプを手放した（生き物に渡した）まま氷の池に落ちると、1 段上の縁へ上がれない。やり直しが要る。
func test_finding_o3_1_the_pond_holds_you_without_a_jump() -> void:
	await _enter("o3_1")
	await _walk_route([Vector3(9.5, 1.0, -1.5), Vector3(7.5, 1.0, -10.6)])
	_give_creature("bunny", [JUMP])
	await _walk_to(Vector3(5.5, 0.0, -6.5), 0.4, 240)
	assert_false(
		await _try_walk_to(Vector3(7.8, 1.0, -6.5), 0.4, 300),
		"FINDING: cannot climb out of the pond"
	)


## 筏に W を繰り返しで渡すと、流れで運ばれている途中の周期も予約されるので、北へ漕ぎ進める
## （2026-11-21 本人の判断「繰り返しの時も予約に」で finding から accepted へ。以前は z -3 までしか進めなかった）。
## 単発で漕ぐ解法も残る。新しい道として認める（関所ではない）。
func test_accepted_o3_2_repeat_rows_against_the_drift() -> void:
	await _enter("o3_2")
	await _pick(Vector3(2.5, 0.0, 6.5), FLOAT)
	var planter := _block("planter")
	await _walk_to(Vector3(-5.5, 0.0, 1.5), 0.3)
	_give(planter, FLOAT, TriggerMode.Kind.NONE)
	_give(planter, FORWARD, REPEAT)
	await _wait(func() -> bool: return planter.cell().z <= -1, 300)
	var furthest := 0
	for i in 600:
		furthest = mini(furthest, planter.cell().z)
		await tree.physics_frame
	assert_lt(
		furthest, -3, "ACCEPTED: the buffered repeat W beats the drift (reached z %d)" % furthest
	)


## 泳ぐが無ければ、水路に入ると沈む（落ちたのと同じ）。
func test_gate_o3_2_the_canal_is_bottomless_without_a_raft() -> void:
	await _enter("o3_2")
	assert_false(await _walk_without_falling(Vector3(-2.5, 0.0, -7.5)), "sank into the canal")
	await _wait_respawn()


## 子どもの札を先にもぐらへ渡すと、もぐらは小山へ跳べない（順番が大事）。
func test_gate_o3_3_banning_the_mole_first_keeps_it_down() -> void:
	await _enter("o3_3")
	await _walk_to(Vector3(2.5, 0.0, 5.5), 0.3)
	_give_creature("mole", [LEFT])
	await wait_physics_frames(60)
	assert_false(_door("gate_1").is_open(), "a mole without a jump stays at the foot")
	_give_creature("mole", [JUMP])
	assert_true(await _wait_open("gate_1", 900), "with the jump it climbs (the order matters)")


## 札の付いた子どもは、ジャンプを渡しても巣の段々を上がれない。
func test_gate_o3_3_the_signed_kit_cannot_climb() -> void:
	await _enter("o3_3")
	await _walk_to(Vector3(2.5, 0.0, 5.5), 0.3)
	_give_creature("mole", [LEFT, JUMP])
	await _wait_open("gate_1", 900)
	await _walk_to(Vector3(4.5, 0.0, 4.6), 0.3)
	await _recall_creature("mole")
	await _walk_route([Vector3(-0.5, 0.0, 0.5), Vector3(-0.5, 0.0, -8.5), Vector3(0.5, 0.0, -16.5)])
	_give(_creature("kit"), RIGHT, TriggerMode.Kind.NONE)
	_give(_creature("kit"), JUMP, TriggerMode.Kind.NONE)
	assert_false(
		await _wait_creature_in("kit", OptionalWorldsO3.NURSERY_NEST, 900), "the sign keeps it down"
	)


## 重いをホットバーに置いたまま泳ぐと沈む。
func test_gate_o3_4_heavy_sinks_a_swimmer() -> void:
	await _enter("o3_4")
	await _pick(Vector3(-5.5, 1.0, 6.5), SWIM)
	await _pick(Vector3(5.5, 1.0, 6.5), HEAVY)
	await _walk_to(Vector3(-6.5, 1.0, 4.5), 0.3)
	assert_false(await _walk_without_falling(Vector3(-6.5, 1.0, -8.0)), "sank with the weight")
	await _wait_respawn()


## 持ち上げ＋自分のジャンプでも、幅 10 の川は跳び越えられない。
func test_gate_o3_4_the_river_is_not_jumped() -> void:
	await _enter("o3_4")
	await _walk_to(Vector3(0.5, 1.0, 4.4), 0.2)
	var landed := await _lift_jump_toward(Vector3i(0, 0, 4), Vector3(0.5, 1.0, -10.0))
	assert_lt(landed.y, 0.0, "fell into the river (%s)" % landed)
	await _wait_respawn()


## 浮くを渡さずに灯りの箱を水路へすべり落とすと、沈んで元の場所へ戻る（詰まない）。
func test_gate_o3_5_a_lantern_without_float_sinks_and_comes_home() -> void:
	await _enter("o3_5")
	await _pick(Vector3(-5.5, 1.0, 6.5), SWIM)
	await _walk_to(Vector3(-6.5, 1.0, 4.5), 0.3)
	for i in 1200:
		var at := _me().global_position
		_me().move_intent = _steer(Vector3(at.x, at.y, -13.0))
		if at.z < -5.6 and not _me().is_on_floor():
			w.press_action(JUMP)
		if at.z < -6.9 and _me().is_on_floor() and at.y > 0.9:
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	await _walk_route(
		[Vector3(-1.6, 1.0, -14.6), Vector3(5.6, 1.0, -14.6), Vector3(5.6, 1.0, -16.5)]
	)
	await _recall_all_from("lantern")
	await _walk_route([Vector3(5.6, 1.0, -14.6), Vector3(4.5, 1.0, -11.0)])
	_hand_off_ban(LEFT, _creature("elder"))
	var lantern := _block("lantern")
	var pushes: Array = [
		[BACK, [Vector3(5.6, 1.0, -14.6), Vector3(5.6, 1.0, -16.5)]],
		[LEFT, [Vector3(5.6, 1.0, -15.5)]],
		[FORWARD, [Vector3(5.6, 1.0, -14.6), Vector3(3.5, 1.0, -14.6)]],
		[RIGHT, [Vector3(-1.6, 1.0, -14.6), Vector3(-1.6, 1.0, -21.6), Vector3(3.5, 1.0, -21.6)]],
		[BACK, [Vector3(4.5, 1.0, -21.6)]],
		[RIGHT, [Vector3(5.6, 1.0, -21.6), Vector3(5.6, 1.0, -20.4)]],
	]
	for push: Array in pushes:
		var route: Array[Vector3] = []
		route.assign(push[1] as Array)
		await _walk_route(route)
		_give(lantern, push[0] as RuleAction.Kind, SINGLE)
		w.press_action(push[0] as RuleAction.Kind)
		await _wait(func() -> bool: return not lantern.is_moving_horizontally(), 30)
		await wait_physics_frames(40)
	assert_true(
		await _wait_block_at("lantern", Vector3i(4, 0, -17), 900), "it sank and came back home"
	)
