extends "res://tests/integration/island_probing.gd"
## ワールド 7「空の頂」の通しプレイ・試遊の共通部品（ファイル名が test_ で始まらないので、これ自体は実行されない）。
## 歩く・跳ぶ・渡す・拾うなどは island_playthrough.gd、関所の試し方は island_probing.gd。
## ここには、浮く・重い・風・水・仕掛けを使う操作を足す。どれもプレイヤーと同じ操作だけで、瞬間移動しない。

const FLOAT := RuleAction.Kind.FLOAT
const HEAVY := RuleAction.Kind.HEAVY
const SWIM := RuleAction.Kind.SWIM
const RIGHT := RuleAction.Kind.RIGHT
const BACK := RuleAction.Kind.BACK


## 脈打つ風が index 番目（StageDef.nature.winds の順）で、いま吹いているか（木の葉が流れているかを見るのと同じ）。
func _wind_blowing(index: int) -> bool:
	var field := w.nature
	return field.layout.winds[index].is_blowing(field.clock)


## 脈打つ風がやみ始める（吹いている → やんだ）まで待つ。
func _wait_for_calm(index: int, frames: int = 600) -> void:
	for i in frames:
		if _wind_blowing(index):
			break
		await tree.physics_frame
	for i in frames:
		if not _wind_blowing(index):
			return
		await tree.physics_frame


## 脈打つ風が吹き始める（やんでいた → 吹いた）まで待つ。
func _wait_for_gust(index: int, frames: int = 600) -> void:
	for i in frames:
		if not _wind_blowing(index):
			break
		await tree.physics_frame
	for i in frames:
		if _wind_blowing(index):
			return
		await tree.physics_frame


## start から land の向きへ走り、床の縁の edge_offset 手前で跳び、頂点で
## 空中ダッシュする。land に着いたら true。
func _dash_glide(start: Vector3, edge_offset: float, land: Vector3, dash_slot: int) -> bool:
	assert_ne(dash_slot, -1, "has a dash")
	await _walk_to(start, 0.25)
	var dir := _face(land).normalized()
	_me().move_intent = Vector2(0.0, 1.0)
	var ground_edge := _edge_ahead(start, dir) - edge_offset
	for i in 120:
		if _me().global_position.dot(dir) >= ground_edge and _me().is_on_floor():
			break
		await tree.physics_frame
	w.press_action(JUMP)
	for i in 60:
		await tree.physics_frame
		if _me().velocity.y < 0.0:
			break
	w.press_action(DASH)
	return await _try_walk_to(land, 0.6, 300)


## start から dir へ進んだとき、足もとの床が途切れる位置（dir の向きの座標）。
func _edge_ahead(start: Vector3, dir: Vector3) -> float:
	var cell_y := floori(start.y - 0.5)
	var p := start
	for i in 40:
		var next := p + dir * 0.5
		if (
			w.terrain == null
			or not w.terrain.cells.has(Vector3i(floori(next.x), cell_y, floori(next.z)))
		):
			return next.dot(dir) - 0.5
		p = next
	return p.dot(dir)


## 扉（key）が開ききるまで待つ。
func _wait_door_open(key: String, frames: int = 240) -> bool:
	for i in frames:
		if _door_open_amount(key) > 0.95:
			return true
		await tree.physics_frame
	return false


## 扉（key）の開き具合（0 = 閉じている、1 = 開いている。無ければ -1）。
func _door_open_amount(key: String) -> float:
	var mechanisms := MechanismSet.of(w)
	if mechanisms != null:
		for door in mechanisms.doors:
			if door.spec.key == key:
				return door.open_amount
	return -1.0


## 生き物に付いているものを F で全部回収する（届く所で）。
func _recall_creature(key: String) -> void:
	var critter := _creature(key)
	for i in 300:
		if w.ledger.tokens_on(critter.entity_id).is_empty():
			break
		if w.is_within_reach(critter):
			w.interact(critter)
		await tree.physics_frame
	assert_true(w.ledger.tokens_on(critter.entity_id).is_empty(), "recalled from %s" % key)


## ワープなどで、自分が at の近く（水平 1.2 以内・高さ ±0.7）へ移るまで待つ。
func _wait_arrival(at: Vector3, frames: int = 240) -> bool:
	for i in frames:
		var flat := _me().global_position - at
		if Vector2(flat.x, flat.z).length() < 1.2 and absf(flat.y) < 0.7:
			_me().move_intent = Vector2.ZERO
			return true
		await tree.physics_frame
	return false


## ワープの石（stone の位置）へ歩いて乗り、arrival の近くへ移ったら止まる。移れたら true。
func _step_onto_warp(stone: Vector3, arrival: Vector3, frames: int = 240) -> bool:
	for i in frames:
		var flat := _me().global_position - arrival
		if Vector2(flat.x, flat.z).length() < 1.2 and absf(flat.y) < 0.7:
			_me().move_intent = Vector2.ZERO
			await wait_physics_frames(2)
			return true
		_face(stone)
		var near := Vector2(stone.x - _me().global_position.x, stone.z - _me().global_position.z)
		_me().move_intent = Vector2(0.0, 1.0) if near.length() > 0.15 else Vector2.ZERO
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	return false


