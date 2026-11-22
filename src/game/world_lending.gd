class_name WorldLending
extends RefCounted
## 渡す操作（ブロック・生き物・地形のセル・仲間へ）。GameWorld が長くなりすぎないよう切り出した。
## 届き方が「投げる」なら、ここではメダルを投げるだけで、付与は当たったときに MedalThrow.land が
## lend_token / give_token を呼ぶ（docs/adr/0017）。「触る」ならその場で付与する。

## 持っているだけで効く性質（拾っても自動ではホットバーへ入れない。to_hotbar_if_free）。
const TRAITS: Array[RuleAction.Kind] = [
	RuleAction.Kind.HEAVY, RuleAction.Kind.FLOAT, RuleAction.Kind.SWIM
]


## 選択中のホットバーの器から、target（ブロック・生き物・地形のセル）へ付与する。
static func lend(w: GameWorld, target: Node3D, use_range: bool) -> RuleLedger.LendResult:
	var v := w.selected_vessel()
	if v == null:
		w._post("ホットバー %d は空です" % (w.selected_slot + 1))
		w._ui_sound(&"ui_error")
		return RuleLedger.LendResult.NO_SUCH_VESSEL
	if target == null or not w.is_within_reach(target):
		w._post("届きません（%s: %.1fブロック）" % ["投げる" if w.throw_mode else "触る", w.reach()])
		w._ui_sound(&"ui_error")
		return RuleLedger.LendResult.NO_TARGETS
	var refusal := _refuse_in_flight(w, v.token_id)
	if refusal == RuleLedger.LendResult.OK:
		refusal = refuse_target(w, target, use_range)
	if refusal != RuleLedger.LendResult.OK:
		return refusal
	if not (w.throw_mode and w.can_throw()):  # 足もとの「投げる禁止」で投げられないときは触る
		return lend_token(w, v.token_id, w.acting_id(), target, use_range, w.lend_mode)
	# 投げる: メダルを投げ、実際に当たった物へ付与する
	var t := w.ledger.token(v.token_id)
	if not t.is_in_vessel():
		w._post(WorldQueries.describe(t, RuleLedger.LendResult.ALREADY_LENT, use_range))
		w._ui_sound(&"ui_error")
		return RuleLedger.LendResult.ALREADY_LENT
	MedalThrow.start(w, target, use_range, v.token_id)
	return RuleLedger.LendResult.OK


## 仲間へ能力を渡す（受け手の承認なし。2026-11-19 本人確定）。選んでいる枠の能力から渡す。
## 枠の器が空なら、受け取って持っている同じ種類の能力を渡す。
static func give(w: GameWorld, target: PlayerAvatar) -> RuleLedger.LendResult:
	var token_id := WorldQueries.giveable_token(w.ledger, w.acting_id(), w.selected_slot)
	if token_id == -1 or not w.is_within_reach(target):
		w._post("渡せる能力がないか、届きません")
		w._ui_sound(&"ui_error")
		return RuleLedger.LendResult.NO_TARGETS
	var refusal := _refuse_in_flight(w, token_id)
	if refusal != RuleLedger.LendResult.OK:
		return refusal
	if w.throw_mode:
		MedalThrow.start(w, target, false, token_id)  # 当たった相手へ
		return RuleLedger.LendResult.OK
	return give_token(w, token_id, w.acting_id(), target)


## 鐘・範囲で渡せない相手なら理由を出し、その結果を返す（渡せるなら OK）。
static func refuse_target(w: GameWorld, target: Node3D, use_range: bool) -> RuleLedger.LendResult:
	if target is Bell:
		w._post("鐘には渡せません（%s で鳴らす）" % InputMode.token(&"interact"))
		w._ui_sound(&"ui_error")
		return RuleLedger.LendResult.UNKNOWN_TARGET
	if use_range and not (target is RuleBlock or target is TerrainCell):
		w._post("生き物には範囲で渡せません（%s で1匹に渡す）" % InputMode.token(&"lend_single"))
		w._ui_sound(&"ui_error")
		return RuleLedger.LendResult.RANGE_ONLY_FOR_BLOCKS
	return RuleLedger.LendResult.OK


## 投げたメダルがまだ飛んでいるなら、理由を出して ALREADY_LENT（同じ能力を二重に渡さない）。
static func _refuse_in_flight(w: GameWorld, token_id: int) -> RuleLedger.LendResult:
	if not MedalThrow.in_flight(w, token_id):
		return RuleLedger.LendResult.OK
	w._post("投げたメダルがまだ飛んでいます")
	w._ui_sound(&"ui_error")
	return RuleLedger.LendResult.ALREADY_LENT


