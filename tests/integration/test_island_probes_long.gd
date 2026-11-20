extends "res://tests/integration/island_probing.gd"
## 「遠征」の関所と詰みを、プレイヤーと同じ操作で壊しにいく試遊（2026-11-20）。
## 書き方は test_island_probes.gd と同じ（test_gate_* は関所、test_finding_* は見つけた挙動の記録）。
## 結果は docs/adr/0011 の「10・18・40 分の島」にまとめた。


## 森の台地へ、岩棚の窪みのブロックで上がる（試遊の準備）。
func _up_to_the_forest_plateau() -> void:
	await _walk_to(Vector3(7.5, 1.0, -18.5))
	await _lift_up("forest_lift", Vector3(7.5, 1.0, -18.5), Vector3(6.5, 3.0, -21.5))


# --- 関所 ---------------------------------------------------------------------


func test_gate_expedition_east_gap_of_five_is_not_a_running_jump() -> void:
	await _enter(StageCatalog.EXPEDITION_ID)
	await _walk_to(Vector3(9.5, 0.0, -14.5))  # チェックポイントで保存して、落ちたらここへ戻る
	var route: Array[Vector3] = [Vector3(9.5, 0.0, -6.5)]
	var offset := await _first_crossing(route, Vector3.RIGHT, 13.0, 5.0)
	assert_true(is_nan(offset), "a plain running jump never crosses the 5-wide gap to the cape")
	assert_false(w.activated.has("east_bell"), "the east bell is still silent")


func test_gate_expedition_ground_dash_alone_does_not_cross_the_east_gap() -> void:
	await _enter(StageCatalog.EXPEDITION_ID)
	await _pick_to_hotbar(Vector3(5.5, 0.0, 10.5), DASH)
	await _walk_to(Vector3(9.5, 0.0, -14.5))
	assert_false(await _ground_dash(Vector3(12.8, 0.0, -6.5), Vector3.RIGHT), "3 m < gap 5")
	assert_lt(_me().global_position.x, 13.0, "back on the meadow")


func test_gate_expedition_cliffs_are_not_plain_jumps() -> void:
	await _enter(StageCatalog.EXPEDITION_ID)
	var best := await _jump_against(Vector3(2.5, 0.0, -19.2), Vector3(2.5, 3.0, -21.5))
	assert_lt(best, 1.5, "meadow (0) to the forest plateau (3)")
	await _walk_to(Vector3(5.5, 1.0, -19.5))
	best = await _jump_against(Vector3(4.5, 1.0, -19.7), Vector3(4.5, 3.0, -21.5))
	assert_lt(best, 2.5, "ledge (1) to the forest plateau (3)")
	await _walk_to(Vector3(-11.5, 0.0, -10.5))
	best = await _jump_against(Vector3(-23.6, 1.0, -12.5), Vector3(-25.5, 3.0, -12.5))
	assert_lt(best, 2.5, "west terrace (1) to the west plateau (3)")


func test_gate_expedition_upper_steps_are_not_plain_jumps() -> void:
	await _enter(StageCatalog.EXPEDITION_ID)
	await _up_to_the_forest_plateau()
	var best := await _jump_against(Vector3(4.5, 3.0, -29.7), Vector3(4.5, 5.0, -31.5))
	assert_lt(best, 4.5, "forest plateau (3) to the upper step (5)")
	await _lift_up("ridge_lift", Vector3(-1.5, 3.0, -28.5), Vector3(-2.5, 5.0, -31.5))
	best = await _jump_against(Vector3(3.5, 5.0, -41.7), Vector3(3.5, 7.0, -43.5))
	assert_lt(best, 6.5, "upper step (5) to the summit (7)")
	best = await _jump_against(Vector3(10.7, 5.0, -38.5), Vector3(12.5, 7.0, -38.5))
	assert_lt(best, 6.5, "upper step (5) to the lookout (7)")


func test_gate_expedition_bells_are_not_rung_from_below() -> void:
	await _enter(StageCatalog.EXPEDITION_ID)
	await _walk_to(Vector3(-11.5, 0.0, -10.5))
	assert_false(await _try_ring_from("west_bell", Vector3(-23.6, 1.0, -9.5)), "west from below")
	await _walk_to(Vector3(-13.5, 1.0, -12.5))
	assert_false(await _try_ring_from("forest_bell", Vector3(0.5, 0.0, -19.7)), "forest from below")
	await _up_to_the_forest_plateau()
	await _lift_up("ridge_lift", Vector3(-1.5, 3.0, -28.5), Vector3(-2.5, 5.0, -31.5))
	assert_false(
		await _try_ring_from("lookout_bell", Vector3(10.6, 5.0, -36.5)), "lookout from below"
	)


