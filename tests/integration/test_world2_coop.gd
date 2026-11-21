extends "res://tests/integration/coop_stage_route.gd"
## 鐘の谷（W2）の新しいステージの協力の道（2 人のオンライン協力。部品は coop_stage_route.gd）。
## ひとりの道は test_world2_stages.gd、関所と詰みの試遊は test_world2_probes.gd。

const BACK := RuleAction.Kind.BACK
const FORWARD := RuleAction.Kind.FORWARD
const LEFT := RuleAction.Kind.LEFT
const RIGHT := RuleAction.Kind.RIGHT
const THROW := RuleAction.Kind.THROW
## こだまの鐘の信号の持ち上げ台の上（休んでいるとき。跳ねている途中の位置では歩く先を決めない）
const LIFT_1_TOP := Vector3(2.5, 0.0, 0.5)
const LIFT_2_TOP := Vector3(2.5, 2.0, -6.5)


## i 番目が、手の届く鐘（key）を F で鳴らし、ホストの画面で鳴るまで待つ。
func _ring(i: int, key: String) -> void:
	await party.settle(i)
	var bell := _w(i).bells_by_key[key]
	_w(i).interact(bell)
	var host_bell := _w(0).bells_by_key[key]
	await party.until(host_bell.is_ringing, "side %d rings %s" % [i, key])


## ホストの画面で鐘（key）が鳴りやむまで待つ。
func _until_quiet(key: String) -> void:
	var bell := _w(0).bells_by_key[key]
	await party.until(func() -> bool: return not bell.is_ringing(), "%s goes quiet" % key, 600)


func _wait_block_at(key: String, cell: Vector3i, frames: int = 900) -> void:
	var block := _block(0, key)
	await party.until(
		func() -> bool:
			return (
				block.cell() == cell and block.is_grounded() and not block.is_moving_horizontally()
			),
		"%s rests at %s" % [key, cell],
		frames
	)


func _push_times(i: int, key: String, action: RuleAction.Kind, times: int, offset: Vector3) -> void:
	for k in times:
		var at := _block(i, key).global_position + offset
		await _walk(i, Vector3(at.x, _w(i).player.global_position.y, at.z), 0.3)
		await _push(i, _block(i, key), action)
		await _settle_block(0, key)


func _give_kit_a_move(i: int) -> void:
	var kit := _creature(i, "kit")
	await _walk(i, kit.global_position + Vector3(-1.4, 0.0, 0.0), 0.4)
	await _lend(i, kit, RIGHT, TriggerMode.Kind.NONE)


## こだまの鐘: 1 人が信号の持ち上げ台に乗り、もう 1 人が鐘を鳴らす。交代して 2 人とも上がる。
func test_echo_bells_one_rides_while_the_other_rings() -> void:
	await _start("w2_echo_bells", 52200)
	await _give_kit_a_move(1)
	await _walk(0, LIFT_1_TOP, 0.25)
	await _walk(1, Vector3(0.5, 0.0, 0.6), 0.3)
	await _ring(1, "echo_bell_1")
	await _ride_up(0, Vector3(2.5, 2.0, -1.6))
	await _walk(0, Vector3(0.5, 2.0, -1.6))
	await _until_quiet("echo_bell_1")
	await _walk(1, LIFT_1_TOP, 0.25)
	await _ring(0, "echo_bell_1")
	await _ride_up(1, Vector3(2.5, 2.0, -1.6))
	await _wait_block_at("echo_stone_1", Vector3i(-4, 0, 0))
	await _until_quiet("echo_bell_1")
	await _walk(0, LIFT_2_TOP, 0.25)
	await _walk(1, Vector3(0.5, 2.0, -6.6), 0.3)
	await _ring(1, "echo_bell_2")
	await _ride_up(0, Vector3(2.5, 4.0, -8.6))
	await _walk(0, Vector3(0.5, 4.0, -8.7))
	await _until_quiet("echo_bell_2")
	await _walk(1, LIFT_2_TOP, 0.25)
	await _ring(0, "echo_bell_2")
	await _ride_up(1, Vector3(2.5, 4.0, -8.6))
	await _wait_block_at("echo_stone_2", Vector3i(-4, 2, -7))
	assert_true(await _wait_creature_in("kit", OpenIslandsW2.ECHO_NEST), "the kit is home")
	await _walk(0, Vector3(2.0, 3.0, -14.5))
	await _walk(1, Vector3(3.9, 3.0, -14.5))
	await _assert_cleared_by_everyone("w2_echo_bells")


