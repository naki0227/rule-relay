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


## 繰り返し方式: 周期ごとに行動を試みる（同じ行動の能力が n 個なら n 倍）。
static func repeats(w: GameWorld, delta: float) -> void:
	for id in w.blocks:
		var actions := w.ledger.repeat_actions(id)
		if actions.is_empty():
			w._repeat_timers[id] = 0.0
			continue
		w._repeat_timers[id] += delta
		if w._repeat_timers[id] < Tuning.REPEAT_PERIOD:
			continue
		w._repeat_timers[id] -= Tuning.REPEAT_PERIOD
		var action := w._repeat_cursors[id].next_action(actions) as RuleAction.Kind
		var block := w.blocks[id]
		var result := BlockRules.attempt(w.ledger, id, action, block.is_ready_for(action))
		if result == BlockRules.Attempt.SUCCESS:
			block.perform(action, w._high(id), PartyQuery.entity_count(w.ledger, id, action))


## 信号方式: 音波が届いている間だけ、繰り返しと同じ周期で行動を試みる。途絶えると次の動作は
## 休止し（周期の途中で止まる）、再び届くと続きから再開する。トークンは自動では戻らない（企画書 5.2）。
static func signals(w: GameWorld, delta: float) -> void:
	for id in w.blocks:
		var actions := w.ledger.signal_actions(id)
		var receiving := not actions.is_empty() and w.is_receiving_signal(id)
		w.blocks[id].set_signal_state(not actions.is_empty(), receiving)
		if actions.is_empty():
			w._signal_timers[id] = 0.0
			continue
		if not receiving:
			continue
		w._signal_timers[id] += delta
		if w._signal_timers[id] < Tuning.REPEAT_PERIOD:
			continue
		w._signal_timers[id] -= Tuning.REPEAT_PERIOD
		var action := w._signal_cursors[id].next_action(actions) as RuleAction.Kind
		var block := w.blocks[id]
		var result := BlockRules.attempt(w.ledger, id, action, block.is_ready_for(action))
		if result == BlockRules.Attempt.SUCCESS:
			block.perform(action, w._high(id), PartyQuery.entity_count(w.ledger, id, action))


## 単発をまとめて起動する。同じブロックに同じ行動の単発が n 個あれば、1回だけ n 倍で試みる
## （例: 4人分のジャンプを単発で渡す → 1回の高いジャンプ。2026-11-19 本人確定）。
## 起動したトークンは成否によらず、直前に付与した人へ戻る（付与者が退出していれば落ちる）。
static func fire_single_shots(w: GameWorld, token_ids: PackedInt32Array) -> void:
	var by_holder := {}
	for token_id in token_ids:
		for holder in w.ledger.token(token_id).holder_ids:
			by_holder[holder] = int(by_holder.get(holder, 0)) + 1
	var outcome := {}
	for holder: int in by_holder:
		var action := w.ledger.token(token_ids[0]).action
		var block := w.blocks[holder]
		var result := BlockRules.attempt(w.ledger, holder, action, block.is_ready_for(action))
		if result == BlockRules.Attempt.SUCCESS:
			block.perform(action, w._high(holder), int(by_holder[holder]))
		outcome[holder] = result
	for token_id in token_ids:
		_finish_single_shot(w, token_id, outcome)


static func _finish_single_shot(w: GameWorld, token_id: int, outcome: Dictionary) -> void:
	var t := w.ledger.token(token_id)
	var results: Array[BlockRules.Attempt] = []
	for holder in t.holder_ids:
		results.append(outcome[holder] as BlockRules.Attempt)
	var label := t.describe()
	var drop_at := w.blocks[t.holder_ids[0]].global_position + Vector3(0.0, 0.8, 0.0)
	w.ledger.complete_single_shot(token_id, results, drop_at)
	if BlockRules.single_shot_succeeded(results):
		w._post("単発の %s が成功して戻りました" % label)
	else:
		w._post("単発の %s は動けなかったので、そのまま戻りました" % label)
		var blocked := results.has(BlockRules.Attempt.PROHIBITED)
		w._ui_sound(&"prohibit" if blocked else &"ui_error")
