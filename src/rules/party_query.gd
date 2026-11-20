class_name PartyQuery
extends RefCounted
## 複数プレイヤーの能力の所在を読む（読み取り専用。RuleLedger の公開メソッド数を抑えるため分けた）。


## そのプレイヤーが器なしで持っている能力・禁止（仲間から受け取った・F で回収した）。ID 順。
static func carried_tokens(ledger: RuleLedger, player_id: int) -> Array[RuleToken]:
	var result: Array[RuleToken] = []
	for t in ledger.all_tokens():
		if t.carrier_id == player_id:
			result.append(t)
	return result


## 世界に落ちている能力（単発成功時に付与者が退出していた）。ID 順。
static func dropped_tokens(ledger: RuleLedger) -> Array[RuleToken]:
	var result: Array[RuleToken] = []
	for t in ledger.all_tokens():
		if t.dropped:
			result.append(t)
	return result


## そのトークンの出自（元の器の持ち主）。器の無いトークンは -1。循環譲渡でも変わらない。
static func origin_owner(ledger: RuleLedger, token_id: int) -> int:
	var t := ledger.token(token_id)
	if t == null or t.vessel_id == -1:
		return -1
	return ledger.vessel(t.vessel_id).owner_id
