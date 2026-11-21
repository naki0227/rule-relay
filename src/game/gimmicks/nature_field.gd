class_name NatureField
extends RefCounted
## 実行中の自然の仕掛け（風・氷・水）。どの画面も同じ StageDef.nature から作るので、置き方は通信で送らない。
## 送るのは時計（脈打つ風の拍子）だけで、ホストが WorldFrame で配り、参加者はそれに合わせる。
## チェックポイントには、時計とブロック・器を運ぶ途中の経過時間を残す（to_dict / restore）。
##
## プレイヤーは自分の画面で動かす（NatureMotion。ホスト権威の位置同期のまま、自分のアバターだけ）。
## ブロック・生き物・落ちている器はホストが動かす（NatureTicks）。

var layout: NatureLayout = NatureLayout.new()
## 仕掛けの時計（秒）。脈打つ風が吹いているかはこれで決まる。
var clock: float = 0.0
## 氷を調べる地形（種類 "ice" のセル）。無ければ氷は無い。
var terrain: TerrainGrid
## 動くブロックの一覧（GameWorld.blocks）。地形から動くブロックにした氷のセルも氷として扱う。
var blocks: Dictionary[int, RuleBlock] = {}
## ブロック・落ちている器を次の 1 マス運ぶまでの経過時間（キーは entity_id、器は "v<ID>" / "t<ID>"）。
var drift_timers: Dictionary = {}


func advance(delta: float) -> void:
	clock += delta


## p で吹いている風の速さ（m/秒。重なっていれば足す）。
func wind_at(p: Vector3) -> Vector3:
	var total := Vector3.ZERO
	for spec in layout.winds:
		if spec.is_blowing(clock) and spec.area().has_point(p):
			total += spec.velocity()
	return total


## p で吹いている風の向き（ブロック・器をマス単位で運ぶ向き）。吹いていなければ ZERO。
func wind_direction_at(p: Vector3) -> Vector3i:
	for spec in layout.winds:
		if spec.is_blowing(clock) and spec.area().has_point(p):
			return spec.direction
	return Vector3i.ZERO


## p を含む水（無ければ null）。
func water_at(p: Vector3) -> NatureLayout.WaterSpec:
	for spec in layout.waters:
		if spec.contains(p):
			return spec
	return null


## そのセルが氷か（動かない地形の "ice"、または地形から動くブロックにした氷のセルがそこにある）。
func is_ice(cell: Vector3i) -> bool:
	if terrain != null and String(terrain.cells.get(cell, "")) == "ice":
		return true
	for block: RuleBlock in blocks.values():
		if is_instance_valid(block) and block.is_ice() and block.cell() == cell:
			return true
	return false


## 足もと（feet）のすぐ下のセルが氷か。
func is_ice_under(feet: Vector3) -> bool:
	return is_ice(Vector3i(floori(feet.x), floori(feet.y - 0.1), floori(feet.z)))


## チェックポイント用。
func to_dict() -> Dictionary:
	return {"clock": clock, "drift_timers": drift_timers.duplicate()}


func restore(data: Dictionary) -> void:
	clock = float(data.get("clock", clock))
	drift_timers = (data.get("drift_timers", {}) as Dictionary).duplicate()
