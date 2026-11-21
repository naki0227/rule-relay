extends "res://tests/integration/island_playthrough.gd"
## ワールド 5・6 の新しいステージのゴールの窪みの中から、下の段の仲間は見えない（狙えない）ことを、
## 物理の光線で確かめる（test_goal_sightlines.gd と同じ確かめ方。並行の作業とぶつからないよう別ファイル）。
## 窪みの中の胸（足もと + 1.0）から、登り口の下に立つ人の胸への光線を地形が遮る。
## 一方、ゴールを出て縁まで歩けば見える（縁から渡すことはできる）ことも確かめる（ルールでは止めない）。

## [ステージ, 登り口の下に立つ人の足もと（いくつか）, ゴールの外の縁に立つ人の足もと（最初の人が見える）]
const CASES: Array = [
	[
		World5Stages.FIRST_ID,
		[Vector3(0.5, 0.0, -3.5), Vector3(-5.5, 0.0, -2.5)],
		Vector3(0.5, 2.0, -4.3),
	],
	[
		World5Stages.RANGE_ID,
		[Vector3(0.5, 0.0, -9.5), Vector3(8.5, 1.0, -9.5)],
		Vector3(0.5, 2.0, -10.3),
	],
	[
		World5Stages.ICE_ID,
		[Vector3(0.5, 0.0, -6.2), Vector3(4.5, 2.0, -7.5)],
		Vector3(0.5, 3.0, -7.2),
	],
	[
		World5Stages.RELAY_ID,
		[Vector3(0.5, 0.0, -15.5), Vector3(8.5, 1.0, -15.5)],
		Vector3(0.5, 2.0, -16.3),
	],
	[
		World6Stages.WARP_ID,
		[Vector3(5.5, 0.0, 0.5), Vector3(-0.5, 0.0, -12.5)],
		Vector3(14.3, 2.0, -1.5),
	],
	[
		World6Stages.MIST_ID,
		[Vector3(3.5, 0.0, -4.6), Vector3(3.5, 1.0, -5.5)],
		Vector3(3.5, 2.0, -7.2),
	],
	[
		World6Stages.PEAK_ID,
		[Vector3(10.5, 2.0, -12.5), Vector3(-15.5, 1.0, -14.5)],
		Vector3(7.6, 4.0, -12.5),
	],
	[
		World6Stages.RIVER_ID,
		[Vector3(9.5, 0.0, -4.5), Vector3(0.5, 0.0, 4.5)],
		Vector3(7.3, 2.0, -4.5),
	],
	[
		World6Stages.RIDGE_ID,
		[Vector3(0.5, 0.0, -14.5), Vector3(4.5, 0.0, -12.5)],
		Vector3(0.5, 2.0, -16.2),
	],
]
const CHEST := Vector3(0.0, 1.0, 0.0)


func test_w56_goal_hollows_hide_the_climbers_below() -> void:
	for case: Array in CASES:
		await _enter(String(case[0]))
		var goal := _goal()
		assert_true(goal.has_volume(), "%s has a goal" % case[0])
		for from in _points_in(goal):
			for base: Vector3 in case[1]:
				assert_true(
					_blocked(from + CHEST, base + CHEST),
					"%s: terrain hides %s from %s in the goal" % [case[0], base, from]
				)
		var edge := case[2] as Vector3
		var first := (case[1] as Array)[0] as Vector3
		assert_false(goal.has_point(edge), "%s: the edge is outside the goal" % case[0])
		assert_false(
			_blocked(edge + CHEST, first + CHEST),
			"%s: from the edge %s the climber at %s is in sight" % [case[0], edge, first]
		)
		director.enter_stage(StageCatalog.HUB_ID)
		await wait_physics_frames(3)


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
