extends "res://tests/integration/world56_play.gd"
## ワールド 5「札の庭」の新しいステージ（5-1・5-2・5-4・5-5）を、ひとりで最初から最後まで自動で遊ぶ。
## 操作はプレイヤーと同じ（move_intent・view_yaw・press_action と、渡す・回収・拾う）で、瞬間移動はしない。
## どのステージも、ひとりの道 2 通りと協力の近道 1 通り（仲間がくれた能力を台帳の普通の配り方で持たせる）を通す。
## 関所と詰みの試遊は test_world5_probes.gd、ゴールの視線は test_goal_sightlines_w56.gd。

const BACK := RuleAction.Kind.BACK

# --- 5-1 はじめての札 ------------------------------------------------------------


## 原っぱから、うさぎの札（投げる禁止）を F で回収し、「投げる」を触って渡して鐘を鳴らす。
func _bunny_rings_the_bell() -> void:
	var bunny := _creature("sign_bunny")
	await _walk_to(Vector3(0.5, 0.0, -3.7), 0.3)
	w.interact(bunny)
	await wait_physics_frames(2)
	assert_true(w.ledger.player_prohibited(THROW, _me().player_id), "the bunny's sign is on me")
	_lend(bunny, _slot_of(THROW), TriggerMode.Kind.NONE)
	assert_true(await _wait_until_rung("terrace_bell"), "the bunny threw its nut at the bell")


## ひとりの道 1: うさぎの願い（木の実）で鐘、札付きの持ち上げ台で段へ。
func test_first_signs_bunny_and_the_signed_lift() -> void:
	await _enter(World5Stages.FIRST_ID)
	await _bunny_rings_the_bell()
	await _walk_to(Vector3(-4.5, 0.0, -3.5), 0.3)
	w.interact(_block("sign_lift"))
	await wait_physics_frames(2)
	assert_true(w.ledger.player_prohibited(JUMP, _me().player_id), "the lift's sign is on me")
	_hand_off_ban(JUMP, w.terrain_target(Vector3i(-3, -1, -2)))
	await _lift_up("sign_lift", Vector3(-4.5, 0.0, -3.5), Vector3(-5.5, 2.0, -7.5))
	await _walk_into_goal()
	assert_true(await _cleared(), "the bell and the goal")


## ひとりの道 2: 石の札（W 禁止）を回収して手放し、石を段の壁まで進めて足場にする。鐘は触って鳴らす。
func test_first_signs_signed_stone_becomes_a_step() -> void:
	await _enter(World5Stages.FIRST_ID)
	var stone := _block("sign_stone")
	await _walk_to(Vector3(6.5, 0.0, 4.1), 0.25)
	w.interact(stone)
	await wait_physics_frames(2)
	assert_false(w.ledger.player_can(FORWARD, _me().player_id), "holding the W ban: no walking on")
	_hand_off_ban(FORWARD, w.terrain_target(Vector3i(8, -1, 4)))
	# 自分の W を石へ繰り返しで渡すと、自分は前へ歩けない。カメラを回して S（後ろ）で石を追いかける
	_lend(stone, _slot_of(FORWARD), TriggerMode.Kind.REPEAT)
	for i in 900:
		if stone.cell() == Vector3i(6, 0, -4) and not stone.is_moving_horizontally():
			break
		await tree.physics_frame
	assert_eq(stone.cell(), Vector3i(6, 0, -4), "the stone walked up to the terrace wall")
	assert_true(await _back_to(Vector3(6.5, 0.0, -1.9)), "followed it walking backwards")
	await _recall_all_from("sign_stone")
	await _walk_to(Vector3(6.5, 1.0, -3.5))
	await _walk_to(Vector3(6.5, 2.0, -6.5))
	await _ring("terrace_bell")
	await _walk_into_goal()
	assert_true(await _cleared(), "climbed the stone the sign was holding back")


## 協力の近道: 仲間のジャンプでジャンプ×2 にすれば、段差 2 を直接跳べる（札に触らない）。
func test_first_signs_coop_double_jump() -> void:
	await _enter(World5Stages.FIRST_ID)
	_gift_from_teammate(JUMP)
	await _walk_to(Vector3(3.5, 0.0, -4.0))
	await _walk_to(Vector3(3.5, 2.0, -7.0))
	await _ring("terrace_bell")
	await _walk_into_goal()
	assert_true(await _cleared(), "jumped up with a teammate's jump")
	assert_eq(w.ledger.tokens_on(_block("sign_lift").entity_id).size(), 1, "the lift kept its sign")


