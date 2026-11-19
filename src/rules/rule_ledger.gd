class_name RuleLedger
extends RefCounted
## 能力・禁止トークンと器の所有を一元管理する。ノード・入力・物理に依存しない。
##
## 守る不変条件（validate() で検査する）:
## - トークンは「器の中」「付与先」「レベルに設置」のどれか1か所にだけある（複製しない）
## - 器はホットバー（9枠）・通常インベントリ（無制限）・装備欄・世界（未回収）のどこか1か所にある
## - 同じ行為に能力と禁止が重なれば禁止を優先する

signal changed

enum LendResult {
	OK,
	NO_SUCH_VESSEL,
	NOT_IN_HOTBAR,
	ALREADY_LENT,
	NO_TARGETS,
	UNKNOWN_TARGET,
	CANNOT_TARGET_PLAYER,
	RANGE_ONLY_FOR_BLOCKS,
	RANGE_PROHIBITION_UNSUPPORTED,
	MODE_REQUIRED_FOR_BLOCK,
	MODE_NOT_SUPPORTED,
	EQUIPPED_CANNOT_LEND,
}

enum EquipResult {
	OK,
	NO_SUCH_VESSEL,
	NOT_EQUIPMENT,
	## 能力を貸し出している装備は、回収するまで装備できない（矛盾防止の仮の方針。企画書 7 の確認事項）
	LENT,
	## 世界に落ちている（先に F で拾う）
	NOT_CARRIED,
}

const PLAYER_ID: int = 1
const HOTBAR_SIZE: int = 9

var _entities: Dictionary[int, EntityKind.Kind] = {}
var _tokens: Dictionary[int, RuleToken] = {}
var _vessels: Dictionary[int, RuleVessel] = {}
var _next_token_id: int = 1
var _next_vessel_id: int = 1


func _init() -> void:
	_entities[PLAYER_ID] = EntityKind.Kind.PLAYER


# --- 登録・初期配置 ---------------------------------------------------------


func register_entity(entity_id: int, kind: EntityKind.Kind) -> void:
	assert(entity_id != PLAYER_ID, "PLAYER_ID is reserved")
	_entities[entity_id] = kind


func entity_kind(entity_id: int) -> EntityKind.Kind:
	return _entities[entity_id]


func has_entity(entity_id: int) -> bool:
	return _entities.has(entity_id)


## プレイヤーの器を1つ作る。hotbar_slot が 0〜8 ならホットバーへ、-1 なら通常インベントリへ。
func give_player_item(
	action: RuleAction.Kind, is_prohibition: bool, hotbar_slot: int = -1
) -> RuleVessel:
	var token := _new_token(action, is_prohibition)
	var vessel := _new_vessel(token)
	if hotbar_slot >= 0:
		assert(hotbar_vessel(hotbar_slot) == null, "hotbar slot already used")
		vessel.location = RuleVessel.Location.HOTBAR
		vessel.slot = hotbar_slot
	changed.emit()
	return vessel


## レベルに最初から置かれた能力・禁止（例: ジャンプ禁止のブロック）。器を持たない。
## ブロックに能力を置く場合は発動方式を指定する。
func place_on_entity(
	action: RuleAction.Kind,
	is_prohibition: bool,
	entity_id: int,
	mode: TriggerMode.Kind = TriggerMode.Kind.NONE
) -> RuleToken:
	assert(_entities.has(entity_id), "unknown entity")
	var token := _new_token(action, is_prohibition)
	token.holder_ids = PackedInt32Array([entity_id])
	token.mode = mode
	changed.emit()
	return token


## 世界に落ちている器（F で拾うまで自分には何も効かない）。
func place_in_world(
	action: RuleAction.Kind,
	is_prohibition: bool,
	position: Vector3,
	part: RuleVessel.Part = RuleVessel.Part.NONE,
	item_name: String = ""
) -> RuleVessel:
	var token := _new_token(action, is_prohibition)
	var vessel := _new_vessel(token)
	vessel.location = RuleVessel.Location.WORLD
	vessel.world_position = position
	vessel.part = part
	vessel.item_name = item_name
	changed.emit()
	return vessel


# --- 問い合わせ -------------------------------------------------------------


func token(token_id: int) -> RuleToken:
	return _tokens.get(token_id) as RuleToken


func vessel(vessel_id: int) -> RuleVessel:
	return _vessels.get(vessel_id) as RuleVessel


