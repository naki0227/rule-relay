class_name RuleToken
extends RefCounted
## 能力または禁止そのもの。同じトークンは世界に1つだけ存在し、複製しない。
## - holder_ids が空: 器（vessel_id）の中にある
## - holder_ids が空でない: その対象へ付与中（範囲付与なら複数ブロックで1トークンを共有）
## vessel_id が -1 のトークンは、レベルに最初から置かれていて、まだ誰の器にも入っていない。
##
## 複数プレイヤー（2026-11-19 本人確定、Vault 提案書 15〜17・27〜30）:
## - vessel_id は出自（元の器）。一度決まったら書き換えない。循環譲渡でも元の持ち主を付け替えない
## - carrier_id が -1 でなければ、器を離れてそのプレイヤーが持っている（仲間から受け取った・F で回収した）
## - lender_id は直前に付与した（渡した）プレイヤー。単発成功の自動返還先
## - dropped なら世界に落ちている（単発成功時に付与者が退出していた）。誰でも拾える

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
var carrier_id: int = -1
var lender_id: int = -1
var dropped: bool = false
var drop_position: Vector3 = Vector3.ZERO


func is_lent() -> bool:
	return not holder_ids.is_empty()


## 元の器の中にある（付与中・誰かが持っている・落ちている、のどれでもない）。
func is_in_vessel() -> bool:
	return holder_ids.is_empty() and carrier_id == -1 and not dropped


## 知らせに出す名前（ホットバーの名前と同じ「ジャンプ」「ジャンプ禁止」）。前は「能力[ジャンプ]」で、
## 画面の案内（「ジャンプを渡す」）と言い方がずれていた（2026-11-22 の通し）。
func describe() -> String:
	return ("%s禁止" if is_prohibition else "%s") % RuleAction.label(action)


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
		"carrier_id": carrier_id,
		"lender_id": lender_id,
		"dropped": dropped,
		"drop_position": drop_position,
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
	token.carrier_id = int(data.get("carrier_id", -1))
	# 1人用の古いスナップショット: 器から付与中なら付与者は本人
	var legacy_lender := RuleLedger.PLAYER_ID if token.is_lent() and token.vessel_id != -1 else -1
	token.lender_id = int(data.get("lender_id", legacy_lender))
	token.dropped = bool(data.get("dropped", false))
	token.drop_position = data.get("drop_position", Vector3.ZERO) as Vector3
	return token
