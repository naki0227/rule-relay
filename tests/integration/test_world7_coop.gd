extends "res://tests/integration/world7_coop.gd"
## ワールド 7「空の頂」の協力の道を、2 人のオンライン協力で最初から最後まで通す（部品は world7_coop.gd）。
## 2 人とも移動の入力・向き・キー・F・仲間へ渡す、の操作だけで進む（瞬間移動しない・台帳を直接書かない）。


## 7-1: 仲間の W で W×2 にして、追い風の通り道の外でも浮いて谷を越える。風船を谷越しに投げ返し、
## 相方は（W を渡したので前へ歩けないまま待ち、W と風船を投げ返してもらってから）追い風の通り道で渡る。台へはジャンプを集めて跳び、上から全部を投げ返す。
func test_summit_1_pair_double_speed_glide_and_pooled_jumps() -> void:
	await _start_pair(World7Stages.SUMMIT_1, 43000)
	_as(1)
	await _walk_to(Vector3(1.5, 1.0, 3.5))
	_as(0)
	await _pick_remote(Vector3(4.5, 1.0, 4.5), FLOAT)
	await _walk_to(Vector3(6.5, 1.0, 4.5))
	_as(1)
	await _hand_to(0, FORWARD, true)
	_as(0)
	assert_true(
		await _run_and_jump(
			Vector3(6.5, 1.0, 4.5), Vector3(6.5, 1.0, 0.3), Vector3(6.5, 0.0, -14.5)
		),
		"W x2 and float cross the gap outside the tailwind"
	)
	_as(0)
	await _walk_to(Vector3(1.5, 0.0, -12.8))
	await _hand_to(1, FLOAT, true)
	await _hand_to(1, FORWARD, true)
	_as(1)
	assert_true(
		await _run_and_jump(
			Vector3(0.5, 1.0, 3.5), Vector3(0.5, 1.0, 0.3), Vector3(0.5, 0.0, -14.5)
		),
		"the partner glides on the tailwind"
	)
	# ジャンプを集めて台へ（窪みのブロックを使わない）
	await _walk_to(Vector3(-4.5, 0.0, -23.2))
	_as(0)
	await _walk_to(Vector3(-5.5, 0.0, -23.2))
	await _hand_to(1, JUMP)
	_as(1)
	await _walk_to(Vector3(-4.5, 2.0, -25.8))
	await _ring_remote("foot_bell")
	await _walk_to(Vector3(-5.5, 2.0, -24.6))
	await _hand_all_to(0, JUMP)
	_as(0)
	await _walk_to(Vector3(-6.5, 2.0, -25.8))
	await _walk_into_goal_at(-1.0)
	_as(1)
	await _walk_into_goal_at(1.0)
	assert_true(await _pair_cleared(), "both at the goal with the bell rung")


## 7-2: 相方が小山の板に立って扉を開けておき（生き物を使わない）、先にワープの石で中の島へ。
## 相方はダッシュと風船で谷を越える。頂の島へはジャンプを集めて跳ぶ。
func test_summit_2_pair_holds_the_gate_and_pools_jumps() -> void:
	await _start_pair(World7Stages.SUMMIT_2, 43400)
	_as(1)
	await _walk_to(Vector3(-4.5, 2.0, 6.5))
	_as(0)
	assert_true(await _wait_door_open("nook_gate"), "the partner's weight opens the gate")
	await _walk_to(Vector3(-5.5, 1.0, 3.5))
	await _walk_to(Vector3(-7.5, 1.0, 3.5))
	assert_true(await _step_onto_warp(Vector3(-8.5, 1.0, 3.5), Vector3(-5.5, 0.0, -13.5)), "warped")
	_as(1)
	await _pick_remote(Vector3(3.5, 1.0, 5.5), DASH)
	var dash_slot := _slot_of(DASH)
	await _pick_remote(Vector3(1.5, 1.0, 2.5), FLOAT)
	assert_true(
		await _dash_glide(Vector3(0.5, 1.0, 3.5), 0.3, Vector3(0.5, 0.0, -14.5), dash_slot),
		"the partner glides over"
	)
	await _walk_to(Vector3(-2.5, 0.0, -21.7))
	_as(0)
	await _walk_to(Vector3(-3.5, 0.0, -21.7))
	await _hand_to(1, JUMP)
	_as(1)
	await _walk_to(Vector3(-2.5, 2.0, -24.8))
	await _ring_remote("cloud_bell")
	await _walk_to(Vector3(-3.5, 2.0, -23.6))
	await _hand_all_to(0, JUMP)
	_as(0)
	await _walk_to(Vector3(-4.5, 2.0, -24.8))
	await _walk_into_goal_at(-1.0)
	_as(1)
	await _walk_into_goal_at(1.0)
	assert_true(await _pair_cleared(), "both at the goal with the bell rung")


