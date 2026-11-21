class_name StageWorld
extends GameWorld
## StageDef から組み立てた島（ハブもステージも）。ルール・物理・操作は GameWorld のまま。
## チェックポイント・死亡・クリアは PartyDirector が受け持つので、1人用の
## 「F で保存」「落ちたら保存した時点へ戻る」はここでは使わない。
## ブロック・生き物は定義の順に作るので、entity_id は StageLoadout.register_entities と同じになる。

## チェックポイントの台座の上で F を押したとき（全員復活の操作）。
signal checkpoint_interacted(player_id: int, checkpoint_id: String)
## ハブの入口で F を押したとき。
signal entrance_chosen(player_id: int, stage_id: String)
## 帰り道の台座で F を押したとき（広場へ戻す）。
signal return_chosen(player_id: int)
## 広場の小さな発見の場所に、自分が入ったとき（知らせを出すだけ）。
signal secret_found(key: String)

const CHECKPOINT_RADIUS: float = 1.3
## 入口・帰り道の門の上に浮かべる文字の高さ（門の吊り札より上）。
const GATE_LABEL_HEIGHT: float = 2.95

var def: StageDef
## ステージの key → 台帳の entity_id。
var entity_ids: Dictionary = {}
## 鐘の key → 鐘（ACTIVATE のクリア条件用）。
var bells_by_key: Dictionary[String, Bell] = {}
## 鳴らされた鐘など、作動した仕掛けの key。
var activated: PackedStringArray = PackedStringArray()
## 見つけた広場の発見（この島にいる間だけ覚える。出入りするとまた見つけられる）。
var found_secrets: PackedStringArray = PackedStringArray()
## 「やり直す」操作（メニューの戻る・最初から）を全員リセットの投票にする（PartyDirector が渡す）。
var vote_request: Callable = Callable()
## メニューの「島のはじめから」（PartyDirector が渡す。ひとりなら本当に最初から）。
var restart_request: Callable = Callable()


## add_child の前に呼ぶ。
func setup(stage: StageDef) -> void:
	def = stage
	name = "Stage_%s" % stage.stage_id


func _ready() -> void:
	super._ready()
	# チェックポイント・落下は PartyDirector が受け持つ（GameWorld の1人用の保存と復元を使わない）
	networked = true
	PrototypeIsland.build_environment(self)
	# 地形のどのセルにも能力を渡せる（渡したセルは動くブロックになる）
	build_terrain(def.terrain_boxes)
	for b in def.blocks:
		var block := (
			add_launcher(b.cell, b.launcher_direction)
			if b.is_launcher()
			else add_block(b.cell, b.color)
		)
		entity_ids[b.key] = block.entity_id
	for c in def.creatures:
		var creature := add_creature(c.position, c.look)
		creature.held_item = c.held_item
		entity_ids[c.key] = creature.entity_id
	for spec in def.bells:
		var bell := add_bell(spec.position)
		bells_by_key[spec.key] = bell
		bell.rang.connect(func() -> void: _mark_activated(spec.key))
	MechanismSet.build(self, def.mechanisms)  # 重さの板・扉・レバー・時の鐘・ワープの石（docs/adr/0014）
	for i in def.checkpoints.size():
		_add_pad(def.checkpoints[i], "チェックポイント", "checkpoint_pad", 1.9)
	for pad in def.return_pads:
		_add_pad(
			pad, "広場へ戻る（%s）" % InputMode.token(&"interact"), "entrance_gate", GATE_LABEL_HEIGHT
		)
	# 広場のポータル・住む生き物・建物（OverworldDressing）。計画に無いステージの入口だけ、従来の門
	if def.overworld != null:
		OverworldDressing.build(self, def.overworld)
	for e in def.entrances:
		if def.overworld != null and def.overworld.portal(e.stage_id) != null:
			continue
		var stage := StageCatalog.by_id(e.stage_id)
		_add_pad(
			e.position,
			(
				"%s\n目安 %d 分（仮）・%s"
				% [stage.display_name, stage.target_minutes, InputMode.token(&"interact")]
			),
			"entrance_gate",
			GATE_LABEL_HEIGHT
		)
	var goal := def.clear_condition.goal_area()
	if goal.has_volume():
		_add_goal_marker(goal)
	spawn_player(def.spawn_point(0))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if def.overworld != null and player != null:
		_check_secrets()


## 自分が広場の発見の場所に入ったら、一度だけ知らせる（ルールは何も変えない）。
func _check_secrets() -> void:
	for secret in def.overworld.secrets:
		if found_secrets.has(secret.key) or not secret.area.has_point(player.global_position):
			continue
		found_secrets.append(secret.key)
		message_posted.emit(secret.text)
		sound_requested.emit(&"goal", player.global_position, false)
		secret_found.emit(secret.key)


