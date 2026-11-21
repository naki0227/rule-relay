extends "res://tests/integration/world7_playthrough.gd"
## ワールド 7「空の頂」を、ひとりで最初から最後まで自動で遊ぶ（通しプレイ。ひとりの道を 2 通りずつ）。
## 操作はプレイヤーと同じ（移動の入力・向き・キー・F・渡す）で、瞬間移動はしない。
## 協力の道は test_world7_coop.gd、関所と詰みの試遊は test_world7_probes.gd。

## 雲の野原から西の尾根を歩いて、ふもとの段へ。
const SUMMIT_1_RIDGE: Array[Vector3] = [
	Vector3(-8.5, 1.0, 2.5),
	Vector3(-13.5, 1.0, 2.5),
	Vector3(-13.5, 1.0, -11.5),
	Vector3(-13.5, 0.0, -13.5),
]

## 塔の段の東の端から、突風の棚を登って上の段へ（重いを持っていれば一気に）。
const SUMMIT_3_LEDGE: Array[Vector3] = [
	Vector3(10.5, 2.0, -9.5),
	Vector3(10.5, 3.0, -11.5),
	Vector3(10.5, 3.0, -18.5),
	Vector3(8.5, 4.0, -18.5),
	Vector3(4.5, 4.0, -18.5),
]

## 頂の扉を抜けて石段を上がる。
const SUMMIT_3_GATE: Array[Vector3] = [
	Vector3(-0.5, 4.0, -22.5), Vector3(-0.5, 5.0, -23.5), Vector3(-0.5, 6.0, -25.5)
]

# --- 7-1 頂のふもと ------------------------------------------------------------


## ひとりの道 1: 風船（浮く）で追い風の通り道を渡り、生き物に「投げる」を投げ渡して鐘、窪みのブロックで台へ。
func test_summit_1_float_on_the_tailwind_and_the_creature() -> void:
	await _enter(World7Stages.SUMMIT_1)
	await _pick_to_hotbar(Vector3(4.5, 1.0, 4.5), FLOAT)
	assert_true(
		await _run_and_jump(
			Vector3(0.5, 1.0, 3.5), Vector3(0.5, 1.0, 0.3), Vector3(0.5, 0.0, -14.5)
		),
		"glided over the sky gap on the tailwind"
	)
	await _walk_to(Vector3(-1.5, 0.0, -19.5))
	_lend_by_throwing(_creature("foot_creature"), _slot_of(THROW))
	assert_true(await _wait_until_rung("foot_bell"), "the creature's nut rang the bell")
	await _lift_up("foot_lift", Vector3(3.5, 0.0, -22.5), Vector3(2.5, 2.0, -26.5))
	await _walk_into_goal()
	assert_true(await _cleared(), "the bell and everyone at the goal")


## ひとりの道 2: おもり（重い）を持って西の尾根の横風を歩いて渡り、窪みのブロックで台へ上がって鐘に触る。
func test_summit_1_heavy_over_the_windy_ridge() -> void:
	await _enter(World7Stages.SUMMIT_1)
	await _pick_to_hotbar(Vector3(-5.5, 1.0, 5.5), HEAVY)
	await _walk_route(SUMMIT_1_RIDGE)
	await _lift_up("foot_lift", Vector3(3.5, 0.0, -22.5), Vector3(2.5, 2.0, -26.5))
	await _ring("foot_bell")
	await _walk_into_goal()
	assert_true(await _cleared(), "the bell and everyone at the goal")


## ひとりの道 3（おもり無し）: 横風のやむ間に尾根を進み、途中の岩の張り出しで次のやむ間を待つ。
func test_summit_1_ridge_between_the_gusts() -> void:
	await _enter(World7Stages.SUMMIT_1)
	await _walk_route([Vector3(-8.5, 1.0, 2.5), Vector3(-13.5, 1.0, 2.5), Vector3(-13.5, 1.0, 0.5)])
	await _wait_for_calm(2)
	await _walk_route([Vector3(-13.5, 1.0, -4.5), Vector3(-14.5, 1.0, -5.5)])
	await _wait_for_calm(1)
	await _walk_route([Vector3(-13.5, 1.0, -7.5), Vector3(-13.5, 0.0, -13.5)])
	assert_gt(_me().global_position.y, -0.5, "made it over the ridge on foot")
	await _lift_up("foot_lift", Vector3(3.5, 0.0, -22.5), Vector3(2.5, 2.0, -26.5))
	await _ring("foot_bell")
	await _walk_into_goal()
	assert_true(await _cleared(), "the bell and everyone at the goal")


