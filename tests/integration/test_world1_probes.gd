extends "res://tests/integration/island_probing.gd"
## はじまりの草原（W1）の新しいステージの関所と詰みを、プレイヤーと同じ操作で壊しにいく試遊（2026-11-21）。
## 書き方は test_island_probes.gd と同じ:
## - test_gate_*: 意図した関所が守られていること（壊れたら失敗する）
## - test_accepted_*: 本人が「残してよい」と決めた技が、この島でも起きること
## - test_finding_*: 試遊で見つけた挙動の記録（直すかどうかは本人が決める）
## どちらの島にも幅 4 以上の谷とダッシュは無い（走って跳ぶ・縁ちょうど・ダッシュで越える場所が無い）。
## 関所の中心は動物の道（1 段ずつしか跳べない・持ち上げ台に乗らない）なので、プレイヤーの移動の技では崩れない。

const BACK := RuleAction.Kind.BACK
const RIGHT := RuleAction.Kind.RIGHT
const STEPS_ID := "w1_lift_steps"
const PATH_ID := "w1_push_path"


func _inventory_to_hotbar(action: RuleAction.Kind) -> void:
	for v in w.ledger.inventory_vessels(_me().player_id):
		var t := w.ledger.token(v.token_id)
		if t.action == action and not t.is_prohibition:
			assert_true(w.ledger_actions.move_to_hotbar(v.id, _free_slot()), "to the hotbar")


func _borrow_jump_from(key: String) -> void:
	var critter := _creature(key)
	await _walk_to(critter.global_position + Vector3(1.4, 0.0, 0.0), 0.4)
	w.interact(critter)
	await wait_physics_frames(2)
	_inventory_to_hotbar(JUMP)
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "borrowed the jump")


func _push_stone(key: String, action: RuleAction.Kind, times: int) -> void:
	var stone := _block(key)
	for i in times:
		_lend(stone, _slot_of(action), TriggerMode.Kind.SINGLE_SHOT)
		w.press_action(action)
		await wait_physics_frames(40)
		for f in 120:
			if stone.is_grounded() and not stone.is_moving_horizontally():
				break
			await tree.physics_frame


func _give_move(key: String) -> void:
	var critter := _creature(key)
	await _walk_to(critter.global_position + Vector3(1.4, 0.0, 0.0), 0.4)
	_lend(critter, _slot_of(RIGHT), TriggerMode.Kind.NONE)


# --- 持ち上げ台の段々: 関所 ---------------------------------------------------------


## だれも最初はジャンプを持っていない。浜から段（2）へも、段差 1 へも跳べない。
func test_gate_steps_nobody_starts_with_a_jump() -> void:
	await _enter(STEPS_ID)
	var best := await _jump_against(Vector3(6.5, 0.0, 0.4), Vector3(6.5, 2.0, -1.5), 90)
	assert_lt(best, 0.2, "no jump at all at the start")


func test_gate_steps_terrace_and_summit_are_not_plain_jumps() -> void:
	await _enter(STEPS_ID)
	await _borrow_jump_from("critter")
	var best := await _jump_against(Vector3(6.5, 0.0, 0.4), Vector3(6.5, 2.0, -1.5))
	assert_lt(best, 1.5, "shore (0) to terrace (2)")
	await _lift_up("shore_lift", Vector3(5.5, 0.0, 1.5), Vector3(4.5, 2.0, -1.5))
	best = await _jump_against(Vector3(6.5, 2.0, -6.6), Vector3(6.5, 4.0, -8.5))
	assert_lt(best, 3.5, "terrace (2) to summit (4)")


## 動物は持ち上げ台に乗らず、1 段ずつしか跳ばない。石が無ければ、移動を渡しても浜で待つ。
func test_gate_steps_critter_waits_on_the_shore_without_the_stones() -> void:
	await _enter(STEPS_ID)
	await _give_move("critter")
	assert_lt(await _creature_top("critter", 360), 0.6, "no stone: the critter stays on the shore")
	assert_eq(_creature("critter").stage, CreatureMind.Stage.WAIT, "it waits")


## 石 1 だけ落とすと、動物は段の縁まで上がって待つ（頂へは上がれない）。そこならまだ浜から手が届くので、
## 動物のジャンプを取り戻せる（ジャンプを渡しても詰まない）。
func test_gate_steps_one_stone_stops_the_critter_at_the_terrace_within_reach() -> void:
	await _enter(STEPS_ID)
	await _walk_to(Vector3(-2.5, 0.0, 0.4), 0.25)
	await _push_stone("stone_low", BACK, 3)
	await _give_move("critter")
	var critter := _creature("critter")
	assert_lt(await _creature_top("critter", 600), 2.6, "up the low stone, but not the summit")
	assert_gt(critter.global_position.y, 1.9, "it reached the terrace")
	await _walk_to(Vector3(critter.global_position.x + 1.0, 0.0, 0.4), 0.3)
	w.interact(critter)
	await wait_physics_frames(2)
	_inventory_to_hotbar(JUMP)
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "took the jump back from below")


