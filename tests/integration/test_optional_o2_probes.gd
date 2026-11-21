extends "res://tests/integration/optional_playthrough.gd"
## 寄り道 O2「さかさ雲」の抜け道と詰みを、プレイヤーと同じ操作で壊しにいく（敵対的な試遊）。
## 浮くの滑空は、高い所から始めるほど遠くへ届く。持ち上げ＋自分のジャンプ（受け入れた技、約 7 上がる）から
## 滑空する抜け道を中心に試す。
## - test_gate_*: 守られている関所 / test_accepted_*: 残してよい技 / test_finding_*: いまはそのままの挙動

const SINGLE := TriggerMode.Kind.SINGLE_SHOT


func _climb_vane_tower() -> void:
	await _walk_route(
		[
			Vector3(-1.5, 0.0, 5.5),
			Vector3(-1.5, 1.0, 4.5),
			Vector3(-1.5, 2.0, 3.5),
			Vector3(-1.5, 3.0, 2.5),
			Vector3(-1.5, 4.0, 1.5),
			Vector3(-1.5, 5.0, 0.5),
			Vector3(-3.5, 6.0, 0.5),
		]
	)


## 塔の上から北へ滑空しても、向かい風で北の島に届かない（地面のセルの持ち上げ＋自分のジャンプからでも）。
func test_gate_o2_1_tower_glide_into_the_headwind_falls_short() -> void:
	await _enter("o2_1")
	await _climb_vane_tower()
	await _pick(Vector3(-4.5, 6.0, 1.5), FLOAT)
	await _walk_to(Vector3(-4.5, 6.0, 0.3), 0.2)
	var landed := await _lift_jump_toward(Vector3i(-5, 5, 0), Vector3(-4.5, 0.0, -45.0))
	assert_lt(landed.y, -1.0, "the headwind beat the glide (%s)" % landed)
	await _wait_respawn()


## 島の地面（追い風の外）から持ち上げて無風で滑空しても、幅 35 の空は越えられない。
func test_gate_o2_1_lifting_from_the_ground_without_the_tailwind_falls_short() -> void:
	await _enter("o2_1")
	await _climb_vane_tower()
	await _pick(Vector3(-4.5, 6.0, 1.5), FLOAT)
	await _walk_route([Vector3(-1.5, 5.0, 0.5), Vector3(-1.5, 1.0, 4.5), Vector3(3.5, 0.0, 0.5)])
	var landed := await _lift_jump_toward(Vector3i(3, -1, 0), Vector3(3.5, 0.0, -45.0))
	assert_lt(landed.y, -1.0, "still air is not enough (%s)" % landed)
	await _wait_respawn()


## 追い風の段の縁から、持ち上げずにふつうに跳んで滑空しても届かない。
func test_gate_o2_1_tailwind_needs_height() -> void:
	await _enter("o2_1")
	await _climb_vane_tower()
	await _pick(Vector3(-4.5, 6.0, 1.5), FLOAT)
	await _walk_route([Vector3(-1.5, 5.0, 0.5), Vector3(-1.5, 1.0, 4.5), Vector3(4.5, 0.0, 4.0)])
	await _walk_route([Vector3(7.5, 1.0, 3.5), Vector3(9.5, 2.0, 3.5)])
	var landed := await _run_jump_glide(
		Vector3(10.5, 2.0, 1.5), Vector3(10.5, 2.0, 0.2), Vector3(10.5, 0.0, -45.0)
	)
	assert_lt(landed.y, -1.0, "a plain jump in the tailwind falls short (%s)" % landed)
	await _wait_respawn()


## 横風の橋（6 m/秒）は、重くないと渡れない（斜めに歩いても流される）。
func test_gate_o2_2_crosswind_bridge_needs_heavy() -> void:
	await _enter("o2_2")
	await _walk_to(Vector3(-5.5, 0.0, -1.5), 0.3)
	assert_false(
		await _walk_without_falling(Vector3(-17.5, 0.0, -2.5)), "blown off the bridge without heavy"
	)
	await _wait_respawn()


## 重いと浮くを両方ホットバーに置くと打ち消し合い、横風に流される。
func test_gate_o2_2_heavy_and_float_cancel_out() -> void:
	await _enter("o2_2")
	await _walk_to(Vector3(0.5, 0.0, -4.5), 0.3)
	await _recall_all_from("anchor")
	_ensure_on_hotbar(HEAVY)
	await _walk_route([Vector3(-5.5, 0.0, -1.5), Vector3(-15.5, 0.0, -1.5), Vector3(-17.5, 0.0, -2.5)])
	await _pick(Vector3(-19.5, 0.0, -2.5), FLOAT)
	assert_eq(BodyTraits.weight(w.ledger, _me().player_id), 0, "they cancel out")
	assert_false(
		await _walk_without_falling(Vector3(-6.0, 0.0, -1.5)), "blown off on the way back"
	)
	await _wait_respawn()