# --- 5-2 まとめて渡す札 ----------------------------------------------------------


## 範囲で渡す（右クリック）。渡したら単体の渡し方に戻す。
func _lend_range(target: Node3D, slot: int, mode: TriggerMode.Kind) -> void:
	w.select_slot(slot)
	w.set_lend_mode(mode)
	assert_eq(w.lend_to(target, true), RuleLedger.LendResult.OK, "range lend to %s" % target.name)


## もこもこに A とジャンプを渡し、小山に乗ったら F で取り戻す。
func _lamb_onto_the_mound() -> void:
	var lamb := _creature("mound_lamb")
	await _walk_to(lamb.global_position + Vector3(1.6, 0.0, 0.0), 0.4)
	_lend(lamb, _slot_of(LEFT), TriggerMode.Kind.NONE)
	_lend(lamb, _slot_of(JUMP), TriggerMode.Kind.NONE)
	assert_true(
		await _wait_creature_in("mound_lamb", World5Stages.RANGE_NEST), "the lamb hopped up"
	)
	await _walk_to(Vector3(-8.6, 0.0, -3.5), 0.3)
	w.interact(lamb)
	await wait_physics_frames(2)
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "took the jump back")
	assert_true(w.ledger.player_can(LEFT, _me().player_id), "took the A back")
	await wait_physics_frames(60)
	assert_true(
		World5Stages.RANGE_NEST.has_point(lamb.global_position), "the lamb stays on the mound"
	)


func _plate_pressed(key: String) -> bool:
	return MechanismSet.of(w).is_source_active(key)


func _door(key: String) -> SwitchDoor:
	for door in MechanismSet.of(w).doors:
		if door.spec.key == key:
			return door
	return null


## 階段から開いた扉を抜けて台地へ上がり、ゴールへ。
func _through_the_gate() -> void:
	for i in 120:
		if _door("stair_gate").is_open():
			break
		await tree.physics_frame
	await _walk_to(Vector3(8.5, 0.0, -8.5))
	await _walk_to(Vector3(8.5, 1.0, -9.5))
	await _walk_to(Vector3(8.5, 2.0, -12.5))
	await _walk_into_goal()


