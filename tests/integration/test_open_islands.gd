extends TestCase
## 開けた島のステージを、ひとりで最初から最後まで自動で遊ぶ（通しプレイ）。
## 歩く（段差では跳ぶ）・谷を跳ぶ・渡す・乗る・拾う・装備する・鐘を鳴らす、をプレイヤーと同じ操作で流す
## （瞬間移動はしない）。「丘の上の旗」は、別々の道でもクリアできることを確かめる（解法は自由）。

const JUMP := RuleAction.Kind.JUMP
const LEFT := RuleAction.Kind.LEFT
const THROW := RuleAction.Kind.THROW
const PROFILE := "zz_test_open_islands"

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


## 谷の手前（edge）まで歩き、走りながら跳んで向こう（land）へ。
func _jump_across(edge: Vector3, land: Vector3) -> void:
	await _walk_to(edge, 0.3)
	_face(land)
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(6)
	w.press_action(JUMP)
	await _walk_to(land, 0.6, 240)


func _lend(target: Node3D, slot: int, mode: TriggerMode.Kind) -> void:
	w.select_slot(slot)
	w.set_lend_mode(mode)
	assert_eq(w.lend_to(target, false), RuleLedger.LendResult.OK, "lend to %s" % target.name)


func _block(key: String) -> RuleBlock:
	return w.blocks[int(w.entity_ids[key])]


