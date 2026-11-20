extends TestCase
## 開けた島を自動で遊ぶテストの共通部品（ファイル名が test_ で始まらないので、これ自体は実行されない）。
## 歩く（段差では跳ぶ）・谷を跳ぶ・渡す・乗る・拾う・装備する・鐘を鳴らす、をプレイヤーと同じ操作で流す
## （瞬間移動はしない）。

const JUMP := RuleAction.Kind.JUMP
const LEFT := RuleAction.Kind.LEFT
const FORWARD := RuleAction.Kind.FORWARD
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
	if await _try_walk_to(target, tolerance, frames):
		return true
	fail("could not walk to %s (at %s)" % [target, _me().global_position])
	return false


## _walk_to と同じ歩き方で、着けなくても失敗にしない（行けないことを確かめる関門のテスト用）。
func _try_walk_to(target: Vector3, tolerance: float = 0.35, frames: int = 1200) -> bool:
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


## ゴールの箱（生きている全員が集まればクリア。docs/adr/0011 決定 9）。
func _goal() -> AABB:
	return w.def.clear_condition.goal_area()


## via を順に歩いてから、ゴールの窪みの真ん中へ歩いて入る（瞬間移動しない）。
func _walk_into_goal(via: Array[Vector3] = []) -> void:
	for p in via:
		await _walk_to(p)
	var goal := _goal()
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


## 仲間から能力を1つ受け取った状態にする（協力の近道を、ひとりのテストで再現する）。
## 台帳の普通の配り方で、空いているホットバーに置く（W×2・ジャンプ×2 になる）。
func _gift_from_teammate(action: RuleAction.Kind) -> void:
	for slot in RuleLedger.HOTBAR_SIZE:
		if w.ledger.hotbar_vessel(slot, _me().player_id) == null:
			w.ledger.give_player_item(action, false, slot, _me().player_id)
			assert_eq(w.ledger.ability_count(action, _me().player_id), 2, "stacked x2")
			return
	fail("no free hotbar slot")


## start から land へ向かって走り、edge（崖の縁の手前）を過ぎたところで跳ぶ。着いたら true。
func _run_and_jump(start: Vector3, edge: Vector3, land: Vector3, frames: int = 240) -> bool:
	await _walk_to(start, 0.25)
	var dir := _face(land).normalized()
	_me().move_intent = Vector2(0.0, 1.0)
	for i in 120:
		var ahead := (edge - _me().global_position).dot(dir)
		if ahead <= 0.0 and _me().is_on_floor():
			break
		await tree.physics_frame
	w.press_action(JUMP)
	return await _try_walk_to(land, 0.6, frames)


## 「投げる」の届き方で、遠くの相手に能力を渡す（渡したら「触る」に戻る）。
func _lend_by_throwing(target: Node3D, slot: int) -> void:
	w.toggle_reach()
	assert_true(w.throw_mode, "throw reach is on")
	_lend(target, slot, TriggerMode.Kind.NONE)
	if w.throw_mode:
		w.toggle_reach()


func _wait_until_rung(key: String, frames: int = 400) -> bool:
	for i in frames:
		if w.activated.has(key):
			return true
		await tree.physics_frame
	return false


func _creature(key: String) -> Creature:
	return w.creatures[int(w.entity_ids[key])]


## 落ちている器を拾い、装備せずにホットバーの空き（無ければ失敗）へ置く。置いたスロットを返す。
func _pick_to_hotbar(at: Vector3, action: RuleAction.Kind) -> int:
	await _walk_to(at, 0.6)
	w.interact(null)
	await wait_physics_frames(2)
	var slot := _free_slot()
	for v in w.ledger.inventory_vessels(_me().player_id):
		if (
			w.ledger.token(v.token_id).action == action
			and not w.ledger.token(v.token_id).is_prohibition
		):
			assert_true(w.ledger_actions.move_to_hotbar(v.id, slot), "%s on the hotbar" % action)
	assert_eq(_slot_of(action), slot, "picked up %s" % action)
	return slot


func _free_slot() -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		if w.ledger.hotbar_vessel(slot, _me().player_id) == null:
			return slot
	return -1


## 手元の禁止（action）をホットバーへ移して、target へ触って渡す（禁止を手放す）。
func _hand_off_ban(action: RuleAction.Kind, target: Node3D) -> void:
	var slot := _free_slot()
	for v in w.ledger.inventory_vessels(_me().player_id):
		var t := w.ledger.token(v.token_id)
		if t.is_prohibition and t.action == action:
			assert_true(w.ledger_actions.move_to_hotbar(v.id, slot), "ban to the hotbar")
	_lend(target, slot, TriggerMode.Kind.NONE)
	assert_false(w.ledger.player_prohibited(action, _me().player_id), "got rid of the ban")


## 台に付いているものを F で全部回収する（届かない間は、届くまで待つ）。
func _recall_all_from(key: String) -> void:
	var block := _block(key)
	for i in 600:
		if w.ledger.tokens_on(block.entity_id).is_empty():
			break
		if w.is_within_reach(block):
			w.interact(block)
		await tree.physics_frame
	assert_true(w.ledger.tokens_on(block.entity_id).is_empty(), "recalled from %s" % key)


## 石に移動を繰り返しで渡し、止まるまで待って回収する（石は壁に当たって止まる）。
func _slide_stone(key: String, stand: Vector3, action: RuleAction.Kind, stop: Vector3i) -> void:
	var stone := _block(key)
	await _walk_to(stand, 0.3)
	_lend(stone, _slot_of(action), TriggerMode.Kind.REPEAT)
	for i in 900:
		if stone.cell() == stop and not stone.is_moving_horizontally():
			break
		await tree.physics_frame
	assert_eq(stone.cell(), stop, "%s slid to %s" % [key, stop])
	await _walk_to(stone.global_position + Vector3(0.0, -0.5, 1.6), 0.4)
	await _recall_all_from(key)


## 生き物がある箱の中に入るまで待つ（生き物は自分の願いで進む）。
func _wait_creature_in(key: String, box: AABB, frames: int = 1800) -> bool:
	var critter := _creature(key)
	for i in frames:
		if box.has_point(critter.global_position):
			return true
		await tree.physics_frame
	print("    %s stopped at %s (%s)" % [key, critter.global_position, critter.stage])
	return false