## かばん（通常インベントリ）にある action の器を、ホットバーの空きへ移す（回収して拾った物を使うため）。
func _bag_to_hotbar(action: RuleAction.Kind) -> int:
	var slot := _free_slot()
	for v in w.ledger.inventory_vessels(_me().player_id):
		var t := w.ledger.token(v.token_id)
		if t.action == action and not t.is_prohibition:
			assert_true(w.ledger_actions.move_to_hotbar(v.id, slot), "%s to the hotbar" % action)
			return slot
	if _picked_slot(action) != -1:
		return _picked_slot(action)  # 拾ったときにホットバーへ入っていた
	fail("no %s in the bag" % action)
	return -1


## ブロック（key）がマス cell に着いて止まるまで待つ。
func _wait_block_at(key: String, cell: Vector3i, frames: int = 1500) -> bool:
	var block := _block(key)
	for i in frames:
		if block.cell() == cell and not block.is_moving_horizontally():
			return true
		await tree.physics_frame
	print("    %s stopped at %s" % [key, block.cell()])
	return false


## 泳いで（または浮いて流されながら）target へ向かう。岸の手前では跳んで上がる。着いたら true。
func _swim_to(target: Vector3, frames: int = 900) -> bool:
	for i in frames:
		var flat := _face(target)
		var me := _me().global_position
		if flat.length() <= 0.5 and absf(me.y - target.y) < 0.7 and _me().is_on_floor():
			_me().move_intent = Vector2.ZERO
			return true
		_me().move_intent = Vector2(0.0, 1.0)
		# 水面（岸より低い）にいる間は、ときどき跳ぶ（岸に着いていれば上がれる。川の中で跳んでも戻るだけ）
		if target.y > me.y + 0.3 and i % 15 == 0:
			w.press_action(JUMP)
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	print("    swim to %s stopped at %s" % [target, _me().global_position])
	return false


## 浮いて流され、x が until_x を越えたら landing の方へ跳んで上がる。上がれたら true。
func _drift_until(until_x: float, landing: Vector3, frames: int = 1200) -> bool:
	for i in frames:
		if _me().global_position.x >= until_x:
			break
		_me().move_intent = Vector2.ZERO
		await tree.physics_frame
	return await _swim_to(landing, 300)


## W を持っていないとき（貸している間）に、後ろ向きに S で target へ歩く。着いたら true。
func _back_to(target: Vector3, tolerance: float = 0.35, frames: int = 900) -> bool:
	for i in frames:
		var flat := Vector3(
			target.x - _me().global_position.x, 0.0, target.z - _me().global_position.z
		)
		if flat.length() <= tolerance:
			_me().move_intent = Vector2.ZERO
			return true
		_me().view_yaw = atan2(flat.x, flat.z)  # target に背を向ける
		_me().move_intent = Vector2(0.0, -1.0)
		await tree.physics_frame
	_me().move_intent = Vector2.ZERO
	fail("could not back up to %s (at %s)" % [target, _me().global_position])
	return false


## 石（key）に W を繰り返しで渡し、北の石垣で cell に止まったら、後ろ向きに近づいて回収する。
func _slide_north(key: String, stand: Vector3, stop: Vector3i) -> void:
	var stone := _block(key)
	await _walk_to(stand, 0.3)
	_lend(stone, _slot_of(FORWARD), TriggerMode.Kind.REPEAT)
	assert_true(await _wait_block_at(key, stop), "%s slid to %s" % [key, stop])
	await _back_to(stone.global_position + Vector3(0.0, -0.5, 1.6))
	await _recall_all_from(key)


## stand に立ったまま（前へ進まず）、その場で跳びながら鐘（key）へ F を押し続ける。鳴ったら true。
func _ring_in_place(key: String, stand: Vector3) -> bool:
	var bell := w.bells_by_key[key]
	await _walk_to(stand, 0.25)
	for i in 120:
		_face(bell.global_position)
		_me().move_intent = Vector2.ZERO
		if _me().is_on_floor():
			w.press_action(JUMP)
		w.interact(bell)
		await tree.physics_frame
	return w.activated.has(key)


## ホットバーの action をかばんへ戻す（持っているだけで効く性質を、一時的に効かなくする）。
func _hotbar_to_bag(action: RuleAction.Kind) -> void:
	var slot := _slot_of(action)
	assert_ne(slot, -1, "%s is on the hotbar" % action)
	var v := w.ledger.hotbar_vessel(slot, _me().player_id)
	assert_true(w.ledger_actions.move_to_inventory(v.id), "%s to the bag" % action)
