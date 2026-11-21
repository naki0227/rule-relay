extends "res://tests/integration/world_playing.gd"
## ワールド 4 の新しいステージの関所と詰みを、プレイヤーと同じ操作で壊しにいく（敵対的な試遊）。
## - test_gate_*: 意図した関所が守られていること（ふつうの跳び・重ね跳びで届かない、板の重さ、閉じた門と檻）
## - test_finding_*: 意図と違うが今は直していない挙動（docs/campaign-plan.md の「直していない発見」）
## ワールド 4 の島にはダッシュ・風・氷を置いていない。瞬間移動・状態の書き換えはしない。

const NORTH := Vector3(0.0, 0.0, -1.0)

# --- 4-1 木の実投げ ---------------------------------------------------------------


## 子どもの島（幅 9 の向こう）へは、受け入れた重ね跳びでも届かない。
func test_gate_nut_toss_the_islet_is_out_of_reach() -> void:
	await _enter(World4Stages.NUT_TOSS_ID)
	var crossed := await _stacked_leap(Vector3(0.5, 0.0, -1.5), Vector3i(0, -1, -2), NORTH, 11.3)
	assert_false(crossed, "the stacked jump falls short of the islet")


## 先に「投げる」を投げ渡すと、子どもはふもとから北へ投げて外す。「投げる」も無くなる（発射台にも
## 投げ渡せない）が、空へ落ちれば保存の時点へ戻る。
func test_finding_nut_toss_throw_first_misses_until_a_fall() -> void:
	await _enter(World4Stages.NUT_TOSS_ID)
	await _walk_to(Vector3(-1.5, 0.0, -1.6), 0.3)
	await _give_creature("kit", [_slot_of(THROW)], true)
	await wait_physics_frames(90)
	assert_eq(_creature("kit").held_item, "", "the nut is gone")
	assert_false(w.activated.has("nut_bell"), "it missed the bell")
	assert_true(await _walk_off(Vector3(-1.5, 0.0, -5.0)), "walked off the meadow")
	assert_ne(_creature("kit").held_item, "", "the nut is back")


# --- 4-2 生き物のはしご -----------------------------------------------------------


## 石を寄せないと、ジャンプと D を渡してもうさぎは石垣（高さ 1）までしか上がれない。
func test_gate_creature_ladder_no_ladder_no_meadow() -> void:
	await _enter(World4Stages.LADDER_ID)
	await _walk_to(Vector3(-4.0, 0.0, -1.0), 0.4)
	await _give_creature("bunny", [_slot_of(JUMP), _slot_of(RIGHT)])
	var top := await _creature_top("bunny", 360)
	assert_lt(top, 1.5, "the bunny only reached the low wall (%.2f)" % top)
	assert_false(_wish_box("bunny").has_point(_creature("bunny").global_position), "not up")


# --- 4-4 重さの板 -----------------------------------------------------------------


## 重いを持たない 1 人では、4 人分の板は沈まない（橋は架からない）。
func test_gate_weight_plates_one_person_is_not_enough() -> void:
	await _enter(World4Stages.PLATES_ID)
	await _walk_to(Vector3(-2.5, 1.0, 2.5), 0.2)
	await wait_physics_frames(60)
	assert_false(_plate_pressed("ground_plate"), "one person is 1 of 4")
	assert_false(_door_closed("plate_bridge"), "no bridge")


## 幅 9 は、受け入れた重ね跳びでも届かない。
func test_gate_weight_plates_gap_of_nine_is_not_a_stacked_jump() -> void:
	await _enter(World4Stages.PLATES_ID)
	var crossed := await _stacked_leap(Vector3(2.5, 1.0, 0.5), Vector3i(2, 0, 0), NORTH, 9.3)
	assert_false(crossed, "the stacked jump falls short of the north isle")


