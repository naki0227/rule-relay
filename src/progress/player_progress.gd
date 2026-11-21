class_name PlayerProgress
extends RefCounted
## 1人のプレイヤーの永続の進行（各自の PC に保存する: docs/adr/0006 の 4）。
## ルームで見えているハブの世界の状態とは別のデータ（引き継ぎ仕様 5.3【提案】）。
##
## - 初回クリア: クリア記録・新エリア開放・ハブの発展・初回報酬を一度だけ反映する
## - 2回目以降: 記録の更新・特殊条件・追加の収集品だけ。初回のものは二度と渡さない（5.1【確定】）
## - 記録は項目ごとに別々に持ち、1つの総合スコアにしない（5.1【確定】）
## - 同じ報酬イベント（reward_event_id）は二度目以降を無視する。ホストの再送・ホスト移譲後の
##   重複・再接続時の再配達で二重に付与しない（5.3、受け入れテスト候補 19・22）

enum Outcome { APPLIED, DUPLICATE, INVALID }

const AXIS_FASTEST: String = "fastest_seconds"
const AXIS_FEWEST_ABILITIES: String = "fewest_abilities_used"
const AXIS_FEWEST_HAND_OFFS: String = "fewest_hand_offs"
## 記録の項目と、比べる走行指標（RunMetrics の項目名）。どれも小さいほど良い
const RECORD_AXES: Dictionary[String, String] = {
	AXIS_FASTEST: "clear_seconds",
	AXIS_FEWEST_ABILITIES: "abilities_used",
	AXIS_FEWEST_HAND_OFFS: "hand_offs",
}
const SET_KEYS: PackedStringArray = [
	"areas", "hub", "cosmetics", "collectibles", "applied_events", "found_secrets"
]

## ステージ ID → {"first_cleared_at", "clear_count", "records", "party_sizes"}
var _stages: Dictionary[String, Dictionary] = {}
## 集合（キーだけ使う）: "areas" / "hub" / "cosmetics" / "collectibles" / "applied_events" /
## "found_secrets"（広場で見つけた寄り道のワールドの入口。ワールドの id。docs/campaign-plan.md）
var _sets: Dictionary[String, Dictionary] = {}
## 最後に入ったステージ（広場へ戻ったとき・次に起動したときに、そのポータルの前に立つ。docs/adr/0018）。
## 空なら出現地点。古い保存には無い（無ければ空として読む）。
var _last_portal: String = ""


## クリアを反映した結果。
class ClearResult:
	var outcome: Outcome = Outcome.INVALID
	## この走行がこのプレイヤーの初回クリアだったか
	var first_clear: bool = false
	## 新しく得たもの（エリア・ハブ発展・衣装・収集品の ID）
	var granted: PackedStringArray = PackedStringArray()
	## 更新した記録の項目（AXIS_*）
	var improved_axes: PackedStringArray = PackedStringArray()

	## 受け取りの返事（ack）を返すべきか。重複も「もう持っている」ので返す
	func should_acknowledge() -> bool:
		return outcome != Outcome.INVALID


func _init() -> void:
	for key: String in SET_KEYS:
		_sets[key] = {}


