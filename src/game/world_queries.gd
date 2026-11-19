class_name WorldQueries
extends RefCounted
## GameWorld から切り出した、状態を持たない補助（付与結果の文言と、マスの高さの調査）。


static func describe(t: RuleToken, result: RuleLedger.LendResult, use_range: bool) -> String:
	match result:
		RuleLedger.LendResult.OK:
			var how := "範囲（%d個）" % t.holder_ids.size() if use_range else "単体"
			var mode := "" if t.mode == TriggerMode.Kind.NONE else "・%s" % TriggerMode.label(t.mode)
			return "%s を%s%sで付与しました" % [t.describe(), how, mode]
		RuleLedger.LendResult.ALREADY_LENT:
			return "%s は貸出中です（F で回収）" % t.describe()
		RuleLedger.LendResult.RANGE_PROHIBITION_UNSUPPORTED:
			return "禁止の範囲付与は未実装です（P0）"
		RuleLedger.LendResult.EQUIPPED_CANNOT_LEND:
			return "装備しているものは渡せません（外してホットバーに置くと渡せます）"
		RuleLedger.LendResult.NO_TARGETS:
			return "範囲内にブロックがありません"
	return "付与できません（%s）" % RuleLedger.LendResult.keys()[result]


## マスごとの立てる高さ（地形とブロックの上面）。上から光線を落として最初に当たった高さ。穴のマスは入れない。
static func survey(space: PhysicsDirectSpaceState3D, center: Vector2i, radius: int) -> Dictionary:
	var heights := {}
	for x in range(center.x - radius, center.x + radius + 1):
		for z in range(center.y - radius, center.y + radius + 1):
			var top := Vector3(x + 0.5, 12.0, z + 0.5)
			var query := PhysicsRayQueryParameters3D.create(
				top, top + Vector3.DOWN * 20.0, Tuning.LAYER_TERRAIN | Tuning.LAYER_BLOCKS
			)
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				heights[Vector2i(x, z)] = snappedf((hit["position"] as Vector3).y, 0.05)
	return heights
