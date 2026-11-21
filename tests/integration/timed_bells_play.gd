extends "res://tests/integration/island_probing.gd"
## 「鳴りつづける鐘」（2-5。時の鐘の初出）のテストの共通部品（ファイル名が test_ で始まらないので、これ自体は
## 実行されない）。通しプレイは test_world2_timed_bells.gd、関所と詰みは test_world2_timed_bells_probes.gd。
## 動きはプレイヤーと同じ入力（move_intent・view_yaw・press_action）と画面の操作（渡す・鐘の F）だけ。

const BACK := RuleAction.Kind.BACK
const RIGHT := RuleAction.Kind.RIGHT
const STAGE_ID := "w2_timed_bells"
const BELL := OpenIslandsW2.RINGING_BELL
## 石が止まるセル（出っ張りの東）。
const STONE_REST := Vector3i(0, 0, 1)
## 鐘のそばの立ち位置（鐘の段の上）と、橋のたもと（鐘に F が届く）。
const BY_THE_BELL := Vector3(3.5, 2.0, -0.4)
const BRIDGE_FOOT := Vector3(0.9, 2.0, -2.7)
## 橋を渡った先（北の台地の縁）。
const FAR_BANK := Vector3(1.0, 4.0, -13.8)
## 浜で出っ張り（-1, 1）をよける立ち寄り先。
const AROUND_THE_BUMP := Vector3(-0.5, 0.0, 3.5)

# --- 共通の部品 -----------------------------------------------------------------


func _bell() -> Bell:
	return w.bells_by_key[BELL]


func _bridge_up() -> bool:
	for door in MechanismSet.of(w).doors:
		if not door.is_closed():
			return false
	return true


func _bridge_down() -> bool:
	for door in MechanismSet.of(w).doors:
		if not door.is_open():
			return false
	return true


func _give_kit_a_move() -> void:
	var kit := _creature("kit")
	await _walk_to(kit.global_position + Vector3(1.4, 0.0, 0.0), 0.4)
	_lend(kit, _slot_of(RIGHT), TriggerMode.Kind.NONE)
	await _walk_to(AROUND_THE_BUMP, 0.5)


## ブロック（key）の横（offset）へ歩いてから、移動を単発で渡してキーで 1 マス押す。times 回くり返す。
func _push_block(key: String, action: RuleAction.Kind, times: int, offset: Vector3) -> void:
	var block := _block(key)
	for i in times:
		var at := block.global_position + offset
		await _walk_to(Vector3(at.x, _me().global_position.y, at.z), 0.3)
		_lend(block, _slot_of(action), TriggerMode.Kind.SINGLE_SHOT)
		w.press_action(action)
		await wait_physics_frames(40)
		for f in 120:
			if block.is_grounded() and not block.is_moving_horizontally():
				break
			await tree.physics_frame


func _wait_block_at(key: String, cell: Vector3i, frames: int = 900) -> void:
	var block := _block(key)
	for i in frames:
		if block.cell() == cell and block.is_grounded() and not block.is_moving_horizontally():
			break
		await tree.physics_frame
	assert_eq(block.cell(), cell, "%s came to rest at %s" % [key, cell])


## 足もとの地面のセル（上面のセル）にジャンプを単発で貸して乗り、上の段（onto）へ移る（受け入れた技）。
func _ground_cell_lift(cell: Vector3i, onto: Vector3) -> void:
	await _walk_to(Vector3(cell.x + 0.5, cell.y + 1.0, cell.z + 0.5), 0.25)
	_lend(w.terrain_target(cell), _slot_of(JUMP), TriggerMode.Kind.SINGLE_SHOT)
	w.press_action(JUMP)
	for i in 300:
		var flat := _face(onto)
		if flat.length() < 0.4 and _me().global_position.y > onto.y - 0.2:
			break
		_me().move_intent = Vector2(0.0, 1.0) if _me().global_position.y > onto.y else Vector2.ZERO
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	assert_gt(_me().global_position.y, onto.y - 0.3, "rode up onto %s" % onto)


## 手の届く所で時の鐘を F で鳴らす（歩いて近づかない）。
func _ring_here() -> void:
	_face(_bell().global_position)
	w.interact(_bell())
	await wait_physics_frames(2)
	assert_true(_bell().is_ringing(), "rang the timed bell from where I stand")


## 鐘のそばに立ち、残りが 1 秒を切るたびに F で鳴らし直す。until が true になったら戻る。
## 鳴らし直した回数を返す。
func _keep_ringing(until: Callable, frames: int) -> int:
	var rings := 0
	for i in frames:
		if until.call():
			break
		if _bell().remaining < 1.0:
			await _ring_here()
			rings += 1
		await tree.physics_frame
	return rings


## 橋のたもとで鳴らし、橋が上がりきってから、鳴りやむ前に北の台地まで走って渡る。
func _race_across() -> void:
	for i in 600:
		if _bridge_down():
			break
		await tree.physics_frame
	await _walk_to(BRIDGE_FOOT, 0.3)
	await _ring_here()
	for i in 120:
		if _bridge_up():
			break
		await tree.physics_frame
	var started := _bell().remaining
	await _walk_to(FAR_BANK, 0.5, 360)
	assert_gt(_me().global_position.y, 3.8, "made it onto the far plateau")
	print("    timed_bells: crossed with %.2f s of %.1f s left" % [_bell().remaining, started])


## 浜の東の地面のセルを持ち上げ台にして、鐘の段へ上がる。
func _climb_to_the_terrace() -> void:
	await _ground_cell_lift(Vector3i(8, -1, 1), Vector3(8.5, 2.0, 0.4))


## 信号の石を、鐘を使わずに手で（単発の A で）出っ張りまで押す。
func _push_the_stone_by_hand() -> void:
	await _push_block("walking_stone", LEFT, 5, Vector3(1.5, -0.5, 0.0))
	await _wait_block_at("walking_stone", STONE_REST)


## ホットバーで、action が器に入っている（まだ貸していない）スロット（無ければ -1）。
func _ready_slot(action: RuleAction.Kind) -> int:
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, _me().player_id)
		if v != null:
			var t := w.ledger.token(v.token_id)
			if t.action == action and not t.is_prohibition and t.is_in_vessel():
				return slot
	return -1
