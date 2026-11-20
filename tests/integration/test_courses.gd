extends TestCase
## 部屋を組み合わせたステージを、ひとりで最初から最後まで自動で遊ぶ（通しプレイ）。
## 歩く（向きを変えて前へ進む・段差では跳ぶ）、能力を渡す、乗る、拾う、装備する、鐘を鳴らす、
## をプレイヤーと同じ操作で順に流し、クリアまで行けることを確かめる（瞬間移動はしない）。
## 部屋の配置は StageModules と同じ式で求める。

const JUMP := RuleAction.Kind.JUMP
const JUMP_SLOT := 4
const BAN_SLOT := 7
const SPARE_SLOT := 8
const PROFILE := "zz_test_courses"

var director: PartyDirector
var w: StageWorld


func before_each() -> void:
	ProgressStore.new().delete(PROFILE)
	director = PartyDirector.new()
	director.profile = PROFILE
	tree.root.add_child(director)


func after_each() -> void:
	director.queue_free()
	await tree.process_frame
	ProgressStore.new().delete(PROFILE)


func _enter(stage_id: String) -> void:
	director.enter_stage(stage_id)
	w = director.world
	await wait_physics_frames(10)


func _me() -> PlayerAvatar:
	return w.player


# --- 操作の部品 ---------------------------------------------------------------


## target へ歩く（水平の距離が tolerance 以内で、高さも近ければ着いた）。段差で止まったら跳ぶ。
func _walk_to(target: Vector3, tolerance: float = 0.35, frames: int = 900) -> bool:
	var stuck := 0
	for i in frames:
		var flat := Vector3(
			target.x - _me().global_position.x, 0.0, target.z - _me().global_position.z
		)
		if flat.length() <= tolerance and absf(_me().global_position.y - target.y) < 0.7:
			_me().move_intent = Vector2.ZERO
			return true
		_me().view_yaw = atan2(-flat.x, -flat.z)
		_me().move_intent = Vector2(0.0, 1.0)
		var moving := Vector2(_me().velocity.x, _me().velocity.z).length() > 0.5
		stuck = 0 if moving else stuck + 1
		if stuck > 8 and _me().is_on_floor():
			w.press_action(JUMP)
			stuck = 0
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	fail("could not walk to %s (at %s)" % [target, _me().global_position])
	return false


func _block(key: String) -> RuleBlock:
	return w.blocks[int(w.entity_ids[key])]


## ブロックの上面の真ん中（ブロックが床の高さの窪みにいるとき）。
func _top_of(block: RuleBlock) -> Vector3:
	return block.global_position + Vector3(0.0, RuleBlock.SIZE * 0.5, 0.0)


func _lend(target: Node3D, slot: int, mode: TriggerMode.Kind) -> void:
	w.select_slot(slot)
	w.set_lend_mode(mode)
	assert_eq(w.lend_to(target, false), RuleLedger.LendResult.OK, "lend to %s" % target.name)


## ブロックの上に立ち、ブロックが跳んだら北の壁の上（onto）へ移る。
## single なら自分でジャンプのキーを押して単発を起こす。
func _ride(block: RuleBlock, onto: Vector3, single: bool) -> void:
	await _walk_to(_top_of(block), 0.25)
	if single:
		w.press_action(JUMP)
	for i in 600:
		var flat := Vector3(onto.x - _me().global_position.x, 0.0, onto.z - _me().global_position.z)
		if flat.length() < 0.4 and _me().global_position.y > onto.y - 0.2:
			break
		_me().view_yaw = atan2(-flat.x, -flat.z)
		_me().move_intent = (
			Vector2(0.0, 1.0) if _me().global_position.y > onto.y - 0.1 or i < 2 else Vector2.ZERO
		)
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_gt(_me().global_position.y, onto.y - 0.3, "rode up onto %s" % onto)


## 落ちている装備を拾って装備する。
func _pick_and_wear(at: Vector3, part: RuleVessel.Part) -> void:
	await _walk_to(at, 0.6)
	w.interact(null)
	await wait_physics_frames(2)
	var me := _me().player_id
	for v in w.ledger.inventory_vessels(me):
		if v.part == part:
			assert_true(w.ledger_actions.equip(v.id), "wear %s" % v.item_name)
	assert_ne(w.ledger.equipped_vessel(part, me), null, "equipped")


