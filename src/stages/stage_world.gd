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

const TERRAIN_COLORS := {
	"grass": Color(0.56, 0.74, 0.42),
	"rock": Color(0.62, 0.6, 0.58),
	"sand": Color(0.86, 0.78, 0.58)
}
const CHECKPOINT_RADIUS: float = 1.3

var def: StageDef
## ステージの key → 台帳の entity_id。
var entity_ids: Dictionary = {}
## 鐘の key → 鐘（ACTIVATE のクリア条件用）。
var bells_by_key: Dictionary[String, Bell] = {}
## 鳴らされた鐘など、作動した仕掛けの key。
var activated: PackedStringArray = PackedStringArray()
## 「やり直す」操作（メニューの戻る・最初から）を全員リセットの投票にする（PartyDirector が渡す）。
var vote_request: Callable = Callable()


## add_child の前に呼ぶ。
func setup(stage: StageDef) -> void:
	def = stage
	name = "Stage_%s" % stage.stage_id


func _ready() -> void:
	super._ready()
	# チェックポイント・落下は PartyDirector が受け持つ（GameWorld の1人用の保存と復元を使わない）
	networked = true
	PrototypeIsland.build_environment(self)
	for box: Array in def.terrain_boxes:
		var kind := String(box[2]) if box.size() > 2 else "grass"
		var color := TERRAIN_COLORS.get(kind, TERRAIN_COLORS["grass"]) as Color
		TerrainBuilder.add_box(self, box[0] as Vector3i, box[1] as Vector3i, color)
	for b in def.blocks:
		var block := (
			add_launcher(b.cell, b.launcher_direction)
			if b.is_launcher()
			else add_block(b.cell, b.color)
		)
		entity_ids[b.key] = block.entity_id
	for c in def.creatures:
		var creature := add_creature(c.position)
		creature.held_item = c.held_item
		entity_ids[c.key] = creature.entity_id
	for spec in def.bells:
		var bell := add_bell(spec.position)
		bells_by_key[spec.key] = bell
		bell.rang.connect(func() -> void: _mark_activated(spec.key))
	for i in def.checkpoints.size():
		_add_pad(def.checkpoints[i], "チェックポイント")
	for e in def.entrances:
		_add_pad(e.position, "入口: %s（F）" % StageCatalog.by_id(e.stage_id).display_name)
	spawn_player(def.spawn_point(0))


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
func interact(target: Node3D) -> void:
	if replica or player == null:
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
	restore_checkpoint()


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


func _mark_activated(key: String) -> void:
	if not activated.has(key):
		activated.append(key)


func _add_pad(at: Vector3, text: String) -> void:
	var pad := ModelLibrary.instantiate("checkpoint_pad")
	pad.position = at
	add_child(pad)
	PrototypeIsland.add_label(self, at + Vector3(0.0, 1.9, 0.0), text)