## by_player の手元のトークンを target（ブロック・生き物・地形のセル）へ付与する。届く距離は呼び出し側で確かめる
## （触るなら lend。投げたメダルは当たった物なので確かめない）。範囲なら target の層の円内の全ブロックへ。
static func lend_token(
	w: GameWorld,
	token_id: int,
	by_player: int,
	target: Node3D,
	use_range: bool,
	chosen: TriggerMode.Kind
) -> RuleLedger.LendResult:
	var t := w.ledger.token(token_id)
	var mode := TriggerMode.Kind.NONE if t.is_prohibition else chosen
	var result := refuse_target(w, target, use_range)
	if result != RuleLedger.LendResult.OK:
		return result
	if target is TerrainCell:
		target = TerrainPromotion.promote(w, (target as TerrainCell).cell)
	if use_range:
		var selection := w.range_selection(target)
		var ids := selection["ids"] as PackedInt32Array
		for cell: Vector3i in selection["cells"] as Array:
			# 範囲内の地形のセルも、全部ブロックとして受け取る
			ids.append(TerrainPromotion.promote(w, cell).entity_id)
		selection["ids"] = ids
		result = w.ledger.lend_token(token_id, by_player, ids, mode, selection)
	else:
		var single := PackedInt32Array([int(target.get("entity_id"))])
		result = w.ledger.lend_token(token_id, by_player, single, mode)
	w._post(WorldQueries.describe(t, result, use_range))
	if result != RuleLedger.LendResult.OK:
		w._ui_sound(&"ui_error")
		return result
	# 法則の音（能力ごとの音程）と、受け取った物が自分の材質の声で応える音
	var motif := (
		"%s@%d" % ["lend_range" if use_range else "lend", RuleAction.motif_semitone(t.action)]
	)
	w._sound(StringName(motif), target.global_position)
	w._sound(WorldQueries.receive_sound(target), target.global_position)
	for holder in t.holder_ids:
		# 付与してすぐ動き出すように、最初の周期を短くする
		if mode == TriggerMode.Kind.SIGNAL:
			w._signal_timers[holder] = Tuning.REPEAT_PERIOD - 0.25
		elif mode == TriggerMode.Kind.REPEAT:
			w._repeat_timers[holder] = Tuning.REPEAT_PERIOD - 0.25
	return result


## from_player の手元のトークンを仲間 target へ渡す（届く距離は呼び出し側で確かめる）。
static func give_token(
	w: GameWorld, token_id: int, from_player: int, target: PlayerAvatar
) -> RuleLedger.LendResult:
	var result := w.ledger.give_to_player(token_id, from_player, target.player_id)
	var t := w.ledger.token(token_id)
	if result == RuleLedger.LendResult.OK:
		w._post("%s を仲間に渡しました" % t.describe())
		w._sound(&"lend", target.global_position)
	else:
		w._post(WorldQueries.describe(t, result, false))
		w._ui_sound(&"ui_error")
	return result


## ブロック・生き物・地形に最初から付いていた（だれの器にも入っていなかった）能力・禁止を F で取ったら、
## ホットバーに空きがあればそこへ入れる（docs/w1-teaching.md）。2026-11-22: 初めての人が F で取ったジャンプを
## 「かばんを開いて並べる」まで使えず止まっていたため。自分の器の能力は今までどおり器へ戻り、落ちている器を
## 拾ったときは今までどおり通常インベントリへ（ほかのワールドの拾う遊びを変えない）。持っているだけで効く性質
## （重い・浮く・泳ぐ。ホットバーに置くと勝手に効く）は、かばんへ。
static func to_hotbar_if_free(w: GameWorld, tokens: Array[RuleToken]) -> void:
	var ledger := w.ledger
	var me := w.acting_id()
	for t in tokens:
		var v := ledger.vessel(t.vessel_id) if t != null else null
		if v == null or v.owner_id != me or v.location != RuleVessel.Location.INVENTORY:
			continue
		if v.is_equipment() or t.action in TRAITS:
			continue
		for slot in RuleLedger.HOTBAR_SIZE:
			if ledger.hotbar_vessel(slot, me) == null:
				ledger.move_to_hotbar(v.id, slot)
				break
