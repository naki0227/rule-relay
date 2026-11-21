extends "res://tests/integration/world7_playthrough.gd"
## ワールド 7「空の頂」の関所と詰みを、プレイヤーと同じ操作で壊しにいく試遊（2026-11-21）。
## 書き方は test_island_probes.gd と同じ（test_gate_* は守られている関所、test_finding_* は見つけた挙動の記録）。
## 結果は docs/campaign-plan.md の「W7 空の頂」にまとめた。

# --- 7-1 頂のふもと ------------------------------------------------------------


## 浮くだけ（追い風の通り道の外）では、幅 11 の谷の途中で落ちる。
func test_gate_summit_1_float_alone_falls_short_outside_the_tailwind() -> void:
	await _enter(World7Stages.SUMMIT_1)
	await _pick_to_hotbar(Vector3(4.5, 1.0, 4.5), FLOAT)
	assert_false(
		await _run_and_jump(
			Vector3(6.5, 1.0, 3.5), Vector3(6.5, 1.0, 0.3), Vector3(6.5, 0.0, -14.5)
		),
		"float alone does not cross the 11-wide gap"
	)
	await _wait_respawn()
	assert_gt(_me().global_position.z, -1.0, "back on the meadow side")


## 追い風だけ（浮かない）でも、走って跳ぶと谷に落ちる。
func test_gate_summit_1_tailwind_alone_is_not_enough() -> void:
	await _enter(World7Stages.SUMMIT_1)
	assert_false(
		await _run_and_jump(
			Vector3(0.5, 1.0, 3.5), Vector3(0.5, 1.0, 0.3), Vector3(0.5, 0.0, -14.5)
		),
		"the tailwind alone does not carry a plain jump over"
	)
	await _wait_respawn()


## 横風が吹いている間に、おもり無しで尾根をまっすぐ歩くと、西の空へ流されて落ちる。
func test_gate_summit_1_gust_blows_a_light_walker_off_the_ridge() -> void:
	await _enter(World7Stages.SUMMIT_1)
	await _walk_route([Vector3(-8.5, 1.0, 2.5), Vector3(-13.5, 1.0, 2.5), Vector3(-13.5, 1.0, 0.5)])
	await _wait_for_gust(2)
	var fell := not await _try_walk_to(Vector3(-13.5, 1.0, -3.5), 0.35, 120)
	assert_true(fell or _me().global_position.y < 0.5, "the gust pushed me off")
	await _wait_respawn()


## ふもとの段から台（2 段上）へは、ふつうのジャンプでは上がれない。鐘は段から触れない。
func test_gate_summit_1_plateau_and_bell_from_below() -> void:
	await _enter(World7Stages.SUMMIT_1)
	await _pick_to_hotbar(Vector3(-5.5, 1.0, 5.5), HEAVY)
	await _walk_route(
		[Vector3(-8.5, 1.0, 2.5), Vector3(-13.5, 1.0, 2.5), Vector3(-13.5, 1.0, -11.5)]
	)
	var best := await _jump_against(Vector3(-1.5, 0.0, -23.3), Vector3(-1.5, 2.0, -26.5))
	assert_lt(best, 1.5, "terrace (0) to the plateau (2)")
	assert_false(await _try_ring_from("foot_bell", Vector3(-1.5, 0.0, -23.3)), "bell from below")


# --- 7-2 雲の階段 --------------------------------------------------------------


## 浮くだけでも、ダッシュだけでも、幅 10 の谷は越えられない（両方を重ねて初めて届く）。
func test_gate_summit_2_float_or_dash_alone_falls_short() -> void:
	await _enter(World7Stages.SUMMIT_2)
	await _pick_to_hotbar(Vector3(1.5, 1.0, 2.5), FLOAT)
	assert_false(
		await _run_and_jump(
			Vector3(0.5, 1.0, 3.5), Vector3(0.5, 1.0, 0.3), Vector3(0.5, 0.0, -14.5)
		),
		"float alone"
	)
	await _wait_respawn()
	await _enter(World7Stages.SUMMIT_2)
	var dash_slot := await _pick_to_hotbar(Vector3(3.5, 1.0, 5.5), DASH)
	assert_false(
		await _dash_glide(Vector3(0.5, 1.0, 3.5), 0.3, Vector3(0.5, 0.0, -14.5), dash_slot),
		"dash alone"
	)
	await _wait_respawn()


