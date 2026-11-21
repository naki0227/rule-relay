extends "res://tests/integration/optional_playthrough.gd"
## 寄り道 O1「からくり工房」を、想定の解き方でひとりで最初から最後まで遊ぶ（通しプレイ）。
## 操作はプレイヤーと同じ（歩く・跳ぶ・渡す・拾う・F・キーを押す）だけで、瞬間移動はしない。
## 抜け道と詰みの試遊は test_optional_o1_probes.gd。

const REPEAT := TriggerMode.Kind.REPEAT
const SINGLE := TriggerMode.Kind.SINGLE_SHOT
const SIGNAL := TriggerMode.Kind.SIGNAL

# --- O1-1 歯車の渡し ----------------------------------------------------------


## 箱に W を繰り返しで渡してから D を単発で押してワープへ送ると、箱は小島で北へ進んで板に乗る。
func test_o1_1_cog_crossing_by_sending_the_crate_with_its_tokens() -> void:
	await _enter("o1_1")
	await _pick(Vector3(-3.5, 0.0, 9.5), RIGHT)
	var cog := _block("cog")
	await _walk_to(Vector3(2.5, 0.0, 7.5))
	_give(cog, FORWARD, REPEAT)
	await wait_physics_frames(120)
	assert_eq(cog.cell(), Vector3i(3, 0, 6), "the bump keeps the crate on the south island")
	_give(cog, RIGHT, SINGLE)
	w.press_action(RIGHT)
	assert_true(await _wait_block_at("cog", Vector3i(13, 0, -1)), "the crate rode onto the plate")
	assert_true(await _wait_open("cog_gate"), "the gate opened")
	await _walk_to(Vector3(0.0, 0.0, 1.5))
	await _walk_to(Vector3(0.0, 0.0, -11.5))
	# 北の島: 板に乗ってから、生き物に D とジャンプを渡す
	await _walk_to(Vector3(-2.5, 0.0, -14.5), 0.25)
	_give_creature("wish", [RIGHT, JUMP])
	assert_true(
		await _wait(func() -> bool: return _door("nest_step").is_closed()),
		"the step stands up while I am on the plate"
	)
	assert_true(await _creature_home("wish", OptionalWorldsO1.COG_NEST), "the creature went home")
	await _recall_creature("wish")
	await _walk_into_goal(
		[Vector3(5.5, 0.0, -17.5), Vector3(5.5, 1.0, -18.5), Vector3(5.5, 2.0, -20.5)]
	)
	assert_true(await _cleared(), "cleared the cog crossing")


# --- O1-2 時計じかけの回廊 ----------------------------------------------------