## ホストから届いた報酬イベント（StageRunRewards の形）を反映する。
## 形が違うイベントは何も変えずに INVALID。知っている reward_event_id は DUPLICATE。
func apply_reward_event(event: Dictionary, table: RewardTable) -> ClearResult:
	var result := ClearResult.new()
	var metrics: RunMetrics = null
	if event.get("metrics") is Dictionary:
		metrics = RunMetrics.from_dict(event["metrics"] as Dictionary)
	var event_id := str(event.get("reward_event_id", ""))
	var stage_id := str(event.get("stage_id", ""))
	if metrics == null or event_id.is_empty() or stage_id.is_empty():
		return result
	if has_applied(event_id):
		result.outcome = Outcome.DUPLICATE
		return result
	result.outcome = Outcome.APPLIED
	result.first_clear = not has_cleared(stage_id)
	var cleared_at := int(event.get("cleared_at", 0))
	var stage := _stage_entry(stage_id)
	if result.first_clear:
		stage["first_cleared_at"] = cleared_at
		_grant("areas", table.first_clear_rewards(stage_id, "areas"), result)
		_grant("hub", table.first_clear_rewards(stage_id, "hub"), result)
		_grant("cosmetics", table.first_clear_rewards(stage_id, "cosmetics"), result)
	stage["clear_count"] = int(stage.get("clear_count", 0)) + 1
	_grant_conditions(stage_id, metrics, table, result)
	var allowed := table.collectibles(stage_id)
	for item: String in metrics.collectibles:
		if allowed.has(item):
			_grant("collectibles", PackedStringArray([item]), result)
	_update_records(stage, metrics, str(event.get("stage_run_id", "")), result)
	_sets["applied_events"][event_id] = true
	return result


func has_cleared(stage_id: String) -> bool:
	return _stages.has(stage_id) and int(_stages[stage_id].get("clear_count", 0)) > 0


## 初回クリアの時刻（UNIX 秒、ホストの時計）。未クリアなら -1。
func first_clear_time(stage_id: String) -> int:
	if not has_cleared(stage_id):
		return -1
	return int(_stages[stage_id].get("first_cleared_at", -1))


func clear_count(stage_id: String) -> int:
	if not _stages.has(stage_id):
		return 0
	return int(_stages[stage_id].get("clear_count", 0))


func cleared_stages() -> PackedStringArray:
	var result := PackedStringArray()
	for stage_id: String in _stages:
		if has_cleared(stage_id):
			result.append(stage_id)
	result.sort()
	return result


func has_area(area_id: String) -> bool:
	return _sets["areas"].has(area_id)


func unlocked_areas() -> PackedStringArray:
	return _sorted("areas")


func hub_developments() -> PackedStringArray:
	return _sorted("hub")


func cosmetics() -> PackedStringArray:
	return _sorted("cosmetics")


func collectibles() -> PackedStringArray:
	return _sorted("collectibles")


## 広場の秘密の入口を見つけたことを記録する（寄り道のワールドの id）。新しく記録したら true。
func record_secret(world_id: String) -> bool:
	if world_id.is_empty() or _sets["found_secrets"].has(world_id):
		return false
	_sets["found_secrets"][world_id] = true
	return true


func found_secrets() -> PackedStringArray:
	return _sorted("found_secrets")


func last_portal() -> String:
	return _last_portal


## 最後に入ったステージを覚える。変わったら true（呼び出し側が保存する）。
func set_last_portal(stage_id: String) -> bool:
	if stage_id == _last_portal:
		return false
	_last_portal = stage_id
	return true


func has_applied(reward_event_id: String) -> bool:
	return _sets["applied_events"].has(reward_event_id)


func applied_event_count() -> int:
	return _sets["applied_events"].size()


## 記録 1 項目: {"value", "party_size", "stage_run_id"}。記録が無ければ空。
func record(stage_id: String, axis: String) -> Dictionary:
	if not _stages.has(stage_id):
		return {}
	var records: Dictionary = _stages[stage_id].get("records", {})
	var entry: Dictionary = records.get(axis, {})
	return entry.duplicate()


## そのステージをクリアしたことのある参加人数（ソロ・2人…を別々の実績として並べる）。
func party_sizes_cleared(stage_id: String) -> PackedInt32Array:
	var result := PackedInt32Array()
	if not _stages.has(stage_id):
		return result
	var sizes: Array = _stages[stage_id].get("party_sizes", [])
	for size: Variant in sizes:
		result.append(int(size))
	result.sort()
	return result


func to_dict() -> Dictionary:
	var data: Dictionary = {"stages": _stages.duplicate(true)}
	for key: String in SET_KEYS:
		data[key] = Array(_sorted(key))
	if _last_portal != "":
		data["last_portal"] = _last_portal
	return data