## 7-3: 木箱の重いを相方へ渡し、相方が板に立って扉を開けておく。段差 2 はジャンプを集めて跳ぶ。
## 頂の扉は、1 人が時の鐘を鳴らしてもう 1 人を先に入れ、入った人が内側の板に立って開けておく。
func test_summit_3_pair_holds_both_gates() -> void:
	await _start_pair(World7Stages.SUMMIT_3, 43800)
	await _walk_route(
		[Vector3(-7.5, 0.0, 1.5), Vector3(-10.5, 0.0, -1.5), Vector3(-17.5, 0.0, -1.5)]
	)
	await _recall_all_from_remote("crate")
	await _bag_to_hotbar_remote(HEAVY)
	await _walk_to(Vector3(-9.5, 0.0, 0.5))
	_as(1)
	await _walk_to(Vector3(-7.5, 0.0, 0.5))
	_as(0)
	await _hand_to(1, HEAVY)
	_as(1)
	await _walk_to(Vector3(-7.5, 0.0, -0.5), 0.2)
	_as(0)
	assert_true(await _wait_door_open("stair_gate"), "the heavy partner holds the gate")
	await _walk_route([Vector3(-6.5, 0.0, 0.5), Vector3(-6.5, 0.0, -1.5), Vector3(-6.5, 1.0, -2.6)])
	await _walk_to(Vector3(-5.5, 2.0, -2.6))
	_as(1)
	await _walk_to(Vector3(-5.5, 0.0, -0.5))
	_as(0)
	await _hand_to(1, JUMP)
	_as(1)
	await _walk_to(Vector3(-4.5, 2.0, -2.6))
	await _walk_to(Vector3(0.5, 2.0, -9.3))
	await _walk_to(Vector3(0.5, 4.0, -11.7))
	await _walk_to(Vector3(-0.5, 4.0, -11.3))
	_as(0)
	await _walk_to(Vector3(-0.5, 2.0, -9.3))
	_as(1)
	await _hand_all_to(0, JUMP)
	_as(0)
	await _walk_to(Vector3(-1.5, 4.0, -11.7))
	_as(1)
	await _walk_to(Vector3(-0.5, 4.0, -21.5))
	_as(0)
	await _walk_to(Vector3(-1.5, 4.0, -20.5))
	await _hand_to(1, JUMP)
	await _ring_remote("summit_chime")
	_as(1)
	await _walk_route([Vector3(-0.5, 4.0, -22.5), Vector3(-0.5, 5.0, -23.6)])
	_as(0)
	assert_true(await _wait_door_open("summit_gate"), "the partner on the inner plate holds it")
	await _walk_route([Vector3(-0.5, 4.0, -21.0), Vector3(-0.5, 4.0, -22.5)])
	_as(1)
	await _walk_to(Vector3(-0.5, 6.0, -26.5))
	_as(0)
	await _walk_route([Vector3(-0.5, 5.0, -23.6), Vector3(-0.5, 6.0, -25.5)])
	await _walk_into_goal_at(-1.0)
	_as(1)
	await _walk_into_goal_at(1.0)
	assert_true(await _pair_cleared(), "both at the goal with the chime rung")


## 7-4: 先に 1 人が足ひれで小島へ泳いで鐘を鳴らし、北の岸から足ひれを南の岸へ投げ返す。相方も泳いで渡る。
## 高台へはジャンプを集めて跳ぶ。
func test_summit_4_pair_throws_the_fins_back() -> void:
	await _start_pair(World7Finale.SUMMIT_4, 44200)
	await _pick_remote(Vector3(6.5, 1.0, 4.5), SWIM)
	await _walk_to(Vector3(-4.5, 1.0, 0.5))
	assert_true(await _swim_to(Vector3(0.0, 1.0, -4.0)), "swam onto the islet")
	await _ring_remote("river_bell")
	await _walk_to(Vector3(-0.5, 1.0, -7.5))
	assert_true(await _swim_to(Vector3(-2.5, 1.0, -12.5)), "swam to the north bank")
	_as(1)
	await _walk_to(Vector3(2.5, 1.0, 0.5))
	_as(0)
	await _walk_to(Vector3(2.5, 1.0, -12.0))
	await _hand_to(1, SWIM, true)
	_as(1)
	assert_true(await _swim_to(Vector3(-4.5, 1.0, -12.5)), "the partner swam across")
	await _walk_to(Vector3(-2.5, 1.0, -19.6))
	_as(0)
	await _walk_to(Vector3(-3.5, 1.0, -19.6))
	await _hand_to(1, JUMP)
	_as(1)
	await _walk_to(Vector3(-2.5, 3.0, -21.8))
	await _walk_to(Vector3(-3.5, 3.0, -20.6))
	await _hand_all_to(0, JUMP)
	_as(0)
	await _walk_to(Vector3(-4.5, 3.0, -21.8))
	await _walk_into_goal_at(-1.0)
	_as(1)
	await _walk_into_goal_at(1.0)
	assert_true(await _pair_cleared(), "both at the goal with the river bell rung")


