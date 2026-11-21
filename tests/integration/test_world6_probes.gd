extends "res://tests/integration/world56_play.gd"
## ワールド 6 の新しいステージ（6-1〜6-5）の関所と詰みを、プレイヤーと同じ操作で壊しにいく試遊。
## 書き方は test_island_probes.gd と同じ（test_gate_*: 守られている関所、test_finding_*: 見つけた挙動の記録）。

const NORTH := Vector3(0.0, 0.0, -1.0)
const EAST := Vector3(1.0, 0.0, 0.0)
const WEST := Vector3(-1.0, 0.0, 0.0)

# --- 6-1 ワープの石 --------------------------------------------------------------


## 広場から北の島（谷 6）へは、走って跳んでも届かない（縁ちょうどでも）。
func test_gate_warp_stones_isle_gap_is_too_wide() -> void:
	await _enter(World6Stages.WARP_ID)
	var route: Array[Vector3] = [Vector3(-2.5, 0.0, 1.5)]
	assert_true(is_nan(await _first_crossing(route, NORTH, 2.0, 6.0)), "the 6-wide gap holds")


## 塔の上から、風船なしで東の高台へ跳んでも届かない（谷に落ちて戻る）。
func test_gate_warp_stones_tower_leap_needs_the_balloon() -> void:
	await _enter(World6Stages.WARP_ID)
	for i in 4:
		await _walk_to(Vector3(1.5 + i, 1.0 + i, -0.5))
	await _walk_to(Vector3(5.5, 5.0, -1.5))
	assert_false(
		await _leap_to(Vector3(6.6, 5.0, -1.5), Vector3(15.5, 2.0, -1.5)), "fell into the gap"
	)
	await _wait_respawn()


## 島のワープの石の上に石が乗っていると、広場の石に乗っても移らない（降りるまで待つ）。
func test_gate_warp_stones_occupied_stone_holds_the_warp() -> void:
	await _enter(World6Stages.WARP_ID)
	var crate := _block("warp_crate")
	await _walk_to(Vector3(-7.5, 0.0, 5.6), 0.3)
	for i in 3:
		_lend(crate, _slot_of(RIGHT), TriggerMode.Kind.SINGLE_SHOT)
		w.press_action(RIGHT)
		await wait_physics_frames(90)
	assert_eq(crate.cell(), Vector3i(-7, 0, -10), "the crate sits on the isle's stone")
	await _walk_to(Vector3(-4.5, 0.0, 4.5), 0.3)
	await wait_physics_frames(60)
	assert_gt(_me().global_position.z, 0.0, "still on the plaza: the far stone is taken")


# --- 6-2 霧の段丘 ----------------------------------------------------------------


## 西の鐘を鳴らして歩いて門へ向かうと、着く前に閉まる（ワープか W×2 が要る）。
func test_gate_misty_terraces_walking_from_the_bell_is_too_slow() -> void:
	await _enter(World6Stages.MIST_ID)
	await _ring("mist_bell")
	await _walk_to(Vector3(3.5, 0.0, -0.4), 0.35, 600)
	assert_false(await _try_walk_to(Vector3(3.5, 0.0, -4.6), 0.35, 120), "the gate closed first")


func test_gate_misty_terraces_shelf_bell_out_of_reach() -> void:
	await _enter(World6Stages.MIST_ID)
	assert_false(await _try_ring_from("shelf_bell", Vector3(10.5, 0.0, 3.4)), "out of reach")


## 門の前の石は出口だけ（踏んでも西へ戻されない）。
func test_gate_misty_terraces_gate_stone_is_an_exit_only() -> void:
	await _enter(World6Stages.MIST_ID)
	await _walk_to(Vector3(3.5, 0.0, -0.5), 0.3)
	await wait_physics_frames(60)
	assert_gt(_me().global_position.x, 0.0, "stayed by the gate")


# --- 6-3 峰の鐘 ------------------------------------------------------------------


## 東の島から、こだまの鐘には F が届かない（うさぎの木の実か、高台へ上がる）。
func test_gate_peak_bells_echo_bell_out_of_reach_from_the_isle() -> void:
	await _enter(World6Stages.PEAK_ID)
	assert_true(await _step_on_warp(Vector3(9.5, 0.0, 8.5)), "warped to the east isle")
	assert_false(await _try_ring_from("echo_bell", Vector3(22.6, 0.0, -2.0)), "out of reach")


## こだま石は、近くで鐘が鳴らなければ跳ねない（乗っていても上がらない）。
func test_gate_peak_bells_echo_stone_is_still_without_a_bell() -> void:
	await _enter(World6Stages.PEAK_ID)
	await _walk_to(Vector3(5.5, 1.0, 8.5))
	var top := _me().global_position.y
	for i in 180:
		top = maxf(top, _me().global_position.y)
		await tree.physics_frame
	assert_lt(top, 1.5, "the echo stone stays put")


## 峰の西の縁から、浮かずに（W×1 で）跳んでも尖塔（谷 7）には届かない。
func test_gate_peak_bells_spire_needs_the_balloon_or_double_speed() -> void:
	await _enter(World6Stages.PEAK_ID)
	assert_true(await _step_on_warp(Vector3(9.5, 0.0, 8.5)), "warped to the east isle")
	await _pick_and_wear(Vector3(21.5, 0.0, -3.5), RuleVessel.Part.FEET)
	await _walk_to(Vector3(24.0, 2.0, -2.5))
	await _walk_to(Vector3(24.5, 2.0, -12.5))
	await _lift_up("peak_lift", Vector3(10.5, 2.0, -12.5), Vector3(7.5, 4.0, -12.5))
	assert_false(
		await _leap_to(Vector3(-7.6, 4.0, -14.5), Vector3(-15.5, 1.0, -14.5)), "fell short"
	)


