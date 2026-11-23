extends "res://tests/integration/island_playthrough.gd"
## 見上げたときにカメラの支点を上げる（2026-11-23 本人の判断「カメラの支点を上げる」。CameraRig.pivot_lift）。
## はじめての 10 分の通しで、1-4「押し石の小道」の段（高さ 2）の真下から縁のセルを見上げると、カメラのばねが
## 地面に当たって人の顔の前まで寄り、壁と顔だけになって縁のセルを狙えなかった。
## - 段の真下で見上げの上限まで見上げても、カメラは地面に寄らず、人から離れたまま
## - 段の真下から、縁のセル（教える場所「地面にも渡せる」の正面）を、そのカメラで狙える
## - 照準の光線（肩越しのずれ、ADR 0016）は、上げた支点の横を通る（照準と狙う先がずれない）

const PATH := "w1_push_path"
## 1-4 の教える場所「地面にも渡せる」の真下（段の南の壁 z = 0 から 0.6 m）と、北を向いたときに照準の先にある
## 縁のセル（段の上の層。照準は肩越しに 0.6 m 右を通る）。
const BELOW_LEDGE := Vector3(-2.5, 0.0, 0.6)
const EDGE_CELL := Vector3i(-2, 1, -1)


func _stand_below_the_ledge() -> void:
	await _enter(PATH)
	await _walk_to(BELOW_LEDGE, 0.15)
	_me().velocity = Vector3.ZERO
	w.camera_rig.yaw = 0.0
	await wait_physics_frames(6)


func _look(pitch: float, yaw: float = 0.0) -> void:
	w.camera_rig.yaw = yaw
	w.camera_rig.pitch = pitch
	await wait_physics_frames(3)


## 照準の光線が通る、肩越しにずらした支点（カメラの右へ h_offset）。
func _shoulder_pivot() -> Vector3:
	var rig := w.camera_rig
	var right := Vector3(cos(rig.yaw), 0.0, -sin(rig.yaw))
	return rig.global_position + right * rig.camera().h_offset


func _crosshair_ray() -> Array[Vector3]:
	var cam := w.camera_rig.camera()
	var center := cam.get_viewport().get_visible_rect().size * 0.5
	return [cam.project_ray_origin(center), cam.project_ray_normal(center)]


## 段の真下で、見下ろしから見上げの上限まで、どの角度でもカメラは足もとより十分上にあり、人から離れたまま。
## 上げる前は、15 度より上を向くとカメラが地面（高さ 0.0〜0.08）に当たり、ばねが 3.3 m まで縮んでいた。
func test_looking_up_at_the_ledge_foot_keeps_the_camera_off_the_ground() -> void:
	await _stand_below_the_ledge()
	var feet := _me().global_position.y
	var degrees := -70
	while degrees <= 30:
		await _look(deg_to_rad(degrees))
		var cam := w.camera_rig.camera().global_position
		var pivot := w.camera_rig.global_position
		assert_gt(
			cam.y - feet,
			CameraRig.MIN_CAMERA_HEIGHT - 0.25,
			"camera off the ground at %d" % degrees
		)
		assert_gt(cam.distance_to(pivot), CameraRig.DISTANCE - 0.5, "not pulled in at %d" % degrees)
		degrees += 5
	assert_almost(w.camera_rig.pitch, CameraRig.MAX_PITCH, 0.001, "the upward limit is unchanged")
	assert_gt(w.camera_rig.lift(), 1.5, "the pivot rose when looking up")


## 段の真下から、縁のセルを狙える。見上げて照準が縁のセルに合う角度では、どれもカメラは地面に寄らず人から
## 離れている（上げる前は、15〜30 度で照準は合っても、カメラが地面に埋まって壁と顔だけが写っていた）。
func test_the_edge_cell_is_aimable_from_right_below_the_ledge() -> void:
	await _stand_below_the_ledge()
	var feet := _me().global_position
	var aimed: Array[int] = []
	for degrees in range(0, 31):
		await _look(deg_to_rad(degrees))
		var hit := w.aimed_block()
		if not (hit is TerrainCell and (hit as TerrainCell).cell == EDGE_CELL):
			continue
		aimed.append(degrees)
		var cam := w.camera_rig.camera().global_position
		var pulled := cam.distance_to(w.camera_rig.global_position)
		assert_gt(
			cam.y - feet.y, CameraRig.MIN_CAMERA_HEIGHT - 0.25, "off the ground at %d" % degrees
		)
		assert_gt(pulled, CameraRig.DISTANCE - 0.5, "not pulled in at %d" % degrees)
	assert_false(aimed.is_empty(), "the edge cell can be aimed at from right below the ledge")
	assert_true(
		aimed.any(func(d: int) -> bool: return d > 0), "while looking up at it: %s" % str(aimed)
	)


## 照準の光線は、上げた支点を肩越しにずらした点を通る（ADR 0016。照準＝狙う先のまま）。照準の補助（AimAssist）は
## 同じカメラで画面に写した位置を比べるので、支点を上げても照準の円と合う。
func test_the_crosshair_ray_passes_the_raised_shoulder_pivot() -> void:
	await _stand_below_the_ledge()
	for degrees: int in [-40, 0, 12, 22, 30]:
		await _look(deg_to_rad(degrees))
		var ray := _crosshair_ray()
		var to_pivot := _shoulder_pivot() - ray[0]
		var off_line := (to_pivot - ray[1] * to_pivot.dot(ray[1])).length()
		assert_lt(off_line, 0.05, "the crosshair ray passes the shoulder pivot at %d" % degrees)
		var expected := _me().global_position.y + CameraRig.pivot_height(deg_to_rad(degrees))
		assert_almost(
			w.camera_rig.global_position.y, expected, 0.02, "pivot height at %d" % degrees
		)
		var cam := w.camera_rig.camera()
		var center := cam.get_viewport().get_visible_rect().size * 0.5
		var far := ray[0] + ray[1] * 6.0
		assert_lt(cam.unproject_position(far).distance_to(center), 1.0, "on the crosshair")


## 支点の真上に地形があれば、そこまでしか上げない（天井の中にカメラの支点を入れない）。
func test_the_pivot_does_not_rise_into_an_overhang() -> void:
	await _enter(PATH)
	var at := Vector3(3.5, 0.0, 4.5)
	var roof := StaticBody3D.new()
	roof.collision_layer = Tuning.LAYER_TERRAIN
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 1.0, 4.0)
	shape.shape = box
	roof.add_child(shape)
	w.add_child(roof)
	roof.global_position = at + Vector3(0.0, 3.5, 0.0)  # 下面が高さ 3
	_me().global_position = at
	_me().velocity = Vector3.ZERO
	await wait_physics_frames(4)
	await _look(CameraRig.MAX_PITCH)
	assert_gt(CameraRig.pivot_height(CameraRig.MAX_PITCH), 3.0, "it would want to rise above 3 m")
	var pivot_y := w.camera_rig.global_position.y - _me().global_position.y
	assert_lt(pivot_y, 3.0 - CameraRig.CEILING_GAP + 0.02, "stops under the overhang")
	assert_gt(pivot_y, CameraRig.PIVOT_HEIGHT, "still rises up to it")
