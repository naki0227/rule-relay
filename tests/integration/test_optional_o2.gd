extends "res://tests/integration/optional_playthrough.gd"
## 寄り道 O2「さかさ雲」を、想定の解き方でひとりで最初から最後まで遊ぶ（通しプレイ）。
## 操作はプレイヤーと同じ（歩く・跳ぶ・渡す・拾う・F・キーを押す）だけで、瞬間移動はしない。
## 抜け道と詰みの試遊は test_optional_o2_probes.gd。

const REPEAT := TriggerMode.Kind.REPEAT
const SINGLE := TriggerMode.Kind.SINGLE_SHOT

# --- O2-1 風見の段々 ----------------------------------------------------------


## 塔の風船を取り、追い風の東の段で地面のセルの持ち上げ＋自分のジャンプから滑空して北の島へ。
func test_o2_1_vane_steps_by_the_tailwind() -> void:
	await _enter("o2_1")
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
	await _pick(Vector3(-4.5, 6.0, 1.5), FLOAT)
	await _walk_route([Vector3(-1.5, 5.0, 0.5), Vector3(-1.5, 1.0, 4.5), Vector3(4.5, 0.0, 4.0)])
	await _walk_route([Vector3(7.5, 1.0, 3.5), Vector3(9.5, 2.0, 3.5)])
	await _pick(Vector3(10.5, 2.0, 5.5), RIGHT)
	await _walk_to(Vector3(10.5, 2.0, 0.5), 0.2)
	var landed := await _lift_jump_toward(Vector3i(10, 1, 0), Vector3(10.5, 0.0, -42.0))
	assert_lt(landed.z, -35.5, "glided over the cloud gap (landed at %s)" % landed)
	assert_almost(landed.y, 0.0, 0.3, "on the north island")
	await _walk_to(Vector3(3.5, 0.0, -37.5), 0.3)
	_give_creature("bunny", [RIGHT, JUMP])
	assert_true(await _creature_home("bunny", OptionalWorldsO2.VANE_NEST), "the bunny went home")
	await _walk_to(Vector3(0.5, 0.0, -37.6), 0.3)
	await _recall_creature("bunny")
	await _walk_into_goal(
		[Vector3(8.5, 0.0, -42.5), Vector3(8.5, 1.0, -43.5), Vector3(8.5, 2.0, -45.5)]
	)
	assert_true(await _cleared(), "cleared the vane steps")


# --- O2-2 雲の筏 --------------------------------------------------------------


## 重いを持って横風の橋を渡り、風船はかばんに入れて戻る。重いを板の上の箱に渡して雲の段を上げ、2 回滑空する。
func test_o2_2_cloud_raft_heavy_then_float() -> void:
	await _enter("o2_2")
	var anchor := _block("anchor")
	await _walk_to(Vector3(0.5, 0.0, -4.5), 0.3)
	await _recall_all_from("anchor")
	_ensure_on_hotbar(HEAVY)
	assert_true(await _wait_block_at("anchor", Vector3i(8, 0, -6), 900), "the wind took the crate")
	# 横風の橋（重いので流されない）
	await _walk_route([Vector3(-5.5, 0.0, -1.5), Vector3(-15.5, 0.0, -1.5), Vector3(-17.5, 0.0, -2.5)])
	await _pick_to_bag(Vector3(-19.5, 0.0, -2.5))
	assert_eq(_slot_of(FLOAT), -1, "the balloon stays in the bag")
	await _walk_route([Vector3(-15.5, 0.0, -1.5), Vector3(-6.0, 0.0, -1.5)])
	await _walk_to(Vector3(7.5, 0.0, -4.5), 0.3)
	_give(anchor, HEAVY, TriggerMode.Kind.NONE)
	assert_true(await _wait(func() -> bool: return _door("cloud_step").is_closed(), 300), "the cloud step rose")
	# 段々を上がって見晴らしへ。生き物を巣へ
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
	await _walk_to(Vector3(2.5, 6.0, -16.15), 0.1)
	_give_creature("lamb", [RIGHT, JUMP])
	assert_true(await _creature_home("lamb", OptionalWorldsO2.RAFT_NEST), "the lamb went home")
	await _recall_creature("lamb")
	_bag_to_hotbar(FLOAT)
	await _walk_to(Vector3(2.5, 6.0, -19.5), 0.2)
	var on_step := await _lift_jump_toward(Vector3i(2, 5, -20), Vector3(2.5, 3.0, -53.5), 900, true)
	assert_almost(on_step.y, 3.0, 0.3, "landed on the cloud step (%s)" % on_step)
	var landed := await _run_jump_glide(
		Vector3(2.5, 3.0, -53.5), Vector3(2.5, 3.0, -54.8), Vector3(2.5, 0.0, -73.0)
	)
	assert_lt(landed.z, -68.5, "glided to the north island (%s)" % landed)
	await _walk_into_goal(
		[Vector3(8.5, 0.0, -72.5), Vector3(8.5, 1.0, -74.5), Vector3(8.5, 2.0, -76.5)]
	)
	assert_true(await _cleared(), "cleared the cloud raft")