## 箱を扉 A の戸口に入れて開けたままにし、あとで同じ箱を真ん中の島の板（重さ 2）へ送る。
func test_o1_2_clockwork_corridor_by_holding_the_doorway() -> void:
	await _enter("o1_2")
	await _pick(Vector3(6.5, 0.0, 15.5), LEFT)
	var cog_a := _block("cog_a")
	await _walk_to(Vector3(0.5, 0.0, 4.5))
	_give(cog_a, FORWARD, REPEAT)
	assert_true(await _wait_block_at("cog_a", Vector3i(0, 0, 1)), "the crate waits at the gate")
	await _ring("clock_a")
	assert_true(
		await _wait_block_at("cog_a", Vector3i(0, 0, 0)), "the crate stepped into the doorway"
	)
	await wait_physics_frames(240)
	assert_true(_door("gate_a").is_open(), "the gate cannot close on the crate")
	await _walk_to(Vector3(-0.5, 0.0, 3.5))
	await _walk_to(Vector3(-0.5, 0.0, -2.5))
	_lend_recall_w("cog_a")
	# 真ん中の島の箱を板の北の段まで送る
	var cog_b := _block("cog_b")
	await _walk_to(Vector3(0.5, 0.0, -6.5))
	_give(cog_b, FORWARD, REPEAT)
	assert_true(await _wait_block_at("cog_b", Vector3i(-1, 0, -12)), "cog_b stopped on the plate")
	await _walk_to(Vector3(0.5, 0.0, -11.5))
	await _recall_all_from("cog_b")
	# 戸口の箱を西へ 1 マス、そこから北へ
	await _walk_to(Vector3(0.5, 0.0, -2.5))
	_give(cog_a, LEFT, SINGLE)
	w.press_action(LEFT)
	assert_true(await _wait_block_at("cog_a", Vector3i(-1, 0, 0)), "cog_a moved to the west lane")
	_give(cog_a, FORWARD, REPEAT)
	assert_true(await _wait_block_at("cog_a", Vector3i(-1, 0, -11)), "cog_a is the second weight")
	assert_true(await _wait_open("gate_b"), "the scale opened gate B")
	await _walk_to(Vector3(0.5, 0.0, -10.5))
	await _recall_all_from("cog_a")
	await _walk_to(Vector3(2.5, 0.0, -13.0))
	_give_creature("kit", [LEFT, JUMP])
	assert_true(await _creature_home("kit", OptionalWorldsO1.CLOCK_NEST), "the kit went home")
	await _walk_route([Vector3(-0.5, 0.0, -16.0), Vector3(-0.5, 0.0, -20.5)])
	await _walk_to(Vector3(-3.5, 0.0, -20.6), 0.3)
	await _recall_creature("kit")
	await _walk_into_goal(
		[Vector3(4.5, 0.0, -24.0), Vector3(4.5, 1.0, -24.5), Vector3(4.5, 2.0, -26.5)]
	)
	assert_true(await _cleared(), "cleared the clockwork corridor")


## 戸口の箱に付いている W を回収する（箱は戸口に残り、扉は開いたまま）。
func _lend_recall_w(key: String) -> void:
	var block := _block(key)
	w.interact(block)
	assert_true(w.ledger.tokens_on(block.entity_id).is_empty(), "recalled the W from %s" % key)


# --- O1-3 重さくらべの秤 ------------------------------------------------------


## おもりで切り替えの扉を開け、発射台をワープで送って時の鐘を鳴らし続け、おもり付きの箱で板 2 を押す。
func test_o1_3_weighing_scale_with_the_weight_and_the_launcher() -> void:
	await _enter("o1_3")
	await _pick(Vector3(-5.5, 0.0, 10.5), HEAVY)
	await _walk_to(Vector3(2.5, 0.0, 3.5), 0.25)
	assert_true(await _wait_open("gate_1"), "the weight (4) opened gate 1")
	await _walk_to(Vector3(-0.5, 0.0, 2.5))
	assert_true(_door("gate_1").is_open(), "the toggle gate stays open")
	await _walk_to(Vector3(-0.5, 0.0, -6.5))
	await _pick(Vector3(-5.5, 0.0, -8.5), THROW)
	await _pick(Vector3(-6.5, 0.0, -14.5), LEFT)
	# 西の小島へ渡り、発射台を北の石へ押して真ん中の島へ送る
	assert_true(await _ride_warp(Vector3(4.5, 0.0, -11.5)), "warped west")
	await _walk_to(Vector3(-15.5, 0.0, -13.0), 0.3)
	var launcher := _block("launcher")
	_give(launcher, FORWARD, SINGLE)
	w.press_action(FORWARD)
	assert_true(
		await _wait_block_at("launcher", Vector3i(6, 0, -9)), "the launcher reached its spot"
	)
	assert_true(await _ride_warp(Vector3(-13.5, 0.0, -14.5)), "warped home")
	await _walk_to(Vector3(4.5, 0.0, -8.5), 0.4)
	_give(launcher, THROW, TriggerMode.Kind.NONE)
	assert_true(await _wait_until_rung("chime"), "the launcher rings the far chime")
	# 箱を板 2 へ送ってから、おもりを渡す
	var crate := _block("scale_crate")
	await _walk_to(Vector3(2.5, 0.0, -9.5), 0.3)
	_give(crate, FORWARD, REPEAT)
	assert_true(await _wait_block_at("scale_crate", Vector3i(2, 0, -17)), "the crate is on plate 2")
	await _walk_route([Vector3(5.5, 0.0, -10.5), Vector3(5.5, 0.0, -14.5), Vector3(3.5, 0.0, -15.5)])
	await _recall_all_from("scale_crate")
	_give(crate, HEAVY, TriggerMode.Kind.NONE)
	assert_true(await _wait_open("gate_2"), "the heavy crate and the chime opened gate 2")
	await _walk_to(Vector3(0.5, 0.0, -17.5), 0.3)
	_give_creature("kid", [LEFT, JUMP])
	assert_true(await _creature_home("kid", OptionalWorldsO1.SCALE_NEST), "the kid went home")
	await _walk_route([Vector3(-0.5, 0.0, -20.0), Vector3(-0.5, 0.0, -25.5)])
	await _walk_to(Vector3(-4.5, 0.0, -25.6), 0.3)
	await _recall_creature("kid")
	await _walk_into_goal(
		[Vector3(4.5, 0.0, -29.0), Vector3(4.5, 1.0, -29.5), Vector3(4.5, 2.0, -31.5)]
	)
	assert_true(await _cleared(), "cleared the weighing scale")


