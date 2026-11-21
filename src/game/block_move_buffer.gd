class_name BlockMoveBuffer
extends RefCounted
## ブロックの W/A/S/D の予約（2026-11-21 本人の判断「W とかの単発がシビア。1マス進ませて。繰り返しの時も予約に」）。
## 規則（docs/adr/0003「横移動の予約」）:
## - 単発・繰り返し・信号で W/A/S/D を起動したとき、ブロックが空中にいる・前の1マス移動の途中なら、失敗に
##   せず予約する。1つのブロックに予約は1つだけ（重ねない）。
## - 予約は、横に動いていない・進む先のマスが「いまの高さで」空いている、になった瞬間に1マスだけ動く。
##   空中でも動き出してよい（ジャンプ → W で縁を越えたら高い段へ乗る）。動いたあとも重力は続く。
## - 着地（地面・水・登るでつかまる高さ）したときに進む先が塞がれていれば、その予約は失敗として使い切る
##   （壁が消えるまで待たない。押したのに後から急に動く、を防ぐ）。待つのは最大 MAX_WAIT 秒。
## - 禁止と能力の判定は、動く瞬間に毎回やり直す。予約中に禁止が付いた・能力を回収されたら動かない。
## - 単発は、そのブロックの予約が動いた／失敗したと決まってから、付与した人へ戻る（範囲単発は全員の結果が
##   そろってから）。予約中に F で回収すれば、予約は消える。予約中のトークンは、もう一度押しても起動しない。
## - ホストだけが持つ状態。チェックポイントや全員リセットで復元したら消す（トークンは貸したまま残るので、
##   もう一度押せば起動できる）。ジャンプとダッシュ、生き物・プレイヤーは対象外。
##
## まとめて動く（2026-11-21 本人「範囲のブロックで右に動かすとかでも、一気に一緒に動いてほしい」。
## docs/adr/0003 決定 6）:
## - 同じ付与（1つのトークン）で同じ瞬間に起動した W/A/S/D は、接している（面で隣り合う）ブロックどうしを
##   1つの組にし、組ごと同じフレームに1マス動く。2×2 を右へ動かしても、隙間は空かない。
## - 組は「全員が動けるときだけ全員動く」。仲間が動いて空くマスは空いているとみなす（同じ向きに同じだけ
##   動くので、仲間どうしはぶつからない）。先頭が壁に当たっていれば、後ろの仲間も動かない（形を崩さない）。
## - 禁止・能力なしの仲間は組から外れ、その場に残る（禁止が上位。そのブロックは壁と同じ扱い）。
## - 組の誰かが空中・1マス移動の途中なら、組ごと予約する。全員が「いまの高さで」進めるようになった瞬間に
##   全員一緒に動く。全員が落ち着いても塞がれていれば、組ごと失敗（最長 MAX_WAIT 秒）。
## - 違う付与のブロックは、今までどおり別々に動く。