# --- 7-2 雲の階段 --------------------------------------------------------------


## ひとりの道 1: ダッシュと風船を拾い、跳んで頂点で空中ダッシュ、浮いて谷を越える。窪みのブロックで頂の島へ。
func test_summit_2_dash_then_float_over_the_gap() -> void:
	await _enter(World7Stages.SUMMIT_2)
	var dash_slot := await _pick_to_hotbar(Vector3(3.5, 1.0, 5.5), DASH)
	await _pick_to_hotbar(Vector3(1.5, 1.0, 2.5), FLOAT)
	assert_true(
		await _dash_glide(Vector3(0.5, 1.0, 3.5), 0.3, Vector3(0.5, 0.0, -14.5), dash_slot),
		"dash at the top of the jump, then float down onto the middle isle"
	)
	await _lift_up("cloud_lift", Vector3(1.5, 0.0, -20.5), Vector3(0.5, 2.0, -24.5))
	await _ring("cloud_bell")
	await _walk_into_goal()
	assert_true(await _cleared(), "the bell and everyone at the goal")


## ひとりの道 2: 生き物に移動とジャンプを渡して小山の板に乗せ、開いた扉の奥のワープの石で中の島へ。
func test_summit_2_creature_holds_the_gate_for_the_warp() -> void:
	await _enter(World7Stages.SUMMIT_2)
	var critter := _creature("knoll_creature")
	await _walk_to(Vector3(-2.5, 1.0, 5.5))
	_lend(critter, _slot_of(RIGHT), TriggerMode.Kind.NONE)
	_lend(critter, _slot_of(JUMP), TriggerMode.Kind.NONE)
	assert_true(
		await _wait_creature_in("knoll_creature", AABB(Vector3(-5, 1.9, 6), Vector3(1, 1, 1))),
		"the creature hopped onto the knoll"
	)
	assert_true(await _wait_door_open("nook_gate"), "its weight opens the gate")
	await _walk_to(Vector3(-3.5, 1.0, 5.0))
	await _recall_creature("knoll_creature")
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "my jump is back")
	await wait_physics_frames(30)
	assert_true(await _wait_door_open("nook_gate"), "the creature stays on the plate")
	await _walk_to(Vector3(-5.5, 1.0, 3.5))
	await _walk_to(Vector3(-7.5, 1.0, 3.5))
	assert_true(
		await _step_onto_warp(Vector3(-8.5, 1.0, 3.5), Vector3(-5.5, 0.0, -13.5)),
		"warped to the middle isle"
	)
	await _walk_to(Vector3(-4.5, 0.0, -15.5))
	await _lift_up("cloud_lift", Vector3(1.5, 0.0, -20.5), Vector3(0.5, 2.0, -24.5))
	await _ring("cloud_bell")
	await _walk_into_goal()
	assert_true(await _cleared(), "the bell and everyone at the goal")


# --- 7-3 風と札の塔 ------------------------------------------------------------


## ひとりの道 1: 木箱の重いを回収して風に運ばせ、板の上で重いを渡し直して扉を開ける。扉の内側から重いを取り戻し、
## 突風の棚を流されずに登る。頂の扉は、生き物に「投げる」を投げ渡して時の鐘を鳴らしてもらう。
func test_summit_3_crate_on_the_wind_heavy_ledge_and_the_creature() -> void:
	await _enter(World7Stages.SUMMIT_3)
	await _walk_route(
		[Vector3(-7.5, 0.0, 1.5), Vector3(-10.5, 0.0, -1.5), Vector3(-17.5, 0.0, -1.5)]
	)
	await _recall_all_from("crate")
	assert_true(
		await _wait_block_at("crate", World7Stages.CRATE_PLATE), "the wind carried the crate"
	)
	assert_lt(_door_open_amount("stair_gate"), 0.05, "the crate alone is too light")
	await _walk_route([Vector3(-9.5, 0.0, -1.5), Vector3(-6.5, 0.0, 0.5)])
	_lend(_block("crate"), _bag_to_hotbar(HEAVY), TriggerMode.Kind.NONE)
	assert_true(await _wait_door_open("stair_gate"), "the heavy crate opens the stair gate")
	await _walk_route([Vector3(-6.5, 0.0, -1.5), Vector3(-6.5, 1.0, -2.6)])
	await _recall_all_from("crate")
	await _walk_to(Vector3(-6.5, 2.0, -4.5))
	assert_ne(_slot_of(HEAVY), -1, "carrying the heavy weight")
	await _walk_route(SUMMIT_3_LEDGE)
	await _walk_to(Vector3(-0.5, 4.0, -21.5))
	_lend_by_throwing(_creature("chime_creature"), _slot_of(THROW))
	assert_true(await _wait_until_rung("summit_chime"), "the creature's nut rang the chime")
	assert_true(await _wait_door_open("summit_gate"), "the chime opens the summit gate")
	await _walk_route(SUMMIT_3_GATE)
	await _walk_into_goal()
	assert_true(await _cleared(), "the chime and everyone at the goal")