func test_gate_expedition_lookout_lift_sign_keeps_it_down() -> void:
	await _enter(StageCatalog.EXPEDITION_ID)
	await _up_to_the_forest_plateau()
	await _lift_up("ridge_lift", Vector3(-1.5, 3.0, -28.5), Vector3(-2.5, 5.0, -31.5))
	var signed := _block("lookout_lift")
	var rest_y := signed.global_position.y
	await _walk_to(Vector3(9.5, 5.0, -35.5))
	_lend(signed, _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	await _walk_to(signed.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	w.press_action(JUMP)
	await wait_physics_frames(40)
	assert_almost(signed.global_position.y, rest_y, 0.05, "the sign keeps the lift down")
	assert_lt(_me().global_position.y, 5.6, "still on the upper step")


# --- 詰み・記録 ------------------------------------------------------------------


## 「投げる」は 1 つだけ。森の生き物に投げ渡すと、生き物は台地の上なので F で取り戻せず、発射台は撃てない。
## それでも東の岬はダッシュ（跳んでから空中で）で渡って鳴らせるので、詰まない。
func test_gate_expedition_throw_spent_on_the_creature_still_leaves_the_dash_way_east() -> void:
	await _enter(StageCatalog.EXPEDITION_ID)
	var dash_slot := await _pick_to_hotbar(Vector3(5.5, 0.0, 10.5), DASH)
	await _walk_to(Vector3(0.5, 0.0, -18.5))
	_lend_by_throwing(_creature("forest_creature"), _slot_of(THROW))
	assert_true(await _wait_until_rung("forest_bell"), "the creature rang the forest bell")
	assert_false(w.ledger.player_can(THROW, _me().player_id), "the throw stays with the creature")
	await _walk_to(Vector3(10.5, 0.0, -6.5), 0.25)
	_face(Vector3(19.5, 0.0, -6.5))
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(12)
	w.press_action(JUMP)
	for i in 60:
		await tree.physics_frame
		if _me().velocity.y < 0.0:
			break
	assert_eq(_slot_of(DASH), dash_slot, "dash on the hotbar")
	w.press_action(DASH)
	await _walk_to(Vector3(19.5, 0.0, -6.5), 0.6, 240)
	await _ring("east_bell")


## 森の台地で自分のジャンプを「投げる」の届き方で上の段の奥のセルへ繰り返しで貸し、そのまま台地の
## チェックポイントに触れると、ジャンプの無い状態が保存される（歩けるので保存は拒まれない）。
## 台地から上へは、ジャンプが無いと窪みのブロックもブーツも使えず、グローブは谷 5 の向こうの岬にある
## （ジャンプなしでは渡れない）。全員リセット（V）はこの保存へ戻るので抜けられない。
## メニューの「島のはじめから」（ひとりなら本当に最初から）で戻れる。40 分の島では、それまでの進み具合を失う。
func test_finding_expedition_jump_thrown_away_then_saved_needs_a_restart() -> void:
	await _enter(StageCatalog.EXPEDITION_ID)
	await _up_to_the_forest_plateau()
	await _walk_to(Vector3(6.5, 3.0, -27.5))
	w.toggle_reach()
	assert_true(w.throw_mode, "throw reach")
	_lend(w.terrain_target(Vector3i(0, 4, -38)), _slot_of(JUMP), TriggerMode.Kind.REPEAT)
	w.toggle_reach()
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "jump is away")
	await _walk_to(Vector3(9.5, 3.0, -27.5), 0.3)
	await wait_physics_frames(4)
	assert_eq(director.lifecycle.latest_checkpoint(), "cp2", "FINDING: saved without a jump")
	# 上の段の縁のセルまで届かない（奥のセルは触る距離の外）
	await _walk_to(Vector3(0.5, 3.0, -29.7), 0.3)
	w.interact(w.terrain_target(Vector3i(0, 4, -38)))
	await wait_physics_frames(2)
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "out of touch from the plateau")
	director.request_vote()
	await wait_physics_frames(6)
	assert_false(
		w.ledger.player_can(JUMP, _me().player_id), "FINDING: V returns to the jumpless save"
	)
	w.restart_island()
	w = director.world
	await wait_physics_frames(10)
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "restart from the beginning recovers")