## 予約の結果がまだ決まっていない（BlockRules.Attempt のどれでもない）。
const PENDING: int = -1
## 予約が待てる最長の時間（秒）。高く跳んでも着地までに収まる長さ（×4 のジャンプで滞空 2 秒）。
const MAX_WAIT: float = 4.0
## 組を作るときの「接している」向き（面で隣り合う6方向）。
const NEIGHBORS: Array[Vector3i] = [
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(0, -1, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]

## ブロック ID → {"action": RuleAction.Kind, "stack": int, "tokens": PackedInt32Array, "age": float}。
## tokens は予約した単発のトークン（繰り返し・信号なら空）。
var _pending: Dictionary[int, Dictionary] = {}
## 予約の結果を待っている単発のトークン ID → {付与先 ID: BlockRules.Attempt}（決まった付与先の分だけ）。
var _shots: Dictionary[int, Dictionary] = {}
## まとめて動く組の予約: [{"members": PackedInt32Array, "action", "stacks": {id: int},
## "tokens": {id: PackedInt32Array}, "age": float}, ...]。
var _groups: Array[Dictionary] = []
## ブロック ID → そのブロックが入っている組の予約。
var _group_of: Dictionary[int, Dictionary] = {}


## 予約できる行動か（ブロックの W/A/S/D だけ）。
static func is_bufferable(action: RuleAction.Kind) -> bool:
	return RuleAction.is_horizontal(action)


## 物理的にいま始められるか。W/A/S/D は空中でも、進む先がいまの高さで空いていればよい。
static func ready_now(block: RuleBlock, action: RuleAction.Kind) -> bool:
	if is_bufferable(action):
		return block.can_step_now(action)
	return block.is_ready_for(action)


func has_pending(block_id: int) -> bool:
	return _pending.has(block_id) or _group_of.has(block_id)


## 予約している行動（無ければ -1）。テストと表示用。
func pending_action(block_id: int) -> int:
	if _group_of.has(block_id):
		return int(_group_of[block_id]["action"])
	return int(_pending[block_id]["action"]) if _pending.has(block_id) else -1


## 組で予約しているか（テスト用）。
func is_group_pending(block_id: int) -> bool:
	return _group_of.has(block_id)


## その単発トークンが予約の結果待ちか（待っている間はもう一度押しても起動しない）。
func is_tracking(token_id: int) -> bool:
	return _shots.has(token_id)


## 行動を起動する。いま動ければ動いて SUCCESS、予約したら PENDING、それ以外は失敗の理由を返す。
## tokens: 単発で起動したトークン（予約したら結果が出るまで覚えておく）。
func trigger(
	w: GameWorld,
	block_id: int,
	action: RuleAction.Kind,
	stack: int,
	tokens: PackedInt32Array = PackedInt32Array()
) -> int:
	var block := w.blocks[block_id]
	var ready := not has_pending(block_id) and ready_now(block, action)
	var result := BlockRules.attempt(w.ledger, block_id, action, ready)
	if result == BlockRules.Attempt.SUCCESS:
		block.perform(action, w._high(block_id), stack)
		return result
	if result != BlockRules.Attempt.NOT_READY or not _can_wait(block, block_id, action):
		return result
	_pending[block_id] = {"action": action, "stack": stack, "tokens": tokens, "age": 0.0}
	return PENDING


## 同じ付与で同時に起動したブロックたちの行動を起動する。W/A/S/D なら、接しているブロックどうしを組にして
## まとめて動かす（それ以外の行動・1つだけなら trigger と同じ）。結果は {ブロック ID: SUCCESS / PENDING / 失敗}。
## stacks: {ID: 同じ能力の数}、tokens: {ID: 単発で起動したトークン}（無い ID は繰り返し・信号）。
func trigger_group(
	w: GameWorld,
	ids: PackedInt32Array,
	action: RuleAction.Kind,
	stacks: Dictionary,
	tokens: Dictionary
) -> Dictionary:
	var results := {}
	var parts: Array[PackedInt32Array] = []
	if is_bufferable(action) and ids.size() > 1:
		parts = components(w, ids)
	else:
		for id in ids:
			parts.append(PackedInt32Array([id]))
	for part in parts:
		if part.size() == 1:
			var id := part[0]
			var own := tokens.get(id, PackedInt32Array()) as PackedInt32Array
			results[id] = trigger(w, id, action, int(stacks.get(id, 1)), own)
			continue
		results.merge(_trigger_part(w, part, action, stacks, tokens))
	return results


## ids を、面で接しているブロックどうしのまとまりに分ける（並びは ids の順を保つ）。
static func components(w: GameWorld, ids: PackedInt32Array) -> Array[PackedInt32Array]:
	var by_cell := {}
	for id in ids:
		by_cell[w.blocks[id].cell()] = id
	var seen := {}
	var parts: Array[PackedInt32Array] = []
	for id in ids:
		if seen.has(id):
			continue
		var part := PackedInt32Array()
		var queue: Array[int] = [id]
		seen[id] = true
		while not queue.is_empty():
			var current: int = queue.pop_front()
			part.append(current)
			var c := w.blocks[current].cell()
			for n: Vector3i in NEIGHBORS:
				var other: int = by_cell.get(c + n, -1)
				if other != -1 and not seen.has(other):
					seen[other] = true
					queue.append(other)
		parts.append(part)
	return parts


func _trigger_part(
	w: GameWorld,
	part: PackedInt32Array,
	action: RuleAction.Kind,
	stacks: Dictionary,
	tokens: Dictionary
) -> Dictionary:
	var results := {}
	var movers := PackedInt32Array()
	for id in part:
		# 別の予約で待っているブロックは、この組では動かない（壁と同じ）
		var verdict := BlockRules.attempt(w.ledger, id, action, not has_pending(id))
		if verdict == BlockRules.Attempt.SUCCESS:
			movers.append(id)
		else:
			results[id] = verdict
	if movers.is_empty():
		return results
	if _group_can_step(w, movers, action):
		_perform_group(w, movers, action, stacks)
		for id in movers:
			results[id] = BlockRules.Attempt.SUCCESS
		return results
	if not _group_settled(w, movers):
		var entry := {"members": movers, "action": action, "stacks": {}, "tokens": {}, "age": 0.0}
		for id in movers:
			entry["stacks"][id] = int(stacks.get(id, 1))
			entry["tokens"][id] = tokens.get(id, PackedInt32Array()) as PackedInt32Array
			_group_of[id] = entry
			results[id] = PENDING
		_groups.append(entry)
		return results
	for id in movers:
		results[id] = BlockRules.Attempt.NOT_READY
	return results


## 組の全員が、仲間の空けるマスを空きとみなして、いまの高さで1マス進めるか。
static func _group_can_step(
	w: GameWorld, members: PackedInt32Array, action: RuleAction.Kind
) -> bool:
	var rids: Array[RID] = []
	for id in members:
		rids.append(w.blocks[id].get_rid())
	for id in members:
		var mates := rids.duplicate()
		mates.erase(w.blocks[id].get_rid())
		if not w.blocks[id].can_step_now(action, mates):
			return false
	return true


static func _group_settled(w: GameWorld, members: PackedInt32Array) -> bool:
	for id in members:
		if not w.blocks[id].is_settled():
			return false
	return true


static func _perform_group(
	w: GameWorld, members: PackedInt32Array, action: RuleAction.Kind, stacks: Dictionary
) -> void:
	var mates: Array[RuleBlock] = []
	for id in members:
		mates.append(w.blocks[id])
	for id in members:
		w.blocks[id].perform(action, w._high(id), int(stacks.get(id, 1)))
		w.blocks[id].set_step_mates(mates)


## 単発のトークンの結果を、決まった付与先の分だけ覚えておく（残りは予約の結果が出たら埋まる）。
func track_shot(token_id: int, decided: Dictionary) -> void:
	var known := {}
	for holder: int in decided:
		known[holder] = decided[holder]
	_shots[token_id] = known


## 毎フレーム（ホストだけ）。動けるようになった予約を1マス動かし、結果が出た単発を戻す。
func advance(w: GameWorld, delta: float) -> void:
	for block_id: int in _pending.keys():
		var entry := _pending[block_id]
		if not w.blocks.has(block_id):
			forget(block_id)
			continue
		var tokens := _live_tokens(w, block_id, entry["tokens"] as PackedInt32Array)
		if (entry["tokens"] as PackedInt32Array).size() > 0 and tokens.is_empty():
			_pending.erase(block_id)  # 予約した単発は全部回収された
			continue
		entry["tokens"] = tokens
		var result := _resolve(w, block_id, entry, delta)
		if result == PENDING:
			continue
		_pending.erase(block_id)
		for token_id in tokens:
			_settle(w, token_id, block_id, result as BlockRules.Attempt)
	for entry: Dictionary in _groups.duplicate():
		_advance_group(w, entry, delta)


## 組の予約を1フレーム進める。全員が進めるようになったら全員一緒に動く。
func _advance_group(w: GameWorld, entry: Dictionary, delta: float) -> void:
	var action := int(entry["action"]) as RuleAction.Kind
	var members := PackedInt32Array()
	var decided := {}
	for id in entry["members"] as PackedInt32Array:
		if not w.blocks.has(id):
			continue
		var own := entry["tokens"][id] as PackedInt32Array
		var live := _live_tokens(w, id, own)
		if own.size() > 0 and live.is_empty():
			_group_of.erase(id)  # 予約した単発は全部回収された
			continue
		entry["tokens"][id] = live
		var verdict := BlockRules.attempt(w.ledger, id, action, true)
		if verdict != BlockRules.Attempt.SUCCESS:
			decided[id] = verdict  # 禁止・能力なしの仲間は組から外れる
			continue
		members.append(id)
	entry["members"] = members
	if not members.is_empty():
		if _group_can_step(w, members, action):
			_perform_group(w, members, action, entry["stacks"] as Dictionary)
			for id in members:
				decided[id] = BlockRules.Attempt.SUCCESS
			members = PackedInt32Array()
		else:
			entry["age"] = float(entry["age"]) + delta
			if _group_settled(w, members) or float(entry["age"]) >= MAX_WAIT:
				for id in members:
					decided[id] = BlockRules.Attempt.NOT_READY
				members = PackedInt32Array()
	entry["members"] = members
	if members.is_empty():
		_groups.erase(entry)
	for id: int in decided:
		_group_of.erase(id)
		for token_id in (
			(entry["tokens"] as Dictionary).get(id, PackedInt32Array()) as PackedInt32Array
		):
			_settle(w, token_id, id, decided[id] as BlockRules.Attempt)


## 全部忘れる（チェックポイント・全員リセットの復元）。
func clear() -> void:
	_pending.clear()
	_shots.clear()
	_groups.clear()
	_group_of.clear()


## ブロックが無くなった（地形へ戻った）。予約していた単発は結果待ちをやめ、貸したまま残す（もう一度押せる）。
func forget(block_id: int) -> void:
	if _group_of.has(block_id):
		var entry := _group_of[block_id]
		_group_of.erase(block_id)
		var own := (
			(entry["tokens"] as Dictionary).get(block_id, PackedInt32Array()) as PackedInt32Array
		)
		for token_id in own:
			_shots.erase(token_id)
		var rest := entry["members"] as PackedInt32Array
		var at := rest.find(block_id)
		if at != -1:
			rest.remove_at(at)
		entry["members"] = rest
		if rest.is_empty():
			_groups.erase(entry)
	if not _pending.has(block_id):
		return
	for token_id in _pending[block_id]["tokens"] as PackedInt32Array:
		_shots.erase(token_id)
	_pending.erase(block_id)


## 予約して待つ意味があるか: 空中か、横に動いている途中のときだけ（地面で塞がれているなら今までどおり失敗）。
func _can_wait(block: RuleBlock, block_id: int, action: RuleAction.Kind) -> bool:
	return is_bufferable(action) and not has_pending(block_id) and not block.is_settled()


func _resolve(w: GameWorld, block_id: int, entry: Dictionary, delta: float) -> int:
	var action := int(entry["action"]) as RuleAction.Kind
	var verdict := BlockRules.attempt(w.ledger, block_id, action, true)
	if verdict != BlockRules.Attempt.SUCCESS:
		return verdict  # 禁止・能力なしが先（禁止は上位の規則）
	var block := w.blocks[block_id]
	if block.can_step_now(action):
		block.perform(action, w._high(block_id), int(entry["stack"]))
		return BlockRules.Attempt.SUCCESS
	entry["age"] = float(entry["age"]) + delta
	if block.is_settled() or float(entry["age"]) >= MAX_WAIT:
		return BlockRules.Attempt.NOT_READY
	return PENDING


## まだ結果待ちで、このブロックに単発として貸したままのトークンだけを残す。
func _live_tokens(w: GameWorld, block_id: int, tokens: PackedInt32Array) -> PackedInt32Array:
	var live := PackedInt32Array()
	for token_id in tokens:
		var t := w.ledger.token(token_id)
		var held := (
			t != null
			and t.is_lent()
			and t.mode == TriggerMode.Kind.SINGLE_SHOT
			and t.holder_ids.has(block_id)
		)
		if held and _shots.has(token_id):
			live.append(token_id)
		else:
			_shots.erase(token_id)
	return live


func _settle(w: GameWorld, token_id: int, block_id: int, result: BlockRules.Attempt) -> void:
	if not _shots.has(token_id):
		return
	var known := _shots[token_id]
	known[block_id] = result
	for holder in w.ledger.token(token_id).holder_ids:
		if not known.has(holder):
			return  # 範囲単発: ほかの付与先の予約がまだ
	_shots.erase(token_id)
	WorldTicks.finish_single_shot(w, token_id, known)
