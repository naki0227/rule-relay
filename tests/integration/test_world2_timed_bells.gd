extends "res://tests/integration/timed_bells_play.gd"
## 「鳴りつづける鐘」（2-5。時の鐘の初出）を、ひとりで最初から最後まで自動で遊ぶ（通しプレイ）と、
## ゴールの窪みの見通し。ひとりの道は 2 通り（F で鳴らし直して最後は走って渡る／発射台に鳴らしつづけさせて
## 石は手で押す）。移動はプレイヤーと同じ入力（move_intent・view_yaw・press_action）と画面の操作（渡す・鐘の F）
## だけで、瞬間移動はしない。協力の道は test_world2_timed_bells_coop.gd、関所と詰みは
## test_world2_timed_bells_probes.gd。部品は timed_bells_play.gd。

## [登り口の下に立つ人の足もと（いくつか）, ゴールの外の縁に立つ人の足もと（最初の人が見える）]
const BELOW: Array[Vector3] = [
	Vector3(0.5, 2.0, -2.5), Vector3(-5.5, 2.0, -1.5), Vector3(0.5, 0.0, 4.5)
]
const GOAL_EDGE := Vector3(2.5, 4.0, -20.7)
const CHEST := Vector3(0.0, 1.0, 0.0)

# --- ひとりの道 -------------------------------------------------------------------


## ひとりの道 1（F）: 鐘のそばで鳴らしつづけ、石を歩かせ、生き物を橋の向こうの巣まで渡す。
## 最後に橋のたもとで鳴らして、鳴りやむ前に走って渡る。
func test_solo_ring_by_hand_then_race_the_bridge() -> void:
	await _enter(STAGE_ID)
	await _give_kit_a_move()
	var stone := _block("walking_stone")
	await _walk_to(stone.global_position + Vector3(0.0, 0.5, 0.0), 0.3)
	await _walk_to(stone.global_position + Vector3(0.0, 1.5, -1.1), 0.3)
	await _walk_to(BY_THE_BELL, 0.3)
	var kit := _creature("kit")
	var home := func() -> bool: return OpenIslandsW2.RINGING_NEST.has_point(kit.global_position)
	var rings := await _keep_ringing(home, 4800)
	assert_true(home.call(), "the kit crossed the bridge and reached its nest")
	assert_eq(stone.cell(), STONE_REST, "the stone walked to the bump")
	assert_true(rings >= 2, "rang %d times (one ring is not enough)" % rings)
	await _race_across()
	await _walk_into_goal()
	assert_true(await _cleared(), "the kit is home and everyone is at the goal")


## ひとりの道 2（F を使わない）: 石は手で押し、発射台を鐘の列へ寄せて「投げる」を渡す。
## 玉が 1.4 秒ごとに当たって鐘が鳴りつづけ、橋は架かったまま。生き物のあとから歩いて渡る。
func test_solo_launcher_keeps_the_bridge_up() -> void:
	await _enter(STAGE_ID)
	await _give_kit_a_move()
	await _push_the_stone_by_hand()
	assert_false(w.activated.has(BELL), "no bell yet")
	await _climb_to_the_terrace()
	await _push_block("launcher", BACK, 1, Vector3(-1.5, -0.5, 0.0))
	await _push_block("launcher", LEFT, 1, Vector3(-1.5, -0.5, 0.0))
	assert_eq(_block("launcher").cell(), Vector3i(10, 2, -2), "lined up with the timed bell")
	_lend(_block("launcher"), _slot_of(THROW), TriggerMode.Kind.NONE)
	assert_true(await _wait_until_rung(BELL, 300), "the launcher rang the timed bell")
	assert_true(
		await _wait_creature_in("kit", OpenIslandsW2.RINGING_NEST, 2400),
		"the kit crossed while the launcher kept it ringing"
	)
	assert_true(_bridge_up(), "the bridge is still up")
	await _walk_to(BRIDGE_FOOT, 0.3)
	await _walk_to(FAR_BANK, 0.5)
	await _walk_into_goal()
	assert_true(await _cleared(), "walked across behind the kit")


# --- ゴールの見通し ---------------------------------------------------------------


## ゴールの窪みの中から、鐘の段と浜の仲間は見えない（地形がさえぎる）。縁へ出れば見える。
func test_goal_hollow_hides_the_climbers_below() -> void:
	await _enter(STAGE_ID)
	var goal := _goal()
	assert_true(goal.has_volume(), "has a goal")
	for from in _points_in(goal):
		for base in BELOW:
			assert_true(
				_blocked(from + CHEST, base + CHEST),
				"terrain hides %s from %s in the goal" % [base, from]
			)
	assert_false(goal.has_point(GOAL_EDGE), "the edge is outside the goal")
	assert_false(
		_blocked(GOAL_EDGE + CHEST, BELOW[0] + CHEST), "from the edge the bridge foot is in sight"
	)


## ゴールの箱の中の、足もとの点（真ん中と四隅。test_goal_sightlines.gd と同じ）。
func _points_in(goal: AABB) -> Array[Vector3]:
	var y := goal.position.y + 0.1
	var lo := Vector3(goal.position.x, y, goal.position.z)
	var hi := Vector3(goal.end.x, y, goal.end.z)
	var center := goal.get_center()
	return [
		Vector3(center.x, y, center.z),
		lo,
		Vector3(hi.x, y, lo.z),
		Vector3(lo.x, y, hi.z),
		hi,
	]


func _blocked(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, Tuning.LAYER_TERRAIN)
	return not w.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