## 窪みのブロックにジャンプを単発で渡し、上に立ってキーで跳ばせ、上の段（onto）へ移る。
func _lift_up(key: String, beside: Vector3, onto: Vector3) -> void:
	var lift := _block(key)
	await _walk_to(beside)
	_lend(lift, _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	await _walk_to(lift.global_position + Vector3(0.0, 0.5, 0.0), 0.25)
	w.press_action(JUMP)
	for i in 600:
		var flat := _face(onto)
		if flat.length() < 0.4 and _me().global_position.y > onto.y - 0.2:
			break
		var high_enough := _me().global_position.y > onto.y - 0.1
		_me().move_intent = Vector2(0.0, 1.0) if high_enough or i < 2 else Vector2.ZERO
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_gt(_me().global_position.y, onto.y - 0.3, "rode %s up onto %s" % [key, onto])


func _pick_and_wear(at: Vector3, part: RuleVessel.Part) -> void:
	await _walk_to(at, 0.6)
	w.interact(null)
	await wait_physics_frames(2)
	for v in w.ledger.inventory_vessels(_me().player_id):
		if v.part == part:
			assert_true(w.ledger_actions.equip(v.id), "wear %s" % v.item_name)
	assert_ne(w.ledger.equipped_vessel(part, _me().player_id), null, "equipped")


func _ring(key: String) -> void:
	var bell := w.bells_by_key[key]
	await _walk_to(
		bell.global_position + (_me().global_position - bell.global_position).normalized() * 1.4,
		0.5
	)
	_face(bell.global_position)
	w.interact(bell)
	await wait_physics_frames(2)
	assert_true(w.activated.has(key), "rang %s" % key)


func _cleared() -> bool:
	for i in 180:
		if director.last_clear_text != "":
			# 自動プレイの所要時間（答えを知っていて迷わないので、人の時間の下限にもならない参考値）
			print("    %s: %s" % [director.stage_id, director.last_clear_text])
			return true
		await tree.physics_frame
	return false


# --- ステージ ----------------------------------------------------------------


func test_hill_top_by_the_lift() -> void:
	await _enter(StageCatalog.HILL_ID)
	await _walk_to(Vector3(0.5, 1.0, 1.5))
	await _walk_to(Vector3(-0.5, 2.0, -1.5))
	await _lift_up("lift", Vector3(-0.5, 2.0, -1.5), Vector3(0.5, 4.0, -5.5))
	assert_true(await _cleared(), "reached the summit")


func test_hill_top_by_the_boots() -> void:
	await _enter(StageCatalog.HILL_ID)
	await _walk_to(Vector3(8.5, 0.0, 3.5))
	await _walk_to(Vector3(8.5, 1.0, 1.5))
	await _walk_to(Vector3(8.5, 2.0, -0.5))
	await _walk_to(Vector3(8.5, 3.0, -3.5))
	await _pick_and_wear(Vector3(7.5, 3.0, -5.0), RuleVessel.Part.FEET)
	await _walk_to(Vector3(5.5, 1.0, -3.5))
	await _walk_to(Vector3(3.5, 2.0, -3.5))
	await _walk_to(Vector3(1.5, 4.0, -5.5))
	assert_true(await _cleared(), "jumped onto the summit with the boots")


func test_quarry_by_pushing_a_stone_and_the_ledge_lift() -> void:
	await _enter(StageCatalog.QUARRY_ID)
	var stone := _block("stone_a")
	await _walk_to(stone.global_position + Vector3(1.6, -0.5, 0.0))
	_lend(stone, _slot_of(LEFT), TriggerMode.Kind.REPEAT)
	for i in 600:
		if stone.cell().x <= -5 and not stone.is_moving_horizontally():
			break
		await tree.physics_frame
	assert_eq(stone.cell().x, -5, "the stone slid to the terrace wall")
	await _walk_to(Vector3(-4.5, 1.0, 1.5))
	await _walk_to(Vector3(-6.5, 2.0, 1.5))
	await _walk_to(Vector3(-4.5, 2.0, -6.5))
	await _walk_to(Vector3(1.5, 3.0, -7.5))
	await _lift_up("ledge_lift", Vector3(1.5, 3.0, -7.5), Vector3(0.5, 5.0, -9.5))
	assert_true(await _cleared(), "climbed out of the quarry")


func test_three_bells_alone() -> void:
	await _enter(StageCatalog.THREE_BELLS_ID)
	# 東: 岸の発射台に「投げる」を渡して、谷の向こうの鐘を撃つ
	await _walk_to(Vector3(9.5, 0.0, 1.5))
	_lend(_block("launcher"), _slot_of(THROW), TriggerMode.Kind.NONE)
	for i in 400:
		if w.activated.has("east_bell"):
			break
		await tree.physics_frame
	assert_true(w.activated.has("east_bell"), "the launcher rang the east bell")
	# 西: 裾へ上がり、窪みのブロックで台地へ
	await _walk_to(Vector3(-13.5, 1.0, 1.5))
	await _lift_up("west_lift", Vector3(-14.5, 1.0, 1.5), Vector3(-16.5, 3.0, -0.5))
	await _ring("west_bell")
	assert_eq(director.last_clear_text, "", "not cleared with two bells")
	# 北: 降りて東側の階段から段へ上がり、窪みのブロックで台地へ
	await _walk_to(Vector3(-12.5, 0.0, -2.5))
	await _walk_to(Vector3(5.5, 0.0, -12.5))
	await _walk_to(Vector3(5.5, 1.0, -15.5))
	await _walk_to(Vector3(5.5, 2.0, -17.5))
	await _walk_to(Vector3(3.5, 3.0, -16.5))
	await _lift_up("north_lift", Vector3(0.5, 3.0, -16.5), Vector3(-0.5, 5.0, -18.5))
	await _ring("north_bell")
	assert_true(await _cleared(), "all three bells")


func test_floating_isles_alone() -> void:
	await _enter(StageCatalog.FLOATING_ID)
	# 東: 発射台で鐘を撃つ
	await _walk_to(Vector3(4.5, 0.0, 1.5))
	_lend(_block("launcher"), _slot_of(THROW), TriggerMode.Kind.NONE)
	for i in 400:
		if w.activated.has("east_bell"):
			break
		await tree.physics_frame
	assert_true(w.activated.has("east_bell"), "the launcher rang the east bell")
	# 北: 塔へ上がり、谷 3 を跳んで北の浮島へ
	await _lift_up("tower_lift", Vector3(1.5, 0.0, -1.5), Vector3(0.5, 2.0, -5.5))
	await _jump_across(Vector3(0.5, 2.0, -5.7), Vector3(0.5, 2.0, -11.0))
	await _ring("north_bell")
	# 戻って南の浮島（谷 2）でブーツを拾い、ブーツで西の谷 4 を越える
	await _walk_to(Vector3(-3.5, 2.0, -10.5))
	await _jump_across(Vector3(-3.5, 2.0, -10.3), Vector3(-3.5, 0.0, -4.5))
	await _jump_across(Vector3(0.5, 0.0, 5.7), Vector3(0.5, 0.0, 10.0))
	await _pick_and_wear(Vector3(2.5, 0.0, 14.0), RuleVessel.Part.FEET)
	await _jump_across(Vector3(0.5, 0.0, 9.3), Vector3(0.5, 0.0, 4.0))
	await _jump_across(Vector3(-5.7, 0.0, 0.5), Vector3(-11.8, 0.0, 0.5))
	await _ring("west_bell")
	assert_true(await _cleared(), "all three bells")
