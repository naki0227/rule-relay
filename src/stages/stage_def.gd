class_name StageDef
extends RefCounted
## ステージ1つ分の定義（純粋なデータ。ノード・物理に依存しない。2026-11-20 引き継ぎ仕様 2・3.1・6）。
## コードで組み立てる（.tres は使わない）。実行時の組み立て（地形・ブロックのノード）は別の層が行う。
##
## 座標は PrototypeIsland と同じ: 1ブロック = 1m、北 = -Z、地面の上面が y = 0。
## 地形は PrototypeIsland.terrain_boxes() と同じ形式: [最小のセル, 最大のセル（両端を含む）, 種類]。
## 種類は grass / rock / sand。新しい地形の仕組みは作らない（TerrainBuilder.add_box でそのまま作れる）。
##
## 能力・禁止の置き方は3種類ある:
## - 固定: blocks / creatures の tokens と world_items。人数によらず毎回同じ
## - 開始時の手持ち: loadouts（プレイヤーごとのホットバー）と prohibitions（全員の手元の禁止）
## - 人数別補助: helpers（参加人数ごと）。全員リセットのときだけ作り直す（引き継ぎ仕様 2-7）
## どれもステージ中だけの一時的なトークンで、クリアしたら消える（引き継ぎ仕様 2-8）。

const MAX_PLAYERS: int = 4

var stage_id: String = ""
var display_name: String = ""
## 地形の箱: [Vector3i 最小, Vector3i 最大, String 種類]（PrototypeIsland.terrain_boxes() と同じ）。
var terrain_boxes: Array = []
## プレイヤーの出現位置（参加順に 0〜3）。
var spawn_points: Array[Vector3] = []
var blocks: Array[BlockSpec] = []
var creatures: Array[CreatureSpec] = []
var bells: Array[BellSpec] = []
## 世界に落ちている器（F で拾う）。人数によらない。
var world_items: Array[PlacementSpec] = []
## 参加順ごとのホットバー（配列の i 番目がスロット i）。人数より短ければ最後の要素を使う。
var loadouts: Array = []
## このステージで全員の手元に置く禁止（通常インベントリ。手元のどこにあっても効く）。
var prohibitions: Array[RuleAction.Kind] = []
## 参加人数 → その人数のときに置く補助（PlacementSpec の配列）。無い人数は補助なし。
var helpers: Dictionary[int, Array] = {}
var clear_condition: ClearCondition = ClearCondition.none()
## ハブだけが使う: ステージの入口（探索して見つける。引き継ぎ仕様 2-2）。
var entrances: Array[EntranceSpec] = []
## チェックポイントの台座の位置（ID は "cp0"・"cp1"… の順）。1人が触れたらチーム共通になる。
var checkpoints: Array[Vector3] = []
## 帰り道の台座（F で出現地点＝広場へ戻る）。手分けするステージで、枝道の奥から広場へ戻るため。
var return_pads: Array[Vector3] = []
## 目安のクリア時間（分。ひとりで初めて遊ぶ想定。仮の値で、本人の試遊で調整する）。
## ハブの入口はこの短い順に並ぶ（2026-11-20 本人の「短い方から順番に試せるように」）。
var target_minutes: int = 0
## 仮の配置か（プレイテスト前の置き場所）。説明・ADR 用の印。
var provisional: bool = true


## 発動方式つきの能力・禁止（ブロック・生き物に最初から付いているもの）。
class TokenSpec:
	var action: RuleAction.Kind
	var is_prohibition: bool = false
	var mode: TriggerMode.Kind = TriggerMode.Kind.NONE

	func _init(
		p_action: RuleAction.Kind,
		p_prohibition: bool = false,
		p_mode: TriggerMode.Kind = TriggerMode.Kind.NONE
	) -> void:
		action = p_action
		is_prohibition = p_prohibition
		mode = p_mode


## ブロック（launcher_direction が ZERO でなければ発射台）。key はステージ内で一意。
class BlockSpec:
	var key: String
	var cell: Vector3i
	var color: Color = Color(0.85, 0.65, 0.35)
	var tokens: Array[TokenSpec] = []
	var launcher_direction: Vector3i = Vector3i.ZERO

	func _init(p_key: String, p_cell: Vector3i) -> void:
		key = p_key
		cell = p_cell

	func is_launcher() -> bool:
		return launcher_direction != Vector3i.ZERO