# --- O1-4 札の歯車 ------------------------------------------------------------


## 跳ね箱に自分のジャンプ禁止を渡して止め（扉 1 は開いたまま）、札付きの箱の W 禁止を生き物に預ける。
func test_o1_4_sign_gears_by_parking_the_bans() -> void:
	await _enter("o1_4")
	var me := _me().player_id
	assert_true(w.ledger.player_prohibited(JUMP, me), "the workshop rule: no jumping")
	var hopper := _block("hopper")
	await _walk_to(Vector3(0.5, 0.0, 4.5), 0.3)
	var stopped := await _wait(
		func() -> bool:
			return (
				_door("gate_1").heading_open and hopper.is_grounded() and hopper.velocity_y == 0.0
			),
		900
	)
	assert_true(stopped, "caught the hopper on the plate with gate 1 opening")
	_hand_off_ban(JUMP, hopper)
	await wait_physics_frames(120)
	assert_true(_door("gate_1").is_open(), "gate 1 stays open once the hopper stops")
	assert_true(w.ledger.player_can(JUMP, me), "and I can jump again")
	await _walk_route([Vector3(-0.5, 0.0, 1.5), Vector3(-0.5, 0.0, -6.5)])
	# 札付きの箱: 札を回収して生き物に預け、箱を板 2 へ
	var signed := _block("signed")
	await _walk_to(Vector3(3.5, 0.0, -7.0), 0.3)
	await _recall_all_from("signed")
	assert_true(w.ledger.player_prohibited(FORWARD, me), "the W ban came to me")
	await _walk_to(Vector3(0.5, 0.0, -15.5), 0.3)
	_hand_off_ban(FORWARD, _creature("bunny"))
	await _walk_to(Vector3(3.5, 0.0, -7.0), 0.3)
	_give(signed, FORWARD, REPEAT)
	assert_true(await _wait_block_at("signed", Vector3i(3, 0, -14)), "the crate is on plate 2")
	assert_true(await _wait_open("gate_2"), "plate 2 opened gate 2")
	await _walk_to(Vector3(4.5, 0.0, -12.5), 0.3)
	await _recall_all_from("signed")
	await _walk_to(Vector3(0.5, 0.0, -16.5), 0.3)
	_give_creature("bunny", [RIGHT, JUMP])
	assert_true(await _creature_home("bunny", OptionalWorldsO1.SIGN_NEST), "the bunny went home")
	await _walk_route([Vector3(-0.5, 0.0, -19.0), Vector3(-0.5, 0.0, -24.5)])
	await _walk_to(Vector3(-4.5, 0.0, -24.6), 0.3)
	await _recall_creature("bunny")
	await _walk_into_goal(
		[Vector3(4.5, 0.0, -28.0), Vector3(4.5, 1.0, -28.5), Vector3(4.5, 2.0, -30.5)]
	)
	assert_true(await _cleared(), "cleared the sign gears")


