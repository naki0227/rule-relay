class_name NatureTicks
extends RefCounted
## ホストだけが毎フレーム行う、自然の仕掛けの仕事（ブロック・生き物・落ちている器。docs/adr/0015）。
## GameWorld._physics_process から WorldTicks の後に呼ぶ（登るの目標を、水に浮く目標で上書きするため）。
##
## ブロック（マス単位の箱庭のまま動かす）:
## - 浮く（重さが負）: 空中ではゆっくり落ち、水ではいちばん上の水のセルに浮かぶ（上面が岸とそろう）。
##   浮いたブロックは床に立つのと同じ扱いで、自分の W/A/S/D・ジャンプも使え、流れに 1 マスずつ運ばれる。
## - 浮かないブロックは水に沈む（底なしなので、島から落ちたブロックと同じく元の位置へ戻る）。
## - 氷: 最後まで進み切った横の移動の後、下が氷なら同じ向きにもう 1 マスすべる（塞がれるまで続く）。
## - 風: 床に立って止まっているブロックを、風下へ 1 マスずつ運ぶ（重いブロックは運ばない）。
## 生き物: 風・流れで押され、浮く・泳ぐなら水面に浮かぶ（泳げなければ沈み、元の場所へ戻る）。
## 落ちている器: 風・流れで 1 マスずつ運ばれる。崖の下へは落とさず、壁は越えない（地形で止まる）。


static func run(w: GameWorld, delta: float) -> void:
	var field := w.nature
	for id in w.blocks:
		_block(w, field, id, delta)
	for id in w.creatures:
		_creature(w, field, w.creatures[id])
	if not field.layout.is_empty():
		_items(w, field, delta)


static func _block(w: GameWorld, field: NatureField, id: int, delta: float) -> void:
	var block := w.blocks[id]
	var weight := BodyTraits.weight(w.ledger, id)
	var finished := block.consume_finished_step()
	block.max_fall_speed = NatureTuning.fall_limit(-weight)
	block.afloat = false
	var water := field.water_at(block.global_position)
	if water != null:
		_block_in_water(field, block, water, weight, delta)
		return
	if finished != Vector3i.ZERO and block.is_grounded():
		if field.is_ice(block.cell() + Vector3i.DOWN):
			block.push(finished, NatureTuning.ICE_STEP_DURATION)
			return
	var dir := Vector3i.ZERO
	if weight <= 0:
		dir = field.wind_direction_at(block.global_position)
	_drift_block(field, block, dir, delta)


static func _block_in_water(
	field: NatureField, block: RuleBlock, water: NatureLayout.WaterSpec, weight: int, delta: float
) -> void:
	if weight >= 0:
		block.max_fall_speed = NatureTuning.BLOCK_SINK_SPEED
		field.drift_timers.erase(block.entity_id)
		return
	block.set_climb_target(water.float_bottom())
	var bottom := block.global_position.y - RuleBlock.SIZE * 0.5
	block.afloat = absf(bottom - water.float_bottom()) < 0.05
	var dir := water.current if block.afloat else Vector3i.ZERO
	if dir == Vector3i.ZERO and block.afloat:
		dir = field.wind_direction_at(block.global_position)
	_drift_block(field, block, dir, delta)


## 床に立つ（浮いている）止まったブロックを、間隔ごとに dir へ 1 マス運ぶ。
static func _drift_block(field: NatureField, block: RuleBlock, dir: Vector3i, delta: float) -> void:
	var id := block.entity_id
	if dir == Vector3i.ZERO or block.is_moving_horizontally() or not block.is_grounded():
		field.drift_timers.erase(id)
		return
	var waited := float(field.drift_timers.get(id, 0.0)) + delta
	if waited < NatureTuning.DRIFT_PERIOD:
		field.drift_timers[id] = waited
		return
	field.drift_timers.erase(id)
	block.push(dir)


static func _creature(w: GameWorld, field: NatureField, c: Creature) -> void:
	var weight := BodyTraits.weight(w.ledger, c.entity_id)
	var push := Vector3.ZERO
	c.max_fall_speed = NatureTuning.fall_limit(-weight)
	c.surface_hold = NAN
	var water := field.water_at(c.global_position)
	if water != null:
		push += water.flow()
		var swims := BodyTraits.swim_level(w.ledger, c.entity_id) > 0
		if weight < 0 or (weight == 0 and swims):
			c.surface_hold = water.surface_y() - NatureTuning.AFLOAT_DEPTH * 0.6
	if weight <= 0:
		push += field.wind_at(c.global_position)
	c.external_velocity = Vector3(push.x, 0.0, push.z)


## 落ちている器（器と、退出した人の手元から落ちた能力）を、風・流れで 1 マスずつ運ぶ。
static func _items(w: GameWorld, field: NatureField, delta: float) -> void:
	var moved := false
	for v in w.ledger.world_vessels():
		var to := _item_step(w, field, "v%d" % v.id, v.world_position, delta)
		if to != v.world_position:
			v.world_position = to
			moved = true
	for t in PartyQuery.dropped_tokens(w.ledger):
		var to := _item_step(w, field, "t%d" % t.id, t.drop_position, delta)
		if to != t.drop_position:
			t.drop_position = to
			moved = true
	if moved:
		w.ledger.changed.emit()  # 台帳の写しと見た目（WorldItem）を合わせる


## 器の次の位置（動かなければ at のまま）。
static func _item_step(
	w: GameWorld, field: NatureField, key: String, at: Vector3, delta: float
) -> Vector3:
	var water := field.water_at(at + Vector3(0.0, -0.1, 0.0))
	var dir := Vector3i.ZERO
	if water != null:
		dir = water.current
	if dir == Vector3i.ZERO:
		dir = field.wind_direction_at(at + Vector3(0.0, 0.5, 0.0))
	if dir == Vector3i.ZERO:
		field.drift_timers.erase(key)
		return at
	var waited := float(field.drift_timers.get(key, 0.0)) + delta
	if waited < NatureTuning.DRIFT_PERIOD:
		field.drift_timers[key] = waited
		return at
	field.drift_timers.erase(key)
	return _item_landing(w, field, at, at + Vector3(dir))


## 器を dest へ運べるなら運んだ先の位置、運べなければ at。水の上なら水面に浮かぶ。地面なら、
## いまの高さから上下 0.5 以内の上面にだけ移る（崖の下へは落とさない・壁は越えない）。
static func _item_landing(w: GameWorld, field: NatureField, at: Vector3, dest: Vector3) -> Vector3:
	var cell := Vector2i(floori(dest.x), floori(dest.z))
	var heights := w.survey_heights(cell, 0)
	var dest_water := field.water_at(Vector3(dest.x, at.y - 0.6, dest.z))
	if heights.has(cell) and absf(float(heights[cell]) - at.y) <= 0.5:
		return Vector3(dest.x, float(heights[cell]), dest.z)
	if not heights.has(cell) and dest_water != null:
		return Vector3(dest.x, dest_water.surface_y(), dest.z)
	return at
