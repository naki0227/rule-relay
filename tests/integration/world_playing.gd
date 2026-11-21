extends "res://tests/integration/island_probing.gd"
## ワールド 3・4 のステージを自動で遊ぶ・壊しにいくテストの共通部品（ファイル名が test_ で始まらないので、
## これ自体は実行されない）。island_playthrough.gd・island_probing.gd の部品に、空中ダッシュ・地上のダッシュ・
## 往復足場に乗る・生き物に渡す・風を待つ、を足す。操作はプレイヤーと同じ（移動の入力・向き・キー・F・渡す）で、
## 瞬間移動・状態の書き換えはしない。

const BACK := RuleAction.Kind.BACK
const RIGHT := RuleAction.Kind.RIGHT
const CLIMB := RuleAction.Kind.CLIMB
const HEAVY := RuleAction.Kind.HEAVY


## 谷の手前（edge）から向こう（land）へ走って跳び、跳んでから dash_frames 後に空中でダッシュする。
func _dash_jump_across(edge: Vector3, land: Vector3, dash_frames: int = 22) -> bool:
	assert_true(w.ledger.player_can(DASH, _me().player_id), "has a dash")
	await _walk_to(edge, 0.25)
	_face(land)
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(4)
	w.press_action(JUMP)
	await wait_physics_frames(dash_frames)
	_face(land)
	w.press_action(DASH)
	return await _try_walk_to(land, 0.6, 240)


## 跳ばずに、縁の手前 edge から land へ向かって地上でダッシュする（ジャンプの無い島で幅 2 を越える）。
func _ground_dash_across(edge: Vector3, land: Vector3) -> bool:
	await _walk_to(edge, 0.2)
	_face(land)
	_me().move_intent = Vector2(0.0, 1.0)
	await wait_physics_frames(1)
	w.press_action(DASH)
	await wait_physics_frames(30)
	return await _try_walk_to(land, 0.5, 200)


## 往復足場（key）が cell に止まるまで待つ。
func _wait_shuttle_at(key: String, cell: Vector3i, frames: int = 900) -> bool:
	var block := _block(key)
	for i in frames:
		if block.cell() == cell and not block.is_moving_horizontally() and block.is_grounded():
			return true
		await tree.physics_frame
	return false


## 岸の from に立って待ち、往復足場が隣（board）に来て止まったら乗り、向こう側（off_cell）へ運ばれて
## 止まったら、降りる先（off_to）へ歩く。
func _ride(
	key: String, from: Vector3, board: Vector3i, off_cell: Vector3i, off_to: Vector3
) -> void:
	await _walk_to(from, 0.3)
	assert_true(await _wait_shuttle_at(key, board), "%s came to %s" % [key, board])
	await _walk_to(RuleBlock.cell_center(board) + Vector3(0.0, 0.5, 0.0), 0.25, 60)
	assert_true(await _wait_shuttle_at(key, off_cell), "%s carried me to %s" % [key, off_cell])
	await _walk_to(off_to, 0.35, 120)


## 生き物に能力を渡す（触って。by_throw なら「投げる」の届き方で）。slots の順に渡す。
func _give_creature(key: String, slots: Array[int], by_throw: bool = false) -> void:
	var critter := _creature(key)
	for slot in slots:
		assert_ne(slot, -1, "has the ability to give")
		if by_throw:
			_lend_by_throwing(critter, slot)
		else:
			_lend(critter, slot, TriggerMode.Kind.NONE)


## 生き物から F で全部取り戻す（届くまで待つ）。
func _recall_creature(key: String) -> void:
	var critter := _creature(key)
	for i in 300:
		if w.ledger.tokens_on(critter.entity_id).is_empty():
			break
		if w.is_within_reach(critter):
			w.interact(critter)
		await tree.physics_frame
	assert_true(
		w.ledger.tokens_on(critter.entity_id).is_empty(), "took everything back from %s" % key
	)


## 願いの場所（clear_condition の carry_object の箱）。
func _wish_box(key: String) -> AABB:
	for part in w.def.clear_condition.parts:
		if part.kind == ClearCondition.Kind.CARRY_OBJECT and part.target_key == key:
			return part.area
	fail("no wish for %s" % key)
	return AABB()


