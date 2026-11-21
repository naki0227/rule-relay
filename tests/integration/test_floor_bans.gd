extends TestCase
## ブロックに付いた禁止は、その上に立つ人にも効く（2026-11-21 本人「ジャンプ禁止ってさ、そのブロックに働く
## 感じになってるから、その上に乗ってもジャンプ禁止は適用してほしい」→「基本的に禁止はその上も禁止にしよう」。
## docs/adr/0003 決定 7・src/game/floor_bans.gd）。床に着いて立っている間だけ効き、降りれば元どおり。

const W := RuleAction.Kind.FORWARD
const D := RuleAction.Kind.RIGHT
const JUMP := RuleAction.Kind.JUMP

var island: PrototypeIsland
## 開けた地面に置いた、禁止を付けるためのブロック（上面 y = 1）。
var pad: RuleBlock


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	pad = island.add_block(Vector3i(-4, 0, 1))
	await wait_physics_frames(10)


func after_each() -> void:
	island.queue_free()
	await tree.process_frame


func ban(action: RuleAction.Kind, block: RuleBlock = pad) -> void:
	island.ledger.place_on_entity(action, true, block.entity_id)


func place_player(at: Vector3) -> void:
	island.player.global_position = at
	island.player.velocity = Vector3.ZERO
	island.player.move_intent = Vector2.ZERO
	island.player.view_yaw = 0.0
	await wait_physics_frames(8)


func stand_on_pad() -> void:
	await place_player(pad.global_position + Vector3(0.0, 0.55, 0.0))


## ジャンプを押してから frames の間に、足もとから上がった最大の高さ。
func jump_rise(frames: int = 40) -> float:
	var start := island.player.global_position.y
	island.press_action(JUMP)
	var top := start
	for i in frames:
		await tree.physics_frame
		top = maxf(top, island.player.global_position.y)
	return top - start


func test_a_jump_ban_on_the_block_stops_the_rider_jumping() -> void:
	ban(JUMP)
	await stand_on_pad()
	assert_true(island.player.floor_bans.has(JUMP), "the ban under the feet is seen")
	assert_lt(await jump_rise(), 0.1, "no jump while standing on it")
	await place_player(Vector3(-3.5, 0.05, 3.5))  # 降りて地面へ
	assert_false(island.player.floor_bans.has(JUMP))
	assert_gt(await jump_rise(), 1.0, "jumping works again once off the block")


func test_refusals_beep_but_tell_only_once() -> void:
	ban(JUMP)
	await stand_on_pad()
	var told := [0]
	island.message_posted.connect(func(_t: String) -> void: told[0] += 1)
	var beeps := [0]
	island.player.floor_ban_refused.connect(func(_a: RuleAction.Kind) -> void: beeps[0] += 1)
	for i in 3:
		await jump_rise(6)
	assert_eq(beeps[0], 3, "every refused press gives the ban sound")
	assert_eq(told[0], 1, "but only the first one shows a message")


func test_a_range_ban_on_ground_cells_blocks_jumps_on_them() -> void:
	var center := Vector3i(-3, -1, 4)
	await place_player(Vector3(-2.5, 0.05, 6.5))
	island.ledger.give_player_item(JUMP, true, 8)
	island.select_slot(8)
	assert_eq(island.lend_to(island.terrain_target(center), true), RuleLedger.LendResult.OK)
	await place_player(Vector3(-2.5, 0.05, 4.5))  # 範囲の真ん中のセルの上
	assert_lt(await jump_rise(), 0.1, "the banned ground does not let you jump")
	await place_player(Vector3(4.5, 0.05, 4.5))  # 範囲の外（半径 5 より遠い）
	assert_gt(await jump_rise(), 1.0)


