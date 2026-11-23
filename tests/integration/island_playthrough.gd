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


## action の能力（禁止ではない）が入っているホットバーの枠（無ければ -1）。取った禁止もホットバーに入るので、
## 禁止の枠は数えない（WorldLending.to_hotbar_if_free）。
func _slot_of(action: RuleAction.Kind) -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, _me().player_id)
		if v == null:
			continue
		var t := w.ledger.token(v.token_id)
		if t.action == action and not t.is_prohibition:
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
	if w.throw_mode:
		# 投げたメダルが当たるまで待つ（docs/adr/0017。呼び出し側は await する）
		assert_true(await wait_throws(w), "the thrown medal lands")


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
	for v in carried(w.ledger, _me().player_id):
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
	await _lend(target, slot, TriggerMode.Kind.NONE)
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
## 拾った能力は、ホットバーに空きがあれば自動でそこへ入る（WorldLending.to_hotbar_if_free）。
func _pick_to_hotbar(at: Vector3, action: RuleAction.Kind) -> int:
	await _walk_to(at, 0.6)
	var before := _slots_holding(action)
	w.interact(null)
	await wait_physics_frames(2)
	var slot := -1
	for s in _slots_holding(action):
		if not before.has(s):
			slot = s
	if slot == -1:
		slot = _free_slot()
		for v in w.ledger.inventory_vessels(_me().player_id):
			var t := w.ledger.token(v.token_id)
			if t.action == action and not t.is_prohibition:
				assert_true(
					w.ledger_actions.move_to_hotbar(v.id, slot), "%s to the hotbar" % action
				)
	assert_true(_slots_holding(action).has(slot), "picked up %s" % action)
	return slot


## action の能力（禁止ではない）が入っているホットバーの枠。
func _slots_holding(action: RuleAction.Kind) -> Array[int]:
	var result: Array[int] = []
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, _me().player_id)
		if v == null:
			continue
		var t := w.ledger.token(v.token_id)
		if t != null and t.action == action and not t.is_prohibition:
			result.append(slot)
	return result


## 拾ったばかりの action の能力が入っているホットバーの枠（拾うとその枠が選ばれる。NewInHotbar）。
## 選んでいる枠に無ければ、action が入っている最後の枠。無ければ -1。
func _picked_slot(action: RuleAction.Kind) -> int:
	var me := _me().player_id
	var v := w.ledger.hotbar_vessel(w.selected_slot, me)
	if v != null and w.ledger.token(v.token_id).action == action:
		return w.selected_slot
	var found := -1
	for slot in _slots_holding(action):
		found = slot
	return found


func _free_slot() -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		if w.ledger.hotbar_vessel(slot, _me().player_id) == null:
			return slot
	return -1


## 手元の禁止（action）をホットバーへ移して、target へ触って渡す（禁止を手放す）。
## 取った禁止は、ホットバーに空きがあれば自動でそこへ入っている（WorldLending.to_hotbar_if_free）。
func _hand_off_ban(action: RuleAction.Kind, target: Node3D) -> void:
	_lend(target, _ban_slot(action), TriggerMode.Kind.NONE)
	assert_false(w.ledger.player_prohibited(action, _me().player_id), "got rid of the ban")


## 手元の禁止（action）が入っているホットバーの枠（かばんにあれば空きへ移す）。
func _ban_slot(action: RuleAction.Kind) -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, _me().player_id)
		var t := w.ledger.token(v.token_id) if v != null else null
		if t != null and t.is_prohibition and t.action == action and t.holder_ids.is_empty():
			return slot
	var free := _free_slot()
	for v in w.ledger.inventory_vessels(_me().player_id):
		var t := w.ledger.token(v.token_id)
		if t.is_prohibition and t.action == action:
			assert_true(w.ledger_actions.move_to_hotbar(v.id, free), "ban to the hotbar")
	return free


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


## 丘の上の旗（1-5）の最初の新しいこと「投げる」: 浜の東の端の台の予備の S を F で取り、幅 14 の空の先の
## 小島の生き物へ投げ渡して、巣へ歩かせる（docs/w1-teaching.md）。
func _throw_a_move_to_the_islet_critter() -> void:
	var slot := await _take_the_spare_s()
	await _walk_to(Vector3(9.2, 0.0, 5.5), 0.3)
	var critter := _creature("islet_critter")
	assert_false(w.is_within_reach(critter), "out of touch reach")
	_face(critter.global_position)
	await _lend_by_throwing(critter, slot)
	assert_true(critter.can_walk(), "the critter caught the thrown S")
	assert_true(
		await _wait_creature_in("islet_critter", OpenIslands.HILL_NEST, 900),
		"the islet critter walked to its nest"
	)


## 丘の上の旗の、浜の東の端の台に付いた予備の S を F で取る。入ったホットバーの枠を返す。
func _take_the_spare_s() -> int:
	var spare := _block("spare_post")
	await _walk_to(spare.global_position + Vector3(1.4, -0.5, 0.0), 0.4)
	var before := _slots_holding(RuleAction.Kind.BACK)
	await _recall_all_from("spare_post")
	for slot in _slots_holding(RuleAction.Kind.BACK):
		if not before.has(slot):
			return slot
	fail("the spare S went to the hotbar")
	return -1


## 採石場（1-6）の最初の新しいこと「禁止」: 底の石のジャンプ禁止を F で取り、もう一方の石へ渡して手放す。
func _free_stone_a_from_its_ban() -> void:
	var stone := _block("stone_a")
	await _walk_to(stone.global_position + Vector3(1.4, -0.5, 0.0), 0.4)
	await _recall_all_from("stone_a")
	assert_false(w.ledger.player_can(JUMP, _me().player_id), "the ban is on me now")
	var other := _block("stone_b")
	await _walk_to(other.global_position + Vector3(-1.4, -0.5, 0.0), 0.4)
	_hand_off_ban(JUMP, other)
	assert_true(w.ledger.player_can(JUMP, _me().player_id), "can jump again")


## 生き物がある箱の中に入るまで待つ（生き物は自分の願いで進む）。
func _wait_creature_in(key: String, box: AABB, frames: int = 1800) -> bool:
	var critter := _creature(key)
	for i in frames:
		if box.has_point(critter.global_position):
			return true
		await tree.physics_frame
	print("    %s stopped at %s (%s)" % [key, critter.global_position, critter.stage])
	return false
