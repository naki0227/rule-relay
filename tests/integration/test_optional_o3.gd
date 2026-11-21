extends "res://tests/integration/optional_playthrough.gd"
## 寄り道 O3「ひみつの温室」を、想定の解き方でひとりで最初から最後まで遊ぶ（通しプレイ）。
## 操作はプレイヤーと同じ（歩く・跳ぶ・渡す・拾う・F・キーを押す）だけで、瞬間移動はしない。
## 抜け道と詰みの試遊は test_optional_o3_probes.gd。

const REPEAT := TriggerMode.Kind.REPEAT
const SINGLE := TriggerMode.Kind.SINGLE_SHOT

# --- O3-1 氷の温室 ------------------------------------------------------------


## 箱の A 禁止を生き物に預け、「投げる」で池の縁から 7 回押して、箱を板の上に止める。
func test_o3_1_ice_greenhouse_by_reading_the_slides() -> void:
	await _enter("o3_1")
	await _pick(Vector3(-5.5, 1.0, 4.5), THROW)
	await _walk_route([Vector3(9.5, 1.0, -1.5), Vector3(7.5, 1.0, -8.5)])
	await _recall_all_from("seed_box")
	assert_true(w.ledger.player_prohibited(LEFT, _me().player_id), "the A ban came to me")
	await _walk_to(Vector3(7.5, 1.0, -10.6), 0.3)
	_hand_off_ban(LEFT, _creature("bunny"))
	await _walk_to(Vector3(7.5, 1.0, -7.5), 0.3)
	var expected: Array[Vector3i] = [
		Vector3i(5, 0, -7),
		Vector3i(3, 0, -7),
		Vector3i(3, 0, -4),
		Vector3i(2, 0, -4),
		Vector3i(2, 0, -6),
		Vector3i(4, 0, -6),
		Vector3i(4, 0, -9),
	]
	var moves: Array[RuleAction.Kind] = [BACK, LEFT, BACK, LEFT, FORWARD, RIGHT, FORWARD]
	for i in moves.size():
		var cell := await _throw_push("seed_box", moves[i])
		assert_eq(cell, expected[i], "push %d slid to %s" % [i + 1, expected[i]])
	assert_true(await _wait_open("garden_gate"), "the box on the plate opened the gate")
	await _walk_to(Vector3(6.5, 1.0, -10.6), 0.3)
	_give_creature("bunny", [RIGHT, JUMP])
	assert_true(await _creature_home("bunny", OptionalWorldsO3.ICE_NEST), "the bunny went home")
	await _walk_route([Vector3(4.5, 1.0, -10.6), Vector3(4.0, 1.0, -11.5), Vector3(4.0, 1.0, -17.5)])
	await _walk_to(Vector3(2.5, 1.0, -17.6), 0.3)
	await _recall_creature("bunny")
	await _walk_into_goal(
		[Vector3(9.5, 1.0, -26.5), Vector3(9.5, 2.0, -27.5), Vector3(9.5, 3.0, -29.5)]
	)
	assert_true(await _cleared(), "cleared the ice greenhouse")


# --- O3-2 水路の花壇 ----------------------------------------------------------


## 植木箱を筏にして単発の W で漕いで渡り、北の箱の札（W 禁止）を生き物に預け、戻ってきた浮くで
## 小さな水路に筏の橋を架ける。
func test_o3_2_canal_garden_by_raft() -> void:
	await _enter("o3_2")
	await _pick(Vector3(2.5, 0.0, 6.5), FLOAT)
	var planter := _block("planter")
	await _walk_to(Vector3(-5.5, 0.0, 1.5), 0.3)
	await _walk_to(planter.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	_give(planter, FLOAT, TriggerMode.Kind.NONE)
	var crossed := false
	for i in 1800:
		var p := planter.global_position
		if planter.cell().z <= -5:
			crossed = true
			break
		if _me().global_position.y < -1.0:
			break
		var still := not planter.is_moving_horizontally() and planter.is_grounded()
		if still and w.ledger.player_can(FORWARD, _me().player_id):
			_give(planter, FORWARD, SINGLE)
			w.press_action(FORWARD)
		# 筏の上にとどまる（流れて東へ動く筏を追う）
		var flat := Vector3(p.x - _me().global_position.x, 0.0, p.z - _me().global_position.z)
		_me().move_intent = _steer(p) if flat.length() > 0.25 else Vector2.ZERO
		await tree.physics_frame
	assert_true(crossed, "rowed the raft across the canal")
	await _walk_to(Vector3(planter.global_position.x, 0.0, -7.0), 0.4)
	assert_almost(_me().global_position.y, 0.0, 0.2, "jumped onto the north bank")
	await _recall_all_from("planter")  # 岸から筏に触って浮くを取り戻す（筏は沈んで元の場所へ戻る）
	assert_true(w.ledger.player_can(FLOAT, _me().player_id), "the balloon came back")
	await _walk_to(Vector3(-6.5, 0.0, -10.5), 0.3)
	await _recall_all_from("stepping")
	assert_true(w.ledger.player_prohibited(FORWARD, _me().player_id), "the W ban came to me")
	await _walk_to(Vector3(0.5, 0.0, -8.0), 0.3)
	_hand_off_ban(FORWARD, _creature("lamb"))
	await _walk_to(Vector3(-7.5, 0.0, -10.5), 0.3)
	var stepping := _block("stepping")
	_give(stepping, FLOAT, TriggerMode.Kind.NONE)
	_give(stepping, FORWARD, SINGLE)
	w.press_action(FORWARD)
	assert_true(
		await _wait_block_at("stepping", Vector3i(4, -1, -13), 1800), "the raft bridges the moat"
	)
	await _walk_to(Vector3(1.5, 0.0, -10.0), 0.3)
	_give_creature("lamb", [RIGHT, JUMP])
	assert_true(await _creature_home("lamb", OptionalWorldsO3.CANAL_NEST), "the lamb went home")
	await _walk_to(Vector3(4.5, 0.0, -11.5), 0.3)
	await _walk_to(Vector3(4.5, 0.0, -13.5), 0.3)
	await _walk_to(Vector3(5.5, 0.0, -14.4), 0.3)
	await _walk_to(Vector3(5.6, 0.0, -17.5), 0.3)
	await _recall_creature("lamb")
	await _walk_into_goal(
		[Vector3(5.5, 0.0, -20.5), Vector3(5.5, 1.0, -21.5), Vector3(5.5, 2.0, -23.5)]
	)
	assert_true(await _cleared(), "cleared the canal garden")
