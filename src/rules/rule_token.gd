class_name RuleToken
extends RefCounted
## 能力または禁止そのもの。同じトークンは世界に1つだけ存在し、複製しない。
## - holder_ids が空: 器（vessel_id）の中にある
## - holder_ids が空でない: その対象へ付与中（範囲付与なら複数ブロックで1トークンを共有）
## vessel_id が -1 のトークンは、レベルに最初から置かれていて、まだ誰の器にも入っていない。

var id: int
var action: RuleAction.Kind
var is_prohibition: bool
var vessel_id: int = -1
var mode: TriggerMode.Kind = TriggerMode.Kind.NONE
var holder_ids: PackedInt32Array = PackedInt32Array()
var is_range: bool = false
var range_center: Vector3 = Vector3.ZERO
var range_radius: float = 0.0
var range_layer: int = 0


func is_lent() -> bool:
	return not holder_ids.is_empty()


func describe() -> String:
	var kind := "禁止" if is_prohibition else "能力"
	return "%s[%s]" % [kind, RuleAction.label(action)]


func to_dict() -> Dictionary:
	return {
		"id": id,
		"action": action,
		"is_prohibition": is_prohibition,
		"vessel_id": vessel_id,
		"mode": mode,
		"holder_ids": holder_ids.duplicate(),
		"is_range": is_range,
		"range_center": range_center,
		"range_radius": range_radius,
		"range_layer": range_layer,
	}


static func from_dict(data: Dictionary) -> RuleToken:
	var token := RuleToken.new()
	token.id = int(data["id"])
	token.action = int(data["action"]) as RuleAction.Kind
	token.is_prohibition = bool(data["is_prohibition"])
	token.vessel_id = int(data["vessel_id"])
	token.mode = int(data["mode"]) as TriggerMode.Kind
	token.holder_ids = (data["holder_ids"] as PackedInt32Array).duplicate()
	token.is_range = bool(data["is_range"])
	token.range_center = data["range_center"] as Vector3
	token.range_radius = float(data["range_radius"])
	token.range_layer = int(data["range_layer"])
	return token
