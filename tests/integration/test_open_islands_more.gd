extends TestCase
## 「風の尾根」と「砦跡」を、ひとりで最初から最後まで自動で遊ぶ（通しプレイ。docs/adr/0011）。
## 操作はプレイヤーと同じ（歩く・段差で跳ぶ・渡す・乗る・回収する・鐘を鳴らす・地形を押す）で、瞬間移動はしない。
## 部品は tests/integration/test_open_islands.gd と同じ。「風の尾根」は別々の道でもクリアできることを確かめる。

const JUMP := RuleAction.Kind.JUMP
const BACK := RuleAction.Kind.BACK
const RIGHT := RuleAction.Kind.RIGHT
const THROW := RuleAction.Kind.THROW
const PROFILE := "zz_test_open_islands_more"

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


func _slot_of(action: RuleAction.Kind) -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, _me().player_id)
		if v != null and w.ledger.token(v.token_id).action == action:
			return slot
	return -1


# --- 操作の部品 ---------------------------------------------------------------


func _face(target: Vector3) -> Vector3:
	var flat := Vector3(target.x - _me().global_position.x, 0.0, target.z - _me().global_position.z)
	_me().view_yaw = atan2(-flat.x, -flat.z)
	return flat


## target へ歩く（水平の距離が tolerance 以内で、高さも近ければ着いた）。段差で止まったら跳ぶ。
func _walk_to(target: Vector3, tolerance: float = 0.35, frames: int = 1200) -> bool:
	var stuck := 0
	for i in frames:
		var flat := _face(target)
		if flat.length() <= tolerance and absf(_me().global_position.y - target.y) < 0.7:
			_me().move_intent = Vector2.ZERO
			return true
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


func _lend(target: Node3D, slot: int, mode: TriggerMode.Kind) -> void:
	w.select_slot(slot)
	w.set_lend_mode(mode)
	assert_eq(w.lend_to(target, false), RuleLedger.LendResult.OK, "lend to %s" % target.name)


func _block(key: String) -> RuleBlock:
	return w.blocks[int(w.entity_ids[key])]


## 乗っている台が跳ねたら、十分高いところで上の段（onto）へ歩いて移る。
func _ride_onto(onto: Vector3, label: String) -> void:
	for i in 900:
		var flat := _face(onto)
		if flat.length() < 0.4 and _me().global_position.y > onto.y - 0.2:
			break
		var high_enough := _me().global_position.y > onto.y - 0.1
		_me().move_intent = Vector2(0.0, 1.0) if high_enough else Vector2.ZERO
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_gt(_me().global_position.y, onto.y - 0.3, "rode %s up onto %s" % [label, onto])


