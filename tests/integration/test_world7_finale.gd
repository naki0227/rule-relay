extends "res://tests/integration/world7_playthrough.gd"
## 最終ステージ 7-6「頂の祭り」を、ひとりで最初から最後まで自動で遊ぶ（ひとりの道 2 通り）と、
## ゴールのお祝い（SummitFestival）。操作はプレイヤーと同じで、瞬間移動はしない。
## 協力の道は test_world7_coop.gd、関所の試遊は test_world7_probes.gd。

## 塔の段の東の端から、突風の棚を登って上の段へ。
const LEDGE: Array[Vector3] = [
	Vector3(10.5, 2.0, -54.5),
	Vector3(10.5, 3.0, -56.5),
	Vector3(10.5, 3.0, -63.5),
	Vector3(8.5, 4.0, -63.5),
	Vector3(4.5, 4.0, -63.5),
]
## 頂の扉を抜けて石段を上がる。
const GATE: Array[Vector3] = [
	Vector3(-0.5, 4.0, -67.5), Vector3(-0.5, 5.0, -68.5), Vector3(-0.5, 6.0, -70.5)
]


## ひとりの道 1: 風船で追い風の通り道 → 川の生き物に「投げる」を投げ渡して鐘 → 浮いて氷の船着き場へ流される →
## 風船をかばんへ戻し、木箱を風に運ばせて重いで扉を開け、重いを持って突風の棚 → 時の鐘を自分で鳴らして走る。
func test_summit_6_float_creature_crate_heavy_and_a_run() -> void:
	await _enter(World7Finale.SUMMIT_6)
	await _pick_to_hotbar(Vector3(4.5, 1.0, 4.5), FLOAT)
	assert_true(
		await _run_and_jump(
			Vector3(0.5, 1.0, 3.5), Vector3(0.5, 1.0, 0.3), Vector3(0.5, 0.0, -14.5)
		),
		"glided over the sky gap on the tailwind"
	)
	await _walk_to(Vector3(0.5, 0.0, -23.0))
	_lend_by_throwing(_creature("river_creature"), _slot_of(THROW))
	assert_true(await _wait_until_rung("river_bell"), "the creature's nut rang the river bell")
	await _walk_to(Vector3(6.5, 0.0, -23.5))
	assert_true(
		await _drift_until(16.4, Vector3(19.2, 0.0, -25.6)), "floated down to the icy landing"
	)
	await _walk_to(Vector3(19.5, 0.0, -37.5))
	_hotbar_to_bag(FLOAT)
	await _walk_route([Vector3(-10.5, 0.0, -44.5), Vector3(-17.5, 0.0, -46.5)])
	await _recall_all_from("crate")
	assert_true(
		await _wait_block_at("crate", World7Finale.FESTIVAL_CRATE_PLATE),
		"the wind carried the crate"
	)
	await _walk_route([Vector3(-9.5, 0.0, -46.5), Vector3(-6.5, 0.0, -44.5)])
	_lend(_block("crate"), _bag_to_hotbar(HEAVY), TriggerMode.Kind.NONE)
	assert_true(await _wait_door_open("stair_gate"), "the heavy crate opens the stair gate")
	await _walk_route([Vector3(-6.5, 0.0, -46.5), Vector3(-6.5, 1.0, -47.6)])
	await _recall_all_from("crate")
	await _walk_to(Vector3(-6.5, 2.0, -49.5))
	await _walk_route(LEDGE)
	await _ring("summit_chime")
	await _walk_route(GATE)
	assert_gt(_me().global_position.y, 5.5, "ran through the gate while the chime rang")
	await _walk_into_goal()
	assert_true(await _cleared(), "both bells and everyone at the summit")
	var festival := SummitFestival.of(w)
	assert_ne(festival, null, "the summit has its festival")
	assert_true(festival.started, "the festival starts with the clear")
	assert_gt(festival.guests.size(), 0, "the wish animals gather")


## ひとりの道 2: おもりを持って西の尾根 → おもりをかばんへ戻して足ひれで小島へ泳ぎ、鐘に触って北の岸へ →
## 札付きの台の札を手放して乗る → おもりを出して突風の棚 → 時の鐘のそばの生き物に「投げる」を投げ渡す。
func test_summit_6_heavy_ridge_swim_signed_lift_and_the_chime_creature() -> void:
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
	_hotbar_to_bag(HEAVY)
	await _pick_to_hotbar(Vector3(6.5, 0.0, -14.5), SWIM)
	await _walk_to(Vector3(-4.5, 0.0, -23.5))
	assert_true(await _swim_to(Vector3(0.0, 0.0, -28.0)), "swam onto the islet")
	await _ring("river_bell")
	await _walk_to(Vector3(-0.5, 0.0, -31.5))
	assert_true(await _swim_to(Vector3(-4.5, 0.0, -36.5)), "swam to the north bank")
	await _walk_to(Vector3(4.5, 0.0, -44.2))
	w.interact(_block("signed_lift"))
	await wait_physics_frames(2)
	assert_true(w.ledger.player_prohibited(JUMP, _me().player_id), "the sign is on me")
	_hand_off_ban(JUMP, w.terrain_target(Vector3i(6, -1, -43)))
	await _lift_up("signed_lift", Vector3(4.5, 0.0, -44.2), Vector3(4.5, 2.0, -47.5))
	_bag_to_hotbar(HEAVY)
	await _walk_route(LEDGE)
	await _walk_to(Vector3(-0.5, 4.0, -66.5))
	_lend_by_throwing(_creature("chime_creature"), _slot_of(THROW))
	assert_true(await _wait_until_rung("summit_chime"), "the creature's nut rang the chime")
	assert_true(await _wait_door_open("summit_gate"), "the chime opens the summit gate")
	await _walk_route(GATE)
	await _walk_into_goal()
	assert_true(await _cleared(), "both bells and everyone at the summit")


## お祝いの置物と並び: 提灯の柱が 4 本（骨格付きで揺れる）、生き物は作ってある本編のステージの分
## （最終ステージ自身は除く）が、ゴールの南の床に並ぶ。お祝いは一度だけ。
func test_summit_6_festival_lanterns_and_guests() -> void:
	await _enter(World7Finale.SUMMIT_6)
	var festival := SummitFestival.of(w)
	assert_ne(festival, null, "built on the final stage")
	assert_eq(festival.lanterns.size(), 4, "four lantern poles")
	for lantern in festival.lanterns:
		assert_eq(lantern.find_children("*", "Skeleton3D", true, false).size(), 1, "rigged")
		var players := lantern.find_children("*", "AnimationPlayer", true, false)
		assert_true(
			not players.is_empty() and (players[0] as AnimationPlayer).is_playing(), "sways"
		)
	var specs := SummitFestival.guest_specs(_goal())
	assert_gt(specs.size(), 10, "everyone the player has helped so far")
	for spec in specs:
		assert_false(_goal().has_point(spec.home), "guests stand outside the goal hollow")
		assert_false(spec.stage_id.ends_with(World7Finale.SUMMIT_6), "not the final stage itself")
	festival.start()
	festival.start()
	assert_eq(festival.guests.size(), specs.size(), "the guests appear once")
	assert_eq(StageCatalog.by_id(StageCatalog.INTRO_ID).festival, false, "only the final stage")