## ひとりの道 2: 札付きの台の札を手放して乗り、突風のやむ間に棚を登り、自分で時の鐘を鳴らして扉まで走る。
func test_summit_3_signed_lift_gust_timing_and_a_run_to_the_gate() -> void:
	await _enter(World7Stages.SUMMIT_3)
	await _walk_to(Vector3(4.5, 0.0, 0.8))
	w.interact(_block("signed_lift"))
	await wait_physics_frames(2)
	assert_true(w.ledger.player_prohibited(JUMP, _me().player_id), "the sign is on me")
	_hand_off_ban(JUMP, w.terrain_target(Vector3i(6, -1, 2)))
	await _lift_up("signed_lift", Vector3(4.5, 0.0, 0.8), Vector3(4.5, 2.0, -2.5))
	await _walk_to(Vector3(10.5, 2.0, -9.5))
	await _wait_for_calm(1)
	await _walk_route([Vector3(10.5, 3.0, -11.5), Vector3(10.5, 3.0, -14.5)])
	await _wait_for_calm(2)
	await _walk_route([Vector3(10.5, 3.0, -18.5), Vector3(8.5, 4.0, -18.5)])
	assert_gt(_me().global_position.y, 3.5, "up on the upper step")
	await _ring("summit_chime")
	await _walk_route(SUMMIT_3_GATE)
	assert_gt(_me().global_position.y, 5.5, "ran through the gate while the chime rang")
	await _walk_into_goal()
	assert_true(await _cleared(), "the chime and everyone at the goal")


# --- 7-4 流れの上の鐘 ----------------------------------------------------------


## 北の岸から窪みのブロックで高台へ上がり、ゴールへ。
func _summit_4_north_bank_to_goal(from: Vector3) -> void:
	await _walk_route([from, Vector3(1.5, 1.0, -18.5)])
	await _lift_up("terrace_lift", Vector3(1.5, 1.0, -18.5), Vector3(0.5, 3.0, -21.5))
	await _walk_into_goal()
	assert_true(await _cleared(), "the river bell and everyone at the goal")


## ひとりの道 1: 生き物に「投げる」を投げ渡して鐘を鳴らし、風船を持って川に入り、浮いて船着き場まで流される。
func test_summit_4_creature_rings_and_the_float_drifts_to_the_landing() -> void:
	await _enter(World7Finale.SUMMIT_4)
	await _walk_to(Vector3(0.5, 1.0, 1.0))
	_lend_by_throwing(_creature("river_creature"), _slot_of(THROW))
	assert_true(await _wait_until_rung("river_bell"), "the creature's nut rang the river bell")
	await _pick_to_hotbar(Vector3(-4.5, 1.0, 5.5), FLOAT)
	await _walk_to(Vector3(6.5, 1.0, 0.5))
	assert_true(
		await _drift_until(14.4, Vector3(17.2, 1.0, -0.6)),
		"floated down to the landing and hopped out"
	)
	await _summit_4_north_bank_to_goal(Vector3(17.5, 1.0, -12.5))


## ひとりの道 2: 足ひれで小島へ泳いで上がって鐘に触り、北の岸へ泳ぐ。
func test_summit_4_swim_to_the_islet_and_across() -> void:
	await _enter(World7Finale.SUMMIT_4)
	await _pick_to_hotbar(Vector3(6.5, 1.0, 4.5), SWIM)
	await _walk_to(Vector3(-4.5, 1.0, 0.5))
	assert_true(await _swim_to(Vector3(0.0, 1.0, -4.0)), "swam onto the islet")
	await _ring("river_bell")
	await _walk_to(Vector3(-0.5, 1.0, -7.5))
	assert_true(await _swim_to(Vector3(4.5, 1.0, -12.5)), "swam over to the north bank")
	await _summit_4_north_bank_to_goal(Vector3(4.5, 1.0, -13.5))


