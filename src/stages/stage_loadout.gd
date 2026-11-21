class_name StageLoadout
extends RefCounted
## StageDef の能力・禁止を RuleLedger に置く（純粋。ノード・物理に依存しない）。
##
## - apply: 固定のトークン（ブロック・生き物・世界の器）、参加順ごとの開始ホットバー、全員の禁止、
##   いまの人数の補助を置く
## - rebuild_helpers: 全員リセットのときだけ呼ぶ（引き継ぎ仕様 2-7。攻略中の増減では呼ばない）。
##   前回置いた補助を、どこにあっても（世界・ブロック・仲間の手元・器の中・束ねた中）トークンごと消し、
##   新しい人数の補助を置き直す。複製しない
## - end_stage: クリアしたらステージ中の一時的なトークンをすべて消す（引き継ぎ仕様 2-8）。
##   個人の永久報酬は別の仕組みで、ここでは扱わない
##
## 補助のトークン ID はこのオブジェクトが覚える。チェックポイントには capture_state() も一緒に保存し、
## 全員リセットで台帳を restore したら restore_state() で戻してから rebuild_helpers を呼ぶ。

var stage: StageDef
## ステージの key（BlockSpec.key / CreatureSpec.key）→ 台帳の entity_id。実行時の層が登録して渡す。
var entity_ids: Dictionary = {}
## 補助を置いたときの人数。
var headcount: int = 0
var _helper_token_ids: PackedInt32Array = PackedInt32Array()


func _init(p_stage: StageDef, p_entity_ids: Dictionary) -> void:
	stage = p_stage
	entity_ids = p_entity_ids


## ノードを作らずに、ステージの対象を台帳へ登録する（テスト・ルールだけの検証用）。
## ID の振り方は GameWorld と同じ（ブロック・発射台は 100 から、生き物は 500 から、定義の順）。
## ルール層をノードの層に依存させないため、番号は既定値として持つ（一致はテストで確かめる）。
static func register_entities(
	ledger: RuleLedger, p_stage: StageDef, first_block: int = 100, first_creature: int = 500
) -> Dictionary:
	var ids := {}
	var next_block := first_block
	for b in p_stage.blocks:
		ledger.register_entity(next_block, EntityKind.Kind.BLOCK)
		ids[b.key] = next_block
		next_block += 1
	var next_creature := first_creature
	for c in p_stage.creatures:
		ledger.register_entity(next_creature, EntityKind.Kind.CREATURE)
		ids[c.key] = next_creature
		next_creature += 1
	return ids


## ステージ開始時の配置。player_ids は正式参加者（並び順が参加順 = loadout・出現位置の番号）。
func apply(ledger: RuleLedger, player_ids: PackedInt32Array) -> void:
	assert(not player_ids.is_empty(), "a stage needs at least one player")
	assert(player_ids.size() <= StageDef.MAX_PLAYERS, "too many players")
	for b in stage.blocks:
		_place_entity_tokens(ledger, b.key, b.tokens)
	for c in stage.creatures:
		_place_entity_tokens(ledger, c.key, c.tokens)
	for spec in stage.world_items:
		_place(ledger, spec)
	for i in player_ids.size():
		give_start(ledger, player_ids[i], i)
	_place_helpers(ledger, player_ids.size())


## 参加順 index のプレイヤーに、開始ホットバー・通常インベントリの能力・ステージの禁止・装備を渡す。
## 全員リセットで正式に合流した人にも使う（呼ぶのは実行時の層）。
func give_start(ledger: RuleLedger, player_id: int, index: int) -> void:
	var actions := stage.loadout_for(index)
	for slot in actions.size():
		ledger.give_player_item(actions[slot], false, slot, player_id)
	for action in stage.prohibitions:
		ledger.give_player_item(action, true, -1, player_id)
	for action in stage.start_inventory:
		ledger.give_player_item(action, false, -1, player_id)
	for action in stage.start_equipment:
		var gear := ledger.give_player_item(action, false, -1, player_id)
		gear.part = equipment_part(action)
		gear.item_name = equipment_name(action)
		ledger.equip(gear.id)


## 装備の部位（HIGH_JUMP は足、CLIMB は手）。装備でなければ NONE。
static func equipment_part(action: RuleAction.Kind) -> RuleVessel.Part:
	match action:
		RuleAction.Kind.HIGH_JUMP:
			return RuleVessel.Part.FEET
		RuleAction.Kind.CLIMB:
			return RuleVessel.Part.HANDS
	return RuleVessel.Part.NONE


static func equipment_name(action: RuleAction.Kind) -> String:
	match action:
		RuleAction.Kind.HIGH_JUMP:
			return "ジャンプブーツ"
		RuleAction.Kind.CLIMB:
			return "クライミンググローブ"
	return ""


## 全員リセットのときだけ: 前回の補助を消して、new_headcount の補助を置き直す。
func rebuild_helpers(ledger: RuleLedger, new_headcount: int) -> void:
	TokenRemoval.remove_tokens(ledger, _helper_token_ids)
	_helper_token_ids = PackedInt32Array()
	_place_helpers(ledger, new_headcount)


## いま台帳にある補助のトークン ID。
func helper_token_ids() -> PackedInt32Array:
	return _helper_token_ids.duplicate()


## チェックポイント用。
func capture_state() -> Dictionary:
	return {"headcount": headcount, "helpers": _helper_token_ids.duplicate()}


func restore_state(state: Dictionary) -> void:
	headcount = int(state["headcount"])
	_helper_token_ids = (state["helpers"] as PackedInt32Array).duplicate()


## クリア後: ステージ中の一時的なトークン・器とステージの対象を消し、全員を手ぶらでハブへ戻す。
## ステージの外へ能力を持ち出させない（引き継ぎ仕様 2-8、受け入れ 23）。
static func end_stage(ledger: RuleLedger) -> void:
	TokenRemoval.clear_stage(ledger)


func _place_helpers(ledger: RuleLedger, count: int) -> void:
	headcount = count
	for spec in stage.helpers_for(count):
		_helper_token_ids.append(_place(ledger, spec))


func _place_entity_tokens(ledger: RuleLedger, key: String, tokens: Array) -> void:
	for spec: StageDef.TokenSpec in tokens:
		ledger.place_on_entity(spec.action, spec.is_prohibition, _entity(key), spec.mode)


## 置いたトークンの ID を返す。
func _place(ledger: RuleLedger, spec: StageDef.PlacementSpec) -> int:
	if spec.block_key != "":
		var t := ledger.place_on_entity(
			spec.action, spec.is_prohibition, _entity(spec.block_key), spec.mode
		)
		return t.id
	var v := ledger.place_in_world(
		spec.action, spec.is_prohibition, spec.position, spec.part, spec.item_name
	)
	return v.token_id


func _entity(key: String) -> int:
	assert(entity_ids.has(key), "entity %s is not registered" % key)
	return int(entity_ids[key])