func _wait_wish(key: String, frames: int = 1800) -> bool:
	return await _wait_creature_in(key, _wish_box(key), frames)


## 位置 p の風が、吹いている（want = true）／止んでいる（want = false）になるまで待つ。
func _wait_wind(p: Vector3, want: bool, frames: int = 400) -> bool:
	for i in frames:
		if (w.nature.wind_at(p).length() > 0.1) == want:
			return true
		await tree.physics_frame
	return false


## 単発で渡したブロックの行動を、キーで起動する（ブロックの単発は、その行動のキーで起動する）。
func _fire(action: RuleAction.Kind) -> void:
	w.press_action(action)
	await wait_physics_frames(40)


## 落ちている器を拾って、手持ち（ホットバーの空き）に置く。拾った行動のスロットを返す。
func _pick(at: Vector3, action: RuleAction.Kind) -> int:
	return await _pick_to_hotbar(at, action)


## 扉・橋（door の key）が閉じている（橋なら架かっている）か。
func _door_closed(key: String) -> bool:
	for door in MechanismSet.of(w).doors:
		if door.spec.key == key:
			return door.is_closed()
	fail("no door %s" % key)
	return false


func _wait_door(key: String, closed: bool, frames: int = 600) -> bool:
	for i in frames:
		if _door_closed(key) == closed:
			return true
		await tree.physics_frame
	return false


## 「投げる」の届き方で、ブロックへ発動方式つきで能力を渡す（渡したら「触る」に戻る）。
func _throw_lend(target: Node3D, slot: int, mode: TriggerMode.Kind) -> void:
	w.toggle_reach()
	assert_true(w.throw_mode, "throw reach is on")
	_lend(target, slot, mode)
	if w.throw_mode:
		w.toggle_reach()


## 板（plate の key）が押されているか。
func _plate_pressed(key: String) -> bool:
	for plate in MechanismSet.of(w).plates:
		if plate.spec.key == key:
			return plate.pressed
	fail("no plate %s" % key)
	return false


## 受け入れた技（地面のセルに単発のジャンプを貸して乗り、上昇中に自分でも跳ぶ）で、stand から toward へ
## 遠く跳ぶ。toward の向こう岸（far_coord より先、進む向き dir）に立てたら true。落ちたら復活を待って false。
func _stacked_leap(stand: Vector3, cell: Vector3i, dir: Vector3, far_coord: float) -> bool:
	await _walk_to(stand, 0.2)
	var floor_y := _me().global_position.y
	_lend(w.terrain_target(cell), _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	_me().view_yaw = atan2(-dir.x, -dir.z)
	w.press_action(JUMP)
	var pressed := false
	var landed := false
	for f in 360:
		if not pressed and w.ledger.player_can(JUMP, _me().player_id) and _me().is_on_floor():
			if _me().global_position.y > floor_y + 0.2:
				w.press_action(JUMP)
				pressed = true
		_me().move_intent = Vector2(0.0, 1.0) if pressed else Vector2.ZERO
		await tree.physics_frame
		var p := _me().global_position.dot(dir)
		if pressed and _me().is_on_floor() and p > far_coord:
			landed = true
			break
		if _me().global_position.y < floor_y - 3.0:
			break
	_me().move_intent = Vector2.ZERO
	print("    stacked leap from %s: %s (at %s)" % [stand, landed, _me().global_position])
	if not landed:
		await _wait_respawn()
	return landed


## toward へ frames の間まっすぐ歩き（向きは変えない）、空へ落ちたら true（復活を待つ）。
func _walk_off(toward: Vector3, frames: int = 150) -> bool:
	_face(toward)
	_me().move_intent = Vector2(0.0, 1.0)
	var fell := false
	for f in frames:
		await tree.physics_frame
		if _me().global_position.y < -2.0:
			fell = true
			break
	_me().move_intent = Vector2.ZERO
	if fell:
		await _wait_respawn()
	return fell
