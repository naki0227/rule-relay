extends TestCase
## 「投げる」で渡すと、メダルを本当に投げ、実際に当たった物へ付与する（docs/adr/0017）。
## 狙った相手の手前に物があればそちらが受け取り、外れたらメダルは手元へ戻る。

const JUMP := RuleAction.Kind.JUMP
const S_SLOT := 2
const JUMP_SLOT := 4
const THROW_SLOT := 5

var island: PrototypeIsland


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	await wait_physics_frames(10)


func after_each() -> void:
	island.queue_free()
	await tree.process_frame


func place_player(at: Vector3) -> void:
	island.player.global_position = at
	island.player.velocity = Vector3.ZERO
	island.player.move_intent = Vector2.ZERO
	await wait_physics_frames(6)


## 狙った相手から west m 西に立って、投げるの届き方にする。
func stand_west_of(target: Node3D, west: float) -> void:
	var at := target.global_position
	await place_player(Vector3(at.x - west, 0.0, at.z))
	if not island.throw_mode:
		island.toggle_reach()
	assert_true(island.throw_mode, "throw reach is on")


func jump_token() -> RuleToken:
	return island.ledger.token(island.ledger.hotbar_vessel(JUMP_SLOT).token_id)


func test_a_throw_flies_and_lands_on_the_block() -> void:
	var block := island.mover
	await stand_west_of(block, 8.0)
	island.select_slot(JUMP_SLOT)
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.OK, "the medal is thrown")
	assert_true(island.player.is_throwing(), "the arm throws")
	assert_eq(island.player.animation_state(), RigAnimator.THROW, "the Blender throw clip plays")
	assert_true(island.ledger.tokens_on(block.entity_id).is_empty(), "nothing lands at once")
	assert_true(jump_token().is_in_vessel(), "the jump stays in hand while the medal flies")
	await wait_physics_frames(int(60 * MedalThrow.RELEASE_DELAY) + 6)
	var medals := MedalThrow.flying(island)
	assert_eq(medals.size(), 1, "one medal in the air")
	if medals.size() == 1:
		var medal: ThrownMedal = medals[0]
		assert_true(medal.is_released(), "released from the hand")
		assert_gt(medal.global_position.y, 1.0, "it leaves from the hand, above the chest")
	assert_true(await wait_throws(island), "the medal lands")
	assert_eq(island.ledger.tokens_on(block.entity_id).size(), 1, "the block got the jump")
	assert_false(island.ledger.player_can(JUMP), "the jump left the hand when it hit")


## 高台（岩、高さ 3）の北のすぐ裏に置いたブロック。南から投げると、どの弧でも高台に遮られる。
func block_behind_the_plateau() -> RuleBlock:
	var hidden := island.add_block(Vector3i(6, 0, -12))
	await wait_physics_frames(4)
	await place_player(Vector3(6.5, 0.0, -3.5))
	island.toggle_reach()
	assert_true(island.throw_mode, "throw reach is on")
	return hidden


## 投げたジャンプが付いている、地形から動くブロックにしたセルのブロック（無ければ null）。
func promoted_holder() -> RuleBlock:
	for cell: Vector3i in island.promoted:
		var block := island.blocks[island.promoted[cell]]
		if not island.ledger.tokens_on(block.entity_id).is_empty():
			return block
	return null


func test_an_obstacle_in_the_way_takes_the_token() -> void:
	var hidden := await block_behind_the_plateau()
	island.select_slot(JUMP_SLOT)
	assert_eq(island.lend_to(hidden, false), RuleLedger.LendResult.OK)
	assert_true(await wait_throws(island), "the medal lands")
	assert_true(island.ledger.tokens_on(hidden.entity_id).is_empty(), "the aimed block got nothing")
	var holder := promoted_holder()
	assert_ne(holder, null, "the plateau in between caught the medal")
	if holder != null:
		assert_gt(holder.global_position.y, 0.9, "a rock cell of the plateau, not the ground")


func test_a_low_ledge_is_cleared_with_a_higher_arc() -> void:
	var block := island.mover
	var ledge := island.add_block(Vector3i(4, 0, -2))
	await wait_physics_frames(4)
	await stand_west_of(block, 8.0)
	island.select_slot(JUMP_SLOT)
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.OK)
	assert_true(await wait_throws(island), "the medal lands")
	assert_eq(island.ledger.tokens_on(block.entity_id).size(), 1, "lobbed over the low block")
	assert_true(island.ledger.tokens_on(ledge.entity_id).is_empty())


func test_an_obstacle_that_moves_in_after_the_release_takes_the_token() -> void:
	var block := island.mover
	await stand_west_of(block, 8.0)
	island.select_slot(JUMP_SLOT)
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.OK)
	await wait_physics_frames(int(60 * MedalThrow.RELEASE_DELAY) + 2)
	# 手を離した後に、通り道に 2 段の壁が現れる（弧は手を離したときに決まっている）
	var wall: Array[RuleBlock] = [
		island.add_block(Vector3i(4, 0, -2)), island.add_block(Vector3i(4, 1, -2))
	]
	assert_true(await wait_throws(island), "the medal lands")
	assert_true(island.ledger.tokens_on(block.entity_id).is_empty(), "the aimed block got nothing")
	var caught := wall.filter(
		func(b: RuleBlock) -> bool: return not island.ledger.tokens_on(b.entity_id).is_empty()
	)
	assert_eq(caught.size(), 1, "the new wall caught the medal")