# --- 6-4 流れる川 ----------------------------------------------------------------


## 川（幅 5）は走って跳んでも越えられない（縁ちょうどでも）。
func test_gate_river_run_river_is_too_wide_to_jump() -> void:
	await _enter(World6Stages.RIVER_ID)
	var route: Array[Vector3] = [Vector3(10.5, 0.0, 6.5)]
	assert_true(is_nan(await _first_crossing(route, NORTH, -3.0, 5.0)), "the 5-wide river holds")


## 泳げないまま川に入ると沈み、落ちたのと同じく戻される。
func test_gate_river_run_without_swim_you_sink() -> void:
	await _enter(World6Stages.RIVER_ID)
	await _walk_to(Vector3(0.5, 0.0, 3.4), 0.3)
	_face(Vector3(0.5, 0.0, -1.0))
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(30)
	_me().move_intent = Vector2.ZERO
	var low := _me().global_position.y
	for i in 120:
		low = minf(low, _me().global_position.y)
		await tree.physics_frame
	assert_lt(low, -3.0, "sank")
	await _wait_respawn()


## 流されている筏に W を繰り返しで渡しても、北へはほとんど進まない（流れの 0.9 秒ごとの運びと、
## 繰り返しの 1.4 秒ごとの発動が重なると、動いている途中の発動が空振りする）。単発で押せば進む。
func test_finding_river_run_repeat_on_a_drifting_raft_rarely_fires() -> void:
	await _enter(World6Stages.RIVER_ID)
	var raft := _block("raft")
	await _walk_to(Vector3(-3.5, 0.0, 5.0), 0.3)
	_lend(raft, _slot_of(FORWARD), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(FORWARD)
	await wait_physics_frames(90)
	assert_true(await _board(raft), "on the raft")
	_lend(raft, _slot_of(FORWARD), TriggerMode.Kind.REPEAT)
	var start_z := raft.cell().z
	await wait_physics_frames(600)
	var moved := start_z - raft.cell().z
	print("    repeat W on a drifting raft: %d cell(s) north in 10 s" % moved)
	assert_lt(moved, 4, "far fewer than the 7 a still block would make")


# --- 6-5 長い尾根 ----------------------------------------------------------------


## 重くなければ、尾根で風が吹くと東の谷へ流される。
func test_gate_long_ridge_gust_blows_a_light_player_off() -> void:
	await _enter(World6Stages.RIDGE_ID)
	await _walk_to(Vector3(0.5, 0.0, 29.6))
	var gust := w.nature.layout.winds[0]
	for i in 600:
		if not gust.is_blowing(w.nature.clock):
			break
		await tree.physics_frame
	for i in 600:
		if gust.is_blowing(w.nature.clock):
			break
		await tree.physics_frame
	_face(Vector3(0.5, 0.0, 20.0))
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(60)
	_me().move_intent = Vector2.ZERO
	await wait_physics_frames(30)
	assert_lt(_me().global_position.y, -1.0, "blown off the ridge (at %s)" % _me().global_position)
	await _wait_respawn()


## 重いと泳ぐを両方ホットバーに置くと、池に沈む（重いは泳げても沈む）。
func test_gate_long_ridge_heavy_sinks_even_with_fins() -> void:
	await _enter(World6Stages.RIDGE_ID)
	await _pick_to_hotbar(Vector3(-3.5, 0.0, 32.5), HEAVY)
	await _pick_to_hotbar(Vector3(3.5, 0.0, 32.5), SWIM)
	await _walk_to(Vector3(0.5, 0.0, 29.6))
	await _walk_to(Vector3(0.5, 0.0, 8.3))
	_face(Vector3(0.5, 0.0, 5.0))
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(40)
	_me().move_intent = Vector2.ZERO
	var low := _me().global_position.y
	for i in 120:
		low = minf(low, _me().global_position.y)
		await tree.physics_frame
	assert_lt(low, -3.0, "sank with the weight")


## 重いと風船を両方ホットバーに置くと打ち消し合い（重さ 0）、風に流されるふつうの体になる。
func test_gate_long_ridge_weight_and_balloon_cancel_out() -> void:
	await _enter(World6Stages.RIDGE_ID)
	await _pick_to_hotbar(Vector3(-3.5, 0.0, 32.5), HEAVY)
	assert_true(BodyTraits.is_heavy(w.ledger, _me().player_id), "heavy")
	await _pick_to_hotbar(Vector3(-3.5, 0.0, 36.5), FLOAT)
	assert_eq(BodyTraits.weight(w.ledger, _me().player_id), 0, "they cancel out")
	assert_false(BodyTraits.is_heavy(w.ledger, _me().player_id), "the wind would carry me")


## 見晴らしから、何も持たずに追い風の無い向き（西）へ跳んでも、谷の向こうへは届かない
## （追い風は谷の上だけに吹き、北へ押す）。
func test_gate_long_ridge_tailwind_only_blows_north() -> void:
	await _enter(World6Stages.RIDGE_ID)
	var tail := w.nature.layout.winds[2]
	assert_eq(tail.direction, Vector3i(0, 0, -1), "the tailwind blows north")
	assert_true(tail.area().has_point(Vector3(0.5, 2.0, -8.0)), "over the gap")
	assert_false(tail.area().has_point(Vector3(0.5, 3.0, -3.5)), "not on the lookout")
