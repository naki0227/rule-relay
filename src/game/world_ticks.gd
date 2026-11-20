class_name WorldTicks
extends RefCounted
## GameWorld の毎フレームの仕事のうち、ホストだけが行うもの（ブロックの登る・発射台・落ちた物の救済）。
## GameWorld が長くなりすぎたので切り出した（WorldSnapshot と同じく GameWorld の中身を直接使う）。


## 登るを持つブロック: 東西南北の隣でいちばん高い上面に、自分の上面がそろうまで登る（rule_block.gd）。
## 禁止は優先（登る禁止を持てば登らない）。
static func climbers(w: GameWorld) -> void:
	for id in w.blocks:
		var block := w.blocks[id]
		if not w.ledger.can_initiate(id, RuleAction.Kind.CLIMB):
			block.set_climb_target(NAN)
			continue
		var c := block.cell()
		var heights := w.survey_heights(Vector2i(c.x, c.z), 1)
		var top := -INF
		for dir: Vector2i in CreatureMind.DIRECTIONS:
			var n := Vector2i(c.x, c.z) + dir
			if heights.has(n):
				top = maxf(top, float(heights[n]))
		block.set_climb_target(NAN if top == -INF else top - RuleBlock.SIZE)


## 発射台: 「投げる」を自分から使える（持っていて禁止されていない）間だけ、周期ごとに玉を撃つ。
## 投げるを n 個持てば玉の速さ（射程）が n 倍。
static func launchers(w: GameWorld, delta: float) -> void:
	for id in w._launchers:
		if not w.ledger.can_initiate(id, RuleAction.Kind.THROW):
			w._launch_timers[id] = Tuning.REPEAT_PERIOD - 0.3  # 渡されたらすぐ1発目を撃つ
			continue
		w._launch_timers[id] += delta
		if w._launch_timers[id] < Tuning.REPEAT_PERIOD:
			continue
		w._launch_timers[id] = 0.0
		var dir := Vector3(w._launchers[id])
		var block := w.blocks[id]
		var from := block.global_position + dir * 0.65 + Vector3(0.0, 0.2, 0.0)
		var stack := Tuning.stack_factor(
			PartyQuery.entity_count(w.ledger, id, RuleAction.Kind.THROW)
		)
		w.throw_ball(from, dir * Tuning.THROW_SPEED * stack + Vector3(0.0, 2.0, 0.0), block)


## 島の外へ落ちきったブロックを救済する（仮の方針、docs/TODO.md）: 付いていた能力・禁止のうち
## 誰かが付与したものは、直前に付与した人へ戻し、ブロックは最初の位置に戻す。
## レベルに置かれていた能力・禁止はブロックに残る。
static func rescue_lost(w: GameWorld) -> void:
	for id in w.blocks:
		var block := w.blocks[id]
		if block.global_position.y >= Tuning.FALL_LIMIT_Y:
			continue
		var returned := _return_lent(w, id)
		block.teleport(RuleBlock.cell_center(w._home_cells[id]), 0.0)
		var note := "（貸していた %d 個は手元に戻りました）" % returned if returned > 0 else ""
		w._post("島から落ちたブロックを元の位置に戻しました%s" % note)
	for id in w.creatures:
		var creature := w.creatures[id]
		if creature.global_position.y >= Tuning.FALL_LIMIT_Y:
			continue
		_return_lent(w, id)
		creature.restore_state({"position": w._creature_homes[id], "velocity": Vector3.ZERO})
		w._post("島から落ちた生き物を元の場所に戻しました")


static func _return_lent(w: GameWorld, entity_id: int) -> int:
	var returned := 0
	for t in w.ledger.tokens_on(entity_id):
		var to := t.lender_id if w.ledger.players().has(t.lender_id) else RuleLedger.PLAYER_ID
		if t.vessel_id != -1 and w.ledger.recall(t.id, to):
			returned += 1
	return returned