## 動物が巣にいなければ、全員がゴールに集まってもクリアしない。
func test_gate_steps_goal_without_the_critter_is_not_a_clear() -> void:
	await _enter(STEPS_ID)
	await _borrow_jump_from("critter")
	await _lift_up("shore_lift", Vector3(5.5, 0.0, 1.5), Vector3(4.5, 2.0, -1.5))
	await _lift_up("terrace_lift", Vector3(5.5, 2.0, -5.5), Vector3(4.5, 4.0, -8.6))
	await _walk_into_goal()
	assert_false(await _cleared(120), "everyone at the goal, but the critter is not home")


## 頂のジャンプは頂にある（浜と段からは拾えない）。下から跳んで拾うこともできない。
func test_gate_steps_second_jump_is_only_on_the_summit() -> void:
	await _enter(STEPS_ID)
	await _borrow_jump_from("critter")
	await _lift_up("shore_lift", Vector3(5.5, 0.0, 1.5), Vector3(4.5, 2.0, -1.5))
	await _jump_against(Vector3(4.5, 2.0, -6.6), Vector3(4.5, 4.0, -11.5), 120)
	w.interact(null)
	await wait_physics_frames(2)
	assert_eq(w.ledger.ability_count(JUMP, _me().player_id), 1, "still only the borrowed jump")


# --- 持ち上げ台の段々: 記録 ---------------------------------------------------------


## 石を繰り返しで押すと止まらない: 石 1 を先に落としてあると、頂から段へ落ちた石 2 は南へ滑り続け、段も越えて
## 浜へ落ち、島の外へ出て元の場所へ戻される（救済）。単発で 1 マスずつ押すのが正しい（ヒントは無い）。
## 石 1 がまだ段にあれば、石 2 はそれに当たって段の途中で止まる（壁ぎわではないので段にはならない）。
func test_finding_steps_repeat_push_slides_the_stone_off_the_island() -> void:
	await _enter(STEPS_ID)
	await _walk_to(Vector3(-2.5, 0.0, 0.4), 0.25)
	await _push_stone("stone_low", BACK, 3)
	await _borrow_jump_from("critter")
	await _lift_up("shore_lift", Vector3(5.5, 0.0, 1.5), Vector3(4.5, 2.0, -1.5))
	await _lift_up("terrace_lift", Vector3(5.5, 2.0, -5.5), Vector3(4.5, 4.0, -8.6))
	await _walk_to(Vector3(-2.5, 4.0, -10.5))
	var stone := _block("stone_high")
	_lend(stone, _slot_of(BACK), TriggerMode.Kind.REPEAT)
	var lowest := stone.global_position.y
	for i in 2700:
		lowest = minf(lowest, stone.global_position.y)
		if lowest < -2.0 and stone.cell() == Vector3i(-4, 4, -10):
			break
		await tree.physics_frame
	assert_lt(lowest, -2.0, "FINDING: the repeated push carried the stone off the island")
	assert_eq(stone.cell(), Vector3i(-4, 4, -10), "FINDING: it was put back where it started")


## ジャンプを 2 つとも動物に渡すと、動物は巣まで上がり、自分は浜から上がれなくなる（取り戻しにも行けない）。
## 自分で選んだ詰みで、メニューの「このステージを最初から」でやり直せる（ルールでは止めない）。
func test_finding_steps_giving_both_jumps_away_needs_a_restart() -> void:
	await _enter(STEPS_ID)
	await _walk_to(Vector3(-2.5, 0.0, 0.4), 0.25)
	await _push_stone("stone_low", BACK, 3)
	await _borrow_jump_from("critter")
	await _walk_route([Vector3(-3.5, 1.0, 0.5), Vector3(-3.5, 2.0, -1.5)])
	await _walk_to(Vector3(-0.5, 2.0, -6.5))
	_lend(w.terrain_target(Vector3i(-1, 1, -7)), _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	for i in 300:
		_face(Vector3(-0.5, 4.0, -8.6))
		_me().move_intent = Vector2(0.0, 1.0) if _me().global_position.y > 4.0 else Vector2.ZERO
		if _me().global_position.z < -8.2 and _me().is_on_floor():
			break
		await tree.physics_frame
	await _walk_to(Vector3(4.5, 4.0, -11.5), 0.6)
	w.interact(null)
	await wait_physics_frames(2)
	_inventory_to_hotbar(JUMP)
	await _walk_to(Vector3(-2.5, 4.0, -10.5))
	await _push_stone("stone_high", BACK, 3)
	await _walk_route([Vector3(-1.5, 2.0, -2.5), Vector3(-1.5, 0.0, 2.5)])
	var critter := _creature("critter")
	await _walk_to(critter.global_position + Vector3(1.4, 0.0, 0.0), 0.4)
	while _slot_of(JUMP) != -1 and w.ledger.player_can(JUMP, _me().player_id):
		_lend(critter, _slot_of_unlent(JUMP), TriggerMode.Kind.NONE)
	_lend(critter, _slot_of(RIGHT), TriggerMode.Kind.NONE)
	assert_true(await _wait_creature_in("critter", OpenIslandsW1.STEPS_NEST, 2400), "it went home")
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "FINDING: no jump left for me")
	assert_false(await _try_walk_to(Vector3(-3.5, 2.0, -1.5), 0.35, 240), "stuck on the shore")
	w.restart_island()
	w = director.world
	await wait_physics_frames(10)
	assert_true(
		w.ledger.entity_has_ability(_creature("critter").entity_id, JUMP), "restart resets it"
	)