## 重いを持って自分で板に乗れば橋は架かるが、降りると沈む（ひとりでは渡れない。協力の道）。
func test_gate_weight_plates_a_heavy_player_cannot_hold_it_and_cross() -> void:
	await _enter(World4Stages.PLATES_ID)
	await _pick(Vector3(-5.5, 1.0, 5.5), HEAVY)
	await _walk_to(Vector3(-2.5, 1.0, 2.5), 0.2)
	assert_true(await _wait_door("plate_bridge", true), "a heavy person holds the bridge")
	await _walk_to(Vector3(0.0, 1.0, 0.6), 0.3)
	assert_true(await _wait_door("plate_bridge", false), "it sinks when they step off")


# --- 4-5 群れの道 -----------------------------------------------------------------


## 門が閉じている間は、動けるひつじも牧場に入れない（高い所が見えても待っている）。
func test_gate_herd_path_the_closed_gate_keeps_the_herd_out() -> void:
	await _enter(World4Stages.HERD_ID)
	var gifts: Array[RuleAction.Kind] = [LEFT, BACK, RIGHT]
	for i in World4Stages.HERD.size():
		var critter := _creature(World4Stages.HERD[i])
		await _walk_to(critter.global_position + Vector3(0.0, 0.0, 1.6), 0.4)
		await _give_creature(World4Stages.HERD[i], [_slot_of(gifts[i])])
	await wait_physics_frames(300)
	for key in World4Stages.HERD:
		assert_false(World4Stages.PASTURE.has_point(_creature(key).global_position), "%s out" % key)
	assert_false(_door_closed("herd_bridge"), "no bridge")


# --- 4-6 森の奥 -------------------------------------------------------------------


## 檻の扉が閉じている間は、扉の前で F を押してもおもりは取れない。
func test_gate_deep_forest_the_closed_cage_keeps_the_weight() -> void:
	await _enter(DeepForest.ID)
	await _walk_to(Vector3(-3.7, 1.0, 2.5), 0.2)
	w.interact(null)
	await wait_physics_frames(4)
	assert_eq(w.ledger.ability_count(HEAVY, _me().player_id), 0, "the weight is still caged")


## 受け入れた重ね跳びで檻の岩（高さ 5）の上へ乗れても、穴には屋根があり、上からおもりへは届かない。
func test_gate_deep_forest_no_way_into_the_cage_from_above() -> void:
	await _enter(DeepForest.ID)
	await _walk_to(Vector3(-3.5, 1.0, 0.5), 0.2)
	_lend(w.terrain_target(Vector3i(-4, 0, 0)), _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	var pressed := false
	for f in 300:
		if not pressed and w.ledger.player_can(JUMP, _me().player_id) and _me().is_on_floor():
			if _me().global_position.y > 1.2:
				w.press_action(JUMP)
				pressed = true
		var high := _me().global_position.y > 5.3
		_face(Vector3(-5.5, 5.0, 0.5))
		_me().move_intent = Vector2(0.0, 1.0) if high else Vector2.ZERO
		await tree.physics_frame
		if _me().global_position.x < -4.6 and _me().is_on_floor():
			break
	_me().move_intent = Vector2.ZERO
	assert_gt(
		_me().global_position.y, 4.5, "ACCEPTED: the stacked jump reaches the top of the rock"
	)
	await _try_walk_to(Vector3(-6.5, 5.0, 2.5), 0.3, 200)
	w.interact(null)
	await wait_physics_frames(4)
	assert_eq(w.ledger.ability_count(HEAVY, _me().player_id), 0, "the roof keeps the weight out")


## 子どもの岩とつながっていない発射台の小島（幅 1）へは、子どもは渡らない（発射台の上へ上がらない）。
func test_gate_deep_forest_the_kit_stays_off_the_launcher() -> void:
	await _enter(DeepForest.ID)
	await _walk_to(Vector3(-3.5, 1.0, 0.6), 0.3)
	await _give_creature("kit", [_slot_of(RIGHT)], true)
	var top := await _creature_top("kit", 300)
	assert_lt(top, 2.5, "the kit stopped on its rock (%.2f)" % top)