## 板が押されていなければ扉は閉じていて、囲いへ入れない。小山の上からも囲いの壁（高さ 4）へは跳べない。
func test_gate_summit_2_nook_is_closed_without_weight_on_the_knoll() -> void:
	await _enter(World7Stages.SUMMIT_2)
	assert_lt(_door_open_amount("nook_gate"), 0.05, "closed at the start")
	await _walk_to(Vector3(-5.5, 1.0, 3.5))
	assert_false(await _try_walk_to(Vector3(-8.5, 1.0, 3.5), 0.35, 180), "the gate stops me")
	await _walk_to(Vector3(-4.5, 2.0, 6.5))
	assert_true(await _wait_door_open("nook_gate"), "standing on the plate opens it")
	var best := await _jump_against(Vector3(-4.6, 2.0, 6.5), Vector3(-7.5, 4.0, 6.5))
	assert_lt(best, 3.5, "the knoll (2) is two below the wall (4)")
	await _walk_to(Vector3(-5.5, 1.0, 3.5))
	await wait_physics_frames(60)
	assert_lt(_door_open_amount("nook_gate"), 0.05, "the gate closes when I step off")


## 中の島から頂の島（2 段上）へは、ふつうのジャンプでは上がれない。鐘は中の島から触れない。
func test_gate_summit_2_top_isle_and_bell_from_below() -> void:
	await _enter(World7Stages.SUMMIT_2)
	var dash_slot := await _pick_to_hotbar(Vector3(3.5, 1.0, 5.5), DASH)
	await _pick_to_hotbar(Vector3(1.5, 1.0, 2.5), FLOAT)
	await _dash_glide(Vector3(0.5, 1.0, 3.5), 0.3, Vector3(0.5, 0.0, -14.5), dash_slot)
	var best := await _jump_against(Vector3(3.5, 0.0, -21.7), Vector3(3.5, 2.0, -24.5))
	assert_lt(best, 1.5, "middle isle (0) to the top isle (2)")
	assert_false(await _try_ring_from("cloud_bell", Vector3(3.5, 0.0, -21.7)), "bell from below")


# --- 7-3 風と札の塔 ------------------------------------------------------------


## 重いが付いている間、木箱は風の通り道でも動かない。ひとりで板に立っても（1 人分）扉は開かず、
## 重いを持って立つ（4 人分）と開く。降りると閉じる（ひとりでは自分で通れない）。
func test_gate_summit_3_crate_waits_for_its_weight_and_the_plate_needs_four() -> void:
	await _enter(World7Stages.SUMMIT_3)
	await _walk_to(Vector3(-10.5, 0.0, -1.5))
	await wait_physics_frames(200)
	assert_eq(_block("crate").cell(), Vector3i(-19, 0, -1), "heavy: the wind does not move it")
	await _walk_to(Vector3(-7.5, 0.0, -0.5), 0.2)
	await wait_physics_frames(40)
	assert_lt(_door_open_amount("stair_gate"), 0.05, "one person is not enough")
	await _walk_to(Vector3(-17.5, 0.0, -1.5))
	await _recall_all_from("crate")
	var heavy_slot := _bag_to_hotbar(HEAVY)
	assert_ne(heavy_slot, -1, "carrying the heavy weight")
	assert_true(await _wait_block_at("crate", World7Stages.CRATE_PLATE), "the crate drifted")
	await _walk_to(Vector3(-6.5, 0.0, 0.5))
	assert_false(await _try_walk_to(Vector3(-6.5, 1.0, -2.6), 0.35, 120), "the gate is shut")


## 突風の棚: 吹いている間に重い無しで進むと流されて落ちる。重いを持てば吹いていても立っていられる。
func test_gate_summit_3_gusts_blow_the_light_and_spare_the_heavy() -> void:
	await _enter(World7Stages.SUMMIT_3)
	await _walk_to(Vector3(4.5, 0.0, 0.8))
	w.interact(_block("signed_lift"))
	await wait_physics_frames(2)
	_hand_off_ban(JUMP, w.terrain_target(Vector3i(6, -1, 2)))
	await _lift_up("signed_lift", Vector3(4.5, 0.0, 0.8), Vector3(4.5, 2.0, -2.5))
	await _walk_to(Vector3(10.5, 2.0, -9.5))
	await _wait_for_gust(1)
	var made_it := await _try_walk_to(Vector3(10.5, 3.0, -13.5), 0.35, 90)
	assert_false(made_it and _me().global_position.y > 2.5, "the gust blew me off the ledge")
	await _wait_respawn()