## 手元（通常インベントリ）の器を、行動・禁止で探してホットバーへ移す。
func _to_hotbar(action: RuleAction.Kind, is_prohibition: bool, slot: int) -> void:
	for v in w.ledger.inventory_vessels(_me().player_id):
		var t := w.ledger.token(v.token_id)
		if t.action == action and t.is_prohibition == is_prohibition:
			assert_true(w.ledger_actions.move_to_hotbar(v.id, slot))
			return
	fail("no %s in the inventory" % RuleAction.label(action))


# --- 部屋ごとの解き方（ローカル座標。xf でステージの座標へ） -------------------


func _solve(room: StageModules.Room, z0: int, tag: String, xf: Callable) -> void:
	match room:
		StageModules.Room.JUMP_LEND, StageModules.Room.ARM_BELL, StageModules.Room.GOAL_PODIUM:
			await _solve_lift(room, z0, tag, xf)
		StageModules.Room.LET_GO_OF_BAN:
			await _solve_ban(z0, tag, xf)
		StageModules.Room.BELL_LIFT:
			await _solve_bell_lift(z0, tag, xf)
		StageModules.Room.BOOTS:
			await _pick_and_wear(xf.call(Vector3(-1.5, 0.0, z0 - 1.5)), RuleVessel.Part.FEET)
			await _walk_to(xf.call(Vector3(0.5, 2.0, z0 - 5.5)))
			await _walk_to(xf.call(Vector3(0.5, 0.0, z0 - 7.5)))
		StageModules.Room.GLOVES:
			await _pick_and_wear(xf.call(Vector3(-1.5, 0.0, z0 - 1.5)), RuleVessel.Part.HANDS)
			await _walk_to(xf.call(Vector3(0.5, 3.0, z0 - 5.5)))
			await _walk_to(xf.call(Vector3(0.5, 0.0, z0 - 7.5)))


## 窪みのブロックにジャンプを単発で渡し、乗って跳んでもらい、壁の上へ。
func _solve_lift(room: StageModules.Room, z0: int, tag: String, xf: Callable) -> void:
	var lift := _block(tag + "_lift")
	await _walk_to(xf.call(Vector3(0.5, 0.0, z0 - 2.5)))
	_lend(lift, JUMP_SLOT, TriggerMode.Kind.SINGLE_SHOT)
	await _ride(lift, xf.call(Vector3(0.5, 2.0, z0 - 5.5)), true)
	if room == StageModules.Room.JUMP_LEND:
		await _walk_to(xf.call(Vector3(0.5, 0.0, z0 - 7.5)))
	elif room == StageModules.Room.ARM_BELL:
		await _walk_to(xf.call(Vector3(0.5, 2.0, z0 - 7.0)), 0.5)
		var bell: Bell = null
		for b in w.bells:
			if b.global_position.distance_to(_me().global_position) < 3.0:
				bell = b
		assert_ne(bell, null, "a bell is near")
		w.interact(bell)
		await wait_physics_frames(2)
		# 広場へ戻る台座
		await _walk_to(xf.call(Vector3(-2.0, 2.0, z0 - 7.5)), 0.5)
		w.interact(null)
		await wait_physics_frames(5)


## ブロックの禁止を回収すると自分が跳べなくなる → 禁止を囮のブロックへ渡して手放す。
## 回収したジャンプをブロックへ繰り返しで渡して乗り、壁の上の小段は自分で跳ぶ。
func _solve_ban(z0: int, tag: String, xf: Callable) -> void:
	var lift := _block(tag + "_lift")
	await _walk_to(xf.call(Vector3(0.5, 0.0, z0 - 2.5)))
	w.interact(lift)
	await wait_physics_frames(2)
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "the ban in hand stops my jump")
	_to_hotbar(JUMP, true, BAN_SLOT)
	_to_hotbar(JUMP, false, SPARE_SLOT)
	_lend(_block(tag + "_decoy"), BAN_SLOT, TriggerMode.Kind.NONE)
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "let go of the ban")
	await _walk_to(xf.call(Vector3(0.5, 0.0, z0 - 2.5)))
	_lend(lift, SPARE_SLOT, TriggerMode.Kind.REPEAT)
	await _ride(lift, xf.call(Vector3(0.5, 2.0, z0 - 5.5)), false)
	await _walk_to(xf.call(Vector3(0.5, 2.0, z0 - 7.5)))
	await _walk_to(xf.call(Vector3(0.5, 3.0, z0 - 9.5)))
	await _walk_to(xf.call(Vector3(0.5, 0.0, z0 - 11.5)))