## 願いを持つ生き物（いまは「高いところへ行きたい」1種だけ）。
class CreatureSpec:
	var key: String
	var position: Vector3
	var held_item: String = ""
	var tokens: Array[TokenSpec] = []

	func _init(p_key: String, p_position: Vector3) -> void:
		key = p_key
		position = p_position


## 鐘。key はクリア条件 ACTIVATE の対象名にもなる。
class BellSpec:
	var key: String
	var position: Vector3

	func _init(p_key: String, p_position: Vector3) -> void:
		key = p_key
		position = p_position


## 置く能力・禁止。block_key が空なら世界に落ちている器（position・part・item_name を使う）、
## 空でなければそのブロックに付いた状態（mode を使う）で置く。
class PlacementSpec:
	var action: RuleAction.Kind
	var is_prohibition: bool = false
	var mode: TriggerMode.Kind = TriggerMode.Kind.NONE
	var block_key: String = ""
	var position: Vector3 = Vector3.ZERO
	var part: RuleVessel.Part = RuleVessel.Part.NONE
	var item_name: String = ""

	func _init(p_action: RuleAction.Kind, p_prohibition: bool = false) -> void:
		action = p_action
		is_prohibition = p_prohibition

	static func in_world(p_action: RuleAction.Kind, at: Vector3) -> PlacementSpec:
		var spec := PlacementSpec.new(p_action)
		spec.position = at
		return spec

	static func on_block(
		p_action: RuleAction.Kind, key: String, p_mode: TriggerMode.Kind
	) -> PlacementSpec:
		var spec := PlacementSpec.new(p_action)
		spec.block_key = key
		spec.mode = p_mode
		return spec


## ハブのステージ入口。area に入るとそのステージへ入れる（入り方の UI は実行時の層が決める）。
class EntranceSpec:
	var stage_id: String
	var position: Vector3
	var area: AABB

	func _init(p_stage_id: String, p_position: Vector3, p_area: AABB) -> void:
		stage_id = p_stage_id
		position = p_position
		area = p_area


## 参加順 index のプレイヤーのホットバー（スロット順の行動）。
func loadout_for(index: int) -> Array[RuleAction.Kind]:
	var result: Array[RuleAction.Kind] = []
	if loadouts.is_empty():
		return result
	for action: RuleAction.Kind in loadouts[clampi(index, 0, loadouts.size() - 1)] as Array:
		result.append(action)
	return result


## 全員に同じホットバーを配る。
func set_loadout_for_all(actions: Array[RuleAction.Kind]) -> void:
	loadouts = [actions]


## その人数のときの補助（無ければ空）。
func helpers_for(headcount: int) -> Array[PlacementSpec]:
	var result: Array[PlacementSpec] = []
	for spec: PlacementSpec in helpers.get(headcount, []) as Array:
		result.append(spec)
	return result


func spawn_point(index: int) -> Vector3:
	return spawn_points[clampi(index, 0, spawn_points.size() - 1)]


func block(key: String) -> BlockSpec:
	for b in blocks:
		if b.key == key:
			return b
	return null


func is_hub() -> bool:
	return not entrances.is_empty()


## 定義の矛盾を列挙する（テスト用）。空なら正常。
func problems() -> PackedStringArray:
	var errors := PackedStringArray()
	if stage_id == "":
		errors.append("stage_id is empty")
	if spawn_points.size() < MAX_PLAYERS:
		errors.append("needs %d spawn points" % MAX_PLAYERS)
	_check_keys(errors)
	for i in MAX_PLAYERS:
		if loadout_for(i).size() > RuleLedger.HOTBAR_SIZE:
			errors.append("loadout %d exceeds the hotbar" % i)
	var placements: Array[PlacementSpec] = world_items.duplicate()
	for headcount: int in helpers:
		placements.append_array(helpers_for(headcount))
	for spec in placements:
		if spec.block_key != "" and block(spec.block_key) == null:
			errors.append("placement refers to unknown block %s" % spec.block_key)
	if clear_condition.kind == ClearCondition.Kind.NONE and not is_hub():
		errors.append("a stage needs a clear condition")
	return errors


func _check_keys(errors: PackedStringArray) -> void:
	var seen := {}
	var keys := PackedStringArray()
	for b in blocks:
		keys.append(b.key)
	for c in creatures:
		keys.append(c.key)
	for b in bells:
		keys.append(b.key)
	for key in keys:
		if seen.has(key):
			errors.append("key %s is used twice" % key)
		seen[key] = true