## edge から跳んで滑空し、target の真上に来たら進むのをやめて降りる（浮くは落ちる速さが遅いので止まれる）。
func _glide_to(edge: Vector3, target: Vector3, frames: int = 900) -> Vector3:
	await _walk_to(edge, 0.2)
	var jumped := false
	for i in frames:
		var flat := Vector3(target.x - _me().global_position.x, 0.0, target.z - _me().global_position.z)
		_me().move_intent = _steer(target) if flat.length() > 0.3 else Vector2.ZERO
		if not jumped and _me().is_on_floor():
			w.press_action(JUMP)
			jumped = true
		elif jumped and i > 5 and _me().is_on_floor():
			break
		if _me().global_position.y < -8.0:
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	return _me().global_position


# --- O2-3 落ちる島々 ----------------------------------------------------------


## 滑空で降り、重いと浮くを入れ替えて強い風の段を登り、風を追い風にして西の島へ滑空する。
func test_o2_3_falling_isles_swap_heavy_and_float() -> void:
	await _enter("o2_3")
	var on_isle := await _glide_to(Vector3(3.5, 8.0, 0.4), Vector3(4.5, 2.0, -15.5))
	assert_almost(on_isle.y, 2.0, 0.3, "glided down to the cloud step (%s)" % on_isle)
	await _pick_to_bag(Vector3(4.5, 2.0, -12.5))
	await _pick_to_bag(Vector3(3.5, 2.0, -14.5))
	_swap(FLOAT, HEAVY)
	await _walk_to(Vector3(4.5, 2.0, -21.5), 0.2)
	var high := await _lift_jump_toward(Vector3i(4, 1, -22), Vector3(4.5, 6.0, -24.5), 900, true)
	assert_almost(high.y, 6.0, 0.3, "up on the windy high step (%s)" % high)
	await _walk_to(Vector3(-3.5, 6.0, -24.5), 0.3)
	_swap(HEAVY, FLOAT)
	var landed := await _lift_jump_toward(Vector3i(-4, 5, -25), Vector3(-27.5, 8.0, -28.5), 900, true)
	assert_almost(landed.y, 8.0, 0.3, "the gale carried me to the west island (%s)" % landed)
	await _walk_to(Vector3(-24.5, 8.0, -27.0), 0.3)
	_bag_to_hotbar(RIGHT)
	_give_creature("kit", [RIGHT, JUMP])
	assert_true(await _creature_home("kit", OptionalWorldsO2.ISLES_NEST), "the kit went home")
	await _recall_creature("kit")
	await _walk_into_goal()
	assert_true(await _cleared(), "cleared the falling isles")


## ホットバーの off をかばんへ、かばんの on をホットバーへ（重いと浮くは同時に効かないので入れ替える）。
func _swap(off: RuleAction.Kind, on: RuleAction.Kind) -> void:
	var slot := _slot_of(off)
	if slot != -1:
		var v := w.ledger.hotbar_vessel(slot, _me().player_id)
		assert_true(w.ledger_actions.move_to_inventory(v.id), "%s to the bag" % off)
	_bag_to_hotbar(on)


# --- O2-4 さかさまの塔 --------------------------------------------------------