func hotbar_vessel(slot: int) -> RuleVessel:
	for v: RuleVessel in _vessels.values():
		if v.location == RuleVessel.Location.HOTBAR and v.slot == slot:
			return v
	return null


func inventory_vessels() -> Array[RuleVessel]:
	var result: Array[RuleVessel] = []
	for v: RuleVessel in _vessels.values():
		if v.location == RuleVessel.Location.INVENTORY:
			result.append(v)
	result.sort_custom(func(a: RuleVessel, b: RuleVessel) -> bool: return a.id < b.id)
	return result


func world_vessels() -> Array[RuleVessel]:
	var result: Array[RuleVessel] = []
	for v: RuleVessel in _vessels.values():
		if v.location == RuleVessel.Location.WORLD:
			result.append(v)
	result.sort_custom(func(a: RuleVessel, b: RuleVessel) -> bool: return a.id < b.id)
	return result


func token_of_vessel(vessel_id: int) -> RuleToken:
	var v := vessel(vessel_id)
	return null if v == null else token(v.token_id)


## プレイヤー自身がその行動を始められるか。
## 能力はホットバーにあり貸出中でないときだけ有効。禁止は手元（ホットバー・通常インベントリ）の
## どこにあっても有効で、能力より優先する（企画書 7）。
func player_can(action: RuleAction.Kind) -> bool:
	return player_has_ability(action) and not player_prohibited(action)


## 能力が自分に効くのは、ホットバーの普通の器と、装備欄の装備だけ（企画書 7）。
## ホットバーに置いた装備品は、装備していないので効かない（付与の元にはできる）。
func player_has_ability(action: RuleAction.Kind) -> bool:
	for v: RuleVessel in _vessels.values():
		if not _applies_to_player(v):
			continue
		var t := token(v.token_id)
		if t.action == action and not t.is_prohibition and not t.is_lent():
			return true
	return false


func _applies_to_player(v: RuleVessel) -> bool:
	if v.location == RuleVessel.Location.EQUIPPED:
		return true
	return v.location == RuleVessel.Location.HOTBAR and not v.is_equipment()


## 部位に装備している器（無ければ null）。
func equipped_vessel(part: RuleVessel.Part) -> RuleVessel:
	for v: RuleVessel in _vessels.values():
		if v.location == RuleVessel.Location.EQUIPPED and v.part == part:
			return v
	return null


func player_prohibited(action: RuleAction.Kind) -> bool:
	for v: RuleVessel in _vessels.values():
		if v.location == RuleVessel.Location.WORLD:
			continue
		var t := token(v.token_id)
		if t.action == action and t.is_prohibition and not t.is_lent():
			return true
	return false


func entity_has_ability(entity_id: int, action: RuleAction.Kind) -> bool:
	if entity_id == PLAYER_ID:
		return player_has_ability(action)
	for t: RuleToken in _tokens.values():
		if not t.is_prohibition and t.action == action and t.holder_ids.has(entity_id):
			return true
	return false


func entity_prohibited(entity_id: int, action: RuleAction.Kind) -> bool:
	if entity_id == PLAYER_ID:
		return player_prohibited(action)
	for t: RuleToken in _tokens.values():
		if t.is_prohibition and t.action == action and t.holder_ids.has(entity_id):
			return true
	return false


## 対象が自分からその行動を始められるか（禁止優先）。外力で動かされることは妨げない。
func can_initiate(entity_id: int, action: RuleAction.Kind) -> bool:
	return entity_has_ability(entity_id, action) and not entity_prohibited(entity_id, action)


func tokens_on(entity_id: int) -> Array[RuleToken]:
	var result: Array[RuleToken] = []
	for t: RuleToken in _tokens.values():
		if t.holder_ids.has(entity_id):
			result.append(t)
	result.sort_custom(func(a: RuleToken, b: RuleToken) -> bool: return a.id < b.id)
	return result


## プレイヤーが貸し出し中の単発トークンのうち、その行動のもの（対応キーで起動する）。
func pending_single_shots(action: RuleAction.Kind) -> Array[RuleToken]:
	var result: Array[RuleToken] = []
	for t: RuleToken in _tokens.values():
		if (
			t.vessel_id != -1
			and t.is_lent()
			and t.mode == TriggerMode.Kind.SINGLE_SHOT
			and t.action == action
		):
			result.append(t)
	result.sort_custom(func(a: RuleToken, b: RuleToken) -> bool: return a.id < b.id)
	return result