## プレイヤーの出現位置（プレイヤー ID の順に 4 か所）。
func spawn_for(player_id: int) -> Vector3:
	return def.spawn_point(clampi(player_id - RuleLedger.PLAYER_ID, 0, StageDef.MAX_PLAYERS - 1))


## プレイヤーが立っているチェックポイント（無ければ ""）。
func checkpoint_at(at: Vector3) -> String:
	for i in def.checkpoints.size():
		var flat := at - def.checkpoints[i]
		flat.y = 0.0
		if flat.length() <= CHECKPOINT_RADIUS and absf(at.y - def.checkpoints[i].y) < 1.0:
			return "cp%d" % i
	return ""


## チェックポイントの位置（"cp0" など。知らなければ出現地点）。
func checkpoint_position(checkpoint_id: String) -> Vector3:
	var index := int(checkpoint_id.trim_prefix("cp")) if checkpoint_id.begins_with("cp") else -1
	if index >= 0 and index < def.checkpoints.size():
		return def.checkpoints[index]
	return def.spawn_point(0)


## プレイヤーが立っているハブの入口（無ければ ""）。
func entrance_at(at: Vector3) -> String:
	for e in def.entrances:
		if e.area.has_point(at + Vector3(0.0, 0.1, 0.0)):
			return e.stage_id
	return ""


## 1人用の「F で保存」の代わり: 台座の上の F は全員復活、入口の F はステージに入る。
## 足もとに拾える物があるとき・手の届く物を狙っているときは、そちらを優先する（台座より先）。
func interact(target: Node3D) -> void:
	if not replica and player != null and MechanismSet.try_interact(self):
		return  # 手の届くレバーを倒した
	if replica or player == null or _has_something_to_handle(target):
		super.interact(target)
		return
	var cp := checkpoint_at(player.global_position)
	if cp != "":
		checkpoint_interacted.emit(acting_id(), cp)
		return
	var entrance := entrance_at(player.global_position)
	if entrance != "":
		entrance_chosen.emit(acting_id(), entrance)
		return
	if _near_any(def.return_pads, player.global_position):
		return_chosen.emit(acting_id())
		return
	super.interact(target)


## GameWorld の「F でチェックポイントに保存」を使わない。
func is_on_checkpoint() -> bool:
	return false


## メニューの「戻る」「最初から」は、全員リセットの投票になる（1人なら自分の1票で成立）。
func restore_checkpoint() -> void:
	if vote_request.is_valid():
		vote_request.call()


func restore_previous_checkpoint() -> bool:
	restore_checkpoint()
	return true


func restart_island() -> void:
	if restart_request.is_valid():
		restart_request.call()


func can_restore_previous_checkpoint() -> bool:
	return true


## クリア条件の判定に渡す世界の様子（ClearCondition.is_met の形）。
## positions は正式参加者（players）のアバターの位置、active は生きて操作している人。
func clear_snapshot(players: PackedInt32Array, active: PackedInt32Array) -> Dictionary:
	var positions := {}
	for player_id in players:
		var avatar := avatar_of(player_id)
		if avatar != null:
			positions[player_id] = avatar.global_position
	var entities := {}
	for key: String in entity_ids:
		var id := int(entity_ids[key])
		if blocks.has(id):
			entities[key] = blocks[id].global_position
		elif creatures.has(id):
			entities[key] = creatures[id].global_position
	return {"positions": positions, "active": active, "entities": entities, "activated": activated}


func _has_something_to_handle(target: Node3D) -> bool:
	if nearest_world_item() != null:
		return true
	if WorldQueries.nearest_dropped(ledger, player.global_position) != -1:
		return true
	return target != null and is_within_reach(target)


func _near_any(points: Array[Vector3], at: Vector3) -> bool:
	for p in points:
		var flat := at - p
		flat.y = 0.0
		if flat.length() <= CHECKPOINT_RADIUS and absf(at.y - p.y) < 1.0:
			return true
	return false


func _mark_activated(key: String) -> void:
	if not activated.has(key):
		activated.append(key)


## ゴールの目印（旗と四隅の灯り、床の板）。当たり判定は持たない（光線も遮らない）。
func _add_goal_marker(goal: AABB) -> void:
	var marker := GoalMarker.new()
	marker.setup(goal)
	add_child(marker)
	var label_at := marker.position + Vector3(0.0, 3.4, 0.0)
	PrototypeIsland.add_label(self, label_at, "ゴール（全員で集まる）")


func _add_pad(at: Vector3, text: String, model_name: String, label_height: float) -> void:
	var pad := ModelLibrary.instantiate(model_name)
	pad.position = at
	add_child(pad)
	PrototypeIsland.add_label(self, at + Vector3(0.0, label_height, 0.0), text)
