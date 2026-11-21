extends "res://tests/integration/island_probing.gd"
## 寄り道のワールド（O1〜O3）を自動で遊ぶテストの共通部品（ファイル名が test_ で始まらないので、これ自体は
## 実行されない）。操作はプレイヤーと同じ（move_intent・view_yaw・press_action と、渡す・拾う・F）だけで、
## 瞬間移動や状態の書き換えはしない。
## 歩くときは、手元にある移動の能力（W が無ければ A・D・S）で、視点を回してその向きへ進む
## （W を貸していても、視点を回せば D だけで好きな方へ歩ける。ADR 0013 の受け入れた操作）。

const BACK := RuleAction.Kind.BACK
const RIGHT := RuleAction.Kind.RIGHT
const HEAVY := RuleAction.Kind.HEAVY
const FLOAT := RuleAction.Kind.FLOAT
const SWIM := RuleAction.Kind.SWIM
const CLIMB := RuleAction.Kind.CLIMB

var _was_near: bool = false


func _mech() -> MechanismSet:
	return MechanismSet.of(w)


func _door(key: String) -> SwitchDoor:
	for door in _mech().doors:
		if door.spec.key == key:
			return door
	return null


func _active(key: String) -> bool:
	return _mech().is_source_active(key)


## 条件が真になるまで待つ（来なければ false。失敗にはしない）。
func _wait(condition: Callable, frames: int = 600) -> bool:
	for i in frames:
		if condition.call():
			return true
		await tree.physics_frame
	return condition.call()


func _wait_open(key: String, frames: int = 600) -> bool:
	return await _wait(func() -> bool: return _door(key).is_open(), frames)


## 手元の移動の能力でいちばん使いやすいもの（W・D・A・S の順）。無ければ -1。
func _move_axis() -> Vector2:
	var me := _me().player_id
	if w.ledger.player_can(FORWARD, me):
		return Vector2(0.0, 1.0)
	if w.ledger.player_can(RIGHT, me):
		return Vector2(1.0, 0.0)
	if w.ledger.player_can(LEFT, me):
		return Vector2(-1.0, 0.0)
	if w.ledger.player_can(BACK, me):
		return Vector2(0.0, -1.0)
	return Vector2.ZERO


## 手元の移動の能力の向きが target を向くように視点を回し、その移動の入力を返す。
func _steer(target: Vector3) -> Vector2:
	var flat := Vector3(target.x - _me().global_position.x, 0.0, target.z - _me().global_position.z)
	var axis := _move_axis()
	if flat.length() < 0.0001:
		return axis
	var dir := flat.normalized()
	if axis == Vector2(1.0, 0.0):
		_me().view_yaw = atan2(-dir.z, dir.x)
	elif axis == Vector2(-1.0, 0.0):
		_me().view_yaw = atan2(dir.z, -dir.x)
	elif axis == Vector2(0.0, -1.0):
		_me().view_yaw = atan2(dir.x, dir.z)
	else:
		_me().view_yaw = atan2(-dir.x, -dir.z)
	return axis


## island_playthrough の歩き方を、W が無くても歩けるように広げたもの（段差で止まったら跳ぶ）。
func _try_walk_to(target: Vector3, tolerance: float = 0.35, frames: int = 1200) -> bool:
	var stuck := 0
	for i in frames:
		var flat := Vector3(
			target.x - _me().global_position.x, 0.0, target.z - _me().global_position.z
		)
		if flat.length() <= tolerance and absf(_me().global_position.y - target.y) < 0.7:
			_me().move_intent = Vector2.ZERO
			return true
		_me().move_intent = _steer(target)
		var moving := Vector2(_me().velocity.x, _me().velocity.z).length() > 0.5
		stuck = 0 if moving else stuck + 1
		if stuck > 8 and _me().is_on_floor():
			w.press_action(JUMP)
			stuck = 0
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	return false


## 付与先に触って渡す（届く所に立っている前提）。
func _give(target: Node3D, action: RuleAction.Kind, mode: TriggerMode.Kind) -> void:
	var slot := _slot_of(action)
	assert_ne(slot, -1, "%s is on the hotbar" % action)
	_lend(target, slot, mode)


## 生き物に能力を渡す（生き物には方式が無い）。
func _give_creature(key: String, actions: Array[RuleAction.Kind]) -> void:
	for action in actions:
		_give(_creature(key), action, TriggerMode.Kind.NONE)


## 生き物に付いているものを F で全部回収する（届く所に立っている前提。届くまで待つ）。
func _recall_creature(key: String) -> void:
	var critter := _creature(key)
	for i in 300:
		if w.ledger.tokens_on(critter.entity_id).is_empty():
			break
		if w.is_within_reach(critter):
			w.interact(critter)
		await tree.physics_frame
	assert_true(w.ledger.tokens_on(critter.entity_id).is_empty(), "recalled from %s" % key)


## 落ちている器を拾ってホットバーの空きへ置く（すでにホットバーにある同じ能力があってもよい）。
func _pick(at: Vector3, action: RuleAction.Kind) -> int:
	return await _pick_to_hotbar(at, action)


## ブロックがあるセルに着いて止まるまで待つ。
func _wait_block_at(key: String, cell: Vector3i, frames: int = 900) -> bool:
	var block := _block(key)
	return await _wait(
		func() -> bool:
			return (
				block.cell() == cell and not block.is_moving_horizontally() and block.is_grounded()
			),
		frames
	)


## 生き物が巣の箱に入るまで待ち、入ったら true。
func _creature_home(key: String, nest: AABB, frames: int = 2400) -> bool:
	return await _wait_creature_in(key, nest, frames)


## ワープの石（stone はその床の真ん中）へ歩いて乗り、別の場所へ移ったら止まる。移れたら true。
func _ride_warp(stone: Vector3, frames: int = 900) -> bool:
	for i in frames:
		var flat := Vector3(stone.x - _me().global_position.x, 0.0, stone.z - _me().global_position.z)
		if flat.length() > 6.0 and i > 0 and _was_near:
			_me().move_intent = Vector2.ZERO
			_was_near = false
			await wait_physics_frames(20)
			return true
		_was_near = _was_near or flat.length() < 1.5
		_me().move_intent = Vector2.ZERO if flat.length() < 0.15 else _steer(stone)
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	_was_near = false
	return false