## ブロックが繰り返し方式で持つ行動（付与された順）。
func repeat_actions(entity_id: int) -> Array[RuleAction.Kind]:
	var result: Array[RuleAction.Kind] = []
	for t: RuleToken in tokens_on(entity_id):
		if not t.is_prohibition and t.mode == TriggerMode.Kind.REPEAT:
			result.append(t.action)
	return result


## ブロックが信号方式で持つ行動（付与された順）。音波が届いている間だけ発動する（企画書 5.2）。
func signal_actions(entity_id: int) -> Array[RuleAction.Kind]:
	var result: Array[RuleAction.Kind] = []
	for t: RuleToken in tokens_on(entity_id):
		if not t.is_prohibition and t.mode == TriggerMode.Kind.SIGNAL:
			result.append(t.action)
	return result


## 範囲付与されたトークンのうち、position（水平距離）がその円の中にあるもの。
## 縦方向は付与した層から上下 vertical_reach ブロック以内（仮値。範囲の上に立って回収するため）。
func range_tokens_at(position: Vector3, vertical_reach: float = 3.0) -> Array[RuleToken]:
	var result: Array[RuleToken] = []
	for t: RuleToken in _tokens.values():
		if not t.is_range or not t.is_lent():
			continue
		var flat := Vector2(position.x - t.range_center.x, position.z - t.range_center.z)
		var dy := absf(position.y - float(t.range_layer))
		if flat.length() <= t.range_radius and dy <= vertical_reach:
			result.append(t)
	return result


# --- 操作 -------------------------------------------------------------------


## ホットバーの器から能力・禁止を付与する。
## range_spec が空でなければ範囲付与: {"center": Vector3, "radius": float, "layer": int}
func lend(
	vessel_id: int,
	target_ids: PackedInt32Array,
	mode: TriggerMode.Kind,
	range_spec: Dictionary = {}
) -> LendResult:
	var v := vessel(vessel_id)
	if v == null:
		return LendResult.NO_SUCH_VESSEL
	if v.location == RuleVessel.Location.EQUIPPED:
		return LendResult.EQUIPPED_CANNOT_LEND
	if v.location != RuleVessel.Location.HOTBAR:
		return LendResult.NOT_IN_HOTBAR
	var t := token(v.token_id)
	if t.is_lent():
		return LendResult.ALREADY_LENT
	var is_range := not range_spec.is_empty()
	var check := _validate_targets(t, target_ids, mode, is_range)
	if check != LendResult.OK:
		return check
	t.holder_ids = target_ids.duplicate()
	var uses_mode := _all_blocks(target_ids) and _needs_mode(t)
	t.mode = mode if uses_mode else TriggerMode.Kind.NONE
	t.is_range = is_range
	if is_range:
		t.range_center = range_spec["center"] as Vector3
		t.range_radius = float(range_spec["radius"])
		t.range_layer = int(range_spec["layer"])
	changed.emit()
	return LendResult.OK


## 付与中のトークンを器へ戻す。範囲付与なら全ブロックから一括で戻る。
## レベルに設置されていたトークン（器なし）は、拾ったものとして通常インベントリに新しい器を作る。
func recall(token_id: int) -> bool:
	var t := token(token_id)
	if t == null or not t.is_lent():
		return false
	if t.vessel_id == -1:
		var v := _new_vessel(t)
		v.location = RuleVessel.Location.INVENTORY
	_clear_lend(t)
	changed.emit()
	return true


## その対象が持つトークンをすべて回収する（F）。回収したトークンIDを返す。
func recall_from_entity(entity_id: int) -> PackedInt32Array:
	var recalled := PackedInt32Array()
	for t: RuleToken in tokens_on(entity_id):
		if recall(t.id):
			recalled.append(t.id)
	return recalled


## 単発の結果を報告する。いずれかの対象が成功していれば器へ自動返還する（返還したら true）。
## 範囲単発で一部だけ成功した場合も返還する、は未決事項に対する仮の方針（docs/TODO.md）。
func complete_single_shot(token_id: int, results: Array[BlockRules.Attempt]) -> bool:
	var t := token(token_id)
	if t == null or t.mode != TriggerMode.Kind.SINGLE_SHOT or not t.is_lent():
		return false
	if not BlockRules.single_shot_succeeded(results):
		return false
	_clear_lend(t)
	changed.emit()
	return true