## 鐘を鳴らして、鳴っている間に信号のブロック（ジャンプ×2）に乗る。
func _solve_bell_lift(z0: int, tag: String, xf: Callable) -> void:
	var bell_at: Vector3 = xf.call(Vector3(2.5, 0.0, z0 - 1.5))
	await _walk_to(bell_at + (xf.call(Vector3(-1.2, 0.0, 0.8)) - xf.call(Vector3.ZERO)), 0.4)
	var bell: Bell = null
	for b in w.bells:
		if b.global_position.distance_to(bell_at) < 0.6:
			bell = b
	assert_ne(bell, null, "found the bell")
	w.interact(bell)
	await _ride(_block(tag + "_lift"), xf.call(Vector3(0.5, 3.0, z0 - 5.5)), false)
	await _walk_to(xf.call(Vector3(0.5, 0.0, z0 - 8.5)))


func _run_line(rooms: Array[StageModules.Room]) -> void:
	var z0 := 0
	for i in rooms.size():
		await _solve(rooms[i], z0, "r%d" % i, func(p: Vector3) -> Vector3: return p)
		z0 -= StageModules._room_length(rooms[i])


func _run_arm(arm: StageModules.Arm, rooms: Array) -> void:
	var xf := func(p: Vector3) -> Vector3: return StageModules._turn_point(p, arm)
	var z0 := -StageModules.HALF_WIDTH - 1
	await _walk_to(xf.call(Vector3(0.5, 0.0, z0 + 1.5)))
	for i in rooms.size():
		var room := rooms[i] as StageModules.Room
		await _solve(room, z0, "a%d_r%d" % [arm, i], xf)
		z0 -= StageModules._room_length(room)


func _cleared() -> bool:
	for i in 120:
		if director.last_clear_text != "":
			# 自動プレイの所要時間（迷わず最短で動いたときの下限。人の目安時間とは別）
			print("    %s: %s" % [director.stage_id, director.last_clear_text])
			return true
		await tree.physics_frame
	return false


# --- ステージ ----------------------------------------------------------------


func test_let_go_of_ban_is_solvable_alone() -> void:
	await _enter(StageCatalog.BAN_ID)
	var r := StageModules.Room
	await _run_line([r.LET_GO_OF_BAN, r.GOAL_PODIUM])
	assert_true(await _cleared(), "cleared")


func test_gear_path_is_solvable_alone() -> void:
	await _enter(StageCatalog.GEAR_ID)
	var r := StageModules.Room
	await _run_line([r.BOOTS, r.GLOVES, r.GOAL_PODIUM])
	assert_true(await _cleared(), "cleared")


func test_three_bells_is_solvable_alone() -> void:
	await _enter(StageCatalog.THREE_BELLS_ID)
	var r := StageModules.Room
	await _run_arm(StageModules.Arm.NORTH, [r.JUMP_LEND, r.ARM_BELL])
	assert_false(director.last_clear_text != "", "one bell is not enough")
	await _run_arm(StageModules.Arm.EAST, [r.BOOTS, r.ARM_BELL])
	await _run_arm(StageModules.Arm.WEST, [r.BELL_LIFT, r.ARM_BELL])
	assert_true(await _cleared(), "cleared after all three bells")


func test_island_tour_is_solvable_alone() -> void:
	await _enter(StageCatalog.ISLAND_TOUR_ID)
	var r := StageModules.Room
	await _run_arm(StageModules.Arm.NORTH, [r.LET_GO_OF_BAN, r.BELL_LIFT, r.ARM_BELL])
	await _run_arm(StageModules.Arm.EAST, [r.BOOTS, r.GLOVES, r.ARM_BELL])
	await _run_arm(StageModules.Arm.WEST, [r.JUMP_LEND, r.LET_GO_OF_BAN, r.ARM_BELL])
	assert_true(await _cleared(), "cleared after all three bells")
