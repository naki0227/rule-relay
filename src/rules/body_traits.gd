class_name BodyTraits
extends RefCounted
## 持っているだけで効く体の性質（重い・浮く・泳ぐ）を、プレイヤーにもブロック・生き物にも同じ形で読む
## （読み取り専用。RuleLedger の公開メソッド数を増やさないため分けた。docs/adr/0015）。
##
## - 数え方は能力の数（同じ能力を n 個持てば n。Tuning.stack_factor と同じ「数に比例」）。
##   禁止を持っていれば、その性質は 0 個と同じ（自分から始められない＝効かない）。
## - 重いと浮くは数で打ち消し合う: 重さ = 重いの数 − 浮くの数。正なら重い、負なら浮く、0 ならふつう。
##   どちらか一方を必ず優先する決まりより、「両方を持つとどうなるか」を数だけで説明できる。
## - 重さの板（別の作業で作る）は is_heavy() / weight_units() だけを見ればよい（板の側を変えずに済む）。

## 重い ×1 の、板の上での重さ（人数）。板が求める人数は最大 4 人なので、重い 1 つで足りる。
const HEAVY_WEIGHT: float = 4.0


## 重さ（重いの数 − 浮くの数）。entity_id はプレイヤー ID でもブロック・生き物の ID でもよい。
static func weight(ledger: RuleLedger, entity_id: int) -> int:
	var heavy := count(ledger, entity_id, RuleAction.Kind.HEAVY)
	return heavy - count(ledger, entity_id, RuleAction.Kind.FLOAT)


## 重いか（重さが正）。風に流されない・水に沈む・重さの板を 1 つで押し下げる。
static func is_heavy(ledger: RuleLedger, entity_id: int) -> bool:
	return weight(ledger, entity_id) > 0


## 浮く強さ（重さが負なら、その大きさ。浮かなければ 0）。
static func float_level(ledger: RuleLedger, entity_id: int) -> int:
	return maxi(-weight(ledger, entity_id), 0)


## 泳ぐ強さ（泳ぐの数。禁止があれば 0）。
static func swim_level(ledger: RuleLedger, entity_id: int) -> int:
	return count(ledger, entity_id, RuleAction.Kind.SWIM)


## 重さの板の上での重さ（人数）。ふつうは 1、重いなら 4 × 重さ。
static func weight_units(ledger: RuleLedger, entity_id: int) -> float:
	var w := weight(ledger, entity_id)
	return HEAVY_WEIGHT * Tuning.stack_factor(w) if w > 0 else 1.0


## 効いている数（禁止があれば 0）。プレイヤーは手元の数、ブロック・生き物は付いている数。
static func count(ledger: RuleLedger, entity_id: int, action: RuleAction.Kind) -> int:
	if ledger == null or not ledger.has_entity(entity_id):
		return 0
	if not ledger.can_initiate(entity_id, action):
		return 0
	if ledger.entity_kind(entity_id) == EntityKind.Kind.PLAYER:
		return ledger.ability_count(action, entity_id)
	return PartyQuery.entity_count(ledger, entity_id, action)
