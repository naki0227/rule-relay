class_name InventoryMoves
extends RefCounted
## 持ち物の画面で「持ち上げた器を、どこかの枠に置く」を、ホストへの依頼（LedgerActions）に直す
## （2026-11-21 本人「クリックしたやつを空いてるスロットでクリックしたらそこに移る、入れ替わるも」）。
## ドラッグ＆ドロップ・クリックで持ち上げて置く・番号キーのどれもここを通るので、入れ替えの規則は1か所。
## 入れ替えは台帳の move_to_hotbar / equip がそれぞれ1回の依頼で行う（参加者でも依頼1つで済み、
## 途中の状態が台帳に残らない）。新しい依頼の種類は足していない。
## 中の能力を貸している器（装備なら空の入れ物）も動かせる。装備欄へ置くことは、装備すること。

enum Place { HOTBAR, EQUIP, BAG }

const EQUIP_PARTS: Array[RuleVessel.Part] = [
	RuleVessel.Part.HEAD, RuleVessel.Part.BODY, RuleVessel.Part.HANDS, RuleVessel.Part.FEET
]


## held_id の器を place の index 番目へ置く。target_id は置き先にいま入っている器（無ければ -1）。
## 置けたか、置く必要が無かった（同じ場所）なら ""、置けないなら短い理由を返す。
static func place(
	ledger: RuleLedger,
	actions: LedgerActions,
	held_id: int,
	where: Place,
	index: int,
	target_id: int = -1
) -> String:
	var v := ledger.vessel(held_id)
	if v == null or v.owner_id != actions.player_id or v.location == RuleVessel.Location.WORLD:
		return "動かせません"
	match where:
		Place.HOTBAR:
			return _to_hotbar(actions, v, index)
		Place.EQUIP:
			return _to_equip(actions, v, EQUIP_PARTS[clampi(index, 0, EQUIP_PARTS.size() - 1)])
	return _to_bag(ledger, actions, v, target_id)


static func _to_hotbar(actions: LedgerActions, v: RuleVessel, slot: int) -> String:
	if v.location == RuleVessel.Location.HOTBAR and v.slot == slot:
		return ""
	# 入っていた器は、持ち上げた器のいた場所へ（台帳が入れ替える）
	return "" if actions.move_to_hotbar(v.id, slot) else "ホットバーへ移せません"


static func _to_equip(actions: LedgerActions, v: RuleVessel, part: RuleVessel.Part) -> String:
	if not v.is_equipment():
		return "装備品ではないので、そうびの枠には置けません"
	if v.part != part:
		return "%sの装備です（%sの枠には置けません）" % [RuleVessel.part_label(v.part), RuleVessel.part_label(part)]
	if v.location == RuleVessel.Location.EQUIPPED:
		return ""
	return "" if actions.equip(v.id) else "そうびできません"


## かばんへ。かばんの器の上に置いたら入れ替える（かばんは並び順を持たないので、かばんの中どうしは動かさない）。
static func _to_bag(
	ledger: RuleLedger, actions: LedgerActions, v: RuleVessel, target_id: int
) -> String:
	var target := ledger.vessel(target_id)
	var swap := target != null and target != v and target.owner_id == v.owner_id
	swap = swap and target.location == RuleVessel.Location.INVENTORY
	if v.location == RuleVessel.Location.INVENTORY:
		return ""
	if swap and v.location == RuleVessel.Location.HOTBAR:
		return "" if actions.move_to_hotbar(target.id, v.slot) else "入れ替えられません"
	if swap and v.location == RuleVessel.Location.EQUIPPED and target.part == v.part:
		return "" if actions.equip(target.id) else "入れ替えられません"
	return "" if actions.move_to_inventory(v.id) else "かばんへ移せません"
