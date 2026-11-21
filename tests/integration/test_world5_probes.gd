extends "res://tests/integration/world56_play.gd"
## ワールド 5 の新しいステージ（5-1・5-2・5-4・5-5）の関所と詰みを、プレイヤーと同じ操作で壊しにいく試遊。
## 書き方は test_island_probes.gd と同じ:
## - test_gate_*: 意図した関所が守られていること（壊れたら失敗する）
## - test_finding_*: 試遊で見つけた挙動の記録（直すかどうかは本人が決める）
## 受け入れた技（どの地面のセルも持ち上げ台・ブロックの上昇＋自分のジャンプ・縁ちょうどの幅 4）は、
## どの段差 2 にも効く（止めない）。ここでは「ふつうの操作では越えられない」ことだけを確かめる。

# --- 5-1 はじめての札 ------------------------------------------------------------


func test_gate_first_signs_terrace_is_two_high() -> void:
	await _enter(World5Stages.FIRST_ID)
	var best := await _jump_against(Vector3(3.5, 0.0, -3.7), Vector3(3.5, 2.0, -7.0))
	assert_lt(best, 1.5, "meadow (0) to terrace (2)")


## 札が付いたままでは、持ち上げ台は跳ばず（単発は戻る）、うさぎは投げない（鐘は鳴らない）。
func test_gate_first_signs_signs_hold_the_lift_and_the_bunny() -> void:
	await _enter(World5Stages.FIRST_ID)
	var lift := _block("sign_lift")
	var rest_y := lift.global_position.y
	await _walk_to(Vector3(-4.5, 0.0, -3.5), 0.3)
	_lend(lift, _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	await wait_physics_frames(40)
	assert_almost(lift.global_position.y, rest_y, 0.05, "the sign keeps the lift down")
	assert_ne(_slot_of(JUMP), -1, "the single shot came back")
	await _walk_to(Vector3(0.5, 0.0, -3.7), 0.3)
	_lend_by_throwing(_creature("sign_bunny"), _slot_of(THROW))
	assert_false(await _wait_until_rung("terrace_bell", 240), "the signed bunny does not throw")


func test_gate_first_signs_bell_out_of_reach_from_the_meadow() -> void:
	await _enter(World5Stages.FIRST_ID)
	assert_false(await _try_ring_from("terrace_bell", Vector3(0.5, 0.0, -3.7)), "out of reach")


# --- 5-2 まとめて渡す札 ----------------------------------------------------------


## 石 2 つを板に乗せても、小山の板が空なら扉は開かない（3 枚全部）。
func test_gate_range_signs_gate_needs_all_three_plates() -> void:
	await _enter(World5Stages.RANGE_ID)
	var east := _block("stone_east")
	await _walk_to(Vector3(1.5, 0.0, 1.1), 0.25)
	w.select_slot(_slot_of(FORWARD))
	w.set_lend_mode(TriggerMode.Kind.SINGLE_SHOT)
	assert_eq(w.lend_to(east, true), RuleLedger.LendResult.OK, "ranged lend")
	w.press_action(FORWARD)
	await wait_physics_frames(90)
	assert_eq(_block("stone_west").cell().z, -2, "both stones on their plates")
	await _walk_to(Vector3(8.5, 0.0, -8.5))
	await _walk_to(Vector3(8.5, 1.0, -9.5))
	assert_false(await _try_walk_to(Vector3(8.5, 2.0, -12.5), 0.35, 180), "the gate stays shut")


## もこもこは、移動だけでは小山（1）へ上がれない（ジャンプが要る）。
func test_gate_range_signs_lamb_needs_a_jump() -> void:
	await _enter(World5Stages.RANGE_ID)
	var lamb := _creature("mound_lamb")
	await _walk_to(lamb.global_position + Vector3(1.6, 0.0, 0.0), 0.4)
	_lend(lamb, _slot_of(LEFT), TriggerMode.Kind.NONE)
	assert_lt(await _creature_top("mound_lamb", 300), 0.4, "a move alone does not climb")


# --- 5-4 氷の庭 ------------------------------------------------------------------


## 石をまっすぐ北へすべらせると、棚のない列（x = -5）の崖で止まる。そこから台地（3）へは跳べない。
func test_gate_ice_garden_straight_slide_misses_the_shelf() -> void:
	await _enter(World5Stages.ICE_ID)
	var stone := _block("ice_stone")
	await _walk_to(Vector3(-5.5, 0.0, 5.4), 0.3)
	w.interact(stone)
	await wait_physics_frames(2)
	_hand_off_ban(RIGHT, w.terrain_target(Vector3i(-7, -1, 7)))
	_lend(stone, _slot_of(FORWARD), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(FORWARD)
	await _wait_block_at("ice_stone", Vector3i(-5, 0, -7))
	assert_ne(stone.cell().x, World5Stages.ICE_PIER_X, "not under the shelf")


## 池から棚（2）へは、ふつうのジャンプでは届かない（氷の上で壁に押しつけて跳び続けても）。
func test_gate_ice_garden_shelf_is_two_high_from_the_ice() -> void:
	await _enter(World5Stages.ICE_ID)
	var best := await _jump_against(Vector3(4.5, 0.0, -5.0), Vector3(4.5, 2.0, -7.5), 240)
	assert_lt(best, 1.5, "ice (0) to shelf (2)")


## 札を持っていても、氷の上の勢いは止まらない（札は行動だけを止める。ADR 0015 の「外の力」と同じ）。
## D 禁止を持ったまま、東へすべり続ける。
func test_finding_ice_garden_d_ban_does_not_stop_a_slide() -> void:
	await _enter(World5Stages.ICE_ID)
	await _walk_to(Vector3(-5.5, 0.0, 5.4), 0.3)
	w.interact(_block("ice_stone"))
	await wait_physics_frames(2)
	assert_false(w.ledger.player_can(RIGHT, _me().player_id), "the D ban is on me")
	await _walk_to(Vector3(-8.5, 0.0, 0.5), 0.4)
	_face(Vector3(8.5, 0.0, 0.5))
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(60)
	_me().move_intent = Vector2.ZERO
	var x0 := _me().global_position.x
	await wait_physics_frames(20)
	assert_gt(_me().global_position.x, x0 + 0.3, "still sliding east with the D ban in hand")


# --- 5-5 札の受け渡し ------------------------------------------------------------


## 生け垣の門は最初閉じていて、小島の重い石は庭から F（触る距離）が届かない。
func test_gate_sign_relay_heavy_stone_is_out_of_touch() -> void:
	await _enter(World5Stages.RELAY_ID)
	var stone := _block("heavy_stone")
	await _walk_to(Vector3(12.6, 0.0, 4.5), 0.25)
	w.interact(stone)
	await wait_physics_frames(30)
	assert_eq(w.ledger.tokens_on(stone.entity_id).size(), 1, "the weight stays on the stone")
	assert_false(_door_open_now("hedge_gate"), "the hedge gate is shut")
	assert_false(await _try_walk_to(Vector3(0.5, 0.0, -6.5), 0.35, 240), "no way through")


## もこもこの札（重い禁止）を残したまま重いを渡しても、小山の板は押せない（4 人分にならない）。
func test_gate_sign_relay_lambs_sign_cancels_the_weight() -> void:
	await _enter(World5Stages.RELAY_ID)
	await _walk_to(Vector3(-4.5, 0.0, 8.5), 0.6)
	w.interact(null)
	await wait_physics_frames(2)
	var heavy := _to_hotbar(HEAVY)
	var lamb := _creature("relay_lamb")
	await _walk_to(lamb.global_position + Vector3(1.6, 0.0, 0.0), 0.4)
	_lend(lamb, _slot_of(LEFT), TriggerMode.Kind.NONE)
	_lend(lamb, _slot_of(JUMP), TriggerMode.Kind.NONE)
	_lend(lamb, heavy, TriggerMode.Kind.NONE)
	assert_true(await _wait_creature_in("relay_lamb", World5Stages.RELAY_NEST), "on the mound")
	await wait_physics_frames(30)
	assert_false(_door_open_now("stair_gate"), "the banned weight does not count")


## 自分が小山の板に乗っても 1 人分なので、階段の扉は開かない。
func test_gate_sign_relay_a_light_player_cannot_hold_the_stair_gate() -> void:
	await _enter(World5Stages.RELAY_ID)
	await _walk_to(Vector3(-7.5, 1.0, 4.5), 0.3)
	await wait_physics_frames(30)
	assert_false(_door_open_now("stair_gate"), "one person is not four")


func _door_open_now(key: String) -> bool:
	for door in MechanismSet.of(w).doors:
		if door.spec.key == key:
			return door.is_open()
	return false
