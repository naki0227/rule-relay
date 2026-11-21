extends "res://tests/integration/island_playthrough.gd"
## ワールド 7 のゴールの窪みの中から、下の段の仲間は見えない（狙えない）ことを、物理の光線で確かめる
## （書き方は test_goal_sightlines.gd と同じ。ゴールから能力を渡すのをルールで禁止せず、地形で難しくする）。
## 縁まで出れば見える（縁から渡すことはできる）ことも確かめる。

## [ステージ, 登り口の下に立つ人の足もと（いくつか）, ゴールの外の縁に立つ人の足もと（最初の人が見える）]
const CASES: Array = [
	[
		World7Stages.SUMMIT_1,
		[Vector3(2.5, 0.0, -22.5), Vector3(-1.5, 0.0, -20.5)],
		Vector3(2.5, 2.0, -24.2),
	],
	[
		World7Stages.SUMMIT_2,
		[Vector3(0.5, 0.0, -20.5), Vector3(3.5, 0.0, -18.5)],
		Vector3(0.5, 2.0, -22.2),
	],
	[
		World7Stages.SUMMIT_3,
		[Vector3(2.5, 4.0, -20.5), Vector3(-3.5, 4.0, -15.5)],
		Vector3(2.5, 6.0, -22.2),
	],
	[
		World7Finale.SUMMIT_4,
		[Vector3(3.5, 1.0, -18.5), Vector3(-3.5, 1.0, -15.5)],
		Vector3(3.5, 3.0, -20.2),
	],
	[
		World7Finale.SUMMIT_5,
		[Vector3(3.5, 1.0, -28.5), Vector3(-3.5, 1.0, -25.5)],
		Vector3(3.5, 3.0, -30.2),
	],
	[
		World7Finale.SUMMIT_6,
		[Vector3(2.5, 4.0, -65.5), Vector3(-3.5, 4.0, -60.5)],
		Vector3(2.5, 6.0, -67.2),
	],
]
const CHEST := Vector3(0.0, 1.0, 0.0)


func test_world7_goal_hollows_hide_the_climbers_below() -> void:
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


## ゴールの箱の中の、足もとの点（真ん中と四隅）。
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
