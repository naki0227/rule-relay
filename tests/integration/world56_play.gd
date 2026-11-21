extends "res://tests/integration/island_probing.gd"
## ワールド 5・6 の通しプレイと試遊で使う、ワープ・氷・水・風・持ち物の入れ替えの操作の部品（ファイル名が test_ で
## 始まらないので、これ自体は実行されない）。どれもプレイヤーと同じ操作（move_intent・view_yaw・
## press_action と、渡す・回収・拾う・インベントリの入れ替え）で、瞬間移動はしない。

const RIGHT := RuleAction.Kind.RIGHT
const FLOAT := RuleAction.Kind.FLOAT
const SWIM := RuleAction.Kind.SWIM
const HEAVY := RuleAction.Kind.HEAVY


## ワープの石へ歩いて乗る。移されたら（位置が大きく跳んだら）止まって true。
func _step_on_warp(at: Vector3, frames: int = 600) -> bool:
	var last := _me().global_position
	for i in frames:
		var now := _me().global_position
		if now.distance_to(last) > 3.0:
			_me().move_intent = Vector2.ZERO
			await wait_physics_frames(4)
			return true
		last = now
		_face(at)
		_me().move_intent = Vector2(0.0, 1.0)
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	fail("the warp at %s did not move me (at %s)" % [at, _me().global_position])
	return false


## 水の中を target へ泳ぐ（水面からは跳べるので、岸に当たって進めなければ跳ぶ）。
func _swim_to(target: Vector3, frames: int = 900) -> bool:
	var stuck := 0
	for i in frames:
		var flat := _face(target)
		var on_level := absf(_me().global_position.y - target.y) < 0.7
		if flat.length() <= 0.5 and on_level and _me().is_on_floor():
			_me().move_intent = Vector2.ZERO
			return true
		_me().move_intent = Vector2(0.0, 1.0)
		var moving := Vector2(_me().velocity.x, _me().velocity.z).length() > 0.5
		stuck = 0 if moving else stuck + 1
		if stuck > 8:
			w.press_action(JUMP)
			stuck = 0
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	fail("could not swim to %s (at %s)" % [target, _me().global_position])
	return false


## 足もとに落ちている器を拾う（通常インベントリへ）。
func _pick_up_here(at: Vector3) -> void:
	await _walk_to(at, 0.6)
	var before := w.ledger.inventory_vessels(_me().player_id).size()
	w.interact(null)
	await wait_physics_frames(2)
	assert_eq(
		w.ledger.inventory_vessels(_me().player_id).size(), before + 1, "picked up at %s" % at
	)


## 通常インベントリの能力（禁止ではない）を、ホットバーの空きへ移す。移した枠を返す。
func _to_hotbar(action: RuleAction.Kind) -> int:
	var slot := _free_slot()
	for v in w.ledger.inventory_vessels(_me().player_id):
		var t := w.ledger.token(v.token_id)
		if t.action == action and not t.is_prohibition:
			assert_true(w.ledger_actions.move_to_hotbar(v.id, slot), "%s to the hotbar" % action)
			return slot
	fail("no %s in the inventory" % action)
	return -1


## ホットバーの能力（禁止ではない）を通常インベントリへ戻す（効かなくなる）。
func _to_inventory(action: RuleAction.Kind) -> void:
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, _me().player_id)
		if v == null:
			continue
		var t := w.ledger.token(v.token_id)
		if t.action == action and not t.is_prohibition:
			assert_true(w.ledger_actions.move_to_inventory(v.id), "%s to the inventory" % action)
			return
	fail("no %s on the hotbar" % action)


## edge（崖の縁の手前）から dir へ走って跳び、空中も進んで、land の上に来たら手を離して降りる。
## 浮く・追い風で遠くへ渡るとき用（行き過ぎないよう、真上で W を離す。人も同じ）。
func _leap_to(edge: Vector3, land: Vector3, frames: int = 400) -> bool:
	await _walk_to(edge, 0.25)
	for i in 30:
		if _me().is_on_floor():
			break
		await tree.physics_frame
	var airborne := false
	w.press_action(JUMP)
	for i in frames:
		var flat := _face(land)
		var p := _me().global_position
		airborne = airborne or not _me().is_on_floor()
		if airborne and _me().is_on_floor():
			_me().move_intent = Vector2.ZERO
			return flat.length() < 2.0 and absf(p.y - land.y) < 0.4
		_me().move_intent = Vector2(0.0, 1.0) if flat.length() > 0.4 else Vector2.ZERO
		if p.y < land.y - 3.0:
			break
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	return false


## 動いている台（筏など）の上へ歩いて乗る。
func _board(block: RuleBlock, frames: int = 600) -> bool:
	for i in frames:
		var top := block.global_position + Vector3(0.0, 0.5, 0.0)
		var flat := _face(top)
		var above := absf(_me().global_position.y - top.y) < 0.3
		if flat.length() < 0.25 and above and _me().is_on_floor():
			_me().move_intent = Vector2.ZERO
			return true
		_me().move_intent = Vector2(0.0, clampf(flat.length(), 0.3, 1.0))
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	return false


## 後ろ向きに歩く（target に背を向けて S。W を貸している間の歩き方）。
func _back_to(target: Vector3, frames: int = 900) -> bool:
	for i in frames:
		var flat := Vector3(
			target.x - _me().global_position.x, 0.0, target.z - _me().global_position.z
		)
		if flat.length() <= 0.35:
			_me().move_intent = Vector2.ZERO
			return true
		_me().view_yaw = atan2(flat.x, flat.z)
		_me().move_intent = Vector2(0.0, -1.0)
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	return false


func _wait_block_at(key: String, cell: Vector3i, frames: int = 900) -> void:
	var block := _block(key)
	for i in frames:
		if block.cell() == cell and not block.is_moving_horizontally():
			break
		await tree.physics_frame
	assert_eq(block.cell(), cell, "%s stopped at %s" % [key, cell])