## 辞書から作る。形が違えば null（呼び出し側が壊れたデータとして扱う）。
static func from_dict(data: Dictionary) -> PlayerProgress:
	var progress := PlayerProgress.new()
	var stages: Variant = data.get("stages", {})
	if not stages is Dictionary:
		return null
	for key: String in SET_KEYS:
		var items: Variant = data.get(key, [])
		if not items is Array:
			return null
		for item: Variant in items:
			if item is String:
				progress._sets[key][item as String] = true
	for stage_id: Variant in stages:
		var entry: Variant = (stages as Dictionary)[stage_id]
		if not (stage_id is String and entry is Dictionary):
			return null
		progress._stages[stage_id as String] = _normalized_stage(entry as Dictionary)
	var last: Variant = data.get("last_portal", "")
	if last is String:
		progress._last_portal = last as String
	return progress


func _stage_entry(stage_id: String) -> Dictionary:
	if not _stages.has(stage_id):
		_stages[stage_id] = {
			"first_cleared_at": -1, "clear_count": 0, "records": {}, "party_sizes": []
		}
	return _stages[stage_id]


func _grant(set_key: String, ids: PackedStringArray, result: ClearResult) -> void:
	for id: String in ids:
		if not _sets[set_key].has(id):
			_sets[set_key][id] = true
			result.granted.append(id)


func _grant_conditions(
	stage_id: String, metrics: RunMetrics, table: RewardTable, result: ClearResult
) -> void:
	for condition: Dictionary in table.conditions(stage_id):
		if RewardTable.condition_met(condition, metrics):
			var set_key := "cosmetics" if str(condition["kind"]) == "cosmetic" else "collectibles"
			_grant(set_key, PackedStringArray([str(condition["id"])]), result)


## 項目ごとに別々に比べる。同じ値なら先の記録を残す。
func _update_records(
	stage: Dictionary, metrics: RunMetrics, run_id: String, result: ClearResult
) -> void:
	var records: Dictionary = stage["records"]
	for axis: String in RECORD_AXES:
		var value := metrics.axis_value(RECORD_AXES[axis])
		var best: Dictionary = records.get(axis, {})
		if best.is_empty() or value < float(best["value"]):
			records[axis] = {
				"value": value, "party_size": metrics.party_size, "stage_run_id": run_id
			}
			result.improved_axes.append(axis)
	var sizes: Array = stage["party_sizes"]
	if not sizes.has(metrics.party_size):
		sizes.append(metrics.party_size)
		sizes.sort()


func _sorted(set_key: String) -> PackedStringArray:
	var result := PackedStringArray(_sets[set_key].keys())
	result.sort()
	return result


## JSON を通ると整数が小数になるので、数を int に戻して形をそろえる。
static func _normalized_stage(entry: Dictionary) -> Dictionary:
	var records: Dictionary = {}
	var raw_records: Variant = entry.get("records", {})
	if raw_records is Dictionary:
		for axis: Variant in raw_records:
			var best: Variant = (raw_records as Dictionary)[axis]
			if RECORD_AXES.has(str(axis)) and best is Dictionary:
				var record_entry := best as Dictionary
				records[str(axis)] = {
					"value": float(record_entry.get("value", INF)),
					"party_size": int(record_entry.get("party_size", 1)),
					"stage_run_id": str(record_entry.get("stage_run_id", "")),
				}
	var sizes: Array = []
	var raw_sizes: Variant = entry.get("party_sizes", [])
	if raw_sizes is Array:
		for size: Variant in raw_sizes:
			if (size is int or size is float) and not sizes.has(int(size)):
				sizes.append(int(size))
	sizes.sort()
	return {
		"first_cleared_at": int(entry.get("first_cleared_at", -1)),
		"clear_count": maxi(0, int(entry.get("clear_count", 0))),
		"records": records,
		"party_sizes": sizes,
	}