## 7-5: 1 人が東の石を東の板へすべらせ、もう 1 人が西の板に立つ（二つ板の扉）。先に入った人が囲いの中の板に
## 立って内の扉を開け、相方を入れる。2 人ともワープの石で北の島へ。高台へはジャンプを集めて跳ぶ。
func test_summit_5_pair_a_stone_and_the_inner_plate() -> void:
	await _start_pair(World7Finale.SUMMIT_5, 44600)
	await _walk_to(Vector3(2.5, 1.0, 7.8), 0.3)
	_lend(_block("east_stone"), _slot_of(FORWARD), TriggerMode.Kind.REPEAT)
	assert_true(await _wait_block_at("east_stone", World7Finale.EAST_PLATE), "the stone slid")
	await _back_to(Vector3(2.5, 1.0, 4.1))
	await _recall_all_from_remote("east_stone")
	_as(1)
	await _walk_to(Vector3(-1.5, 1.0, 2.5), 0.2)
	_as(0)
	assert_true(await _wait_door_open("twin_gate"), "a stone and the partner on the twin plates")
	await _walk_route([Vector3(-0.5, 1.0, -1.5), Vector3(-0.5, 1.0, -4.5), Vector3(2.5, 1.0, -4.5)])
	_as(1)
	assert_true(await _wait_door_open("inner_gate"), "standing inside opens the inner gate")
	await _walk_route([Vector3(1.5, 1.0, -1.5), Vector3(1.5, 1.0, -4.0), Vector3(0.5, 1.0, -5.5)])
	assert_true(
		await _step_onto_warp(Vector3(0.5, 1.0, -6.5), Vector3(0.5, 1.0, -21.5)), "warped north"
	)
	await _walk_to(Vector3(-2.5, 1.0, -24.5))
	_as(0)
	await _walk_to(Vector3(0.5, 1.0, -5.5))
	assert_true(
		await _step_onto_warp(Vector3(0.5, 1.0, -6.5), Vector3(0.5, 1.0, -21.5)), "warped too"
	)
	await _walk_to(Vector3(-3.5, 1.0, -29.6))
	_as(1)
	await _walk_to(Vector3(-2.5, 1.0, -29.6))
	await _hand_to(0, JUMP)
	_as(0)
	await _walk_to(Vector3(-3.5, 3.0, -31.8))
	await _ring_remote("bridge_bell")
	await _walk_to(Vector3(-2.5, 3.0, -30.6))
	await _hand_all_to(1, JUMP)
	_as(1)
	await _walk_to(Vector3(-1.5, 3.0, -31.8))
	await _walk_into_goal_at(1.0)
	_as(0)
	await _walk_into_goal_at(-1.0)
	assert_true(await _pair_cleared(), "both at the goal with the bridge bell rung")


