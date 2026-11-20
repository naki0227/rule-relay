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
			return "%s は貸出中です（%s で回収）" % [t.describe(), InputMode.token(&"interact")]
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


## 「投げる」が使えない理由（HUD の案内用）。
static func throw_unavailable_reason(ledger: RuleLedger, player_id: int) -> String:
	if ledger.player_prohibited(RuleAction.Kind.THROW, player_id):
		return "投げる禁止を持っています"
	for v in ledger.all_vessels():
		var t := ledger.token(v.token_id)
		var mine := v.owner_id == player_id and v.location != RuleVessel.Location.WORLD
		if mine and t.action == RuleAction.Kind.THROW and not t.is_in_vessel():
			return "貸出中です（%s で回収）" % InputMode.token(&"interact")
	return "ホットバーにありません"


## 通信で付与先を伝えるための参照 {"kind": "entity"|"bell"|"player"|"none", "id": int}。
static func target_ref(w: GameWorld, target: Node3D) -> Dictionary:
	if target is PlayerAvatar:
		return {"kind": "player", "id": (target as PlayerAvatar).player_id}
	if target is Bell:
		return {"kind": "bell", "id": w.bells.find(target as Bell)}
	if target is RuleBlock or target is Creature:
		return {"kind": "entity", "id": int(target.get("entity_id"))}
	if target is TerrainCell:
		return {"kind": "cell", "id": -1, "cell": (target as TerrainCell).cell}
	return {"kind": "none", "id": -1}


## target_ref の逆。見つからなければ null（通信から来た値なので信用しない）。
static func resolve_target(w: GameWorld, ref: Dictionary) -> Node3D:
	var id := int(ref.get("id", -1))
	match String(ref.get("kind", "")):
		"player":
			return w.avatar_of(id)
		"bell":
			return w.bells[id] if id >= 0 and id < w.bells.size() else null
		"entity":
			if w.blocks.has(id):
				return w.blocks[id]
			return w.creatures.get(id) as Node3D
		"cell":
			return _resolve_cell(w, ref.get("cell"))
	return null


## 地形のセル（動くブロックになっていればそのブロック）。
static func _resolve_cell(w: GameWorld, value: Variant) -> Node3D:
	if typeof(value) != TYPE_VECTOR3I or w.terrain == null:
		return null
	var cell := value as Vector3i
	if w.promoted.has(cell):
		return w.blocks[w.promoted[cell]]
	return w.terrain_target(cell) if w.terrain.has_cell(cell) else null


## 仲間へ渡すトークン（無ければ -1）。選んでいる枠の器に能力があればそれ、
## 器が空（貸出中・渡した）なら、受け取って持っている同じ種類の能力。枠が空なら、受け取った能力の最初のもの。
## 受け取った能力の置き場の UI は未決（引き継ぎ仕様 7-7）。これは仮の選び方。
static func giveable_token(ledger: RuleLedger, player_id: int, slot: int) -> int:
	var v := ledger.hotbar_vessel(slot, player_id)
	var bans_ok := ledger.allow_prohibition_to_player
	var carried := PartyQuery.carried_tokens(ledger, player_id).filter(
		func(t: RuleToken) -> bool: return bans_ok or not t.is_prohibition
	)
	if v != null:
		var own := ledger.token(v.token_id)
		if own.is_in_vessel() and (bans_ok or not own.is_prohibition):
			return own.id
		carried = carried.filter(func(t: RuleToken) -> bool: return t.action == own.action)
	return -1 if carried.is_empty() else (carried[0] as RuleToken).id


## 拾える距離に落ちている能力（単発成功時に付与者が退出していた）。無ければ -1。
static func nearest_dropped(ledger: RuleLedger, at: Vector3) -> int:
	var best := -1
	var best_distance := Tuning.PICKUP_REACH
	for t in PartyQuery.dropped_tokens(ledger):
		var d := at.distance_to(t.drop_position)
		if d <= best_distance:
			best = t.id
			best_distance = d
	return best


## 能力を受け取った物が鳴らす音（材質ごと）。木のブロック・発射台は木、石・砂岩のセルは石、草のセルは草、生き物。
static func receive_sound(target: Node3D) -> StringName:
	if target is Creature:
		return &"receive_creature"
	match String(target.get_meta("model", "ability_block")):
		"grass_cell":
			return &"receive_grass"
		"rock_cell", "sandstone_cell":
			return &"receive_stone"
	return &"receive_wood"
