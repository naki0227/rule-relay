extends "res://tests/integration/island_probing.gd"
## 鐘の谷（W2）の新しいステージの関所と詰みを、プレイヤーと同じ操作で壊しにいく試遊（2026-11-21）。
## 書き方は test_island_probes.gd と同じ（test_gate_* / test_accepted_* / test_finding_*）。
## どの島にもダッシュは無い。谷は「転がる玉」の幅 10（歩いても跳んでも、受け入れた重ね跳びでも越えない）だけ。
## 「鳴りつづける鐘」（2-5。時の鐘）は test_world2_timed_bells_probes.gd。

const BACK := RuleAction.Kind.BACK
const RIGHT := RuleAction.Kind.RIGHT
const ECHO_ID := "w2_echo_bells"
const ROLLING_ID := "w2_rolling_shots"


func _give_kit_a_move() -> void:
	var kit := _creature("kit")
	await _walk_to(kit.global_position + Vector3(-1.4, 0.0, 0.0), 0.4)
	_lend(kit, _slot_of(RIGHT), TriggerMode.Kind.NONE)


func _ring_here(key: String) -> void:
	var bell := w.bells_by_key[key]
	_face(bell.global_position)
	w.interact(bell)
	await wait_physics_frames(2)
	assert_true(bell.is_ringing(), "rang %s" % key)


func _block_cell_after(key: String, frames: int) -> Vector3i:
	await wait_physics_frames(frames)
	return _block(key).cell()


# --- こだまの鐘 -------------------------------------------------------------------