func test_a_range_throw_centers_on_what_it_hit() -> void:
	var hidden := await block_behind_the_plateau()
	island.select_slot(JUMP_SLOT)
	island.set_lend_mode(TriggerMode.Kind.REPEAT)
	assert_eq(island.lend_to(hidden, true), RuleLedger.LendResult.OK)
	assert_true(await wait_throws(island), "the medal lands")
	var t := jump_token()
	assert_true(t.is_range, "lent as a range")
	assert_false(t.holder_ids.has(hidden.entity_id), "the aimed block is not in the range")
	var hit := promoted_holder()
	assert_ne(hit, null, "the plateau caught the range throw")
	var centered := false
	for cell: Vector3i in island.promoted:
		var b := island.blocks[island.promoted[cell]]
		centered = centered or t.range_center.distance_to(b.global_position) < 0.01
	assert_true(centered, "centered on the hit cell of the plateau")
	assert_gt(t.range_layer, -1, "on the plateau's layer, not the ground")
	assert_eq(t.mode, TriggerMode.Kind.REPEAT, "the chosen mode is kept")


func test_a_miss_returns_the_medal_to_the_thrower() -> void:
	var block := island.add_block(Vector3i(13, 0, 2))
	await wait_physics_frames(4)
	await stand_west_of(block, 8.0)
	var messages: Array[String] = []
	island.message_posted.connect(func(text: String) -> void: messages.append(text))
	island.select_slot(JUMP_SLOT)
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.OK)
	# 手を離す前に、狙ったブロックを高く持ち上げる。メダルは空いた所を抜けて島の外へ落ちる
	block.teleport(block.global_position + Vector3(0.0, 40.0, 0.0), 0.0)
	assert_true(await wait_throws(island), "the medal comes back")
	assert_true(jump_token().is_in_vessel(), "the jump is still in hand")
	assert_true(island.ledger.player_can(JUMP), "and usable")
	assert_true(island.ledger.tokens_on(block.entity_id).is_empty(), "nothing was lent")
	assert_true(
		messages.any(func(text: String) -> bool: return text.contains("手元へ戻りました")),
		"a short notice says it came back"
	)


func test_repeat_mode_is_kept_on_the_hit_block() -> void:
	var block := island.mover
	await stand_west_of(block, 8.0)
	island.select_slot(S_SLOT)
	island.set_lend_mode(TriggerMode.Kind.REPEAT)
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.OK)
	assert_true(await wait_throws(island), "the medal lands")
	var tokens := island.ledger.tokens_on(block.entity_id)
	assert_eq(tokens.size(), 1)
	if tokens.size() == 1:
		assert_eq(tokens[0].mode, TriggerMode.Kind.REPEAT, "repeat survives the flight")


func test_the_same_medal_cannot_be_thrown_twice_in_flight() -> void:
	var block := island.mover
	await stand_west_of(block, 8.0)
	island.select_slot(JUMP_SLOT)
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.OK)
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.ALREADY_LENT, "still flying")
	assert_true(await wait_throws(island))
	assert_eq(island.ledger.tokens_on(block.entity_id).size(), 1, "lent once")


func test_a_bell_in_the_way_sends_the_medal_back() -> void:
	var bell := island.bell
	await stand_west_of(bell, 3.5)
	island.select_slot(JUMP_SLOT)
	# 鐘を狙うと渡す前に断る（今までどおり）
	assert_ne(island.lend_to(bell, false), RuleLedger.LendResult.OK, "a bell is not a target")
	assert_true(MedalThrow.flying(island).is_empty(), "nothing was thrown")
	# 別の物へ投げたメダルが鐘に当たったら、付与せずに戻る（鳴らさない）
	assert_eq(island.lend_to(island.mover, false), RuleLedger.LendResult.OK)
	var medal: ThrownMedal = MedalThrow.flying(island)[0]
	var at := bell.global_position + Vector3(0.0, 1.0, 0.0)
	MedalThrow.land(island, medal, {"collider": bell, "position": at, "normal": Vector3.LEFT})
	assert_eq(medal.phase, ThrownMedal.Phase.RETURNING, "the medal heads back")
	assert_true(await wait_throws(island))
	assert_true(jump_token().is_in_vessel(), "the jump is still in hand")
	assert_false(bell.is_ringing(), "a medal does not ring the bell")


func test_restoring_a_checkpoint_mid_flight_returns_the_token() -> void:
	var block := island.mover
	await stand_west_of(block, 8.0)
	island.select_slot(JUMP_SLOT)
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.OK)
	await wait_physics_frames(int(60 * MedalThrow.RELEASE_DELAY) + 8)
	assert_eq(MedalThrow.flying(island).size(), 1, "in flight")
	island.restore_checkpoint()
	await wait_physics_frames(2)
	assert_true(MedalThrow.flying(island).is_empty(), "the medal is not saved")
	assert_true(jump_token().is_in_vessel(), "the jump is back in hand")
	await wait_physics_frames(60)
	assert_true(island.ledger.tokens_on(block.entity_id).is_empty(), "nothing lands afterwards")
	island.select_slot(JUMP_SLOT)
	assert_true(island.throw_mode, "still throwing")
	await stand_west_of(block, 8.0)
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.OK, "can throw again")
	assert_true(await wait_throws(island))
	assert_eq(island.ledger.tokens_on(block.entity_id).size(), 1)


func test_throwing_the_throw_lands_and_then_falls_back_to_touch() -> void:
	var block := island.mover
	await stand_west_of(block, 8.0)
	island.select_slot(THROW_SLOT)
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.OK)
	assert_true(island.throw_mode, "still throwing while the medal flies")
	assert_true(await wait_throws(island))
	assert_false(island.throw_mode, "back to touch once the throw has landed")