## 世界に落ちている器を拾い、通常インベントリへ入れる（企画書 7: F で拾ったものは通常インベントリへ）。
func pickup(vessel_id: int) -> bool:
	var v := vessel(vessel_id)
	if v == null or v.location != RuleVessel.Location.WORLD:
		return false
	v.location = RuleVessel.Location.INVENTORY
	v.slot = -1
	changed.emit()
	return true


## 装備品を装備欄へ。同じ部位に別の装備があれば、入れ替えて元の場所（ホットバーの枠か通常インベントリ）へ移す。
func equip(vessel_id: int) -> EquipResult:
	var v := vessel(vessel_id)
	if v == null:
		return EquipResult.NO_SUCH_VESSEL
	if not v.is_equipment():
		return EquipResult.NOT_EQUIPMENT
	if v.location == RuleVessel.Location.WORLD:
		return EquipResult.NOT_CARRIED
	if token(v.token_id).is_lent():
		return EquipResult.LENT
	if v.location == RuleVessel.Location.EQUIPPED:
		return EquipResult.OK
	var occupant := equipped_vessel(v.part)
	if occupant != null:
		occupant.location = v.location
		occupant.slot = v.slot
	v.location = RuleVessel.Location.EQUIPPED
	v.slot = -1
	changed.emit()
	return EquipResult.OK


## 装備を外して通常インベントリへ。
func unequip(vessel_id: int) -> bool:
	var v := vessel(vessel_id)
	if v == null or v.location != RuleVessel.Location.EQUIPPED:
		return false
	return move_to_inventory(vessel_id)


## 通常インベントリの器をホットバーの slot へ移す。slot に器があれば入れ替える。
func move_to_hotbar(vessel_id: int, slot: int) -> bool:
	var v := vessel(vessel_id)
	if v == null or slot < 0 or slot >= HOTBAR_SIZE:
		return false
	if v.location == RuleVessel.Location.WORLD:
		return false
	var occupant := hotbar_vessel(slot)
	if occupant == v:
		return true
	if occupant != null:
		var into_equipment := v.location == RuleVessel.Location.EQUIPPED
		if into_equipment and (occupant.part != v.part or token(occupant.token_id).is_lent()):
			# 装備欄の部位に合わない（または貸出中の）器とは入れ替えず、押し出された器は通常インベントリへ
			occupant.location = RuleVessel.Location.INVENTORY
			occupant.slot = -1
		else:
			occupant.location = v.location
			occupant.slot = v.slot
	v.location = RuleVessel.Location.HOTBAR
	v.slot = slot
	changed.emit()
	return true


## ホットバーの器を通常インベントリへ戻す。
func move_to_inventory(vessel_id: int) -> bool:
	var v := vessel(vessel_id)
	if v == null or v.location == RuleVessel.Location.WORLD:
		return false
	v.location = RuleVessel.Location.INVENTORY
	v.slot = -1
	changed.emit()
	return true


# --- チェックポイント -------------------------------------------------------


func snapshot() -> Dictionary:
	var tokens: Array[Dictionary] = []
	for t: RuleToken in _tokens.values():
		tokens.append(t.to_dict())
	var vessels: Array[Dictionary] = []
	for v: RuleVessel in _vessels.values():
		vessels.append(v.to_dict())
	return {
		"entities": _entities.duplicate(),
		"tokens": tokens,
		"vessels": vessels,
		"next_token_id": _next_token_id,
		"next_vessel_id": _next_vessel_id,
	}


## snapshot() の時点へ丸ごと戻す。トークンは置き換えるので二重生成しない。
func restore(data: Dictionary) -> void:
	_entities.clear()
	var entities := data["entities"] as Dictionary
	for key: int in entities:
		_entities[key] = int(entities[key]) as EntityKind.Kind
	_tokens.clear()
	for d: Dictionary in data["tokens"] as Array:
		var t := RuleToken.from_dict(d)
		_tokens[t.id] = t
	_vessels.clear()
	for d: Dictionary in data["vessels"] as Array:
		var v := RuleVessel.from_dict(d)
		_vessels[v.id] = v
	_next_token_id = int(data["next_token_id"])
	_next_vessel_id = int(data["next_vessel_id"])
	changed.emit()