## 塔から滑空して 1 枚目の風の壁をダッシュで抜け、間の足場に降りてダッシュを取り戻し、2 枚目も抜ける。
func test_o2_4_upside_tower_dash_through_the_gales() -> void:
	await _enter("o2_4")
	await _pick(Vector3(-1.5, 9.0, 4.5), RuleAction.Kind.DASH)
	var on_step := await _glide_dash(
		Vector3(0.5, 9.0, 0.4), Vector3(0.5, 2.0, -18.0), Vector3(0.5, 0.0, -8.6)
	)
	assert_almost(on_step.y, 2.0, 0.3, "through the first gale onto the cloud step (%s)" % on_step)
	var landed := await _glide_dash(
		Vector3(0.5, 2.0, -19.5), Vector3(0.5, 0.0, -36.5), Vector3(0.5, 0.0, -24.6), true, true
	)
	assert_lt(landed.z, -33.5, "through the second gale to the north island (%s)" % landed)
	await _pick(Vector3(4.5, 0.0, -35.5), RIGHT)
	await _walk_to(Vector3(1.5, 0.0, -35.0), 0.3)
	_give_creature("wish", [RIGHT, JUMP])
	assert_true(await _creature_home("wish", OptionalWorldsO2.TOWER_NEST), "the creature went home")
	await _walk_to(Vector3(-4.5, 0.0, -34.6), 0.3)
	await _recall_creature("wish")
	await _walk_into_goal(
		[Vector3(5.5, 0.0, -37.5), Vector3(5.5, 1.0, -38.5), Vector3(5.5, 2.0, -40.5)]
	)
	assert_true(await _cleared(), "cleared the upside-down tower")


# --- O2-5 空の大渦 ------------------------------------------------------------


## 重いで横風の橋を渡って浮くとダッシュを取り、重いを板の上の箱に渡して雲の段を上げ、塔から滑空して
## 風の壁をダッシュで抜け、雲の段のワープで北の島へ。
func test_o2_5_sky_maelstrom() -> void:
	await _enter("o2_5")
	var anchor := _block("anchor")
	await _walk_to(Vector3(0.5, 0.0, -1.5), 0.3)
	await _recall_all_from("anchor")
	_ensure_on_hotbar(HEAVY)
	assert_true(await _wait_block_at("anchor", Vector3i(6, 0, -3), 900), "the wind took the crate")
	await _walk_route([Vector3(-5.5, 0.0, 1.5), Vector3(-15.5, 0.0, 1.5), Vector3(-17.5, 0.0, 1.5)])
	await _pick_to_bag(Vector3(-19.5, 0.0, 0.5))
	await _pick(Vector3(-18.5, 0.0, 2.5), RuleAction.Kind.DASH)
	await _walk_route([Vector3(-15.5, 0.0, 1.5), Vector3(-6.0, 0.0, 1.5)])
	await _walk_to(Vector3(4.5, 0.0, -1.5), 0.3)
	_give(anchor, HEAVY, TriggerMode.Kind.NONE)
	assert_true(
		await _wait(func() -> bool: return _door("sky_step").is_closed(), 300), "the sky step rose"
	)
	assert_true(await _ride_warp(Vector3(4.5, 0.0, 5.5)), "warped to the tower")
	_bag_to_hotbar(FLOAT)
	var on_step := await _glide_dash(
		Vector3(12.5, 9.0, -13.6), Vector3(12.5, 7.0, -25.5), Vector3(12.5, 0.0, -14.6)
	)
	assert_almost(on_step.y, 7.0, 0.3, "through the gale onto the sky step (%s)" % on_step)
	assert_true(await _ride_warp(Vector3(12.5, 7.0, -24.5)), "warped to the far island")
	await _walk_to(Vector3(1.5, 8.0, -58.5), 0.3)
	_give_creature("elder", [RIGHT, JUMP])
	assert_true(
		await _creature_home("elder", OptionalWorldsO2.MAELSTROM_NEST), "the elder went home"
	)
	await _walk_to(Vector3(-2.8, 8.0, -59.0), 0.3)
	await _recall_creature("elder")
	await _walk_into_goal()
	assert_true(await _cleared(), "cleared the sky maelstrom")
