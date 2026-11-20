extends "res://tests/integration/island_playthrough.gd"
## 島の関所と詰みを、プレイヤーと同じ操作で壊しにいく試遊の共通部品（ファイル名が test_ で始まらないので、
## これ自体は実行されない）。動きは test_island_probes.gd と同じ（走って縁から跳ぶ・段へ跳び続ける・
## 下から鐘へ F を押し続ける・落ちたら復活を待つ）。瞬間移動・状態の直接書き換えはしない。

const DASH := RuleAction.Kind.DASH
## 谷の縁から踏み切る位置（m、進む向きに +）。
const OFFSETS: Array[float] = [-0.2, -0.1, 0.0, 0.1, 0.2, 0.3]


func _walk_route(route: Array[Vector3]) -> void:
	for p in route:
		await _walk_to(p)


## 落ちて死んだあと、全員リセットでどこかの床に立つまで待つ。
func _wait_respawn() -> void:
	for i in 400:
		if _me().global_position.y > -0.6 and _me().is_on_floor():
			await wait_physics_frames(4)
			return
		await tree.physics_frame
	fail("did not respawn (at %s)" % _me().global_position)


## 谷の手前から dir（東西南北のどれか）へ全力で走り、谷の縁（進む向きの座標 edge）より offset 先で
## 跳ぶ。向こう岸（edge + gap より先）に同じ高さで立てたら true。落ちたら復活を待って false。
func _running_jump(
	route: Array[Vector3], dir: Vector3, edge: float, gap: float, offset: float
) -> bool:
	await _walk_route(route)
	_me().view_yaw = atan2(-dir.x, -dir.z)
	_me().move_intent = Vector2(0.0, 1.0)
	var jumped := false
	var result := false
	var floor_y := _me().global_position.y
	for i in 300:
		var p := _me().global_position.dot(dir)
		if not jumped and p >= edge + offset:
			if _me().is_on_floor():
				w.press_action(JUMP)
			else:
				jumped = true
		if jumped and _me().is_on_floor() and p > edge + gap - 0.4:
			result = absf(_me().global_position.y - floor_y) < 0.3
			break
		if _me().global_position.y < floor_y - 2.0:
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	if not result:
		await _wait_respawn()
	return result


## 縁ちょうどから offset を変えて試し、最初に越えた offset を返す（越えられなければ NAN）。
func _first_crossing(route: Array[Vector3], dir: Vector3, edge: float, gap: float) -> float:
	for offset in OFFSETS:
		if await _running_jump(route, dir, edge, gap, offset):
			return offset
	return NAN


## 段の手前 start から、toward へ押しながら床に着くたび跳び続ける。届いた最高の足の高さを返す。
func _jump_against(start: Vector3, toward: Vector3, frames: int = 300) -> float:
	await _walk_to(start)
	var best := _me().global_position.y
	for i in frames:
		_face(toward)
		_me().move_intent = Vector2(0.0, 1.0)
		if _me().is_on_floor():
			w.press_action(JUMP)
		best = maxf(best, _me().global_position.y)
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	return best


## 鐘の下側 stand から、壁へ押しつけて跳びながら毎フレーム F。鳴ったら true。
func _try_ring_from(bell_key: String, stand: Vector3) -> bool:
	var bell := w.bells_by_key[bell_key]
	await _walk_to(stand, 0.3)
	var closest := 99.0
	for i in 120:
		_face(bell.global_position)
		_me().move_intent = Vector2(0.0, 1.0)
		if _me().is_on_floor():
			w.press_action(JUMP)
		var chest := _me().global_position + Vector3(0.0, 1.0, 0.0)
		closest = minf(closest, chest.distance_to(bell.global_position))
		w.interact(bell)
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	print(
		(
			"    %s from %s: closest chest distance %.2f (touch reach %.2f)"
			% [bell_key, stand, closest, Tuning.TOUCH_REACH + RuleBlock.SIZE * 0.5]
		)
	)
	return w.activated.has(bell_key)


## 縁の手前 stand から dir へ、跳ばずに地上でダッシュする。落ちたら復活を待つ。立っていた高さに
## 留まって向こうへ着いたら true。
func _ground_dash(stand: Vector3, dir: Vector3) -> bool:
	await _walk_to(stand, 0.2)
	var floor_y := _me().global_position.y
	_me().view_yaw = atan2(-dir.x, -dir.z)
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(1)
	w.press_action(DASH)
	assert_true(_me().is_dashing(), "ground dash")
	await wait_physics_frames(40)
	_me().move_intent = Vector2.ZERO
	await wait_physics_frames(30)
	var stayed := absf(_me().global_position.y - floor_y) < 0.3 and _me().is_on_floor()
	if not stayed:
		await _wait_respawn()
	return stayed


## 生き物の高さの最大を、frames の間見る。
func _creature_top(key: String, frames: int) -> float:
	var critter := _creature(key)
	var top := critter.global_position.y
	for i in frames:
		await tree.physics_frame
		top = maxf(top, critter.global_position.y)
	return top