## 不変条件の違反を列挙する（テスト・デバッグ用）。空なら正常。
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var used_slots := {}
	for v: RuleVessel in _vessels.values():
		var t := token(v.token_id)
		if t == null:
			errors.append("vessel %d has missing token %d" % [v.id, v.token_id])
		elif t.vessel_id != v.id:
			errors.append("token %d does not point back to vessel %d" % [t.id, v.id])
		if v.location == RuleVessel.Location.HOTBAR:
			if v.slot < 0 or v.slot >= HOTBAR_SIZE:
				errors.append("vessel %d has invalid hotbar slot %d" % [v.id, v.slot])
			elif used_slots.has(v.slot):
				errors.append("hotbar slot %d used twice" % v.slot)
			used_slots[v.slot] = true
	var used_parts := {}
	for v: RuleVessel in _vessels.values():
		if v.location != RuleVessel.Location.EQUIPPED:
			continue
		if not v.is_equipment():
			errors.append("vessel %d is equipped but is not equipment" % v.id)
		elif used_parts.has(v.part):
			errors.append("part %d equipped twice" % v.part)
		used_parts[v.part] = true
		if token(v.token_id) != null and token(v.token_id).is_lent():
			errors.append("equipped vessel %d has its ability lent" % v.id)
	for v: RuleVessel in _vessels.values():
		if v.location == RuleVessel.Location.WORLD and token(v.token_id) != null:
			if token(v.token_id).is_lent():
				errors.append("token %d is lent from a vessel still in the world" % v.token_id)
	for t: RuleToken in _tokens.values():
		if t.vessel_id == -1 and not t.is_lent():
			errors.append("token %d is neither in a vessel nor placed" % t.id)
		if t.vessel_id != -1 and not _vessels.has(t.vessel_id):
			errors.append("token %d points to missing vessel" % t.id)
		for holder in t.holder_ids:
			if not _entities.has(holder):
				errors.append("token %d held by unknown entity %d" % [t.id, holder])
			if holder == PLAYER_ID:
				errors.append("token %d lent to the player" % t.id)
	return errors


# --- 内部 -------------------------------------------------------------------


func _validate_targets(
	t: RuleToken, target_ids: PackedInt32Array, mode: TriggerMode.Kind, is_range: bool
) -> LendResult:
	if target_ids.is_empty() or (not is_range and target_ids.size() != 1):
		return LendResult.NO_TARGETS
	var known := _validate_known_targets(target_ids)
	if known != LendResult.OK:
		return known
	var all_blocks := _all_blocks(target_ids)
	if is_range and not all_blocks:
		return LendResult.RANGE_ONLY_FOR_BLOCKS
	if is_range and t.is_prohibition:
		return LendResult.RANGE_PROHIBITION_UNSUPPORTED
	if all_blocks and _needs_mode(t):
		return _validate_block_mode(mode)
	return LendResult.OK


## ブロックへ渡すときに発動方式が要るか（能力で、1回ずつ起こす行動のとき）。
func _needs_mode(t: RuleToken) -> bool:
	return not t.is_prohibition and RuleAction.is_triggered(t.action)


func _validate_known_targets(target_ids: PackedInt32Array) -> LendResult:
	for target in target_ids:
		if not _entities.has(target):
			return LendResult.UNKNOWN_TARGET
		if target == PLAYER_ID:
			return LendResult.CANNOT_TARGET_PLAYER
	return LendResult.OK


func _validate_block_mode(mode: TriggerMode.Kind) -> LendResult:
	if mode == TriggerMode.Kind.NONE:
		return LendResult.MODE_REQUIRED_FOR_BLOCK
	if not TriggerMode.is_supported(mode):
		return LendResult.MODE_NOT_SUPPORTED
	return LendResult.OK


func _all_blocks(target_ids: PackedInt32Array) -> bool:
	for target in target_ids:
		if _entities.get(target, -1) != EntityKind.Kind.BLOCK:
			return false
	return true


func _clear_lend(t: RuleToken) -> void:
	t.holder_ids = PackedInt32Array()
	t.mode = TriggerMode.Kind.NONE
	t.is_range = false
	t.range_center = Vector3.ZERO
	t.range_radius = 0.0
	t.range_layer = 0


func _new_token(action: RuleAction.Kind, is_prohibition: bool) -> RuleToken:
	var t := RuleToken.new()
	t.id = _next_token_id
	_next_token_id += 1
	t.action = action
	t.is_prohibition = is_prohibition
	_tokens[t.id] = t
	return t


func _new_vessel(t: RuleToken) -> RuleVessel:
	var v := RuleVessel.new()
	v.id = _next_vessel_id
	_next_vessel_id += 1
	v.token_id = t.id
	t.vessel_id = v.id
	_vessels[v.id] = v
	return v