## 窪みのブロックにジャンプを単発で渡し、上に立ってキーで跳ばせ、上の段（onto）へ移る。
func _lift_up(key: String, beside: Vector3, onto: Vector3) -> void:
	var lift := _block(key)
	await _walk_to(beside)
	_lend(lift, _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	await _walk_to(lift.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	w.press_action(JUMP)
	await _ride_onto(onto, key)


## 台に付いているものを F で全部回収する（台が跳ねていて届かない間は、届くまで待つ）。
func _recall_all_from(key: String) -> void:
	var block := _block(key)
	for i in 600:
		if w.ledger.tokens_on(block.entity_id).is_empty():
			break
		if w.is_within_reach(block):
			w.interact(block)
		await tree.physics_frame
	assert_true(w.ledger.tokens_on(block.entity_id).is_empty(), "recalled from %s" % key)


## 段の縁の地形のセル（上面の 1 つ）に S（南）を単発で渡して押し出す。セルは南へ 1 マス動いて下の段へ落ち、
## 下の段 → 落ちたセル（+1）→ 削れた縁（+1）→ 上の段（+1）の階段になる。
func _push_south(cell: Vector3i, stand: Vector3) -> void:
	await _walk_to(stand, 0.3)
	_lend(w.terrain_target(cell), _slot_of(BACK), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(BACK)
	var block := w.blocks[w.promoted[cell]]
	var landed := Vector3i(cell.x, cell.y - 1, cell.z + 1)
	for i in 240:
		if block.cell() == landed and block.is_grounded() and not block.is_moving_horizontally():
			break
		await tree.physics_frame
	assert_eq(block.cell(), landed, "the edge cell %s fell one step down" % cell)


func _wait_for(key: String, frames: int = 400) -> void:
	for i in frames:
		if w.activated.has(key):
			break
		await tree.physics_frame
	assert_true(w.activated.has(key), "%s rang" % key)


## via を順に歩いてから、ゴールの窪みの真ん中へ歩いて入る（docs/adr/0011 決定 9。瞬間移動しない）。
func _walk_into_goal(via: Array[Vector3] = []) -> void:
	for p in via:
		await _walk_to(p)
	var goal := w.def.clear_condition.goal_area()
	var center := goal.get_center()
	await _walk_to(Vector3(center.x, goal.position.y + 0.1, center.z))
	await wait_physics_frames(10)  # 窪みへ降りきるまで待つ
	assert_true(goal.has_point(_me().global_position), "standing in the goal")


func _cleared(frames: int = 180) -> bool:
	for i in frames:
		if director.last_clear_text != "":
			# 自動プレイの所要時間（答えを知っていて迷わないので、人の時間の下限にもならない参考値）
			print("    %s: %s" % [director.stage_id, director.last_clear_text])
			return true
		await tree.physics_frame
	return false


# --- 風の尾根 -----------------------------------------------------------------


## 札（ジャンプ禁止）を取って繰り返し → 風鈴で信号の台 → 札を押し付けて単発、の道。
func test_windy_ridge_by_the_ban_and_the_wind_bell() -> void:
	await _enter(StageCatalog.WINDY_ID)
	var me := _me().player_id
	# 浜: 錆びた台の札を取ると、自分が跳べなくなる（単発も起動できない）
	var rusty := _block("rusty_lift")
	await _walk_to(Vector3(7.5, 0.0, -4.5))
	w.interact(rusty)
	assert_true(w.ledger.player_prohibited(JUMP, me), "the ban moved onto me")
	# 札を持ったままでも渡すことはできる: 台に乗って、ジャンプを繰り返しで渡す
	await _walk_to(rusty.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	_lend(rusty, _slot_of(JUMP), TriggerMode.Kind.REPEAT)
	await _ride_onto(Vector3(6.5, 2.0, -8.5), "rusty_lift")
	await _walk_to(Vector3(6.5, 2.0, -7.4), 0.25)
	await _recall_all_from("rusty_lift")
	# 段: 風の台にジャンプを信号で渡し、台の上から風鈴を鳴らす。鳴っている間だけ跳ねる
	var wind := _block("wind_lift_a")
	await _walk_to(wind.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	_lend(wind, _slot_of(JUMP), TriggerMode.Kind.SIGNAL)
	w.interact(w.bells_by_key["wind_bell"])
	assert_true(w.bells_by_key["wind_bell"].is_ringing(), "rang the wind bell")
	await _ride_onto(Vector3(-6.5, 4.0, -15.0), "wind_lift_a")
	await _walk_to(Vector3(-6.5, 4.0, -14.3), 0.25)
	await _recall_all_from("wind_lift_a")
	# 肩: 札（取った禁止はホットバーに入っている）を、地形のセルに押し付けてから、肩の台に単発で頂へ
	assert_true(w.ledger.player_prohibited(JUMP, me), "carrying the ban")
	var ban_slot := -1
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, me)
		if v != null and w.ledger.token(v.token_id).is_prohibition:
			ban_slot = slot
	assert_ne(ban_slot, -1, "the taken ban went to the hotbar")
	_lend(w.terrain_target(Vector3i(-5, 3, -15)), ban_slot, TriggerMode.Kind.NONE)
	assert_false(w.ledger.player_prohibited(JUMP, me), "got rid of the ban")
	await _lift_up("summit_lift", Vector3(-1.5, 4.0, -18.5), Vector3(-1.5, 6.0, -22.5))
	assert_eq(director.last_clear_text, "", "the summit's edge is not the goal")
	await _walk_into_goal()
	assert_true(await _cleared(), "reached the goal on the summit")


## 段の縁の地形のセルを押し出して、1 段ずつの階段を 3 回作る道（ブロックも装備も使わない）。
func test_windy_ridge_by_pushing_the_cliff_edges() -> void:
	await _enter(StageCatalog.WINDY_ID)
	await _push_south(Vector3i(0, 1, -7), Vector3(2.0, 0.0, -4.5))
	await _walk_to(Vector3(0.5, 0.0, -4.5))
	await _walk_to(Vector3(0.5, 1.0, -5.5))
	await _walk_to(Vector3(0.5, 1.0, -6.5))
	await _walk_to(Vector3(0.5, 2.0, -8.5))
	await _push_south(Vector3i(0, 3, -14), Vector3(2.0, 2.0, -11.5))
	await _walk_to(Vector3(0.5, 2.0, -11.5))
	await _walk_to(Vector3(0.5, 3.0, -12.5))
	await _walk_to(Vector3(0.5, 3.0, -13.5))
	await _walk_to(Vector3(0.5, 4.0, -15.5))
	await _push_south(Vector3i(0, 5, -21), Vector3(2.0, 4.0, -18.5))
	await _walk_to(Vector3(0.5, 4.0, -18.5))
	await _walk_to(Vector3(0.5, 5.0, -19.5))
	await _walk_to(Vector3(0.5, 5.0, -20.5))
	await _walk_to(Vector3(0.5, 6.0, -22.5))
	await _walk_into_goal()
	assert_true(await _cleared(), "climbed the crumbled edges to the summit")


# --- 砦跡 ---------------------------------------------------------------------


## 窪みのブロックで上の郭へ → 櫓の縁の発射台で鐘 → 要石を東の柱まで押し、壁の切れ目から南の窪みへ。
func test_ruined_fort_alone() -> void:
	await _enter(StageCatalog.FORT_ID)
	await _lift_up("court_lift", Vector3(7.5, 0.0, -4.5), Vector3(6.5, 2.0, -8.5))
	# 鐘: 櫓の縁の発射台へ、東の郭から「投げる」を渡す
	await _walk_to(Vector3(5.5, 2.0, -10.5))
	_lend(_block("launcher"), _slot_of(THROW), TriggerMode.Kind.NONE)
	await _wait_for("keep_bell")
	assert_eq(director.last_clear_text, "", "the bell alone does not clear")
	# 要石: 東へ押すと柱で止まる。回収して南へ押すと、壁の切れ目を抜けて下の郭の窪みへ落ちる
	var stone := _block("keystone")
	await _walk_to(Vector3(5.5, 2.0, -17.5))
	await _walk_to(Vector3(8.5, 2.0, -17.5))
	_lend(stone, _slot_of(RIGHT), TriggerMode.Kind.REPEAT)
	for i in 600:
		if stone.cell().x >= 10 and not stone.is_moving_horizontally():
			break
		await tree.physics_frame
	assert_eq(stone.cell(), Vector3i(10, 2, -16), "the pillar stopped the keystone")
	await _recall_all_from("keystone")
	_lend(stone, _slot_of(BACK), TriggerMode.Kind.REPEAT)
	# 鐘と要石だけではクリアしない。東の郭の窪みのブロックで櫓へ上がり、奥のゴールに入る
	await _lift_up("keep_lift", Vector3(6.5, 2.0, -14.5), Vector3(3.5, 4.0, -14.5))
	await _walk_into_goal()
	assert_true(await _cleared(3600), "the keystone sits in the socket and the bell has rung")
	for i in 400:
		if stone.cell() == Vector3i(10, -1, 5):
			break
		await tree.physics_frame
	assert_eq(
		stone.cell(), Vector3i(10, -1, 5), "slid through the breach to the far side of the socket"
	)


## 協力だけの近道: 東の谷筋の突風の台は、ジャンプ 1 個では頂（崖の高さ 4）に届かず、×2 なら届く。
## 2 個目は仲間から受け取った想定で、手元に 1 個足して確かめる（ひとりの装備では 2 個目は手に入らない）。
func test_windy_ridge_gust_lift_needs_two_jumps() -> void:
	await _enter(StageCatalog.WINDY_ID)
	await _push_south(Vector3i(0, 1, -7), Vector3(2.0, 0.0, -4.5))
	await _walk_to(Vector3(0.5, 0.0, -4.5))
	await _walk_to(Vector3(0.5, 1.0, -5.5))
	await _walk_to(Vector3(0.5, 1.0, -6.5))
	await _walk_to(Vector3(0.5, 2.0, -8.5))
	await _walk_to(Vector3(5.5, 2.0, -12.5))
	var gust := _block("gust_lift")
	await _walk_to(gust.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	_lend(gust, _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	var top := _me().global_position.y
	for i in 120:
		await tree.physics_frame
		top = maxf(top, _me().global_position.y)
	assert_lt(top, 5.5, "one jump does not lift the rider up to the summit (6)")
	await wait_physics_frames(30)
	w.ledger.give_player_item(JUMP, false, 7, _me().player_id)
	_lend(gust, _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	_lend(gust, 7, TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	await _ride_onto(Vector3(1.5, 6.0, -22.5), "gust_lift")
	await _walk_into_goal()
	assert_true(await _cleared(), "two jumps reach the summit directly")
