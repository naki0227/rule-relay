extends TestCase
## 範囲で渡した W/A/S/D はまとめて動く（2026-11-21 本人「範囲のブロックで右に動かすとかでも、一気に一緒に
## 動いてほしい。2×2 だと先に右のやつだけ動いて、次のティックで1マス開けた状態で一緒に動く」。
## docs/adr/0003 決定 6・src/game/block_move_buffer.gd）。
## 同じ付与で同時に起動し、面で接しているブロックは1つの組になり、全員が動けるときだけ同じフレームに動く。

const D := RuleAction.Kind.RIGHT
const JUMP := RuleAction.Kind.JUMP
const D_SLOT := 3
const JUMP_SLOT := 4
const SINGLE := TriggerMode.Kind.SINGLE_SHOT

var island: PrototypeIsland
## 2×2: 西の列 x = -4、東の列 x = -3（z = 0, 1）。東（D）の x = -2 は空いている。
var square: Array[RuleBlock] = []


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	square.clear()
	for cell: Vector3i in [
		Vector3i(-4, 0, 0), Vector3i(-3, 0, 0), Vector3i(-4, 0, 1), Vector3i(-3, 0, 1)
	]:
		square.append(island.add_block(cell))
	await wait_physics_frames(10)


func after_each() -> void:
	island.queue_free()
	await tree.process_frame


## ホットバーの枠の能力を、1つのトークンで square 全員へ貸す（範囲付与と同じ「1つの付与」）。
func lend_square(slot: int, mode: TriggerMode.Kind) -> void:
	var ids := PackedInt32Array()
	for b in square:
		ids.append(b.entity_id)
	var v := island.ledger.hotbar_vessel(slot)
	var spec := {"center": square[0].global_position, "radius": 5.0, "layer": 0}
	assert_eq(island.ledger.lend(v.id, ids, mode, spec), RuleLedger.LendResult.OK)


func cells() -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for b in square:
		result.append(b.cell())
	return result


## 4つのブロックの x のずれ（最初の位置から）がそろっているか。
func offsets_match(start: Array[float]) -> bool:
	var first := square[0].global_position.x - start[0]
	for i in square.size():
		if absf(square[i].global_position.x - start[i] - first) > 0.001:
			return false
	return true


func start_xs() -> Array[float]:
	var xs: Array[float] = []
	for b in square:
		xs.append(b.global_position.x)
	return xs


func test_a_2x2_range_moves_right_as_one_in_the_same_tick() -> void:
	lend_square(D_SLOT, SINGLE)
	var start := start_xs()
	island.press_action(D)
	for b in square:
		assert_true(b.is_moving_horizontally(), "%s started in the same tick" % b.name)
	var mid_checked := false
	for i in int(60 * Tuning.BLOCK_STEP_DURATION) + 6:
		await tree.physics_frame
		assert_true(offsets_match(start), "no gap opens mid-move (frame %d)" % i)
		mid_checked = true
	assert_true(mid_checked)
	assert_eq(
		cells(),
		[Vector3i(-3, 0, 0), Vector3i(-2, 0, 0), Vector3i(-3, 0, 1), Vector3i(-2, 0, 1)],
		"the whole square shifted one cell east with no gap"
	)
	assert_true(island.ledger.player_can(D), "the single shot came back")


func test_a_blocked_leader_blocks_the_whole_group() -> void:
	island.add_block(Vector3i(-2, 0, 1))  # 東の列の南だけ塞ぐ
	await wait_physics_frames(10)
	lend_square(D_SLOT, SINGLE)
	island.press_action(D)
	await wait_physics_frames(60)
	assert_eq(
		cells(),
		[Vector3i(-4, 0, 0), Vector3i(-3, 0, 0), Vector3i(-4, 0, 1), Vector3i(-3, 0, 1)],
		"nobody moves: the square does not tear apart"
	)
	assert_true(island.ledger.player_can(D), "the single shot returned anyway")


