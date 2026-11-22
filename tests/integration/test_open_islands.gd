extends "res://tests/integration/island_playthrough.gd"
## 開けた島のステージを、ひとりで最初から最後まで自動で遊ぶ（通しプレイ）。
## 歩く（段差では跳ぶ）・谷を跳ぶ・渡す・乗る・拾う・装備する・鐘を鳴らす、をプレイヤーと同じ操作で流す
## （瞬間移動はしない）。「丘の上の旗」は、別々の道でもクリアできることを確かめる（解法は自由）。
## 操作の部品は island_playthrough.gd。協力の近道・生き物の道は test_open_islands_coop.gd。

# --- ステージ ----------------------------------------------------------------


func test_hill_top_by_the_lift() -> void:
	await _enter(StageCatalog.HILL_ID)
	await _throw_a_move_to_the_islet_critter()
	await _walk_to(Vector3(0.5, 1.0, 1.5))
	await _walk_to(Vector3(-0.5, 2.0, -1.5))
	await _lift_up("lift", Vector3(-0.5, 2.0, -1.5), Vector3(0.5, 4.0, -4.5))
	assert_eq(director.last_clear_text, "", "the summit's edge is not the goal")
	await _walk_into_goal()
	assert_true(await _cleared(), "reached the goal on the summit")


func test_hill_top_by_the_boots() -> void:
	await _enter(StageCatalog.HILL_ID)
	await _throw_a_move_to_the_islet_critter()
	await _walk_to(Vector3(8.5, 0.0, 3.5))
	await _walk_to(Vector3(8.5, 1.0, 1.5))
	await _walk_to(Vector3(8.5, 2.0, -0.5))
	await _walk_to(Vector3(8.5, 3.0, -3.5))
	await _pick_and_wear(Vector3(7.5, 3.0, -5.0), RuleVessel.Part.FEET)
	await _walk_to(Vector3(5.5, 1.0, -3.5))
	await _walk_to(Vector3(3.5, 2.0, -3.5))
	await _walk_to(Vector3(1.5, 4.0, -4.5))
	await _walk_into_goal()
	assert_true(await _cleared(), "jumped onto the summit with the boots")


func test_quarry_by_pushing_a_stone_and_the_ledge_lift() -> void:
	await _enter(StageCatalog.QUARRY_ID)
	var stone := _block("stone_a")
	await _walk_to(stone.global_position + Vector3(1.6, -0.5, 0.0))
	_lend(stone, _slot_of(LEFT), TriggerMode.Kind.REPEAT)
	for i in 600:
		if stone.cell().x <= -5 and not stone.is_moving_horizontally():
			break
		await tree.physics_frame
	assert_eq(stone.cell().x, -5, "the stone slid to the terrace wall")
	await _free_stone_a_from_its_ban()
	await _walk_to(Vector3(-4.5, 1.0, 1.5))
	await _walk_to(Vector3(-6.5, 2.0, 1.5))
	await _walk_to(Vector3(-4.5, 2.0, -6.5))
	await _walk_to(Vector3(1.5, 3.0, -7.5))
	await _lift_up("ledge_lift", Vector3(1.5, 3.0, -7.5), Vector3(0.5, 5.0, -9.5))
	await _walk_into_goal()
	assert_true(await _cleared(), "climbed out of the quarry")


func test_three_bells_alone() -> void:
	await _enter(StageCatalog.THREE_BELLS_ID)
	# 東: 岸の発射台に「投げる」を渡して、谷の向こうの鐘を撃つ
	await _walk_to(Vector3(9.5, 0.0, 1.5))
	_lend(_block("launcher"), _slot_of(THROW), TriggerMode.Kind.NONE)
	for i in 400:
		if w.activated.has("east_bell"):
			break
		await tree.physics_frame
	assert_true(w.activated.has("east_bell"), "the launcher rang the east bell")
	# 西: 裾へ上がり、窪みのブロックで台地へ
	await _walk_to(Vector3(-13.5, 1.0, 1.5))
	await _lift_up("west_lift", Vector3(-14.5, 1.0, 1.5), Vector3(-16.5, 3.0, -0.5))
	await _ring("west_bell")
	assert_eq(director.last_clear_text, "", "not cleared with two bells")
	# 北: 降りて東側の階段から段へ上がり、窪みのブロックで台地へ
	await _walk_to(Vector3(-12.5, 0.0, -2.5))
	await _walk_to(Vector3(5.5, 0.0, -12.5))
	await _walk_to(Vector3(5.5, 1.0, -15.5))
	await _walk_to(Vector3(5.5, 2.0, -17.5))
	await _walk_to(Vector3(3.5, 3.0, -16.5))
	await _lift_up("north_lift", Vector3(0.5, 3.0, -16.5), Vector3(-0.5, 5.0, -18.5))
	await _ring("north_bell")
	assert_eq(director.last_clear_text, "", "all bells rang but nobody is at the goal yet")
	await _walk_into_goal([Vector3(2.0, 5.0, -21.5), Vector3(1.5, 4.0, -24.2)])
	assert_true(await _cleared(), "all three bells and everyone at the goal")


func test_floating_isles_alone() -> void:
	await _enter(StageCatalog.FLOATING_ID)
	# 東: 発射台で鐘を撃つ
	await _walk_to(Vector3(4.5, 0.0, 1.5))
	_lend(_block("launcher"), _slot_of(THROW), TriggerMode.Kind.NONE)
	for i in 400:
		if w.activated.has("east_bell"):
			break
		await tree.physics_frame
	assert_true(w.activated.has("east_bell"), "the launcher rang the east bell")
	# 北: 塔へ上がり、谷 3 を跳んで北の浮島へ
	await _lift_up("tower_lift", Vector3(1.5, 0.0, -1.5), Vector3(0.5, 2.0, -5.5))
	await _jump_across(Vector3(0.5, 2.0, -5.7), Vector3(0.5, 2.0, -11.0))
	await _ring("north_bell")
	# 戻って南の浮島（谷 2）でブーツを拾い、ブーツで西の谷 4 を越える
	await _walk_to(Vector3(-3.5, 2.0, -10.5))
	await _jump_across(Vector3(-3.5, 2.0, -10.3), Vector3(-3.5, 0.0, -4.5))
	await _jump_across(Vector3(0.5, 0.0, 5.7), Vector3(0.5, 0.0, 10.0))
	await _pick_and_wear(Vector3(2.5, 0.0, 14.0), RuleVessel.Part.FEET)
	await _jump_across(Vector3(0.5, 0.0, 9.3), Vector3(0.5, 0.0, 4.0))
	await _jump_across(Vector3(-5.7, 0.0, 0.5), Vector3(-11.8, 0.0, 0.5))
	await _ring("west_bell")
	assert_eq(director.last_clear_text, "", "all bells rang but nobody is at the goal yet")
	# ブーツのまま谷 4 を戻り、塔（高さ 2）へ跳び上がって、谷 3 を越えて北の浮島のゴールへ
	await _jump_across(Vector3(-10.3, 0.0, 0.5), Vector3(-4.5, 0.0, 0.5))
	await _walk_to(Vector3(-1.5, 0.0, -2.5))
	await _walk_to(Vector3(-1.5, 2.0, -4.5))
	await _jump_across(Vector3(-1.5, 2.0, -5.7), Vector3(-1.5, 2.0, -11.0))
	await _walk_into_goal([Vector3(-1.5, 1.0, -16.0)])
	assert_true(await _cleared(), "all three bells and everyone at the goal")
