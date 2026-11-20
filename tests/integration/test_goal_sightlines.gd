extends "res://tests/integration/island_playthrough.gd"
## ゴールの窪みの中から、下の段の仲間は見えない（狙えない）ことを、物理の光線で確かめる。
## 2026-11-20 本人の判断（docs/adr/0011 決定 9・10）: クリアは「島の条件＋生きている全員がゴールに集まる」。
## ゴールから下の仲間へ能力を投げ渡すのを「ルール」で禁止はしない（本人: システム的に妨害するとかは
## 絶対にしたくない。自由な発想を妨げるから）。代わりに地形で難しくする: ゴールは縁より 1 段低い窪みで、
## 窪みの中の胸（足もと + 1.0）から、登り口の下に立つ人の胸への光線は地形が遮る。
## 一方、ゴールを出て縁まで歩けば見える（縁から渡すことはできる）ことも確かめる。
## カメラは人の後ろ上にあるので、カメラの位置からの光線はここでは確かめていない（docs/adr/0011 決定 10）。

## [ステージ, 登り口の下に立つ人の足もと（いくつか）, ゴールの外の縁に立つ人の足もと（最初の人が見える）]
const CASES: Array = [
	[StageCatalog.INTRO_ID, [Vector3(0.5, 0.0, -3.5)], Vector3(0.5, 2.0, -5.2)],
	[
		StageCatalog.HILL_ID,
		[Vector3(0.5, 2.0, -1.5), Vector3(0.5, 0.0, 5.5)],
		Vector3(0.5, 4.0, -4.2),
	],
	[
		StageCatalog.QUARRY_ID,
		[Vector3(1.5, 3.0, -7.5), Vector3(0.5, 0.0, 0.5)],
		Vector3(1.5, 5.0, -8.2),
	],
	[
		StageCatalog.THREE_BELLS_ID,
		[Vector3(0.5, 3.0, -16.5), Vector3(-0.5, 0.0, -13.5)],
		Vector3(0.5, 5.0, -17.2),
	],
	[StageCatalog.FLOATING_ID, [Vector3(-3.5, 0.0, -4.5)], Vector3(-3.5, 2.0, -9.2)],
	[
		StageCatalog.WINDY_ID,
		[Vector3(-1.5, 4.0, -18.5), Vector3(4.5, 2.0, -22.5)],
		Vector3(-1.5, 6.0, -20.2),
	],
	[
		StageCatalog.FORT_ID,
		[Vector3(6.5, 2.0, -14.5), Vector3(0.5, 0.0, -4.5)],
		Vector3(4.8, 4.0, -14.5),
	],
]
const CHEST := Vector3(0.0, 1.0, 0.0)


func test_goal_hollows_hide_the_climbers_below() -> void:
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


## 実際に窪みの床に立てること（足もとがゴールの箱に入る）も、ひとりで歩いて確かめる。
func test_goal_hollow_floor_is_inside_the_goal_box() -> void:
	await _enter(StageCatalog.HILL_ID)
	var goal := _goal()
	await _walk_to(Vector3(0.5, 1.0, 1.5))
	await _walk_to(Vector3(-0.5, 2.0, -1.5))
	await _lift_up("lift", Vector3(-0.5, 2.0, -1.5), Vector3(0.5, 4.0, -4.5))
	await _walk_into_goal()
	assert_lt(_me().global_position.y, 3.3, "stepped down into the hollow")
	assert_true(goal.has_point(_me().global_position))
	# 自分のジャンプで窪みから出られる（閉じ込めない）
	await _walk_to(Vector3(0.5, 4.0, -4.5))


## ゴールの箱の中の、足もとの点（真ん中と、内側へ 0.3 寄せた四隅）。
func _points_in(goal: AABB) -> Array[Vector3]:
	var y := goal.position.y + 0.1
	var lo := Vector3(goal.position.x + 0.3, y, goal.position.z + 0.3)
	var hi := Vector3(goal.end.x - 0.3, y, goal.end.z - 0.3)
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