## ひとりの道 3: 筏に乗って W を単発で渡し、川へ押し出して船着き場まで流される（鐘は生き物で）。
func test_summit_4_raft_ride_to_the_landing() -> void:
	await _enter(World7Finale.SUMMIT_4)
	await _walk_to(Vector3(0.5, 1.0, 1.0))
	_lend_by_throwing(_creature("river_creature"), _slot_of(THROW))
	assert_true(await _wait_until_rung("river_bell"), "the creature's nut rang the river bell")
	var raft := _block("raft")
	await _walk_to(Vector3(-7.5, 1.0, 2.5))
	await _walk_to(raft.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	await wait_physics_frames(20)
	_lend(raft, _slot_of(FORWARD), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(FORWARD)
	assert_true(
		await _wait_block_at("raft", Vector3i(15, 0, -1), 2400), "the current took the raft"
	)
	assert_gt(_me().global_position.y, 0.6, "rode it all the way")
	await _walk_to(Vector3(17.5, 1.0, -1.5))
	await _summit_4_north_bank_to_goal(Vector3(17.5, 1.0, -12.5))


# --- 7-5 みんなの橋 ------------------------------------------------------------


## 囲いの扉（x）を抜けてワープの石で北の島へ渡り、窪みのブロックで高台、鐘、ゴール。
func _summit_5_through_the_cage(door_x: float) -> void:
	await _walk_route(
		[Vector3(door_x, 1.0, -1.5), Vector3(door_x, 1.0, -4.5), Vector3(0.5, 1.0, -5.5)]
	)
	assert_true(
		await _step_onto_warp(Vector3(0.5, 1.0, -6.5), Vector3(0.5, 1.0, -21.5)), "warped north"
	)
	await _walk_to(Vector3(1.5, 1.0, -24.5))
	await _lift_up("isle_lift", Vector3(1.5, 1.0, -28.5), Vector3(0.5, 3.0, -31.5))
	await _ring("bridge_bell")
	await _walk_into_goal()
	assert_true(await _cleared(), "the bridge bell and everyone at the goal")


## ひとりの道 1: 2 つの石に範囲で W を繰り返しで渡し、2 枚の板に一度に乗せる（二つ板の扉）。
func test_summit_5_range_slides_both_stones_onto_the_plates() -> void:
	await _enter(World7Finale.SUMMIT_5)
	await _walk_to(Vector3(0.5, 1.0, 7.8), 0.3)
	w.select_slot(_slot_of(FORWARD))
	w.set_lend_mode(TriggerMode.Kind.REPEAT)
	assert_eq(w.lend_to(_block("west_stone"), true), RuleLedger.LendResult.OK, "range lend")
	assert_true(await _wait_block_at("west_stone", World7Finale.WEST_PLATE), "west stone slid")
	assert_true(await _wait_block_at("east_stone", World7Finale.EAST_PLATE), "east stone slid")
	assert_true(await _wait_door_open("twin_gate"), "both plates down")
	await _back_to(Vector3(0.5, 1.0, 3.6))
	for i in 120:
		if w.ledger.player_can(FORWARD, _me().player_id):
			break
		if i % 10 == 0:
			w.interact(_block("west_stone"))
		await tree.physics_frame
	assert_true(w.ledger.player_can(FORWARD, _me().player_id), "my W is back")
	await _summit_5_through_the_cage(-0.5)


## ひとりの道 2: 生き物を小山の板に乗せ、東の石だけを東の板へすべらせる（小山の扉）。
func test_summit_5_creature_on_the_knoll_and_one_stone() -> void:
	await _enter(World7Finale.SUMMIT_5)
	var critter := _creature("knoll_creature")
	await _walk_to(Vector3(-4.5, 1.0, 3.5))
	_lend(critter, _slot_of(RIGHT), TriggerMode.Kind.NONE)
	_lend(critter, _slot_of(JUMP), TriggerMode.Kind.NONE)
	assert_true(
		await _wait_creature_in("knoll_creature", AABB(Vector3(-7, 1.9, 1), Vector3(1, 1, 1))),
		"the creature hopped onto the knoll"
	)
	await _recall_creature("knoll_creature")
	await _slide_north("east_stone", Vector3(2.5, 1.0, 7.8), World7Finale.EAST_PLATE)
	assert_true(await _wait_door_open("knoll_gate"), "the knoll and the east plate are down")
	assert_lt(_door_open_amount("twin_gate"), 0.05, "the twin gate stays shut")
	await _summit_5_through_the_cage(0.5)