# --- O1-5 大からくり ----------------------------------------------------------


## 戸口に箱を入れて西の島へ → レバーとおもり → 発射台の札を外す → 東の小島で板とおもり・生き物を送る
## → 発射台に投げるを渡して、3 つそろった扉 F を通る。
func test_o1_5_grand_contraption() -> void:
	await _enter("o1_5")
	var cog := _block("cog")
	await _walk_to(Vector3(-7.0, 0.0, 1.5), 0.3)
	_give(cog, LEFT, REPEAT)
	assert_true(await _wait_block_at("cog", Vector3i(-9, 0, 1)), "the crate waits at the west gate")
	await _ring("west_clock")
	assert_true(await _wait_block_at("cog", Vector3i(-10, 0, 1)), "the crate holds the doorway")
	await _walk_to(Vector3(-7.5, 0.0, 0.5), 0.3)
	await _walk_to(Vector3(-14.5, 0.0, 0.5), 0.3)
	await _walk_to(Vector3(-16.5, 0.0, 2.6), 0.3)
	w.interact(null)
	assert_true(_active("west_lever"), "the west lever is on")
	await _pick(Vector3(-18.5, 0.0, -2.5), HEAVY)
	await _walk_to(Vector3(-11.0, 0.0, 0.5), 0.3)
	await _recall_all_from("cog")
	await _walk_to(Vector3(-5.5, 0.0, 0.5), 0.3)
	# 発射台の札を外す（投げる禁止が自分に来る）
	await _walk_route([Vector3(6.5, 0.0, -1.5), Vector3(6.5, 0.0, -4.5)])
	await _recall_all_from("launcher")
	assert_true(w.ledger.player_prohibited(THROW, _me().player_id), "the sign came to me")
	# 東の小島
	assert_true(await _ride_warp(Vector3(5.5, 0.0, -3.5)), "warped east")
	await _pick(Vector3(17.5, 0.0, 2.5), THROW)
	var crate := _block("weight_crate")
	await _walk_to(Vector3(16.5, 0.0, 2.0), 0.3)
	_give(crate, FORWARD, REPEAT)
	assert_true(
		await _wait_block_at("weight_crate", Vector3i(16, 0, -3)), "the crate is on the plate"
	)
	await _walk_to(Vector3(17.5, 0.0, -1.5), 0.3)
	await _recall_all_from("weight_crate")
	_give(crate, HEAVY, TriggerMode.Kind.NONE)
	assert_true(await _wait(func() -> bool: return _active("east_plate")), "the plate is down")
	await _walk_to(Vector3(15.5, 0.0, 1.5), 0.3)
	_give_creature("elder", [LEFT, JUMP])
	var critter := _creature("elder")
	assert_true(
		await _wait(func() -> bool: return critter.global_position.x < 8.0, 1200),
		"the elder took the warp stone home"
	)
	await wait_physics_frames(120)
	assert_true(await _ride_warp(Vector3(14.5, 0.0, -2.5)), "warped home")
	await _walk_to(Vector3(6.5, 0.0, -5.5), 0.3)
	_give(_block("launcher"), THROW, TriggerMode.Kind.NONE)
	assert_true(await _wait_until_rung("far_chime"), "the launcher rings the far chime")
	assert_true(await _wait_open("final_gate"), "all three opened the final gate")
	assert_true(await _creature_home("elder", OptionalWorldsO1.GRAND_NEST), "the elder went home")
	await _walk_route(
		[Vector3(-0.5, 0.0, -5.5), Vector3(-0.5, 0.0, -7.5), Vector3(-0.5, 0.0, -13.5)]
	)
	await _walk_to(Vector3(-3.5, 0.0, -13.4), 0.3)
	await _recall_creature("elder")
	await _walk_into_goal(
		[Vector3(4.5, 0.0, -20.0), Vector3(4.5, 1.0, -20.5), Vector3(4.5, 2.0, -22.5)]
	)
	assert_true(await _cleared(), "cleared the grand contraption")
