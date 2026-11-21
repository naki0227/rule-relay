extends "res://tests/integration/optional_playthrough.gd"
## 寄り道 O1「からくり工房」の抜け道と詰みを、プレイヤーと同じ操作で壊しにいく（敵対的な試遊）。
## - test_gate_*: 守られている関所（直したもの・最初から守られているもの）
## - test_accepted_*: 本人が残してよいと決めた技（ブロックの上昇＋自分のジャンプ・協力でジャンプを集める）
## - test_finding_*: 意図と違うが、いまはそのままにしている挙動（docs/campaign-plan.md の「未解決の所見」）

const SINGLE := TriggerMode.Kind.SINGLE_SHOT
const REPEAT := TriggerMode.Kind.REPEAT


## 受け入れた技の高さを測る: 地面のセルに単発のジャンプを貸して乗り、戻ったジャンプですぐ自分も跳ぶと
## 約 7 上がる（だから寄り道の関所の扉は高さ 9）。
func test_accepted_lift_then_own_jump_reaches_about_seven() -> void:
	await _enter("o1_1")
	await _walk_to(Vector3(-2.5, 0.0, 6.5), 0.2)
	_lend(w.terrain_target(Vector3i(-3, -1, 6)), _slot_of(JUMP), SINGLE)
	w.press_action(JUMP)
	var best := 0.0
	var pressed := false
	for i in 150:
		if not pressed and w.ledger.player_can(JUMP, _me().player_id) and _me().is_on_floor():
			if _me().global_position.y > 0.05:
				w.press_action(JUMP)
				pressed = true
		best = maxf(best, _me().global_position.y)
		await tree.physics_frame
	print("    lift + own jump: feet reached %.2f" % best)
	assert_gt(best, 6.0, "ACCEPTED: about 7 above the ground")
	assert_lt(best, OptionalWorlds.GATE_HEIGHT - 0.5, "still below the gate height")


## 扉（高さ 9）の前の土手のセルで持ち上げ＋自分のジャンプをしても、扉を越えられない。
func test_gate_o1_1_gate_is_not_jumped_over() -> void:
	await _enter("o1_1")
	await _walk_to(Vector3(0.0, 0.0, -3.6), 0.2)
	await _lift_jump_toward(Vector3i(0, -1, -4), Vector3(0.0, 0.0, -9.0))
	assert_gt(_me().global_position.z, -5.0, "stayed south of the closed gate")


## 南の島から東の小島（幅 5 の空の先）へは、走って跳んでも届かない（ワープの石からだけ）。
func test_gate_o1_1_isle_is_not_a_running_jump() -> void:
	await _enter("o1_1")
	var landed := await _run_jump_glide(
		Vector3(4.5, 0.0, 2.5), Vector3(6.6, 0.0, 2.2), Vector3(13.5, 0.0, -0.5)
	)
	assert_lt(landed.y, -1.0, "fell short of the isle (%s)" % landed)
	await _wait_respawn()


## 生き物に能力を渡しても、板を押さずにいると 2 段目がせり上がらず、1 段目で待つ（巣へは行けない）。
func test_gate_o1_1_creature_waits_without_the_step() -> void:
	await _enter("o1_1")
	await _pick(Vector3(-3.5, 0.0, 9.5), RIGHT)
	var cog := _block("cog")
	await _walk_to(Vector3(2.5, 0.0, 7.5))
	_give(cog, FORWARD, REPEAT)
	_give(cog, RIGHT, SINGLE)
	w.press_action(RIGHT)
	assert_true(await _wait_open("cog_gate"), "the gate opened")
	await _walk_route([Vector3(0.0, 0.0, 1.5), Vector3(0.0, 0.0, -11.5)])
	await _walk_to(Vector3(-1.5, 0.0, -12.5), 0.3)
	_give_creature("wish", [RIGHT, JUMP])
	assert_false(
		await _wait_creature_in("wish", OptionalWorldsO1.COG_NEST, 600), "no step, no way home"
	)
	assert_eq(director.last_clear_text, "", "not cleared")


## 箱を送ってすぐ（まだ動いている間に）単発の W を押すと、W は動けずに戻り、箱は小島の石の上に残る。
## 石がふさがっているので自分も小島へ行けない。やり直し（全員リセット・島のはじめから）が要る。
func test_finding_o1_1_pressing_too_early_strands_the_crate() -> void:
	await _enter("o1_1")
	await _pick(Vector3(-3.5, 0.0, 9.5), RIGHT)
	var cog := _block("cog")
	await _walk_to(Vector3(2.5, 0.0, 7.5))
	_give(cog, FORWARD, SINGLE)
	_give(cog, RIGHT, SINGLE)
	w.press_action(RIGHT)
	await wait_physics_frames(2)
	w.press_action(FORWARD)
	assert_true(await _wait_block_at("cog", Vector3i(13, 0, 0)), "the crate sits on the isle stone")
	await wait_physics_frames(60)
	assert_eq(cog.cell(), Vector3i(13, 0, 0), "FINDING: stranded on the stone")
	assert_false(await _ride_warp(Vector3(4.5, 0.0, 6.5), 240), "the stone is blocked")


## 鐘を鳴らしてから走っても、扉 A に着く前に閉じる（約 19 m）。
func test_gate_o1_2_ring_and_run_is_too_slow() -> void:
	await _enter("o1_2")
	await _ring("clock_a")
	assert_false(await _dash_for_gate_a(), "the gate shut before I got there")
	assert_gt(_me().global_position.z, 0.5, "still south of gate A")


