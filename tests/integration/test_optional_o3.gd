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


# --- O3-3 札の苗床 ------------------------------------------------------------


## もぐらを小山の板へ上げてから能力を回収し（板の上にとどまる）、子どもの札をもぐらに預けて、子どもを巣へ。
func test_o3_3_sign_nursery_mole_holds_the_plate() -> void:
	await _enter("o3_3")
	await _walk_to(Vector3(2.5, 0.0, 5.5), 0.3)
	_give_creature("mole", [LEFT, JUMP])
	assert_true(await _wait_open("gate_1", 900), "the mole climbed onto the knoll plate")
	await _walk_to(Vector3(4.5, 0.0, 4.6), 0.3)
	await _recall_creature("mole")
	await wait_physics_frames(120)
	assert_true(_door("gate_1").is_open(), "the mole stays on the plate without abilities")
	await _walk_route([Vector3(-0.5, 0.0, 0.5), Vector3(-0.5, 0.0, -8.5)])
	await _walk_to(Vector3(0.5, 0.0, -16.5), 0.3)
	_recall_creature_bans("kit")
	assert_true(w.ledger.player_prohibited(JUMP, _me().player_id), "the kit's sign came to me")
	await _walk_route([Vector3(-0.5, 0.0, -6.5), Vector3(-0.5, 0.0, 0.5), Vector3(4.5, 0.0, 4.6)])
	_hand_off_ban(JUMP, _creature("mole"))
	await _walk_route([Vector3(-0.5, 0.0, 0.5), Vector3(-0.5, 0.0, -8.5), Vector3(0.5, 0.0, -16.5)])
	_give_creature("kit", [RIGHT, JUMP])
	assert_true(await _creature_home("kit", OptionalWorldsO3.NURSERY_NEST), "the kit went home")
	# 子どもが踏んで開けた扉 2 は、自分が板を踏むと閉じる。踏み直して開ける
	await _walk_to(Vector3(-0.5, 0.0, -20.8), 0.2)
	assert_true(_door("gate_2").is_open(), "the kit opened gate 2 on its way")
	await _walk_to(Vector3(-0.5, 0.0, -21.6), 0.2)
	assert_true(
		await _wait(func() -> bool: return not _door("gate_2").heading_open, 60),
		"my step on the plate flips gate 2 shut"
	)
	await _walk_to(Vector3(-0.5, 0.0, -20.6), 0.2)
	await _walk_to(Vector3(-0.5, 0.0, -21.6), 0.2)
	assert_true(await _wait_open("gate_2"), "stepping on it again opens gate 2")
	await _walk_route([Vector3(-0.5, 0.0, -26.5), Vector3(2.5, 0.0, -28.6)])
	await _recall_creature("kit")
	await _walk_into_goal(
		[Vector3(-5.5, 0.0, -33.0), Vector3(-5.5, 1.0, -33.5), Vector3(-5.5, 2.0, -35.5)]
	)
	assert_true(await _cleared(), "cleared the sign nursery")


## 生き物に付いている札（禁止）を F で回収する（届く所に立っている前提）。
func _recall_creature_bans(key: String) -> void:
	var critter := _creature(key)
	w.interact(critter)
	assert_true(w.ledger.tokens_on(critter.entity_id).is_empty(), "took the sign off %s" % key)


# --- O3-4 凍った池 ------------------------------------------------------------


