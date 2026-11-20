class_name RunTracker
extends RefCounted
## ステージ1回分の記録の数え方（仮。引き継ぎ仕様 7-10 で厳密な定義は未決。docs/adr/0010）。
## - abilities_used: 能力・禁止がブロック・生き物・範囲へ付与された回数（同じトークンでも付与するたびに1）
## - hand_offs: プレイヤーからプレイヤーへ直接渡した回数
## - clear_seconds: ステージ開始からクリアまでの秒数（一時停止・ホスト移譲中も含む）
## 台帳が変わるたびに、トークンの所在の変化を見て数える。

var abilities_used: int = 0
var hand_offs: int = 0
var seconds: float = 0.0
## トークン ID → [付与先が空でないか, carrier_id, lender_id]
var _seen: Dictionary = {}


func reset(ledger: RuleLedger) -> void:
	abilities_used = 0
	hand_offs = 0
	seconds = 0.0
	_seen.clear()
	observe(ledger, false)


## 台帳の変化を見る。count が false なら記録だけ更新して数えない（リセット直後など）。
func observe(ledger: RuleLedger, count: bool = true) -> void:
	for t in ledger.all_tokens():
		var before := _seen.get(t.id, [false, -1, -1]) as Array
		var was_lent := bool(before[0])
		if count and t.is_lent() and not was_lent:
			abilities_used += 1
		var carrier_changed := t.carrier_id != int(before[1])
		var given := t.carrier_id != -1 and carrier_changed and t.lender_id != int(before[2])
		if count and given:
			hand_offs += 1
		_seen[t.id] = [t.is_lent(), t.carrier_id, t.lender_id]


func metrics(picked: PackedStringArray = PackedStringArray()) -> RunMetrics:
	return RunMetrics.create(seconds, abilities_used, hand_offs, picked)


func to_dict() -> Dictionary:
	return {"abilities_used": abilities_used, "hand_offs": hand_offs, "seconds": seconds}


func restore(data: Dictionary, ledger: RuleLedger) -> void:
	abilities_used = int(data.get("abilities_used", 0))
	hand_offs = int(data.get("hand_offs", 0))
	seconds = float(data.get("seconds", 0.0))
	_seen.clear()
	observe(ledger, false)