## ひとりの道 1: W を範囲で単発に渡し、石 2 つを 1 回で板へ。
func test_range_signs_one_ranged_push_moves_both_stones() -> void:
	await _enter(World5Stages.RANGE_ID)
	await _lamb_onto_the_mound()
	var east := _block("stone_east")
	await _walk_to(Vector3(1.5, 0.0, 1.1), 0.25)
	_lend_range(east, _slot_of(FORWARD), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(FORWARD)
	await wait_physics_frames(60)
	assert_eq(east.cell(), Vector3i(1, 0, -2), "east stone on its plate")
	assert_eq(_block("stone_west").cell(), Vector3i(-1, 0, -2), "west stone too, same push")
	assert_true(_plate_pressed("plate_west") and _plate_pressed("plate_east"), "both plates down")
	assert_true(_plate_pressed("plate_mound"), "the lamb holds the mound plate")
	await _through_the_gate()
	assert_true(await _cleared(), "one ranged push, the lamb's wish and the gate")


## ひとりの道 2: 単発の W を 1 つずつ渡す（使うと手元に戻る）。
func test_range_signs_push_the_stones_one_by_one() -> void:
	await _enter(World5Stages.RANGE_ID)
	for key: String in ["stone_west", "stone_east"]:
		var stone := _block(key)
		await _walk_to(stone.global_position + Vector3(0.0, -0.5, 1.6), 0.25)
		_lend(stone, _slot_of(FORWARD), TriggerMode.Kind.SINGLE_SHOT)
		w.press_action(FORWARD)
		await wait_physics_frames(60)
		assert_eq(stone.cell().z, -2, "%s on its plate" % key)
		assert_ne(_slot_of(FORWARD), -1, "the single shot came back")
	await _lamb_onto_the_mound()
	await _through_the_gate()
	assert_true(await _cleared(), "pushed the stones one at a time")


## 協力の近道: ジャンプ×2 で台地へ直接（扉を開けない）。動物の願いは協力でも要る。
func test_range_signs_coop_double_jump_still_needs_the_lamb() -> void:
	await _enter(World5Stages.RANGE_ID)
	_gift_from_teammate(JUMP)
	await _walk_to(Vector3(-0.5, 0.0, -9.6))
	await _walk_to(Vector3(-0.5, 2.0, -12.5))
	await _walk_into_goal()
	assert_false(await _cleared(90), "the lamb is not on its mound yet")
	await _walk_to(Vector3(-4.5, 2.0, -12.5))
	await _walk_to(Vector3(-6.5, 0.0, -6.5))
	await _lamb_onto_the_mound()
	await _walk_to(Vector3(-0.5, 0.0, -9.6))
	await _walk_to(Vector3(-0.5, 2.0, -12.5))
	await _walk_into_goal()
	assert_true(await _cleared(), "the lamb on the mound and everyone up top")


# --- 5-4 氷の庭 ------------------------------------------------------------------


## 池の石の札を回収して手放し、D と W を単発で渡して、杭 → 桟橋 → 台地の壁まですべらせる。
func _slide_the_ice_stone() -> void:
	var stone := _block("ice_stone")
	await _walk_to(Vector3(-5.5, 0.0, 5.4), 0.3)
	w.interact(stone)
	await wait_physics_frames(2)
	assert_false(w.ledger.player_can(RIGHT, _me().player_id), "the D ban is on me")
	_hand_off_ban(RIGHT, w.terrain_target(Vector3i(-7, -1, 7)))
	_lend(stone, _slot_of(RIGHT), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(RIGHT)
	await _wait_block_at("ice_stone", Vector3i(World5Stages.ICE_PIER_X, 0, 2))
	await _walk_to(Vector3(4.5, 0.0, 5.4), 0.3)
	_lend(stone, _slot_of(FORWARD), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(FORWARD)
	await _wait_block_at("ice_stone", Vector3i(World5Stages.ICE_PIER_X, 0, -7))


## 氷の上で target に止まる（人が W を弱めたり離したりして寄せるのと同じ。入力の強さだけを変える）。
func _ice_settle(target: Vector3, tolerance: float = 0.2) -> bool:
	for i in 900:
		var flat := Vector3(
			target.x - _me().global_position.x, 0.0, target.z - _me().global_position.z
		)
		var speed := Vector2(_me().velocity.x, _me().velocity.z).length()
		if flat.length() <= tolerance and speed < 0.4:
			_me().move_intent = Vector2.ZERO
			return true
		_face(target)
		_me().move_intent = Vector2(0.0, clampf(flat.length() * 0.25, 0.0, 1.0))
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	return false


## 氷の上では壁に押しつけたまま跳ぶと勢いが無いので、下がって止まり、助走してから跳ぶ（人も同じ）。
func _ice_leap(jump_z: float, land: Vector3) -> void:
	assert_true(await _ice_settle(Vector3(4.5, 0.0, 0.5)), "stopped on the ice for a run-up")
	var jumped := false
	for i in 300:
		_face(Vector3(4.5, 0.0, land.z))
		_me().move_intent = Vector2(0.0, 1.0)
		if not jumped and _me().global_position.z <= jump_z and _me().is_on_floor():
			w.press_action(JUMP)
			jumped = true
		var landed := _me().is_on_floor() and _me().global_position.y > land.y - 0.2
		if jumped and landed and _me().global_position.z < land.z + 0.6:
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_gt(_me().global_position.y, land.y - 0.2, "leapt onto %s" % land)


## 棚（2）→ 台地（3）へ上がる。
func _up_the_shelf() -> void:
	await _walk_to(Vector3(4.5, 2.0, -7.5))
	await _walk_to(Vector3(4.5, 3.0, -9.5))


## ひとりの道 1: 石を氷ですべらせて棚の下の足場にし、うさぎに「投げる」を触って渡す。
func test_ice_garden_slide_the_stone_under_the_shelf() -> void:
	await _enter(World5Stages.ICE_ID)
	await _slide_the_ice_stone()
	await _ice_leap(-4.9, Vector3(4.5, 1.0, -6.5))
	await _up_the_shelf()
	var bunny := _creature("ice_bunny")
	await _walk_to(Vector3(-3.5, 3.0, -9.5), 0.3)
	_lend(bunny, _slot_of(THROW), TriggerMode.Kind.NONE)
	assert_true(await _wait_until_rung("ice_bell"), "the bunny's nut rang the bell")
	await _walk_into_goal()
	assert_true(await _cleared(), "the slid stone was the way up")


## ひとりの道 2: 岸のブーツで、池から棚へ跳ぶ。鐘は触って鳴らす。
func test_ice_garden_boots_onto_the_shelf() -> void:
	await _enter(World5Stages.ICE_ID)
	await _pick_and_wear(Vector3(9.5, 0.0, 9.5), RuleVessel.Part.FEET)
	await _ice_leap(-5.1, Vector3(4.5, 2.0, -7.5))
	await _up_the_shelf()
	await _ring("ice_bell")
	await _walk_into_goal()
	assert_true(await _cleared(), "boots onto the shelf")


## 協力の近道: 岸から「投げる」をうさぎへ投げ渡し（遠くへ渡す）、ジャンプ×2 で池から棚へ。
func test_ice_garden_coop_double_jump() -> void:
	await _enter(World5Stages.ICE_ID)
	await _walk_to(Vector3(-5.5, 0.0, 5.4))
	await _lend_by_throwing(_creature("ice_bunny"), _slot_of(THROW))
	assert_true(await _wait_until_rung("ice_bell"), "thrown to the bunny from the shore")
	_gift_from_teammate(JUMP)
	await _ice_leap(-5.1, Vector3(4.5, 2.0, -7.5))
	await _up_the_shelf()
	await _walk_into_goal()
	assert_true(await _cleared(), "jumped onto the shelf with a teammate's jump")


# --- 5-5 札の受け渡し ------------------------------------------------------------


func _door_open(key: String, frames: int = 120) -> bool:
	for i in frames:
		if _door(key).is_open():
			return true
		await tree.physics_frame
	return false


## もこもこの札（重い禁止）を F で回収する。
func _take_the_lambs_sign() -> void:
	await _walk_to(Vector3(-8.0, 0.0, 6.5), 0.3)
	w.interact(_creature("relay_lamb"))
	await wait_physics_frames(2)
	assert_true(w.ledger.player_prohibited(RuleAction.Kind.HEAVY, _me().player_id), "sign on me")


## もこもこに A・ジャンプ・重いを渡して小山に乗せ、F で全部取り戻してから重いだけ返す。
func _lamb_weighs_down_the_mound() -> void:
	var lamb := _creature("relay_lamb")
	await _walk_to(lamb.global_position + Vector3(1.6, 0.0, 0.0), 0.4)
	_lend(lamb, _slot_of(LEFT), TriggerMode.Kind.NONE)
	_lend(lamb, _slot_of(JUMP), TriggerMode.Kind.NONE)
	_lend(lamb, _heavy_slot(), TriggerMode.Kind.NONE)
	assert_true(await _wait_creature_in("relay_lamb", World5Stages.RELAY_NEST), "on the mound")
	await _walk_to(Vector3(-6.6, 0.0, 4.5), 0.3)
	w.interact(lamb)
	await wait_physics_frames(2)
	_lend(lamb, _heavy_slot(), TriggerMode.Kind.NONE)
	assert_true(await _door_open("stair_gate"), "the heavy lamb holds the stair gate open")


## 重い（能力）のあるホットバーの枠。無ければ通常インベントリから空きへ移す。
func _heavy_slot() -> int:
	for hotbar in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(hotbar, _me().player_id)
		var t := w.ledger.token(v.token_id) if v != null else null
		if (
			t != null
			and t.action == RuleAction.Kind.HEAVY
			and not t.is_prohibition
			and not t.is_lent()
		):
			return hotbar
	var slot := _free_slot()
	for v in w.ledger.inventory_vessels(_me().player_id):
		var t := w.ledger.token(v.token_id)
		if t.action == RuleAction.Kind.HEAVY and not t.is_prohibition:
			assert_true(w.ledger_actions.move_to_hotbar(v.id, slot), "heavy to the hotbar")
			return slot
	fail("no heavy at hand")
	return -1


## 生け垣の門を抜け、中の原を通って階段の扉から台地へ上がり、ゴールへ。
func _gates_to_the_goal() -> void:
	assert_true(await _door_open("hedge_gate"), "the hedge gate is open")
	await _walk_to(Vector3(0.5, 0.0, -1.0))
	await _walk_to(Vector3(0.5, 0.0, -7.5))
	await _walk_to(Vector3(8.5, 0.0, -14.5))
	await _walk_to(Vector3(8.5, 1.0, -15.5))
	await _walk_to(Vector3(8.5, 2.0, -18.5))
	await _walk_into_goal()


## ひとりの道 1: もこもこの札を、投げる届き方で小島の重い石へ投げ渡す（石が軽くなり門が開く）。
## 重いは庭のおもり。
func test_sign_relay_throw_the_lambs_sign_onto_the_heavy_stone() -> void:
	await _enter(World5Stages.RELAY_ID)
	assert_false(_door("hedge_gate").is_open(), "the heavy stone keeps the hedge gate shut")
	await _take_the_lambs_sign()
	await _walk_to(Vector3(12.3, 0.0, 4.5), 0.3)
	var slot := _free_slot()
	for v in w.ledger.inventory_vessels(_me().player_id):
		if w.ledger.token(v.token_id).is_prohibition:
			assert_true(w.ledger_actions.move_to_hotbar(v.id, slot), "the sign to the hotbar")
	await _lend_by_throwing(_block("heavy_stone"), slot)
	assert_true(await _door_open("hedge_gate"), "the banned stone is light: the gate opens")
	await _walk_to(Vector3(-4.5, 0.0, 8.5), 0.6)
	w.interact(null)  # おもりを拾う（通常インベントリへ。_heavy_slot がホットバーへ移す）
	await wait_physics_frames(2)
	await _lamb_weighs_down_the_mound()
	await _gates_to_the_goal()
	assert_true(await _cleared(), "the sign went to the stone, the weight went to the lamb")


## ひとりの道 2: ダッシュで小島へ渡り、石の重いを F で回収する。それをもこもこへ。
func test_sign_relay_dash_over_and_take_the_weight() -> void:
	await _enter(World5Stages.RELAY_ID)
	var dash_slot := await _pick_to_hotbar(Vector3(8.5, 0.0, 9.5), RuleAction.Kind.DASH)
	await _dash_jump_across(Vector3(12.6, 0.0, 4.5), Vector3(18.6, 0.0, 4.5), dash_slot)
	await _walk_to(Vector3(19.5, 0.0, 5.7), 0.3)
	w.interact(_block("heavy_stone"))
	await wait_physics_frames(2)
	assert_true(await _door_open("hedge_gate"), "the stone is light without its weight")
	await _dash_jump_across(Vector3(18.3, 0.0, 4.5), Vector3(12.2, 0.0, 4.5), dash_slot)
	await _take_the_lambs_sign()
	await _lamb_weighs_down_the_mound()
	await _gates_to_the_goal()
	assert_true(await _cleared(), "carried the island's weight to the lamb")


## 協力の近道: 仲間の W で W×2 にすれば、ダッシュなしで幅 5 を走って跳べる。
func test_sign_relay_coop_double_speed_leap() -> void:
	await _enter(World5Stages.RELAY_ID)
	_gift_from_teammate(FORWARD)
	assert_true(
		await _run_and_jump(
			Vector3(9.5, 0.0, 4.5), Vector3(12.9, 0.0, 4.5), Vector3(18.8, 0.0, 4.5)
		),
		"leapt to the island with W x2"
	)
	await _walk_to(Vector3(19.5, 0.0, 5.7), 0.3)
	w.interact(_block("heavy_stone"))
	await wait_physics_frames(2)
	assert_true(
		await _run_and_jump(
			Vector3(20.5, 0.0, 4.5), Vector3(18.1, 0.0, 4.5), Vector3(11.8, 0.0, 4.5)
		),
		"leapt back"
	)
	await _take_the_lambs_sign()
	await _lamb_weighs_down_the_mound()
	await _gates_to_the_goal()
	assert_true(await _cleared(), "a teammate's W instead of the dash")


## 谷の縁の手前（edge）から向こう（land）へ走って跳び、落ち始めたら空中でダッシュする。
func _dash_jump_across(edge: Vector3, land: Vector3, dash_slot: int) -> void:
	assert_ne(dash_slot, -1, "has a dash")
	await _walk_to(edge, 0.25)
	_face(land)
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(4)
	w.press_action(JUMP)
	for i in 60:
		await tree.physics_frame
		if _me().velocity.y < 0.0:
			break
	w.press_action(RuleAction.Kind.DASH)
	await _walk_to(land, 0.6, 240)
