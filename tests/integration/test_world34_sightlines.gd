extends "res://tests/integration/island_playthrough.gd"
## ワールド 3・4 の新しいステージのゴールの窪みの中から、来た道（下の段・手前の島）の仲間は見えない
## （狙えない）ことを、物理の光線で確かめる（test_goal_sightlines.gd と同じ考え方。docs/adr/0011 決定 9・10）。
## ルールは足さず、窪みの縁か、窪みの手前の岩の尾根で遮る。ゴールを出て縁まで歩けば見える（渡せる）ことも確かめる。

## [ステージ, 来た道に立つ人の足もと（いくつか）, ゴールの外の縁に立つ人の足もと（最初の人が見える）]
const CASES: Array = [
	[
		World3Stages.DASH_BEACH_ID,
		[Vector3(0.5, 0.0, 0.5), Vector3(5.5, 1.0, 1.5)],
		Vector3(7.5, 2.0, -11.5),
	],
	[
		World3Stages.SHUTTLE_COVE_ID,
		[Vector3(0.5, 1.0, 5.5), Vector3(-1.5, 1.0, -3.5)],
		Vector3(-5.5, 1.0, -13.5),
	],
	[
		World3Stages.WIND_PATH_ID,
		[Vector3(-1.5, 0.0, 1.5), Vector3(2.5, 0.0, -8.5)],
		Vector3(-3.5, 2.0, -12.5),
	],
	[
		World3Stages.GAP_RELAY_ID,
		[Vector3(0.5, 0.0, 1.5), Vector3(-0.5, 0.0, -12.5)],
		Vector3(-4.5, 2.0, -15.5),
	],
	[
		CloudCorridor.ID,
		[Vector3(3.5, 1.0, -10.5), Vector3(0.5, 1.0, -3.5)],
		Vector3(-4.5, 1.0, -28.5),
	],
	[
		World4Stages.NUT_TOSS_ID,
		[Vector3(0.5, 0.0, -0.5), Vector3(1.0, 0.0, 6.5)],
		Vector3(-2.5, 2.0, 4.5),
	],
	[
		World4Stages.LADDER_ID,
		[Vector3(1.5, 0.0, 0.5), Vector3(-4.5, 0.0, -1.5)],
		Vector3(5.5, 2.0, -4.5),
	],
	[
		World4Stages.PLATES_ID,
		[Vector3(0.5, 1.0, 5.5), Vector3(3.5, 1.0, 3.5)],
		Vector3(-5.5, 1.0, -15.5),
	],
	[
		World4Stages.HERD_ID,
		[Vector3(0.5, 1.0, 4.5), Vector3(5.5, 1.0, 5.5)],
		Vector3(22.5, 1.0, 0.5),
	],
	[
		DeepForest.ID,
		[Vector3(0.5, 1.0, 5.5), Vector3(3.5, 1.0, 2.5)],
		Vector3(23.5, 1.0, 2.5),
	],
]
const CHEST := Vector3(0.0, 1.0, 0.0)


func test_world34_goal_hollows_hide_the_way_back() -> void:
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
			"%s: from the edge %s the teammate at %s is in sight" % [case[0], edge, first]
		)
		director.enter_stage(StageCatalog.HUB_ID)
		await wait_physics_frames(3)


## ゴールの箱の中の、足もとの点（真ん中と四隅。数える箱は窪みの壁から 0.3 内側）。
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