## 頂の扉は、時の鐘が鳴っていなければ閉じている。
func test_gate_summit_3_summit_gate_is_shut_without_the_chime() -> void:
	await _enter(World7Stages.SUMMIT_3)
	assert_lt(_door_open_amount("summit_gate"), 0.05, "shut at the start")
	assert_lt(_door_open_amount("stair_gate"), 0.05, "shut at the start")


## 受け入れた技: 塔の段の崖の下の地面のセルにジャンプを単発で渡して乗ると、扉も札も使わずに段へ上がれる
## （2026-11-20 本人が残すと決めた技。どの段差 2 にも効く）。
func test_accepted_summit_3_ground_cell_lift_skips_the_stair_gate() -> void:
	await _enter(World7Stages.SUMMIT_3)
	await _walk_to(Vector3(0.5, 0.0, -0.5), 0.2)
	_lend(w.terrain_target(Vector3i(0, -1, -1)), _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	await wait_physics_frames(4)
	w.press_action(JUMP)
	for i in 300:
		var high := _me().global_position.y > 1.9
		_face(Vector3(0.5, 2.0, -3.5))
		_me().move_intent = Vector2(0.0, 1.0) if high else Vector2.ZERO
		if high and _me().global_position.z < -2.4 and _me().is_on_floor():
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_gt(_me().global_position.y, 1.9, "the ground cell lifted me onto the tower step")


# --- 7-4 流れの上の鐘 ----------------------------------------------------------


## 泳げず浮かないまま川に入ると沈んで落ちる（死亡 → 全員リセットで戻る）。
func test_gate_summit_4_river_sinks_the_unprepared() -> void:
	await _enter(World7Finale.SUMMIT_4)
	await _walk_to(Vector3(6.5, 1.0, 0.5))
	var lowest := _me().global_position.y
	for i in 150:
		_face(Vector3(6.5, 1.0, -3.5))
		_me().move_intent = Vector2(0.0, 1.0)
		lowest = minf(lowest, _me().global_position.y)
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_lt(lowest, -3.0, "sank in the bottomless river")
	await _wait_respawn()
	assert_gt(_me().global_position.z, -0.5, "back on the south bank")


## 川の小島の鐘は、南の岸からも北の岸からも触れない。
func test_gate_summit_4_bell_is_out_of_reach_from_both_banks() -> void:
	await _enter(World7Finale.SUMMIT_4)
	assert_false(await _ring_in_place("river_bell", Vector3(0.5, 1.0, 0.3)), "from the south bank")
	await _pick_to_hotbar(Vector3(6.5, 1.0, 4.5), SWIM)
	await _walk_to(Vector3(2.5, 1.0, 0.5))
	assert_true(await _swim_to(Vector3(-4.5, 1.0, -12.5)), "swam across east of the islet")
	await _walk_to(Vector3(0.5, 1.0, -12.0))
	assert_false(
		await _ring_in_place("river_bell", Vector3(0.5, 1.0, -11.3)), "from the north bank"
	)


## 見つけた挙動: 泳げないまま鐘へ向かって川へ走り込み、沈む途中で F を押すと鐘に届いて鳴る（そのあと沈んで死亡）。
## ひとりなら全員リセットで鐘も戻るが、協力では死んだ人を置いて残りがゴールに集まればクリアになる
## （「生きている全員」の条件）。ルールで止めず、身を捨てる解き方として残す（本人の判断待ち）。
func test_finding_summit_4_a_sinking_dash_rings_the_island_bell() -> void:
	await _enter(World7Finale.SUMMIT_4)
	assert_true(await _try_ring_from("river_bell", Vector3(0.5, 1.0, 0.3)), "rang it while sinking")
	await _wait_respawn()


# --- 7-5 みんなの橋 ------------------------------------------------------------


## 扉は 3 つとも最初は閉じている。平らな板 1 枚にひとりで立っても二つ板の扉は開かない。囲いの壁（3 段上）は跳べない。
func test_gate_summit_5_one_plate_is_not_enough_and_the_cage_walls_hold() -> void:
	await _enter(World7Finale.SUMMIT_5)
	for key: String in ["twin_gate", "knoll_gate", "inner_gate"]:
		assert_lt(_door_open_amount(key), 0.05, "%s is shut" % key)
	await _walk_to(Vector3(-1.5, 1.0, 2.5), 0.2)
	await wait_physics_frames(40)
	assert_lt(_door_open_amount("twin_gate"), 0.05, "one plate alone")
	var best := await _jump_against(Vector3(-2.5, 1.0, -1.6), Vector3(-2.5, 4.0, -3.5))
	assert_lt(best, 2.5, "the island (1) to the cage wall (4)")


## 石 1 つと自分で 2 枚の板を押すと二つ板の扉が開くが、自分が板を降りると閉じる（ひとりでは通れない）。
func test_gate_summit_5_twin_gate_shuts_when_i_step_off() -> void:
	await _enter(World7Finale.SUMMIT_5)
	await _slide_north("east_stone", Vector3(2.5, 1.0, 7.8), Vector3i(2, 1, 2))
	await _walk_to(Vector3(-1.5, 1.0, 2.5), 0.2)
	assert_true(await _wait_door_open("twin_gate"), "me and a stone on the twin plates")
	await _walk_to(Vector3(-0.5, 1.0, -2.0))
	await wait_physics_frames(60)
	assert_lt(_door_open_amount("twin_gate"), 0.05, "it shuts once I step off the plate")


# --- 7-6 頂の祭り --------------------------------------------------------------


## 読み合い 1: 風船とおもりを両方ホットバーに置くと、浮くと重いが打ち消し合って（重さ 0）、
## 追い風の通り道でも谷を越えられない。
func test_gate_summit_6_float_and_heavy_cancel_out() -> void:
	await _enter(World7Finale.SUMMIT_6)
	await _pick_to_hotbar(Vector3(4.5, 1.0, 4.5), FLOAT)
	await _pick_to_hotbar(Vector3(-5.5, 1.0, 5.5), HEAVY)
	assert_eq(BodyTraits.weight(w.ledger, _me().player_id), 0, "float and heavy cancel")
	assert_false(
		await _run_and_jump(
			Vector3(0.5, 1.0, 3.5), Vector3(0.5, 1.0, 0.3), Vector3(0.5, 0.0, -14.5)
		),
		"no glide while carrying both"
	)
	await _wait_respawn()


## 読み合い 2: おもりを持ったままでは、足ひれがあっても川に沈む（泳ぐ前におもりをかばんへ戻す）。
func test_gate_summit_6_heavy_sinks_even_with_fins() -> void:
	await _enter(World7Finale.SUMMIT_6)
	await _pick_to_hotbar(Vector3(-5.5, 1.0, 5.5), HEAVY)
	await _walk_route(
		[
			Vector3(-8.5, 1.0, 2.5),
			Vector3(-13.5, 1.0, 2.5),
			Vector3(-13.5, 1.0, -11.5),
			Vector3(-13.5, 0.0, -13.5),
		]
	)
	await _pick_to_hotbar(Vector3(6.5, 0.0, -14.5), SWIM)
	await _walk_to(Vector3(4.5, 0.0, -23.5))
	var lowest := _me().global_position.y
	for i in 150:
		_face(Vector3(4.5, 0.0, -30.5))
		_me().move_intent = Vector2(0.0, 1.0)
		lowest = minf(lowest, _me().global_position.y)
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_lt(lowest, -3.0, "the weight pulled me under")
	await _wait_respawn()


## 川の小島の鐘は南の岸から触れない。頂の扉と石段の扉は最初は閉じている。
func test_gate_summit_6_bell_and_gates_at_the_start() -> void:
	await _enter(World7Finale.SUMMIT_6)
	assert_lt(_door_open_amount("stair_gate"), 0.05, "the stair gate is shut")
	assert_lt(_door_open_amount("summit_gate"), 0.05, "the summit gate is shut")
	await _pick_to_hotbar(Vector3(4.5, 1.0, 4.5), FLOAT)
	await _run_and_jump(Vector3(0.5, 1.0, 3.5), Vector3(0.5, 1.0, 0.3), Vector3(0.5, 0.0, -14.5))
	assert_false(
		await _ring_in_place("river_bell", Vector3(0.5, 0.0, -23.7)), "from the south bank"
	)