## 転がる玉: ホストが発射台を押し、参加者が台地の「投げる」を取ってきて発射台へ渡す（投げる×2）。
## ホストが発射台を台地の壁ぎわへ滑らせ、参加者が生き物に移動を渡す。2 人とも発射台を足場に上がる。
func test_rolling_shots_one_pushes_and_one_fetches_the_throw() -> void:
	await _start("w2_rolling_shots", 52300)
	await _walk(1, Vector3(-0.5, 0.0, -7.5), 0.25)
	await _ride_lift(1, "plateau_lift", Vector3(-2.5, 2.0, -8.5))
	await _walk(1, Vector3(-3.5, 2.0, -6.5), 0.6)
	await _interact_and_hold(1, null, THROW)
	await _walk(1, Vector3(0.5, 0.0, -3.5))
	await _push_times(0, "launcher", FORWARD, 5, Vector3(-1.5, -0.5, 0.0))
	await _push_times(0, "launcher", RIGHT, 4, Vector3(0.0, -0.5, 1.5))
	assert_eq(_block(0, "launcher").cell(), Vector3i(6, 0, -1), "lined up")
	var launcher_at := _block(0, "launcher").global_position
	await _walk(0, launcher_at + Vector3(-1.5, -0.5, 0.0), 0.3)
	await _walk(1, launcher_at + Vector3(-1.5, -0.5, 1.2), 0.3)
	await _lend(0, _block(0, "launcher"), THROW, TriggerMode.Kind.NONE)
	await _lend(1, _block(1, "launcher"), THROW, TriggerMode.Kind.NONE)
	await party.until(
		func() -> bool: return _w(0).activated.has("isle_bell"), "the far bell rings", 600
	)
	await _push_times(0, "launcher", FORWARD, 4, Vector3(-1.5, -0.5, 0.0))
	await _walk(0, Vector3(5.5, 0.0, -3.5), 0.3)
	await _lend(0, _block(0, "launcher"), LEFT, TriggerMode.Kind.REPEAT)
	await _wait_block_at("launcher", Vector3i(-1, 0, -5))
	await _walk(0, _block(0, "launcher").global_position + Vector3(0.0, -0.5, 1.6), 0.4)
	await party.settle(0)
	_w(0).interact(_block(0, "launcher"))
	await party.until(
		func() -> bool: return _w(0).ledger.tokens_on(_block(0, "launcher").entity_id).is_empty(),
		"recalled everything from the launcher"
	)
	await _give_kit_a_move(1)
	assert_true(await _wait_creature_in("kit", OpenIslandsW2.ROLLING_NEST), "the kit is home")
	await _walk_route(0, [Vector3(-0.5, 1.0, -4.5), Vector3(-3.5, 2.0, -5.5)])
	await _walk_route(1, [Vector3(-0.5, 1.0, -4.5), Vector3(-3.5, 2.0, -6.0)])
	await _walk(0, Vector3(-6.5, 1.0, -11.5))
	await _walk(1, Vector3(-5.5, 1.0, -11.5))
	await _assert_cleared_by_everyone("w2_rolling_shots")


## 鳴りつづける鐘: 参加者が岩へ跳んで鐘を鳴らしつづけ、ホストが生き物に移動を渡す。2 人とも石の段で上がる。
func test_ringing_bell_one_keeps_ringing_on_the_rock() -> void:
	await _start("w2_timed_bells", 52400)
	await _give_kit_a_move(0)
	await _walk(1, Vector3(6.55, 0.0, 1.5), 0.2)
	await _leap(1, Vector3(10.5, 0.0, 1.5))
	var stone := _block(0, "walking_stone")
	var bell := _w(0).bells_by_key["rock_bell"]
	for f in 2400:
		if stone.cell() == Vector3i(6, 0, -3) and not stone.is_moving_horizontally():
			break
		if not bell.is_ringing():
			_w(1).interact(_w(1).bells_by_key["rock_bell"])
			if not await party.until(bell.is_ringing, "the guest rings the rock bell"):
				break
		await tree.physics_frame
	assert_eq(stone.cell(), Vector3i(6, 0, -3), "the stone walked to the wall")
	assert_true(await _wait_creature_in("kit", OpenIslandsW2.RINGING_NEST), "the kit is home")
	await _walk(1, Vector3(10.9, 0.0, 1.5), 0.2)
	await _leap(1, Vector3(5.5, 0.0, 1.5))
	for i in 2:
		var lane := 5.4 - float(i)
		await _walk_route(i, [Vector3(lane, 0.0, -2.5), Vector3(6.5, 1.0, -2.5)])
		await _walk_route(i, [Vector3(6.5, 2.0, -4.5), Vector3(5.5, 2.0, -7.5)])
	await _walk(0, Vector3(-4.0, 1.0, -10.5))
	await _walk(1, Vector3(-2.6, 1.0, -10.5))
	await _assert_cleared_by_everyone("w2_timed_bells")


## i 番目が、いまの位置から land へ向かって走り、少し進んでから跳んで谷を越える。
func _leap(i: int, land: Vector3) -> void:
	var me := _w(i).player
	var flat := Vector3(land.x - me.global_position.x, 0.0, land.z - me.global_position.z)
	me.view_yaw = atan2(-flat.x, -flat.z)
	me.move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(6)
	_w(i).press_action(JUMP)
	await _walk(i, land, 0.6)