## 7-6: 最終ステージを 2 人で通す。谷は W×2 と風船（投げ返して追い風の通り道）、川は足ひれ（投げ返す）、
## 石段の扉は重いを持った相方が板に立って開け（風船は返してから。持ったままだと重さが 0 になる）、
## 段差 2 はジャンプを集め、頂の扉は先に入った人が内側の板に立つ。
func test_summit_6_pair_climbs_to_the_festival() -> void:
	await _start_pair(World7Finale.SUMMIT_6, 45000)
	# 空の谷
	_as(1)
	await _walk_to(Vector3(1.5, 1.0, 3.5))
	_as(0)
	await _pick_remote(Vector3(4.5, 1.0, 4.5), FLOAT)
	await _walk_to(Vector3(6.5, 1.0, 4.5))
	_as(1)
	await _hand_to(0, FORWARD, true)
	_as(0)
	assert_true(
		await _run_and_jump(
			Vector3(6.5, 1.0, 4.5), Vector3(6.5, 1.0, 0.3), Vector3(6.5, 0.0, -14.5)
		),
		"W x2 and float cross the gap"
	)
	await _walk_to(Vector3(1.5, 0.0, -12.8))
	await _hand_to(1, FLOAT, true)
	await _hand_to(1, FORWARD, true)
	_as(1)
	assert_true(
		await _run_and_jump(
			Vector3(0.5, 1.0, 3.5), Vector3(0.5, 1.0, 0.3), Vector3(0.5, 0.0, -14.5)
		),
		"the partner glides on the tailwind"
	)
	# 川
	_as(0)
	await _pick_remote(Vector3(6.5, 0.0, -14.5), SWIM)
	await _walk_to(Vector3(-4.5, 0.0, -23.5))
	assert_true(await _swim_to(Vector3(0.0, 0.0, -28.0)), "swam onto the islet")
	await _ring_remote("river_bell")
	await _walk_to(Vector3(-0.5, 0.0, -31.5))
	assert_true(await _swim_to(Vector3(-2.5, 0.0, -36.5)), "swam to the north bank")
	_as(1)
	await _walk_to(Vector3(2.5, 0.0, -23.5))
	_as(0)
	await _walk_to(Vector3(2.5, 0.0, -36.0))
	await _hand_to(1, SWIM, true)
	_as(1)
	assert_true(await _swim_to(Vector3(-4.5, 0.0, -36.5)), "the partner swam across")
	# 石段の扉
	_as(0)
	await _walk_route([Vector3(-10.5, 0.0, -44.5), Vector3(-17.5, 0.0, -46.5)])
	await _recall_all_from_remote("crate")
	await _bag_to_hotbar_remote(HEAVY)
	await _walk_to(Vector3(-6.5, 0.0, -42.5))  # 風の通り道の外で受け渡す
	_as(1)
	await _walk_to(Vector3(-5.5, 0.0, -42.5))
	await _hand_to(0, FLOAT)  # 浮くを持ったままだと重いと打ち消し合う（重さ 0）ので、先に返す
	_as(0)
	await _hand_to(1, HEAVY)
	_as(1)
	await _walk_to(Vector3(-7.5, 0.0, -45.5), 0.2)
	_as(0)
	assert_true(await _wait_door_open("stair_gate"), "the heavy partner holds the gate")
	await _walk_route(
		[Vector3(-6.5, 0.0, -44.5), Vector3(-6.5, 0.0, -46.5), Vector3(-6.5, 1.0, -47.6)]
	)
	await _walk_to(Vector3(-5.5, 2.0, -47.6))
	_as(1)
	await _walk_to(Vector3(-5.5, 0.0, -45.5))
	_as(0)
	await _hand_to(1, JUMP)
	# 段差 2 はジャンプを集める
	_as(1)
	await _walk_to(Vector3(-4.5, 2.0, -47.6))
	await _walk_to(Vector3(0.5, 2.0, -54.3))
	await _walk_to(Vector3(0.5, 4.0, -56.7))
	await _walk_to(Vector3(-0.5, 4.0, -56.3))
	_as(0)
	await _walk_to(Vector3(-0.5, 2.0, -54.3))
	_as(1)
	await _hand_all_to(0, JUMP)
	_as(0)
	await _walk_to(Vector3(-1.5, 4.0, -56.7))
	# 頂の扉
	_as(1)
	await _walk_to(Vector3(-0.5, 4.0, -66.5))
	_as(0)
	await _walk_to(Vector3(-1.5, 4.0, -65.5))
	await _hand_to(1, JUMP)
	await _ring_remote("summit_chime")
	_as(1)
	await _walk_route([Vector3(-0.5, 4.0, -67.5), Vector3(-0.5, 5.0, -68.6)])
	_as(0)
	assert_true(await _wait_door_open("summit_gate"), "the partner on the inner plate holds it")
	await _walk_route([Vector3(-0.5, 4.0, -66.0), Vector3(-0.5, 4.0, -67.5)])
	_as(1)
	await _walk_to(Vector3(-0.5, 6.0, -71.5))
	_as(0)
	await _walk_route([Vector3(-0.5, 5.0, -68.6), Vector3(-0.5, 6.0, -70.5)])
	await _walk_into_goal_at(-1.0)
	_as(1)
	await _walk_into_goal_at(1.0)
	assert_true(await _pair_cleared(), "both at the summit with both bells rung")
	for i in party.count():
		var festival := SummitFestival.of(party.world(i))
		assert_true(
			await party.until(func() -> bool: return festival.started, "festival on side %d" % i),
			"the festival starts on every screen"
		)
