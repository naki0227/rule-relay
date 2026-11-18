class_name RuleVessel
extends RefCounted
## 能力・禁止が宿る「器」（アイテム）。付与してもトークンだけが移り、器はスロットに残る。

enum Location { HOTBAR, INVENTORY }

var id: int
var token_id: int
var location: Location = Location.INVENTORY
## HOTBAR のときのスロット番号（0〜8）。INVENTORY では -1。
var slot: int = -1


func to_dict() -> Dictionary:
	return {"id": id, "token_id": token_id, "location": location, "slot": slot}


static func from_dict(data: Dictionary) -> RuleVessel:
	var vessel := RuleVessel.new()
	vessel.id = int(data["id"])
	vessel.token_id = int(data["token_id"])
	vessel.location = int(data["location"]) as Location
	vessel.slot = int(data["slot"])
	return vessel
