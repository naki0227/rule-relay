class_name RuleLedger
extends RefCounted
## 能力・禁止トークンと器の所有を一元管理する。ノード・入力・物理に依存しない。
##
## 守る不変条件（validate() で検査する）:
## - トークンは「器の中」「付与先」「レベルに設置」のどれか1か所にだけある（複製しない）
## - 器はホットバー（9枠）・通常インベントリ（無制限）・装備欄・世界（未回収）のどこか1か所にある
## - 同じ行為に能力と禁止が重なれば禁止を優先する
## - 器を持つのはプレイヤー（owner_id）。能力を仲間へ渡しても器は持ち主に残る
##
## 複数プレイヤー（1〜4人。2026-11-19 本人確定。Vault 提案書 15〜17・27〜30）:
## - 能力はプレイヤー間で直接渡せる（受け手の承認なし。give_to_player）。範囲付与はブロックだけ
## - 同じ能力を複数持つと数だけ効果が強まる（ability_count。空の器は数えない）
## - F で回収した人が受け取る（元の持ち主へは戻さない）
## - 単発の自動返還先は、直前にその能力を付与した人。その人が退出していたら現場に落ちる
## - 出自（vessel_id）は書き換えない。持ち主の器に戻るのは、持ち主本人の手に渡ったときだけ
## 1人用の呼び出しは player_id を省略すると PLAYER_ID として動き、従来どおり。

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
	MODE_REQUIRED_FOR_BLOCK,
	MODE_NOT_SUPPORTED,
	EQUIPPED_CANNOT_LEND,
	## そのプレイヤーの手元にない（他人の器・他人が持っているトークン）か、そのプレイヤーが退出している
	NOT_HELD,
	## 禁止をプレイヤーへ直接渡すかは未決（2026-11-20 時点）。いまは渡せない
	PROHIBITION_TO_PLAYER,
}