## おもりをかばんに入れて川を泳いで渡り、霜の箱の札を外しておもりを渡し、6 回押して板に止める。
func test_o3_4_frozen_pond_swim_then_slide() -> void:
	await _enter("o3_4")
	await _pick(Vector3(-5.5, 1.0, 6.5), SWIM)
	await _pick_to_bag(Vector3(5.5, 1.0, 6.5))
	assert_eq(_slot_of(HEAVY), -1, "the weight stays in the bag while swimming")
	await _walk_to(Vector3(-6.5, 1.0, 4.5), 0.3)
	var landed := false
	for i in 1200:
		var at := _me().global_position
		_me().move_intent = _steer(Vector3(at.x, at.y, -12.0))
		if at.z < -5.6 and not _me().is_on_floor():
			w.press_action(JUMP)
		if at.z < -6.9 and _me().is_on_floor() and at.y > 0.9:
			landed = true
			break
		if at.y < -5.0:
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_true(landed, "swam across the river (%s)" % _me().global_position)
	await _walk_to(Vector3(5.5, 1.0, -7.4), 0.3)
	await _rim_walk(Vector3(0.5, 1.0, -7.6))
	await _recall_all_from("frost_box")
	await _rim_walk(Vector3(3.6, 1.0, -13.6))
	await _walk_to(Vector3(4.5, 1.0, -14.0), 0.3)
	_hand_off_ban(BACK, _creature("bunny"))
	_bag_to_hotbar(HEAVY)
	await _rim_walk(Vector3(0.5, 1.0, -7.6))
	var crate := _block("frost_box")
	_give(crate, HEAVY, TriggerMode.Kind.NONE)
	var pushes: Array = [
		[FORWARD, Vector3(0.5, 1.0, -7.6), Vector3i(0, 0, -12)],
		[RIGHT, Vector3(-2.6, 1.0, -11.5), Vector3i(2, 0, -12)],
		[FORWARD, Vector3(3.6, 1.0, -11.5), Vector3i(2, 0, -13)],
		[LEFT, Vector3(3.6, 1.0, -12.5), Vector3i(1, 0, -13)],
		[BACK, Vector3(1.5, 1.0, -13.6), Vector3i(1, 0, -10)],
		[LEFT, Vector3(1.5, 1.0, -7.6), Vector3i(0, 0, -10)],
	]
	for push: Array in pushes:
		await _rim_walk(push[1] as Vector3)
		var cell := await _touch_push("frost_box", push[0] as RuleAction.Kind)
		assert_eq(cell, push[2] as Vector3i, "slid to %s" % push[2])
	assert_true(await _wait_open("garden_gate"), "the heavy box on the plate opened the gate")
	await _rim_walk(Vector3(3.6, 1.0, -15.0))
	_give_creature("bunny", [RIGHT, JUMP])
	assert_true(await _creature_home("bunny", OptionalWorldsO3.FROST_NEST), "the bunny went home")
	await _walk_route([Vector3(-0.5, 1.0, -17.5), Vector3(-0.5, 1.0, -23.5)])
	await _walk_to(Vector3(3.5, 1.0, -25.6), 0.3)
	await _recall_creature("bunny")
	await _walk_into_goal(
		[Vector3(5.5, 1.0, -27.0), Vector3(5.5, 2.0, -27.5), Vector3(5.5, 3.0, -29.5)]
	)
	assert_true(await _cleared(), "cleared the frozen pond")


## 氷の池のまわりの縁（高さ 1）だけを歩いて target へ（池へ落ちない）。縁の角を順に通る。
func _rim_walk(target: Vector3) -> void:
	var corners: Array[Vector3] = [
		Vector3(-2.6, 1.0, -7.6), Vector3(3.6, 1.0, -7.6), Vector3(3.6, 1.0, -13.6), Vector3(-2.6, 1.0, -13.6)
	]
	var here := _me().global_position
	var near := 0
	for i in corners.size():
		if corners[i].distance_to(here) < corners[near].distance_to(here):
			near = i
	var far := 0
	for i in corners.size():
		if corners[i].distance_to(target) < corners[far].distance_to(target):
			far = i
	var i := near
	await _walk_to(corners[i], 0.3)
	while i != far:
		i = (i + 1) % corners.size()
		await _walk_to(corners[i], 0.3)
	await _walk_to(target, 0.3)


