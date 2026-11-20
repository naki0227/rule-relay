class_name RuleVessel
extends RefCounted
## 能力・禁止が宿る「器」（アイテム）。付与してもトークンだけが移り、器はスロットに残る。
##
## 置き場所:
## - HOTBAR: ホットバー（9枠）。能力が自分に効く
## - INVENTORY: 通常インベントリ（無制限）。能力は効かないが、禁止は効く
## - EQUIPPED: 装備欄（部位ごとに1個）。装備の能力が自分に効く
## - WORLD: 世界に落ちている（まだ拾っていない）。自分には何も効かない。F で拾うと INVENTORY へ

enum Location { HOTBAR, INVENTORY, EQUIPPED, WORLD }
## 装備の部位。NONE は装備ではない普通の器。
enum Part { NONE, HEAD, BODY, HANDS, FEET }

var id: int
var token_id: int
var location: Location = Location.INVENTORY
## HOTBAR のときのスロット番号（0〜8）。それ以外では -1。
var slot: int = -1
var part: Part = Part.NONE
## 装備の名前（例: ジャンプブーツ）。普通の器は空。
var item_name: String = ""
## WORLD のときの位置。
var world_position: Vector3 = Vector3.ZERO
## 器を持っているプレイヤー。WORLD（未回収）のときは -1。能力を仲間へ渡しても器は持ち主に残る。
var owner_id: int = RuleLedger.PLAYER_ID


func is_equipment() -> bool:
	return part != Part.NONE


static func part_label(value: Part) -> String:
	match value:
		Part.HEAD:
			return "頭"
		Part.BODY:
			return "体"
		Part.HANDS:
			return "手"
		Part.FEET:
			return "足"
	return "-"


func to_dict() -> Dictionary:
	return {
		"id": id,
		"token_id": token_id,
		"location": location,
		"slot": slot,
		"part": part,
		"item_name": item_name,
		"world_position": world_position,
		"owner_id": owner_id,
	}


static func from_dict(data: Dictionary) -> RuleVessel:
	var vessel := RuleVessel.new()
	vessel.id = int(data["id"])
	vessel.token_id = int(data["token_id"])
	vessel.location = int(data["location"]) as Location
	vessel.slot = int(data["slot"])
	vessel.part = int(data.get("part", Part.NONE)) as Part
	vessel.item_name = String(data.get("item_name", ""))
	vessel.world_position = data.get("world_position", Vector3.ZERO) as Vector3
	var legacy_owner := -1 if vessel.location == Location.WORLD else RuleLedger.PLAYER_ID
	vessel.owner_id = int(data.get("owner_id", legacy_owner))
	return vessel
