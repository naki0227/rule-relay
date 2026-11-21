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

## 予約の結果がまだ決まっていない（BlockRules.Attempt のどれでもない）。
const PENDING: int = -1
## 予約が待てる最長の時間（秒）。高く跳んでも着地までに収まる長さ（×4 のジャンプで滞空 2 秒）。
const MAX_WAIT: float = 4.0

## ブロック ID → {"action": RuleAction.Kind, "stack": int, "tokens": PackedInt32Array, "age": float}。
## tokens は予約した単発のトークン（繰り返し・信号なら空）。
var _pending: Dictionary[int, Dictionary] = {}
## 予約の結果を待っている単発のトークン ID → {付与先 ID: BlockRules.Attempt}（決まった付与先の分だけ）。
var _shots: Dictionary[int, Dictionary] = {}


## 予約できる行動か（ブロックの W/A/S/D だけ）。
static func is_bufferable(action: RuleAction.Kind) -> bool:
	return RuleAction.is_horizontal(action)


## 物理的にいま始められるか。W/A/S/D は空中でも、進む先がいまの高さで空いていればよい。
static func ready_now(block: RuleBlock, action: RuleAction.Kind) -> bool:
	if is_bufferable(action):
		return block.can_step_now(action)
	return block.is_ready_for(action)


func has_pending(block_id: int) -> bool:
	return _pending.has(block_id)


## 予約している行動（無ければ -1）。テストと表示用。
func pending_action(block_id: int) -> int:
	return int(_pending[block_id]["action"]) if _pending.has(block_id) else -1


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


## 全部忘れる（チェックポイント・全員リセットの復元）。
func clear() -> void:
	_pending.clear()
	_shots.clear()


## ブロックが無くなった（地形へ戻った）。予約していた単発は結果待ちをやめ、貸したまま残す（もう一度押せる）。
func forget(block_id: int) -> void:
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
