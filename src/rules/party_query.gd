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


## ブロック・生き物に付いている同じ能力の数（同じ能力を n 個持てば効果が n 倍）。
static func entity_count(ledger: RuleLedger, entity_id: int, action: RuleAction.Kind) -> int:
	var count := 0
	for t in ledger.tokens_on(entity_id):
		if not t.is_prohibition and t.action == action:
			count += 1
	return count