func test_gate_echo_mid_and_top_are_not_plain_jumps() -> void:
	await _enter(ECHO_ID)
	var best := await _jump_against(Vector3(6.5, 0.0, 0.4), Vector3(6.5, 2.0, -1.5))
	assert_lt(best, 1.5, "lower field (0) to the middle step (2)")
	await _walk_to(_block("echo_lift_1").global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	await _ring_here("echo_bell_1")
	for i in 300:
		_face(Vector3(2.5, 2.0, -1.6))
		_me().move_intent = Vector2(0.0, 1.0) if _me().global_position.y > 2.0 else Vector2.ZERO
		if _me().global_position.z < -1.2 and _me().is_on_floor():
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	best = await _jump_against(Vector3(6.5, 2.0, -6.6), Vector3(6.5, 4.0, -8.5))
	assert_lt(best, 3.5, "middle step (2) to the top (4)")


## 鐘が鳴らなければ、信号の台は跳ねず、信号の石も動かない。
func test_gate_echo_signal_blocks_wait_for_a_bell() -> void:
	await _enter(ECHO_ID)
	var lift := _block("echo_lift_1")
	await _walk_to(lift.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	var top := 0.0
	for i in 240:
		top = maxf(top, _me().global_position.y)
		await tree.physics_frame
	assert_lt(top, 0.2, "the signal lift stays down without a bell")
	assert_eq(_block("echo_stone_1").cell(), Vector3i(-4, 2, -5), "the stone stays put")


## 鐘 1 回（5 秒）では石 1 は 3 マスしか動かず、中の段の上で止まる。生き物は下の原で待つ。
func test_gate_echo_one_ring_is_not_enough_for_the_first_stone() -> void:
	await _enter(ECHO_ID)
	await _give_kit_a_move()
	await _walk_to(Vector3(0.5, 0.0, 0.6), 0.3)
	await _ring_here("echo_bell_1")
	var cell := await _block_cell_after("echo_stone_1", 420)
	assert_eq(cell, Vector3i(-4, 2, -2), "three steps in one ring, still on the middle step")
	assert_lt(await _creature_top("kit", 120), 1.6, "the kit is still below the middle step")


## 鐘 2 の音は石 1 に届かない（6 m の外）。鐘 1 の音は石 2 に届かない。
func test_gate_echo_each_bell_reaches_only_its_own_stone() -> void:
	await _enter(ECHO_ID)
	await _walk_to(_block("echo_lift_1").global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	await _ring_here("echo_bell_1")
	for i in 300:
		_face(Vector3(2.5, 2.0, -1.6))
		_me().move_intent = Vector2(0.0, 1.0) if _me().global_position.y > 2.0 else Vector2.ZERO
		if _me().global_position.z < -1.2 and _me().is_on_floor():
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_eq(
		await _block_cell_after("echo_stone_2", 300), Vector3i(-4, 4, -11), "bell 1 ≠ stone 2"
	)
	var stone_1 := _block("echo_stone_1").cell()
	await _walk_to(Vector3(1.5, 2.0, -6.6), 0.3)
	for i in 400:
		if not w.bells_by_key["echo_bell_1"].is_ringing():
			break
		await tree.physics_frame
	await _ring_here("echo_bell_2")
	assert_eq(await _block_cell_after("echo_stone_1", 420), stone_1, "bell 2 ≠ stone 1")


func test_gate_echo_goal_without_the_kit_is_not_a_clear() -> void:
	await _enter(ECHO_ID)
	await _walk_to(Vector3(-0.5, 0.0, 0.5), 0.25)
	_lend(w.terrain_target(Vector3i(-1, -1, 0)), _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	await _climb_off_lift(Vector3(-0.5, 2.0, -1.6))
	await _walk_to(Vector3(-0.5, 2.0, -6.5), 0.25)
	_lend(w.terrain_target(Vector3i(-1, 1, -7)), _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	await _climb_off_lift(Vector3(-0.5, 4.0, -8.6))
	await _walk_into_goal([Vector3(0.5, 4.0, -11.5)])
	assert_false(await _cleared(120), "everyone at the goal, but the kit is not home")


## 石を繰り返しで押して島の外へ落としても、元の場所へ戻される（救済）。信号の能力も付いたまま（詰まない）。
func test_gate_echo_stone_pushed_off_the_island_comes_back() -> void:
	await _enter(ECHO_ID)
	await _walk_to(Vector3(-0.5, 0.0, 0.5), 0.25)
	_lend(w.terrain_target(Vector3i(-1, -1, 0)), _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	await _climb_off_lift(Vector3(-0.5, 2.0, -1.6))
	var stone := _block("echo_stone_1")
	await _walk_to(stone.global_position + Vector3(1.5, -0.5, 0.0), 0.3)
	_lend(stone, _slot_of(RuleAction.Kind.LEFT), TriggerMode.Kind.REPEAT)
	var lowest := stone.global_position.y
	for i in 900:
		lowest = minf(lowest, stone.global_position.y)
		if lowest < -2.0 and stone.cell() == Vector3i(-4, 2, -5):
			break
		await tree.physics_frame
	assert_lt(lowest, -2.0, "slid off the west edge")
	assert_eq(stone.cell(), Vector3i(-4, 2, -5), "put back where it started")
	assert_eq(w.ledger.tokens_on(stone.entity_id).size(), 1, "its signal is still on it")
	assert_ne(_slot_of(RuleAction.Kind.LEFT), -1, "my A came back to me")


func _climb_off_lift(onto: Vector3) -> void:
	for i in 300:
		_face(onto)
		_me().move_intent = Vector2(0.0, 1.0) if _me().global_position.y > onto.y else Vector2.ZERO
		if (
			Vector2(onto.x - _me().global_position.x, onto.z - _me().global_position.z).length()
			< 0.4
		):
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_gt(_me().global_position.y, onto.y - 0.3, "up onto %s" % onto)


# --- 転がる玉 ---------------------------------------------------------------------


## 東の小島（谷の幅 10）へは、浜の東の端から走って跳んでも届かない。
func test_gate_rolling_isle_is_not_a_running_jump() -> void:
	await _enter(ROLLING_ID)
	var route: Array[Vector3] = [Vector3(3.5, 0.0, -1.5)]
	assert_false(
		await _running_jump(route, Vector3.RIGHT, 7.0, 10.0, 0.0), "gap 10 by a running jump"
	)
	assert_false(w.activated.has("isle_bell"), "the far bell is silent")


## 受け入れた重ね跳び（足もとのセルの上昇＋自分のジャンプ）でも、同じ高さへは約 8.4 m なので届かない。
func test_gate_rolling_isle_is_out_of_reach_even_by_stacking_jumps() -> void:
	await _enter(ROLLING_ID)
	await _walk_to(Vector3(6.5, 0.0, -0.5), 0.2)
	_lend(w.terrain_target(Vector3i(6, -1, -1)), _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	var pressed := false
	var farthest := 0.0
	for i in 240:
		if not pressed and w.ledger.player_can(JUMP, _me().player_id) and _me().is_on_floor():
			if _me().global_position.y > 0.05:
				w.press_action(JUMP)
				pressed = true
		_me().view_yaw = atan2(-1.0, 0.0)
		_me().move_intent = Vector2(0.0, 1.0) if _me().global_position.y > 0.3 else Vector2.ZERO
		if _me().global_position.y > -0.5:
			farthest = maxf(farthest, _me().global_position.x)
		if _me().global_position.y < -3.0:
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	print("    rolling_shots: stacked jump reached x = %.2f (isle starts at 17)" % farthest)
	assert_true(pressed, "jumped on the rising cell")
	assert_lt(farthest, 16.5, "short of the far isle")
	await _wait_respawn()
	assert_false(w.activated.has("isle_bell"), "the far bell is silent")


## 鐘は浜の東の端から手が届かない（跳びながら F を押しても）。
func test_gate_rolling_bell_is_not_rung_from_the_shore() -> void:
	await _enter(ROLLING_ID)
	assert_false(await _try_ring_from("isle_bell", Vector3(6.3, 0.0, -0.5)), "from the shore")


## 発射台に「投げる」1 つでは、鐘の列の東の端からでも届かない（約 6.4 m）。最初の位置からも当たらない。
func test_gate_rolling_one_throw_falls_short() -> void:
	await _enter(ROLLING_ID)
	var launcher := _block("launcher")
	await _walk_to(launcher.global_position + Vector3(-1.5, -0.5, 0.0), 0.3)
	_lend(launcher, _slot_of(THROW), TriggerMode.Kind.NONE)
	assert_false(await _wait_until_rung("isle_bell", 240), "not from the starting spot")
	_recall_launcher()
	for i in 5:
		await _push_block(launcher, RuleAction.Kind.FORWARD, Vector3(-1.5, -0.5, 0.0))
	for i in 4:
		await _push_block(launcher, RIGHT, Vector3(0.0, -0.5, 1.5))
	assert_eq(launcher.cell(), Vector3i(6, 0, -1), "lined up with the bell")
	await _walk_to(launcher.global_position + Vector3(-1.5, -0.5, 0.0), 0.3)
	_lend(launcher, _slot_of(THROW), TriggerMode.Kind.NONE)
	assert_false(await _wait_until_rung("isle_bell", 360), "one throw falls short of the bell")


func _recall_launcher() -> void:
	var launcher := _block("launcher")
	w.interact(launcher)
	assert_true(w.ledger.tokens_on(launcher.entity_id).is_empty(), "took the throw back")


func _push_block(block: RuleBlock, action: RuleAction.Kind, offset: Vector3) -> void:
	var at := block.global_position + offset
	await _walk_to(Vector3(at.x, 0.0, at.z), 0.3)
	_lend(block, _slot_of(action), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(action)
	await wait_physics_frames(40)


func test_gate_rolling_plateau_is_not_a_plain_jump_and_the_kit_waits() -> void:
	await _enter(ROLLING_ID)
	await _give_kit_a_move()
	var best := await _jump_against(Vector3(-0.5, 0.0, -4.2), Vector3(-0.5, 2.0, -6.5))
	assert_lt(best, 1.5, "shore (0) to plateau (2)")
	# 1 段の物（発射台）には跳び乗るが、台地（2）へは上がれない
	assert_lt(await _creature_top("kit", 240), 1.6, "no step: the kit stays below the plateau")


## 発射台を繰り返しで東へ押すと、浜の端から落ちて最初の場所へ戻される（渡した能力は手元に戻る）。詰まない。
func test_gate_rolling_launcher_pushed_off_the_shore_comes_back() -> void:
	await _enter(ROLLING_ID)
	var launcher := _block("launcher")
	await _walk_to(launcher.global_position + Vector3(-1.5, -0.5, 0.0), 0.3)
	_lend(launcher, _slot_of(RIGHT), TriggerMode.Kind.REPEAT)
	var lowest := launcher.global_position.y
	for i in 900:
		lowest = minf(lowest, launcher.global_position.y)
		if lowest < -2.0 and launcher.cell() == Vector3i(2, 0, 4):
			break
		await tree.physics_frame
	assert_lt(lowest, -2.0, "slid off the east edge")
	assert_eq(launcher.cell(), Vector3i(2, 0, 4), "put back where it started")
	assert_ne(_slot_of(RIGHT), -1, "my D came back")


func test_gate_rolling_goal_without_the_bell_and_the_kit_is_not_a_clear() -> void:
	await _enter(ROLLING_ID)
	await _lift_up("plateau_lift", Vector3(0.5, 0.0, -7.5), Vector3(-2.5, 2.0, -8.5))
	await _walk_into_goal()
	assert_false(await _cleared(120), "at the goal, but no bell and no kit")
