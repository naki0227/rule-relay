extends "res://tests/integration/island_playthrough.gd"
## 寄り道のワールドのゴールの窪みの中から、下の段の仲間は見えない（狙えない）ことを物理の光線で確かめる
## （test_goal_sightlines.gd と同じ考え方。docs/adr/0011 決定 9・10）。縁まで出れば見えることも確かめる。

## [ステージ, 下に立つ人の足もと（いくつか）, ゴールの外の縁に立つ人の足もと（最初の人が見える）]
const CASES: Array = [
	["o1_1", [Vector3(0.5, 0.0, -18.5), Vector3(5.5, 1.0, -18.5)], Vector3(0.5, 2.0, -19.3)],
	["o1_2", [Vector3(0.5, 0.0, -24.5), Vector3(4.5, 1.0, -24.5)], Vector3(0.5, 2.0, -25.3)],
	["o1_3", [Vector3(0.5, 0.0, -29.5), Vector3(4.5, 1.0, -29.5)], Vector3(0.5, 2.0, -30.3)],
	["o1_4", [Vector3(0.5, 0.0, -28.5), Vector3(4.5, 1.0, -28.5)], Vector3(0.5, 2.0, -29.3)],
	["o1_5", [Vector3(0.5, 0.0, -20.5), Vector3(4.5, 1.0, -20.5)], Vector3(0.5, 2.0, -21.3)],
	["o2_1", [Vector3(3.5, 0.0, -43.5), Vector3(8.5, 1.0, -43.5)], Vector3(3.5, 2.0, -44.3)],
	["o2_2", [Vector3(2.5, 0.0, -74.5), Vector3(8.5, 1.0, -74.5)], Vector3(2.5, 2.0, -75.3)],
	["o2_3", [Vector3(-3.5, 6.0, -24.5), Vector3(4.5, 2.0, -15.5)], Vector3(-24.3, 8.0, -31.5)],
	["o2_4", [Vector3(0.5, 0.0, -38.5), Vector3(5.5, 1.0, -38.5)], Vector3(0.5, 2.0, -39.3)],
	["o2_5", [Vector3(12.5, 7.0, -25.0), Vector3(0.5, 0.0, 0.5)], Vector3(0.5, 8.0, -56.3)],
	["o3_1", [Vector3(2.5, 1.0, -27.5), Vector3(9.5, 2.0, -27.5)], Vector3(2.5, 3.0, -28.3)],
	["o3_2", [Vector3(0.5, 0.0, -21.5), Vector3(5.5, 1.0, -21.5)], Vector3(0.5, 2.0, -22.3)],
	["o3_3", [Vector3(0.5, 0.0, -33.5), Vector3(-5.5, 1.0, -33.5)], Vector3(0.5, 2.0, -34.3)],
	["o3_4", [Vector3(0.5, 1.0, -27.5), Vector3(5.5, 2.0, -27.5)], Vector3(0.5, 3.0, -28.3)],
	["o3_5", [Vector3(0.5, 1.0, -35.5), Vector3(5.5, 2.0, -35.5)], Vector3(0.5, 3.0, -36.3)],
]
const CHEST := Vector3(0.0, 1.0, 0.0)


func test_optional_goal_hollows_hide_the_climbers_below() -> void:
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