enum EquipResult {
	OK,
	NO_SUCH_VESSEL,
	NOT_EQUIPMENT,
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
## 参加中のプレイヤー。退出したプレイヤーは _entities に残るが、ここから外れる。
var _present: Dictionary[int, bool] = {}


func _init() -> void:
	_entities[PLAYER_ID] = EntityKind.Kind.PLAYER
	_present[PLAYER_ID] = true


# --- 登録・初期配置 ---------------------------------------------------------


func register_entity(entity_id: int, kind: EntityKind.Kind) -> void:
	assert(entity_id != PLAYER_ID, "PLAYER_ID is reserved")
	assert(kind != EntityKind.Kind.PLAYER, "use register_player")
	_entities[entity_id] = kind


## 2人目以降のプレイヤーを参加させる（PLAYER_ID は最初からいる）。
func register_player(player_id: int) -> void:
	assert(not _entities.has(player_id), "entity id already used")
	_entities[player_id] = EntityKind.Kind.PLAYER
	_present[player_id] = true
	changed.emit()


## 退出・再参加。退出しても、その人がブロック等へ付与した能力は残る（2026-11-19 本人確定）。
## 退出した人の手元の器・受け取っていた能力をどうするかは未決なので、ここでは何も動かさない。
func set_player_present(player_id: int, present: bool) -> void:
	assert(_entities.get(player_id, -1) == EntityKind.Kind.PLAYER, "not a player")
	if present:
		_present[player_id] = true
	else:
		_present.erase(player_id)
	changed.emit()


## 参加中のプレイヤー（ID 順）。
func players() -> PackedInt32Array:
	var ids := PackedInt32Array(_present.keys())
	ids.sort()
	return ids


## 付与先を取り除く（地形から動くブロックにしたセルを、地形へ戻すとき）。付いていたトークンは戻らないので、
## 呼ぶ側で先に回収するか、台帳ごと restore すること。
func unregister_entity(entity_id: int) -> void:
	_entities.erase(entity_id)


func entity_kind(entity_id: int) -> EntityKind.Kind:
	return _entities[entity_id]


func has_entity(entity_id: int) -> bool:
	return _entities.has(entity_id)


## プレイヤーの器を1つ作る。hotbar_slot が 0〜8 ならホットバーへ、-1 なら通常インベントリへ。
func give_player_item(
	action: RuleAction.Kind, is_prohibition: bool, hotbar_slot: int = -1, player_id: int = PLAYER_ID
) -> RuleVessel:
	assert(_present.has(player_id), "unknown or absent player")
	var token := _new_token(action, is_prohibition)
	var vessel := _new_vessel(token)
	vessel.owner_id = player_id
	if hotbar_slot >= 0:
		assert(hotbar_vessel(hotbar_slot, player_id) == null, "hotbar slot already used")
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
	vessel.owner_id = -1
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


func hotbar_vessel(slot: int, player_id: int = PLAYER_ID) -> RuleVessel:
	for v: RuleVessel in _vessels.values():
		if v.location == RuleVessel.Location.HOTBAR and v.slot == slot and v.owner_id == player_id:
			return v
	return null


func inventory_vessels(player_id: int = PLAYER_ID) -> Array[RuleVessel]:
	var result: Array[RuleVessel] = []
	for v: RuleVessel in _vessels.values():
		if v.location == RuleVessel.Location.INVENTORY and v.owner_id == player_id:
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


## すべてのトークン（ID 順。PartyQuery・LedgerValidator など読み取り専用の問い合わせ用）。
func all_tokens() -> Array[RuleToken]:
	var result: Array[RuleToken] = []
	for t: RuleToken in _tokens.values():
		result.append(t)
	result.sort_custom(func(a: RuleToken, b: RuleToken) -> bool: return a.id < b.id)
	return result


## すべての器（ID 順。読み取り専用の問い合わせ用）。
func all_vessels() -> Array[RuleVessel]:
	var result: Array[RuleVessel] = []
	for v: RuleVessel in _vessels.values():
		result.append(v)
	result.sort_custom(func(a: RuleVessel, b: RuleVessel) -> bool: return a.id < b.id)
	return result


## プレイヤー自身がその行動を始められるか。
## 能力はホットバーにあり貸出中でないときだけ有効。禁止は手元（ホットバー・通常インベントリ）の
## どこにあっても有効で、能力より優先する（企画書 7）。
func player_can(action: RuleAction.Kind, player_id: int = PLAYER_ID) -> bool:
	return player_has_ability(action, player_id) and not player_prohibited(action, player_id)


## 能力が自分に効くのは、ホットバーの普通の器と、装備欄の装備だけ（企画書 7）。
## ホットバーに置いた装備品は、装備していないので効かない（付与の元にはできる）。
func player_has_ability(action: RuleAction.Kind, player_id: int = PLAYER_ID) -> bool:
	return ability_count(action, player_id) > 0


## そのプレイヤーに効いている同じ能力の数（禁止は考えない。禁止の判定は player_can）。
## 4人のジャンプを1人に集めれば 4（2026-11-19 本人確定: 数に比例して効果が強まる）。
## 仲間から受け取った・回収した能力は、器が無いまま効く扱い（仮。受け取った能力の置き場の UI は未決）。
func ability_count(action: RuleAction.Kind, player_id: int = PLAYER_ID) -> int:
	var count := 0
	for t: RuleToken in _tokens.values():
		if not t.is_prohibition and t.action == action and _held_by(t, player_id, true):
			count += 1
	return count


## そのトークンがプレイヤーの手元で効くか。for_ability なら能力の効き方、そうでなければ禁止の効き方。
func _held_by(t: RuleToken, player_id: int, for_ability: bool) -> bool:
	if t.carrier_id != -1:
		return t.carrier_id == player_id
	if not t.is_in_vessel():
		return false
	var v := vessel(t.vessel_id)
	if v == null or v.owner_id != player_id:
		return false
	return _applies_to_player(v) if for_ability else v.location != RuleVessel.Location.WORLD


func _applies_to_player(v: RuleVessel) -> bool:
	if v.location == RuleVessel.Location.EQUIPPED:
		return true
	return v.location == RuleVessel.Location.HOTBAR and not v.is_equipment()


## 部位に装備している器（無ければ null）。
func equipped_vessel(part: RuleVessel.Part, player_id: int = PLAYER_ID) -> RuleVessel:
	for v: RuleVessel in _vessels.values():
		var here := v.location == RuleVessel.Location.EQUIPPED and v.owner_id == player_id
		if here and v.part == part:
			return v
	return null


## 禁止は手元（ホットバー・通常インベントリ・装備欄、回収して持っているもの）のどこにあっても効く。
func player_prohibited(action: RuleAction.Kind, player_id: int = PLAYER_ID) -> bool:
	for t: RuleToken in _tokens.values():
		if t.is_prohibition and t.action == action and _held_by(t, player_id, false):
			return true
	return false


func entity_has_ability(entity_id: int, action: RuleAction.Kind) -> bool:
	if _entities.get(entity_id, -1) == EntityKind.Kind.PLAYER:
		return player_has_ability(action, entity_id)
	for t: RuleToken in _tokens.values():
		if not t.is_prohibition and t.action == action and t.holder_ids.has(entity_id):
			return true
	return false


func entity_prohibited(entity_id: int, action: RuleAction.Kind) -> bool:
	if _entities.get(entity_id, -1) == EntityKind.Kind.PLAYER:
		return player_prohibited(action, entity_id)
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


## プレイヤーが貸し出し中の単発トークンのうち、その行動のもの（付与した人の対応キーで起動する）。
## レベルに最初から置かれた単発（付与した人がいない）は含まない。
func pending_single_shots(action: RuleAction.Kind, player_id: int = PLAYER_ID) -> Array[RuleToken]:
	var result: Array[RuleToken] = []
	for t: RuleToken in _tokens.values():
		if (
			t.lender_id == player_id
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


## ホットバーの器から能力・禁止を付与する（器の持ち主が付与する）。
## range_spec が空でなければ範囲付与: {"center": Vector3, "radius": float, "layer": int}
## プレイヤーへ渡すときは give_to_player を使う（ここではプレイヤーを対象にできない）。
func lend(
	vessel_id: int,
	target_ids: PackedInt32Array,
	mode: TriggerMode.Kind,
	range_spec: Dictionary = {}
) -> LendResult:
	var v := vessel(vessel_id)
	if v == null:
		return LendResult.NO_SUCH_VESSEL
	return lend_token(v.token_id, v.owner_id, target_ids, mode, range_spec)


## by_player の手元のトークン（ホットバーの自分の器、または受け取って持っているもの）を付与する。
func lend_token(
	token_id: int,
	by_player: int,
	target_ids: PackedInt32Array,
	mode: TriggerMode.Kind,
	range_spec: Dictionary = {}
) -> LendResult:
	var t := token(token_id)
	if t == null:
		return LendResult.NO_SUCH_VESSEL
	var source := _lend_source(t, by_player)
	if source != LendResult.OK:
		return source
	var is_range := not range_spec.is_empty()
	var check := _validate_targets(t, target_ids, mode, is_range)
	if check != LendResult.OK:
		return check
	t.carrier_id = -1
	t.lender_id = by_player
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


## 能力を仲間へ直接渡す（受け手の承認なし。2026-11-19 本人確定）。器は from_player に残る。
## 渡した先が元の器の持ち主なら、その器へ戻る。
func give_to_player(token_id: int, from_player: int, to_player: int) -> LendResult:
	var t := token(token_id)
	if t == null:
		return LendResult.NO_SUCH_VESSEL
	if t.is_prohibition:
		return LendResult.PROHIBITION_TO_PLAYER
	if to_player == from_player or not _present.has(to_player):
		return LendResult.UNKNOWN_TARGET
	var source := _lend_source(t, from_player)
	if source != LendResult.OK:
		return source
	_deliver(t, to_player)
	t.lender_id = from_player
	changed.emit()
	return LendResult.OK


## 付与中のトークンを回収する（F）。範囲付与なら全ブロックから一括で戻る。
## 受け取るのは回収した人（by_player）。元の器の持ち主が回収したら器へ戻る（2026-11-19 本人確定）。
## レベルに設置されていたトークン（器なし）は、拾ったものとして回収した人の通常インベントリに器を作る。
func recall(token_id: int, by_player: int = PLAYER_ID) -> bool:
	var t := token(token_id)
	if t == null or not t.is_lent():
		return false
	_clear_lend(t)
	_deliver(t, by_player)
	changed.emit()
	return true


## その対象が持つトークンをすべて回収する（F）。回収したトークンIDを返す。
func recall_from_entity(entity_id: int, by_player: int = PLAYER_ID) -> PackedInt32Array:
	var recalled := PackedInt32Array()
	for t: RuleToken in tokens_on(entity_id):
		if recall(t.id, by_player):
			recalled.append(t.id)
	return recalled


## 単発を起動した結果を報告し、器へ返す（返したら true）。成功したときはもちろん、
## 発動できなかったとき（禁止・能力なし・塞がれている・空中）も、発動したのと同じ扱いで戻る
## （2026-11-19 本人の判断。単発は手動で回収しなくてよい方式なので、動けないまま残さない）。
## 範囲単発で一部だけ成功した場合も同じく戻る。
## 戻る先は直前に付与した人（元の器の持ち主ではない。2026-11-19 本人確定）。
## その人が退出していたら、成功したときは drop_position に落ちる（同日確定）。誰でも拾える。
## 退出していて失敗したときの扱いは未決なので、ブロックに付けたまま false を返す（F で回収はできる）。
func complete_single_shot(
	token_id: int, results: Array[BlockRules.Attempt], drop_position: Vector3 = Vector3.ZERO
) -> bool:
	var t := token(token_id)
	if t == null or t.mode != TriggerMode.Kind.SINGLE_SHOT or not t.is_lent():
		return false
	if results.is_empty():
		return false
	var lender_left := t.lender_id != -1 and not _present.has(t.lender_id)
	if lender_left and not BlockRules.single_shot_succeeded(results):
		return false
	_clear_lend(t)
	if lender_left:
		t.dropped = true
		t.drop_position = drop_position
	elif t.lender_id != -1:
		_deliver(t, t.lender_id)
	changed.emit()
	return true


## 落ちている能力を拾う。拾った人が受け取る（元の器の持ち主なら器へ戻る）。
func pickup_token(token_id: int, player_id: int = PLAYER_ID) -> bool:
	var t := token(token_id)
	if t == null or not t.dropped or not _present.has(player_id):
		return false
	_deliver(t, player_id)
	changed.emit()
	return true


## 世界に落ちている器を拾い、通常インベントリへ入れる（企画書 7: F で拾ったものは通常インベントリへ）。
func pickup(vessel_id: int, player_id: int = PLAYER_ID) -> bool:
	var v := vessel(vessel_id)
	if v == null or v.location != RuleVessel.Location.WORLD:
		return false
	v.owner_id = player_id
	v.location = RuleVessel.Location.INVENTORY
	v.slot = -1
	changed.emit()
	return true


## 装備品を装備欄へ。同じ部位に別の装備があれば、入れ替えて元の場所（ホットバーの枠か通常インベントリ）へ移す。
## 能力を貸している装備も装備できる。ただし回収するまで、その能力は自分に効かない（2026-11-19 本人の判断）。
func equip(vessel_id: int) -> EquipResult:
	var v := vessel(vessel_id)
	if v == null:
		return EquipResult.NO_SUCH_VESSEL
	if not v.is_equipment():
		return EquipResult.NOT_EQUIPMENT
	if v.location == RuleVessel.Location.WORLD:
		return EquipResult.NOT_CARRIED
	if v.location == RuleVessel.Location.EQUIPPED:
		return EquipResult.OK
	var occupant := equipped_vessel(v.part, v.owner_id)
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
	var occupant := hotbar_vessel(slot, v.owner_id)
	if occupant == v:
		return true
	if occupant != null:
		var into_equipment := v.location == RuleVessel.Location.EQUIPPED
		if into_equipment and occupant.part != v.part:
			# 装備欄の部位に合わない器とは入れ替えず、押し出された器は通常インベントリへ
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
		"present": players(),
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
	_present.clear()
	for id in data.get("present", PackedInt32Array([PLAYER_ID])) as PackedInt32Array:
		_present[id] = true
	changed.emit()


## 不変条件の違反を列挙する（テスト・デバッグ用）。空なら正常。中身は LedgerValidator。
func validate() -> PackedStringArray:
	return LedgerValidator.check(self)


# --- 内部 -------------------------------------------------------------------


## 付与・譲渡の元として by_player の手元にあるか。
func _lend_source(t: RuleToken, by_player: int) -> LendResult:
	if t.carrier_id != -1:
		return _carried_source(t, by_player)
	var v := vessel(t.vessel_id)
	if v == null:
		return LendResult.NO_SUCH_VESSEL
	var place := _vessel_lend_check(v)
	if place != LendResult.OK:
		return place
	if not t.is_in_vessel():
		return LendResult.ALREADY_LENT
	var mine := v.owner_id == by_player and _present.has(by_player)
	return LendResult.OK if mine else LendResult.NOT_HELD


## 器を離れて誰かが持っているトークン。元の器の持ち主から見れば貸出中。
func _carried_source(t: RuleToken, by_player: int) -> LendResult:
	if t.carrier_id == by_player:
		return LendResult.OK if _present.has(by_player) else LendResult.NOT_HELD
	var v := vessel(t.vessel_id)
	var is_origin := v != null and v.owner_id == by_player
	return LendResult.ALREADY_LENT if is_origin else LendResult.NOT_HELD


func _vessel_lend_check(v: RuleVessel) -> LendResult:
	if v.location == RuleVessel.Location.EQUIPPED:
		return LendResult.EQUIPPED_CANNOT_LEND
	if v.location != RuleVessel.Location.HOTBAR:
		return LendResult.NOT_IN_HOTBAR
	return LendResult.OK


## トークンをプレイヤーの手元へ。元の器の持ち主なら器に戻し、そうでなければ器なしで持たせる。
## 器の無いトークン（レベルに置かれていたもの）は、その人の通常インベントリに器を作る。
func _deliver(t: RuleToken, player_id: int) -> void:
	t.dropped = false
	t.drop_position = Vector3.ZERO
	t.carrier_id = -1
	if t.vessel_id == -1:
		var made := _new_vessel(t)
		made.location = RuleVessel.Location.INVENTORY
		made.owner_id = player_id
		return
	if vessel(t.vessel_id).owner_id != player_id:
		t.carrier_id = player_id


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
		if _entities[target] == EntityKind.Kind.PLAYER:
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
