class_name PartyCommand
extends RefCounted
## 参加者がホストへ送る「依頼」（能力を渡す・付与する・回収する・拾う・退出する）。
## ホストが apply で検証して台帳へ適用する（ホスト権威。docs/adr/0006）。通信から来た値は信用せず、
## 型と中身をここで確かめる。誰の依頼かは通信の送信元から決め、依頼の中身には書かせない（なりすまし防止）。

enum Kind {
	GIVE,
	LEND,
	RECALL_ENTITY,
	RECALL_TOKEN,
	PICKUP_TOKEN,
	LEAVE,
	MOVE_TO_HOTBAR,
	MOVE_TO_INVENTORY,
	EQUIP,
	UNEQUIP,
}
enum Result {
	OK,
	## 形が壊れている（キーが無い・型が違う・知らない種類）
	INVALID,
	## 台帳が断った（detail に RuleLedger.LendResult など）
	REFUSED,
}


static func give(token_id: int, to_player: int) -> Dictionary:
	return {"kind": Kind.GIVE, "token": token_id, "to": to_player}


static func lend(
	token_id: int, target_ids: PackedInt32Array, mode: TriggerMode.Kind, range_spec: Dictionary = {}
) -> Dictionary:
	return {
		"kind": Kind.LEND,
		"token": token_id,
		"targets": target_ids,
		"mode": mode,
		"range": range_spec
	}


static func recall_entity(entity_id: int) -> Dictionary:
	return {"kind": Kind.RECALL_ENTITY, "entity": entity_id}


static func recall_token(token_id: int) -> Dictionary:
	return {"kind": Kind.RECALL_TOKEN, "token": token_id}


static func pickup_token(token_id: int) -> Dictionary:
	return {"kind": Kind.PICKUP_TOKEN, "token": token_id}


static func leave() -> Dictionary:
	return {"kind": Kind.LEAVE}


static func move_to_hotbar(vessel_id: int, slot: int) -> Dictionary:
	return {"kind": Kind.MOVE_TO_HOTBAR, "vessel": vessel_id, "slot": slot}


static func move_to_inventory(vessel_id: int) -> Dictionary:
	return {"kind": Kind.MOVE_TO_INVENTORY, "vessel": vessel_id}


static func equip(vessel_id: int) -> Dictionary:
	return {"kind": Kind.EQUIP, "vessel": vessel_id}


static func unequip(vessel_id: int) -> Dictionary:
	return {"kind": Kind.UNEQUIP, "vessel": vessel_id}


## player_id の依頼を台帳へ適用する。{"result": Result, "detail": int} を返す。
## 物理の条件（手が届くか・見えているか）はまだ見ていない。アバターの同期を入れたらここで確かめる。
static func apply(ledger: RuleLedger, player_id: int, command: Dictionary) -> Dictionary:
	if not ledger.players().has(player_id) or not _well_formed(command):
		return _out(Result.INVALID)
	var kind := int(command["kind"]) as Kind
	var ok := false
	var detail := 0
	match kind:
		Kind.GIVE:
			detail = ledger.give_to_player(int(command["token"]), player_id, int(command["to"]))
			ok = detail == RuleLedger.LendResult.OK
		Kind.LEND:
			detail = _apply_lend(ledger, player_id, command)
			ok = detail == RuleLedger.LendResult.OK
		Kind.RECALL_ENTITY:
			ok = not ledger.recall_from_entity(int(command["entity"]), player_id).is_empty()
		Kind.RECALL_TOKEN:
			ok = ledger.recall(int(command["token"]), player_id)
		Kind.PICKUP_TOKEN:
			ok = ledger.pickup_token(int(command["token"]), player_id)
		Kind.LEAVE:
			# ホストの退出はホスト移譲（P5）で扱う。ここでは参加者だけ
			ok = player_id != RuleLedger.PLAYER_ID
			if ok:
				ledger.set_player_present(player_id, false)
		_:
			ok = _apply_inventory(ledger, player_id, command)
	return _out(Result.OK if ok else Result.REFUSED, detail)


## 持ち物の整理。自分の器だけを動かせる。
static func _apply_inventory(ledger: RuleLedger, player_id: int, command: Dictionary) -> bool:
	var vessel_id := int(command["vessel"])
	var v := ledger.vessel(vessel_id)
	if v == null or v.owner_id != player_id:
		return false
	match int(command["kind"]):
		Kind.MOVE_TO_HOTBAR:
			return ledger.move_to_hotbar(vessel_id, int(command["slot"]))
		Kind.MOVE_TO_INVENTORY:
			return ledger.move_to_inventory(vessel_id)
		Kind.EQUIP:
			return ledger.equip(vessel_id) == RuleLedger.EquipResult.OK
	return ledger.unequip(vessel_id)


static func _apply_lend(ledger: RuleLedger, player_id: int, command: Dictionary) -> int:
	var targets := command["targets"] as PackedInt32Array
	var mode := int(command["mode"]) as TriggerMode.Kind
	var spec := command["range"] as Dictionary
	return ledger.lend_token(int(command["token"]), player_id, targets, mode, spec)


static func _well_formed(command: Dictionary) -> bool:
	if typeof(command.get("kind")) != TYPE_INT:
		return false
	var kind := int(command["kind"])
	if kind < 0 or kind >= Kind.size():
		return false
	for key: String in _int_keys(kind as Kind):
		if typeof(command.get(key)) != TYPE_INT:
			return false
	if kind == Kind.LEND:
		return _well_formed_lend(command)
	return true


static func _int_keys(kind: Kind) -> PackedStringArray:
	match kind:
		Kind.GIVE:
			return ["token", "to"]
		Kind.LEND:
			return ["token", "mode"]
		Kind.RECALL_ENTITY:
			return ["entity"]
		Kind.RECALL_TOKEN, Kind.PICKUP_TOKEN:
			return ["token"]
		Kind.MOVE_TO_HOTBAR:
			return ["vessel", "slot"]
		Kind.MOVE_TO_INVENTORY, Kind.EQUIP, Kind.UNEQUIP:
			return ["vessel"]
	return []


static func _well_formed_lend(command: Dictionary) -> bool:
	if typeof(command.get("targets")) != TYPE_PACKED_INT32_ARRAY:
		return false
	if not TriggerMode.Kind.values().has(int(command["mode"])):
		return false
	if typeof(command.get("range")) != TYPE_DICTIONARY:
		return false
	var spec := command["range"] as Dictionary
	if spec.is_empty():
		return true
	return (
		typeof(spec.get("center")) == TYPE_VECTOR3
		and typeof(spec.get("radius")) in [TYPE_FLOAT, TYPE_INT]
		and typeof(spec.get("layer")) == TYPE_INT
	)


static func _out(result: Result, detail: int = 0) -> Dictionary:
	return {"result": result, "detail": detail}
