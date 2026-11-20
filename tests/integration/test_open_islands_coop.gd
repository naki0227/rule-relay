extends "res://tests/integration/island_playthrough.gd"
## 開けた島の協力の近道・生き物の道・追加したひとりの道を、プレイヤーと同じ操作で通す（瞬間移動はしない）。
## 協力の近道は、仲間がくれた能力（W・ジャンプをもう1つ）を台帳の普通の配り方で持たせて再現する。
## 関門（ふつうのジャンプでは 2 段に上がれない・鐘は下から鳴らせない）が残っていることも確かめる。

## 採石場の南の縁から、縁づたいに北のゴールへ歩く道。
const RIM_TO_GOAL: Array[Vector3] = [
	Vector3(9.5, 5.0, 9.5), Vector3(9.5, 5.0, -9.5), Vector3(1.5, 5.0, -9.5)
]

# --- 丘の上の旗 ----------------------------------------------------------------


func _climb_lookout() -> void:
	await _walk_to(Vector3(8.5, 1.0, 1.5))
	await _walk_to(Vector3(8.5, 2.0, -0.5))
	await _walk_to(Vector3(8.5, 3.0, -4.5))


func test_hill_top_leap_from_the_lookout_needs_double_speed() -> void:
	await _enter(StageCatalog.HILL_ID)
	await _walk_to(Vector3(8.5, 0.0, 3.5))
	await _climb_lookout()
	var edge := Vector3(7.2, 3.0, -4.5)
	var summit := Vector3(1.5, 4.0, -4.5)
	# ひとりの走り跳びでは届かず、下の段丘に落ちる（何度でも試せる）
	assert_false(await _run_and_jump(Vector3(8.6, 3.0, -4.5), edge, summit, 90), "too far alone")
	assert_lt(_me().global_position.y, 3.5, "landed below the summit")
	assert_eq(director.last_clear_text, "", "not cleared by the failed leap")
	await _walk_to(Vector3(6.5, 1.0, 1.5))
	await _climb_lookout()
	_gift_from_teammate(FORWARD)
	assert_true(await _run_and_jump(Vector3(8.6, 3.0, -4.5), edge, summit), "leapt with W x2")
	await _walk_into_goal()
	assert_true(await _cleared(), "reached the summit from the lookout")


# --- 採石場 --------------------------------------------------------------------


func test_quarry_double_jump_skips_the_stone_and_the_lifts() -> void:
	await _enter(StageCatalog.QUARRY_ID)
	await _walk_to(Vector3(0.5, 0.0, 4.5))
	assert_false(await _try_walk_to(Vector3(0.5, 2.0, 6.5), 0.35, 180), "2 high is a wall alone")
	_gift_from_teammate(JUMP)
	await _walk_to(Vector3(0.5, 2.0, 6.5))
	await _walk_to(Vector3(0.5, 3.0, 8.5))
	await _walk_to(Vector3(0.5, 5.0, 9.6))
	await _walk_into_goal(RIM_TO_GOAL)
	assert_true(await _cleared(), "jumped out of the quarry with jump x2")


func test_quarry_banned_lift_after_moving_the_ban_away() -> void:
	await _enter(StageCatalog.QUARRY_ID)
	var stone := _block("stone_a")
	await _walk_to(stone.global_position + Vector3(1.6, -0.5, 0.0))
	_lend(stone, _slot_of(LEFT), TriggerMode.Kind.REPEAT)
	for i in 600:
		if stone.cell().x <= -5 and not stone.is_moving_horizontally():
			break
		await tree.physics_frame
	await _walk_to(Vector3(-4.5, 1.0, 1.5))
	await _walk_to(Vector3(-6.5, 2.0, 1.5))
	await _walk_to(Vector3(-6.5, 2.0, 6.5))
	await _walk_to(Vector3(0.5, 2.0, 6.5))
	await _walk_to(Vector3(0.5, 3.0, 8.5))
	# ズリ山から縁（2 段上）へは、ふつうのジャンプでは上がれない
	assert_false(await _try_walk_to(Vector3(0.5, 5.0, 9.6), 0.35, 180), "2 high is a wall alone")
	await _walk_to(Vector3(0.5, 3.0, 8.5))
	var lift := _block("banned_lift")
	var rest_y := lift.global_position.y
	# 禁止が付いたままでは、ジャンプを貸して起動しても跳ばない（単発は戻ってくる）
	_lend(lift, _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	await wait_physics_frames(40)
	assert_almost(lift.global_position.y, rest_y, 0.05, "the ban keeps the lift down")
	assert_ne(_slot_of(JUMP), -1, "the single shot came back")
	# F で全部回収すると、禁止が手元に来て自分も跳べなくなる
	w.interact(lift)
	await wait_physics_frames(2)
	assert_eq(w.ledger.tokens_on(lift.entity_id).size(), 0, "took the ban off the lift")
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "now the ban is on me")
	# 禁止をホットバーへ移し、投げて底の石に渡す
	var ban_slot := _free_slot()
	for v in w.ledger.inventory_vessels(_me().player_id):
		if w.ledger.token(v.token_id).is_prohibition:
			assert_true(w.ledger_actions.move_to_hotbar(v.id, ban_slot), "ban to the hotbar")
	_lend_by_throwing(_block("stone_b"), ban_slot)
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "can jump again")
	await _lift_up("banned_lift", Vector3(0.5, 3.0, 8.5), Vector3(1.5, 5.0, 9.6))
	await _walk_into_goal(RIM_TO_GOAL)
	assert_true(await _cleared(), "rode the freed lift out of the quarry")