func _slot_of_unlent(action: RuleAction.Kind) -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, _me().player_id)
		if v != null:
			var t := w.ledger.token(v.token_id)
			if t.action == action and t.is_in_vessel():
				return slot
	return -1


# --- 押し石の小道: 関所 -------------------------------------------------------------


func test_gate_path_ledge_is_not_a_plain_jump() -> void:
	await _enter(PATH_ID)
	var best := await _jump_against(Vector3(4.5, 0.0, 0.4), Vector3(4.5, 2.0, -1.5))
	assert_lt(best, 1.5, "meadow (0) to ledge (2)")


## 階段を削らなければ、子どもの生き物は移動をもらっても原っぱで待つ。
func test_gate_path_kit_waits_on_the_meadow_without_stairs() -> void:
	await _enter(PATH_ID)
	await _give_move("kit")
	assert_lt(await _creature_top("kit", 360), 0.6, "no stairs: the kit stays on the meadow")
	assert_eq(_creature("kit").stage, CreatureMind.Stage.WAIT, "it waits")


## 溝を埋めなければ、生き物は段の上で待つ（溝へは降りない。降りても花畑へは 2 段で上がれない）。
func test_gate_path_kit_waits_on_the_ledge_without_filling_the_ditch() -> void:
	await _enter(PATH_ID)
	await _walk_to(Vector3(1.5, 0.0, 0.5), 0.3)
	_lend(w.terrain_target(Vector3i(-1, 1, -1)), _slot_of(BACK), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(BACK)
	await wait_physics_frames(60)
	await _give_move("kit")
	assert_lt(await _creature_top("kit", 900), 2.6, "never higher than the ledge")
	var kit := _creature("kit")
	assert_gt(kit.global_position.z, -6.9, "it did not cross the ditch")
	assert_eq(kit.stage, CreatureMind.Stage.WAIT, "it waits on the ledge")


func test_gate_path_goal_without_the_kit_is_not_a_clear() -> void:
	await _enter(PATH_ID)
	await _lift_up("meadow_lift", Vector3(-3.5, 0.0, 1.5), Vector3(-4.5, 2.0, -1.5))
	await _walk_into_goal([Vector3(1.5, 2.0, -2.5)])
	assert_false(await _cleared(120), "everyone at the goal, but the kit is not home")


## 溝（幅 1）に落ちても、段の側（1 段）へ跳んで出られる（詰まない）。
func test_gate_path_the_ditch_is_escapable() -> void:
	await _enter(PATH_ID)
	await _lift_up("meadow_lift", Vector3(-3.5, 0.0, 1.5), Vector3(-4.5, 2.0, -1.5))
	await _walk_to(Vector3(-4.5, 1.0, -6.5), 0.3)
	await wait_physics_frames(20)
	assert_lt(_me().global_position.y, 1.3, "down in the ditch")
	assert_true(await _try_walk_to(Vector3(-4.5, 2.0, -5.0), 0.35, 300), "hopped out to the ledge")


## 受け入れた技 F3: 足もとの地面のセルを持ち上げ台にすれば、階段も窪みのブロックも無しで段へ上がれる。
## ゴールへは行けるが、生き物の道（階段と溝）は自分で作るしかない。
func test_accepted_path_any_ground_cell_lifts_you_to_the_ledge() -> void:
	await _enter(PATH_ID)
	await _walk_to(Vector3(4.5, 0.0, 0.5), 0.25)
	_lend(w.terrain_target(Vector3i(4, -1, 0)), _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	for i in 300:
		_face(Vector3(4.5, 2.0, -1.5))
		_me().move_intent = Vector2(0.0, 1.0) if _me().global_position.y > 2.05 else Vector2.ZERO
		if _me().global_position.z < -1.2 and _me().is_on_floor():
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_gt(_me().global_position.y, 1.9, "ACCEPTED: on the ledge without stairs")
	assert_true(w.ledger.tokens_on(_block("meadow_lift").entity_id).is_empty(), "lift unused")
