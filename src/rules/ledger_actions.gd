class_name LedgerActions
extends RefCounted
## 持ち物の画面からの操作（ホットバーへ移す・かばんへ戻す・装備する・外す）。
## 1人用とホストは台帳をその場で変える。参加者は remote にホストへの依頼（PartyCommand）を渡し、
## 結果はホストから届く台帳で反映される（そのため戻り値は「依頼を出せたか」）。
## 自分の器だけを動かせる（他人の器は持ち主のもの）。

var ledger: RuleLedger
var player_id: int = RuleLedger.PLAYER_ID
## 参加者のとき、依頼を送る関数 func(command: Dictionary)。空なら台帳をその場で変える。
var remote: Callable = Callable()


func move_to_hotbar(vessel_id: int, slot: int) -> bool:
	return _run(PartyCommand.move_to_hotbar(vessel_id, slot))


func move_to_inventory(vessel_id: int) -> bool:
	return _run(PartyCommand.move_to_inventory(vessel_id))


func equip(vessel_id: int) -> bool:
	return _run(PartyCommand.equip(vessel_id))


func unequip(vessel_id: int) -> bool:
	return _run(PartyCommand.unequip(vessel_id))


func _run(command: Dictionary) -> bool:
	var v := ledger.vessel(int(command["vessel"]))
	if v == null or v.owner_id != player_id:
		return false
	if remote.is_valid():
		remote.call(command)
		return true
	return PartyCommand.apply(ledger, player_id, command)["result"] == PartyCommand.Result.OK
