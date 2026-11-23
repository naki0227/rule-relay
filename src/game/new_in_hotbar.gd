class_name NewInHotbar
extends RefCounted
## F で取った・拾った能力が、前は無かった器としてホットバーに入ったら、その枠を選ぶ（GameWorld.interact）。
## 2026-11-23（はじめての 10 分の通し・1-2）: 台のジャンプを F で取っても選んでいる枠は W のままで、空の台を
## 狙うと「W を渡す」と出ていた。
## - 禁止は選ばない（禁止を手放す操作は、案内「[7] 禁止をえらぶ」で自分で選ぶ。うっかり渡さない）
## - 自分の器へ戻っただけ（取り戻す）なら、器は前からあったので選び直さない
## - 協力中にホストが参加者の代わりに F を処理するときは、選んだ枠を WorldParty.act_as が元に戻す。
##   参加者の画面では、ホストから台帳が届いたとき（arrived）に同じ判断をする

## 参加者の画面で、F の後にホストから台帳が届くのを待つミリ秒。
const WAIT_MS: int = 2000

## F を押す前のホットバーの器の ID（枠 → ID）。
var _before: Dictionary = {}
## 見張りの締め切り（Time.get_ticks_msec）。0 なら見張っていない。
var _until: int = 0


## F を押した: いまのホットバーを覚えて見張り始める。
func watch(w: GameWorld) -> void:
	_before = _ids(w)
	_until = Time.get_ticks_msec() + WAIT_MS


## ホストが F を処理し終えた（台帳はもう変わっている）: 新しく入った能力を選び、見張りをやめる。
func settle(w: GameWorld) -> void:
	_select(w)
	_until = 0


## 参加者の画面に台帳が届いた: 見張っていれば選ぶ（締め切りを過ぎたらやめる）。
func arrived(w: GameWorld) -> void:
	if _until == 0:
		return
	if Time.get_ticks_msec() > _until:
		_until = 0
		return
	_select(w)


func _select(w: GameWorld) -> void:
	if _until == 0:
		return
	var known := {}
	for slot: int in _before:
		known[_before[slot]] = true
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, w.acting_id())
		if v == null or known.has(v.id):
			continue
		var t := w.ledger.token(v.token_id)
		if t != null and not t.is_prohibition and t.is_in_vessel():
			w.select_slot(slot)
			_until = 0
			return


static func _ids(w: GameWorld) -> Dictionary:
	var ids := {}
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, w.acting_id())
		if v != null:
			ids[slot] = v.id
	return ids