## 見晴らしから持ち上げ＋自分のジャンプで高く上がって、北の島へまっすぐ滑空しても届かない（雲の段が要る）。
func test_gate_o2_2_deck_to_the_goal_needs_the_cloud_step() -> void:
	await _enter("o2_2")
	await _walk_route(
		[
			Vector3(2.5, 0.0, -9.5),
			Vector3(2.5, 1.0, -10.5),
			Vector3(2.5, 2.0, -11.5),
			Vector3(2.5, 3.0, -12.5),
			Vector3(2.5, 4.0, -13.6),
			Vector3(2.5, 5.0, -14.5),
			Vector3(2.5, 6.0, -16.5),
		]
	)
	_receive(FLOAT)  # 西の小島の風船を持ってきたことにする
	await _walk_to(Vector3(2.5, 6.0, -19.5), 0.2)
	var landed := await _lift_jump_toward(Vector3i(2, 5, -20), Vector3(2.5, 0.0, -75.0))
	assert_lt(landed.y, -1.0, "the straight glide falls into the void (%s)" % landed)
	await _wait_respawn()


## 雲の段は、板が押されていない間は沈んでいて、乗ろうとすると落ちる（下で止まって詰むことはない）。
func test_gate_o2_2_sunken_cloud_step_is_a_fall() -> void:
	await _enter("o2_2")
	assert_true(_door("cloud_step").is_open(), "sunk at the start")
	var step := _door("cloud_step")
	var sunk_top := step.closed_box().end.y - float(step.spec.size.y)
	assert_lt(sunk_top, Tuning.FALL_LIMIT_Y, "its sunken top sits below the fall limit")


## 雲の段（高さ 2）から持ち上げ＋自分のジャンプで西の島（高さ 8）へ滑空しても、着く前に低くなる。
## 風の無い高い段の西半分からふつうに跳んでも届かない（持ち上げてから滑空する）。
func test_gate_o2_3_low_starts_fall_short() -> void:
	await _enter("o2_3")
	var on_isle := await _glide_to(Vector3(3.5, 8.0, 0.4), Vector3(4.5, 2.0, -15.5))
	assert_almost(on_isle.y, 2.0, 0.3, "down on the cloud step")
	await _walk_to(Vector3(3.5, 2.0, -19.5), 0.2)
	var landed := await _lift_jump_toward(Vector3i(3, 1, -20), Vector3(-27.5, 8.0, -28.5))
	assert_lt(landed.y, 7.0, "the west island is too high from the cloud step (%s)" % landed)


## 南の高い雲（高さ 8）から持ち上げて滑空しても、西の島へは届かない。
func test_gate_o2_3_spawn_cloud_to_the_west_island_falls_short() -> void:
	await _enter("o2_3")
	await _walk_to(Vector3(-3.5, 8.0, 0.4), 0.2)
	var landed := await _lift_jump_toward(Vector3i(-4, 7, 0), Vector3(-27.5, 8.0, -28.5))
	assert_lt(landed.y, 7.0, "too far from the spawn cloud (%s)" % landed)


## ダッシュなしで滑空すると、1 枚目の風の壁に押し戻される。
func test_gate_o2_4_gale_pushes_a_glider_back() -> void:
	await _enter("o2_4")
	var landed := await _glide_to(Vector3(0.5, 9.0, 0.4), Vector3(0.5, 2.0, -18.0))
	assert_lt(landed.y, -1.0, "the gale won (%s)" % landed)
	await _wait_respawn()


## 1 回のダッシュで 1 枚目を抜けたあと、足場に降りずに 2 枚目へ向かうと、2 枚目は抜けられない。
func test_gate_o2_4_one_dash_does_not_pass_both_gales() -> void:
	await _enter("o2_4")
	await _pick(Vector3(-1.5, 9.0, 4.5), RuleAction.Kind.DASH)
	var landed := await _glide_dash(
		Vector3(0.5, 9.0, 0.4), Vector3(0.5, 0.0, -36.5), Vector3(0.5, 0.0, -8.6), false
	)
	assert_gt(landed.z, -33.5, "the second gale stopped me (%s)" % landed)
	await _wait_respawn()


## 塔のてっぺんから持ち上げて滑空し、風の壁をダッシュで抜けても、はるか北の島へは届かない（ワープで行く）。
## 浮くとダッシュは、西の小島から持ってきた（仲間から受け取った）ことにする。
func test_gate_o2_5_tower_glide_does_not_reach_the_far_island() -> void:
	await _enter("o2_5")
	assert_true(await _ride_warp(Vector3(4.5, 0.0, 5.5)), "warped to the tower")
	_receive(FLOAT)
	_receive(RuleAction.Kind.DASH)
	var landed := await _glide_dash(
		Vector3(12.5, 9.0, -13.4), Vector3(0.5, 8.0, -60.0), Vector3(12.5, 0.0, -14.6), false, true
	)
	assert_lt(landed.y, 7.5, "the far island is out of reach (%s)" % landed)