func test_boots_high_jump_is_blocked_too() -> void:
	var boots := island.ledger.place_in_world(
		RuleAction.Kind.HIGH_JUMP, false, Vector3(-6.5, 0.0, 3.5), RuleVessel.Part.FEET
	)
	island.ledger.pickup(boots.id)
	assert_eq(island.ledger.equip(boots.id), RuleLedger.EquipResult.OK)
	ban(JUMP)
	await stand_on_pad()
	assert_lt(await jump_rise(), 0.1, "boots do not get around the ban under the feet")


func test_a_high_jump_ban_takes_away_only_the_boots_bonus() -> void:
	var boots := island.ledger.place_in_world(
		RuleAction.Kind.HIGH_JUMP, false, Vector3(-6.5, 0.0, 3.5), RuleVessel.Part.FEET
	)
	island.ledger.pickup(boots.id)
	island.ledger.equip(boots.id)
	ban(RuleAction.Kind.HIGH_JUMP)
	await stand_on_pad()
	var rise: float = await jump_rise(60)
	assert_gt(rise, 1.0, "a plain jump still works")
	assert_lt(rise, Tuning.BOOTS_JUMP_HEIGHT - 0.4, "but not the boots height")


func test_riding_a_lifted_banned_block_still_blocks_the_jump() -> void:
	ban(JUMP)
	island.ledger.place_on_entity(JUMP, false, pad.entity_id, TriggerMode.Kind.REPEAT)
	await stand_on_pad()
	await wait_physics_frames(int(60 * Tuning.REPEAT_PERIOD))
	# 禁止が上位なので、このブロックは自分では跳ばない。登るで持ち上げる代わりに、下から押し上げる
	pad.receive_lift(4.0)
	await wait_physics_frames(3)
	assert_gt(pad.global_position.y, 0.55, "the block is rising with the rider on it")
	assert_true(island.player.is_on_floor(), "the rider stands on it")
	island.press_action(JUMP)
	await wait_physics_frames(2)
	assert_lt(
		island.player.velocity.y, Tuning.jump_velocity(1.0) * 0.5, "no jump off the rising block"
	)


func test_a_dash_ban_on_the_block_stops_the_rider_dashing() -> void:
	island.ledger.give_player_item(RuleAction.Kind.DASH, false, 8)
	ban(RuleAction.Kind.DASH)
	await stand_on_pad()
	island.player.move_intent = Vector2(0.0, 1.0)
	island.press_action(RuleAction.Kind.DASH)
	await wait_physics_frames(1)
	assert_false(island.player.is_dashing(), "no dash from the banned block")


func test_a_move_ban_stops_that_key_but_the_rider_can_still_leave() -> void:
	ban(W)
	await stand_on_pad()
	var start := island.player.global_position
	island.player.move_intent = Vector2(0.0, 1.0)  # W（カメラの前 = 北）
	await wait_physics_frames(20)
	assert_almost(
		island.player.global_position.z, start.z, 0.05, "W does not walk on a W-banned block"
	)
	island.player.move_intent = Vector2(1.0, 0.0)  # D はできる
	await wait_physics_frames(40)
	assert_gt(island.player.global_position.x, start.x + 0.5, "D still walks off the block")


func test_all_four_moves_banned_still_lets_you_jump_off() -> void:
	for action: RuleAction.Kind in [W, RuleAction.Kind.LEFT, RuleAction.Kind.BACK, D]:
		ban(action)
	await stand_on_pad()
	assert_gt(await jump_rise(), 0.8, "jumping is the way off (or F to take the bans back)")


func test_a_throw_ban_on_the_block_falls_back_to_touch() -> void:
	island.toggle_reach()
	assert_true(island.throw_mode)
	ban(RuleAction.Kind.THROW)
	await stand_on_pad()
	assert_false(island.can_throw(), "throwing is banned while standing here")
	assert_almost(island.reach(), Tuning.TOUCH_REACH, 0.001, "only touch reach")