func test_a_banned_member_stays_and_counts_as_a_wall() -> void:
	island.ledger.place_on_entity(D, true, square[1].entity_id)  # 東の列の北に D 禁止
	lend_square(D_SLOT, SINGLE)
	island.press_action(D)
	await wait_physics_frames(60)
	assert_eq(square[1].cell(), Vector3i(-3, 0, 0), "the banned block stays")
	assert_eq(square[0].cell(), Vector3i(-4, 0, 0), "the block behind it is blocked by it")
	assert_eq(square[2].cell(), Vector3i(-4, 0, 1), "the group is solid: the south row waits too")
	assert_eq(square[3].cell(), Vector3i(-3, 0, 1))


func test_repeat_cycles_move_the_square_together() -> void:
	lend_square(D_SLOT, TriggerMode.Kind.REPEAT)
	for b in square:
		island._repeat_timers[b.entity_id] = Tuning.REPEAT_PERIOD - 0.05
	var start := start_xs()
	for i in int(60 * (Tuning.REPEAT_PERIOD * 2.0 + 0.2)):
		await tree.physics_frame
		assert_true(offsets_match(start), "repeat: no gap (frame %d)" % i)
	assert_true(square[0].cell().x >= -2, "at least two cycles moved the square")


func test_signal_cycles_move_the_square_together() -> void:
	lend_square(D_SLOT, TriggerMode.Kind.SIGNAL)
	# 鐘の音波は距離 6 まで。2×2 のすぐ南へ鐘を寄せて鳴らす
	island.bell.global_position = Vector3(-3.0, 0.0, 3.5)
	island.bell.ring()
	var start := start_xs()
	for i in int(60 * (Tuning.REPEAT_PERIOD + 0.6)):
		await tree.physics_frame
		assert_true(offsets_match(start), "signal: no gap (frame %d)" % i)
	assert_almost(square[0].global_position.x - start[0], 1.0, 0.01, "one cycle, one cell")
	assert_almost(square[3].global_position.x - start[3], 1.0, 0.01)


func test_a_buffered_group_in_the_air_steps_together_onto_a_ledge() -> void:
	# 東の列の前だけ高さ 1 の段。跳んでから D: 段の上を越えたら全員一緒に動く
	island.add_block(Vector3i(-2, 0, 0))
	island.add_block(Vector3i(-2, 0, 1))
	await wait_physics_frames(10)
	lend_square(JUMP_SLOT, SINGLE)
	lend_square(D_SLOT, SINGLE)
	island.press_action(JUMP)
	await wait_physics_frames(2)
	island.press_action(D)
	for b in square:
		assert_true(
			island.move_buffer.is_group_pending(b.entity_id), "%s waits with the group" % b.name
		)
	var start := start_xs()
	var started := false
	for i in 120:
		await tree.physics_frame
		var moving := 0
		for b in square:
			if b.is_moving_horizontally():
				moving += 1
		assert_true(moving == 0 or moving == 4, "all four start together (frame %d)" % i)
		started = started or moving == 4
		if moving == 4:
			assert_true(offsets_match(start), "in step (frame %d)" % i)
	assert_true(started, "the group stepped in the air")
	assert_eq(square[1].cell(), Vector3i(-2, 1, 0), "the east column is on the ledge")
	assert_eq(square[0].cell(), Vector3i(-3, 0, 0), "the west column took its place")
	assert_true(island.ledger.player_can(D))


func test_separate_lumps_of_one_lend_move_on_their_own() -> void:
	# 同じ付与でも、離れているブロック（ここでは南東の1つ）は別の組。塞がれた 2×2 につられない
	var far := island.add_block(Vector3i(-3, 0, 4))
	island.add_block(Vector3i(-2, 0, 0))
	await wait_physics_frames(10)
	square.append(far)
	lend_square(D_SLOT, SINGLE)
	island.press_action(D)
	await wait_physics_frames(60)
	assert_eq(far.cell(), Vector3i(-2, 0, 4), "the lone block moved")
	assert_eq(square[0].cell(), Vector3i(-4, 0, 0), "the blocked square did not")


func test_one_block_still_behaves_as_before() -> void:
	var v := island.ledger.hotbar_vessel(D_SLOT)
	island.ledger.lend(v.id, PackedInt32Array([square[1].entity_id]), SINGLE, {})
	island.press_action(D)
	await wait_physics_frames(60)
	assert_eq(square[1].cell(), Vector3i(-2, 0, 0))
	assert_eq(square[0].cell(), Vector3i(-4, 0, 0), "the others were not lent anything")