func _free_slot() -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		if w.ledger.hotbar_vessel(slot, _me().player_id) == null:
			return slot
	return -1


# --- 三つの鐘の島 --------------------------------------------------------------


func test_three_bells_creature_throws_its_nut_at_the_north_bell() -> void:
	await _enter(StageCatalog.THREE_BELLS_ID)
	var critter := _creature("cliff_creature")
	await _walk_to(Vector3(-0.5, 0.0, -13.5))
	assert_eq(critter.stage, CreatureMind.Stage.WAIT, "it sits on the cliff")
	assert_ne(critter.held_item, "", "holding a nut")
	# 鐘は下からは鳴らせない
	w.interact(w.bells_by_key["north_bell"])
	await wait_physics_frames(2)
	assert_false(w.activated.has("north_bell"), "the bell is out of reach from below")
	_lend_by_throwing(critter, _slot_of(THROW))
	assert_true(await _wait_until_rung("north_bell"), "the creature's nut rang the bell")
	assert_eq(critter.held_item, "", "the nut is gone")


func test_three_bells_double_jump_up_the_fallen_rock() -> void:
	await _enter(StageCatalog.THREE_BELLS_ID)
	await _walk_to(Vector3(-2.5, 0.0, -12.5))
	assert_false(await _try_walk_to(Vector3(-2.5, 2.0, -13.5), 0.35, 180), "2 high alone")
	_gift_from_teammate(JUMP)
	await _walk_to(Vector3(-2.5, 2.0, -13.5))
	await _walk_to(Vector3(-2.5, 3.0, -15.5))
	await _walk_to(Vector3(-2.5, 5.0, -18.5))
	await _ring("north_bell")


# --- 浮島めぐり ----------------------------------------------------------------


func test_floating_isles_creature_rings_the_west_bell_across_the_gap() -> void:
	await _enter(StageCatalog.FLOATING_ID)
	var critter := _creature("isle_creature")
	await _walk_to(Vector3(-5.5, 0.0, 4.5))
	_lend_by_throwing(critter, _slot_of(THROW))
	assert_true(await _wait_until_rung("west_bell"), "the creature's nut rang the bell")
	assert_lt(_me().global_position.x, -4.0, "never crossed the gap")
	assert_gt(_me().global_position.x, -6.5, "still on the middle island")


func test_floating_isles_double_jump_onto_the_north_isle() -> void:
	await _enter(StageCatalog.FLOATING_ID)
	_gift_from_teammate(JUMP)
	var land := Vector3(3.5, 2.0, -11.0)
	assert_true(
		await _run_and_jump(Vector3(3.5, 0.0, -3.5), Vector3(3.5, 0.0, -5.8), land), "hopped"
	)
	await _ring("north_bell")


func test_floating_isles_double_speed_across_the_east_gap() -> void:
	await _enter(StageCatalog.FLOATING_ID)
	_gift_from_teammate(FORWARD)
	var land := Vector3(13.5, 0.0, 2.5)
	assert_true(
		await _run_and_jump(Vector3(3.5, 0.0, 2.5), Vector3(6.8, 0.0, 2.5), land), "crossed gap 5"
	)
	await _ring("east_bell")