## 触って単発の移動を渡して押し、止まったセルを返す。
func _touch_push(key: String, action: RuleAction.Kind) -> Vector3i:
	var block := _block(key)
	_give(block, action, TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(action)
	var still := 0
	for i in 600:
		var moving := block.is_moving_horizontally() or not block.is_grounded()
		still = 0 if moving else still + 1
		if still > 20:
			break
		await tree.physics_frame
	return block.cell()


# --- O3-5 大温室 --------------------------------------------------------------


## 川を泳いで渡り、鉄の箱とおもりで扉を開け、灯りの箱を氷の池から水路へすべり落として筏の橋にする。
func test_o3_5_grand_greenhouse() -> void:
	await _enter("o3_5")
	await _pick(Vector3(-5.5, 1.0, 6.5), SWIM)
	await _pick_to_bag(Vector3(5.5, 1.0, 6.5))
	await _walk_to(Vector3(-6.5, 1.0, 4.5), 0.3)
	assert_true(await _swim_north(-6.9), "swam across the river")
	# 鉄の箱を板へ送り、重いを渡す
	var anvil := _block("anvil")
	await _walk_to(Vector3(-3.5, 1.0, -7.4), 0.3)
	_give(anvil, FORWARD, REPEAT)
	assert_true(await _wait_block_at("anvil", Vector3i(-4, 1, -12)), "the anvil is on the plate")
	await _walk_to(Vector3(-2.5, 1.0, -11.5), 0.3)
	await _recall_all_from("anvil")
	_bag_to_hotbar(HEAVY)
	_give(anvil, HEAVY, TriggerMode.Kind.NONE)
	assert_true(await _wait_open("garden_gate"), "the heavy anvil opened the gate")
	# 灯りの箱: 札を生き物に預け、浮くを渡して 6 回押す
	await _pick(Vector3(-5.5, 1.0, -20.5), FLOAT)
	var lantern := _block("lantern")
	await _walk_route([Vector3(-1.6, 1.0, -14.6), Vector3(5.6, 1.0, -14.6), Vector3(5.6, 1.0, -16.5)])
	await _recall_all_from("lantern")
	await _walk_route([Vector3(5.6, 1.0, -14.6), Vector3(4.5, 1.0, -11.0)])
	_hand_off_ban(LEFT, _creature("elder"))
	await _walk_route([Vector3(5.6, 1.0, -14.6), Vector3(5.6, 1.0, -16.5)])
	_give(lantern, FLOAT, TriggerMode.Kind.NONE)
	var pushes: Array = [
		[BACK, [Vector3(5.6, 1.0, -16.5)], Vector3i(4, 0, -16)],
		[LEFT, [Vector3(5.6, 1.0, -15.5)], Vector3i(3, 0, -16)],
		[FORWARD, [Vector3(5.6, 1.0, -14.6), Vector3(3.5, 1.0, -14.6)], Vector3i(3, 0, -20)],
		[
			RIGHT,
			[Vector3(-1.6, 1.0, -14.6), Vector3(-1.6, 1.0, -21.6), Vector3(3.5, 1.0, -21.6)],
			Vector3i(4, 0, -20)
		],
		[BACK, [Vector3(4.5, 1.0, -21.6)], Vector3i(4, 0, -19)],
		[RIGHT, [Vector3(5.6, 1.0, -21.6), Vector3(5.6, 1.0, -20.4)], Vector3i(6, 0, -19)],
	]
	for push: Array in pushes:
		var route: Array[Vector3] = []
		route.assign(push[1] as Array)
		await _walk_route(route)
		var cell := await _touch_push("lantern", push[0] as RuleAction.Kind)
		assert_eq(cell, push[2] as Vector3i, "slid to %s" % push[2])
	assert_true(await _wait_block_at("lantern", Vector3i(6, 0, -9), 1800), "the raft docked")
	await _walk_route([Vector3(5.6, 1.0, -21.6), Vector3(-1.6, 1.0, -21.6), Vector3(-1.6, 1.0, -14.6)])
	await _walk_to(Vector3(4.5, 1.0, -11.0), 0.3)
	_give_creature("elder", [RIGHT, JUMP])
	assert_true(
		await _creature_home("elder", OptionalWorldsO3.GREENHOUSE_NEST), "the elder went home"
	)
	await _walk_route(
		[
			Vector3(5.6, 1.0, -14.6),
			Vector3(-1.6, 1.0, -14.6),
			Vector3(-1.6, 1.0, -22.5),
			Vector3(-0.5, 1.0, -23.5),
			Vector3(-0.5, 1.0, -30.5),
		]
	)
	await _walk_into_goal()
	assert_true(await _cleared(), "cleared the grand greenhouse")


## 川を北へ泳ぐ（流されながら）。北の岸（z が bank より北）に上がれたら true。
func _swim_north(bank: float) -> bool:
	for i in 1200:
		var at := _me().global_position
		_me().move_intent = _steer(Vector3(at.x, at.y, bank - 6.0))
		if at.z < bank + 1.3 and not _me().is_on_floor():
			w.press_action(JUMP)
		if at.z < bank and _me().is_on_floor() and at.y > 0.9:
			_me().move_intent = Vector2.ZERO
			return true
		if at.y < -5.0:
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	return false