## 協力の近道: 仲間の W をもらって速さ 2 倍なら、鳴らしてから走って間に合う。
func test_accepted_o1_2_double_speed_rings_and_runs() -> void:
	await _enter("o1_2")
	_gift_from_teammate(FORWARD)
	await _ring("clock_a")
	assert_true(await _dash_for_gate_a(), "ACCEPTED: made it with W x2")


## 鐘から土手の入口へ、そこから扉 A の北へ走る（鐘が鳴り終わって扉が閉じるまでの間に）。
func _dash_for_gate_a() -> bool:
	await _try_walk_to(Vector3(-0.5, 0.0, 4.5), 0.4, 300)
	return await _try_walk_to(Vector3(-0.5, 0.0, -2.5), 0.4, 150)


## 板（重さ 2）は自分ひとりでは押せない（扉 B は開かない）。
func test_gate_o1_2_scale_needs_two() -> void:
	await _enter("o1_2")
	await _pick(Vector3(6.5, 0.0, 15.5), LEFT)
	var cog_a := _block("cog_a")
	await _walk_to(Vector3(0.5, 0.0, 4.5))
	_give(cog_a, FORWARD, REPEAT)
	await _wait_block_at("cog_a", Vector3i(0, 0, 1))
	await _ring("clock_a")
	await _wait_block_at("cog_a", Vector3i(0, 0, 0))
	await _walk_route([Vector3(-0.5, 0.0, 3.5), Vector3(-0.5, 0.0, -6.5)])
	await _walk_to(Vector3(-0.5, 0.0, -11.5), 0.2)
	await wait_physics_frames(60)
	assert_false(_active("scale"), "one person is not enough")
	assert_false(_door("gate_b").is_open())


## 扉 2 は時の鐘も要る。おもりの箱で板 2 を押しても、鐘が鳴っていなければ開かない。小島の鐘へは跳べない。
func test_gate_o1_3_gate_two_needs_the_chime_too() -> void:
	await _enter("o1_3")
	await _pick(Vector3(-5.5, 0.0, 10.5), HEAVY)
	await _walk_to(Vector3(2.5, 0.0, 3.5), 0.25)
	await _wait_open("gate_1")
	await _walk_route([Vector3(-0.5, 0.0, 2.5), Vector3(-0.5, 0.0, -6.5)])
	await _pick(Vector3(-6.5, 0.0, -14.5), LEFT)
	var crate := _block("scale_crate")
	await _walk_to(Vector3(2.5, 0.0, -9.5), 0.3)
	_give(crate, FORWARD, REPEAT)
	await _wait_block_at("scale_crate", Vector3i(2, 0, -17))
	await _walk_route(
		[Vector3(5.5, 0.0, -10.5), Vector3(5.5, 0.0, -14.5), Vector3(3.5, 0.0, -15.5)]
	)
	await _recall_all_from("scale_crate")
	_give(crate, HEAVY, TriggerMode.Kind.NONE)
	await wait_physics_frames(60)
	assert_true(_active("plate_2"), "the heavy crate presses plate 2")
	assert_false(_door("gate_2").is_open(), "but the chime is silent")
	await _walk_to(Vector3(5.5, 0.0, -14.5), 0.3)
	var landed := await _run_jump_glide(
		Vector3(5.5, 0.0, -10.5), Vector3(6.6, 0.0, -10.5), Vector3(12.5, 0.0, -10.5)
	)
	assert_lt(landed.y, -1.0, "the chime isle is out of reach (%s)" % landed)
	await _wait_respawn()


## 工房の決まり（ジャンプ禁止）を持っている間は、自分で跳べず、地面のセルの持ち上げも起動できない。
## 跳ね箱は着地するたびに扉 1 を切り替える。
func test_gate_o1_4_the_rule_blocks_lifts_and_the_hopper_flips_the_gate() -> void:
	await _enter("o1_4")
	await _walk_to(Vector3(-3.5, 0.0, 6.5), 0.2)
	_lend(w.terrain_target(Vector3i(-4, -1, 6)), _slot_of(JUMP), SINGLE)
	w.press_action(JUMP)
	await wait_physics_frames(40)
	assert_lt(_me().global_position.y, 0.3, "the banned single shot does not fire")
	var flips := 0
	var was_open := _door("gate_1").heading_open
	for i in 600:
		if _door("gate_1").heading_open != was_open:
			flips += 1
			was_open = _door("gate_1").heading_open
		await tree.physics_frame
	assert_gt(flips, 2, "the hopper keeps flipping gate 1")


## 扉 F は 3 つ全部が要る。レバーと板だけでは開かない。
func test_gate_o1_5_final_gate_needs_all_three() -> void:
	await _enter("o1_5")
	var cog := _block("cog")
	await _walk_to(Vector3(-7.0, 0.0, 1.5), 0.3)
	_give(cog, LEFT, REPEAT)
	await _wait_block_at("cog", Vector3i(-9, 0, 1))
	await _ring("west_clock")
	await _wait_block_at("cog", Vector3i(-10, 0, 1))
	await _walk_route([Vector3(-7.5, 0.0, 0.5), Vector3(-14.5, 0.0, 0.5), Vector3(-16.5, 0.0, 2.6)])
	w.interact(null)
	assert_true(_active("west_lever"), "lever on")
	await wait_physics_frames(30)
	assert_false(_door("final_gate").is_open(), "the lever alone does not open the final gate")
	# 扉 F の前の土手で持ち上げ＋自分のジャンプをしても越えられない
	await _walk_route(
		[Vector3(-11.0, 0.0, 0.5), Vector3(-0.5, 0.0, -5.5), Vector3(-0.5, 0.0, -9.0)]
	)
	await _lift_jump_toward(Vector3i(-1, -1, -9), Vector3(-0.5, 0.0, -14.0))
	assert_gt(_me().global_position.z, -10.6, "stayed south of the final gate")