func test_a_climb_ban_on_the_block_stops_climbing_from_it() -> void:
	var gloves := island.ledger.place_in_world(
		RuleAction.Kind.CLIMB, false, Vector3(-6.5, 0.0, 3.5), RuleVessel.Part.HANDS
	)
	island.ledger.pickup(gloves.id)
	island.ledger.equip(gloves.id)
	island.add_block(Vector3i(-4, 1, 0))
	island.add_block(Vector3i(-4, 2, 0))  # pad の北に高さ 2 の壁（pad の上から見て）
	ban(RuleAction.Kind.CLIMB)
	await wait_physics_frames(6)
	await stand_on_pad()
	island.player.move_intent = Vector2(0.0, 1.0)
	var top := island.player.global_position.y
	for i in 40:
		await tree.physics_frame
		top = maxf(top, island.player.global_position.y)
	assert_lt(top, pad.global_position.y + 1.0, "no climbing up from the banned block")


func test_heavy_float_and_swim_bans_do_not_touch_the_rider() -> void:
	for action: RuleAction.Kind in [
		RuleAction.Kind.HEAVY, RuleAction.Kind.FLOAT, RuleAction.Kind.SWIM
	]:
		ban(action)
	await stand_on_pad()
	assert_true(island.player.floor_bans.is_empty(), "these traits have no meaning for a rider")
	assert_gt(await jump_rise(), 1.0)


func test_a_creature_does_not_plan_a_jump_from_a_banned_block() -> void:
	var c := island.creature
	island.ledger.place_on_entity(JUMP, false, c.entity_id)
	# 生き物の東に、ジャンプ禁止の台（上面 1）と、その先に高さ 2 の段
	var step := island.add_block(Vector3i(6, 0, 0))
	island.add_block(Vector3i(7, 0, 0))
	island.add_block(Vector3i(7, 1, 0))
	await wait_physics_frames(6)
	var heights := island.survey_heights(Vector2i(6, 0), 2)
	assert_almost(float(heights[Vector2i(6, 0)]), 1.0, 0.05)
	var free_plan: Dictionary = c.call(&"_banned_steps", heights)
	assert_false(free_plan.has(CreatureMind.step_key(Vector2i(6, 0), Vector2i(7, 0))))
	ban(JUMP, step)
	var steps: Dictionary = c.call(&"_banned_steps", heights)
	assert_true(
		steps.has(CreatureMind.step_key(Vector2i(6, 0), Vector2i(7, 0))),
		"the jump up from the banned block is not planned"
	)
	assert_false(
		steps.has(CreatureMind.step_key(Vector2i(5, 0), Vector2i(6, 0))),
		"walking onto it (a low step) is still fine"
	)
	assert_true(
		c.situation().blocked.has(CreatureMind.step_key(Vector2i(6, 0), Vector2i(7, 0))),
		"the brain's situation carries the banned step"
	)


## 生き物を禁止のブロック（上面 1）に乗せ、東の高さ 2 の段へはそのブロックから跳ぶしかない置き方で、
## 段の上（x = 7）に立ったか。banned なら台にジャンプ禁止を付ける（判断は CreatureBrain の通り道）。
func creature_climbs_from_pad(banned: bool) -> bool:
	var c := island.creature
	island.ledger.place_on_entity(JUMP, false, c.entity_id)
	var step := island.add_block(Vector3i(6, 0, 0))
	island.add_block(Vector3i(7, 0, 0))
	island.add_block(Vector3i(7, 1, 0))
	if banned:
		ban(JUMP, step)
	await wait_physics_frames(6)
	c.restore_state({"position": Vector3(6.5, 1.05, 0.5), "velocity": Vector3.ZERO})
	c.notify_environment_changed()
	for i in 300:
		await tree.physics_frame
		if c.global_position.y > 1.9 and c.cell() == Vector2i(7, 0):
			return true
	return false


func test_a_creature_jumps_up_from_the_pad_when_it_is_not_banned() -> void:
	assert_true(await creature_climbs_from_pad(false), "control: the brain jumps up from the pad")


func test_a_creature_on_a_jump_banned_pad_does_not_jump_up() -> void:
	assert_false(await creature_climbs_from_pad(true), "the ban under its feet keeps it down")
