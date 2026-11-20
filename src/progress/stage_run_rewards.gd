class_name StageRunRewards
extends RefCounted
## 1回のステージ走行（stage_id・stage_run_id）の報酬台帳。ホストが持つ。
## クリア時の参加者の状態から、引き継ぎ仕様 5.2 の真理値表どおりに誰へ報酬を出すかを決め、
## 受け取りの返事（ack）が来るまで配達待ちとして持つ。
##
## - 報酬イベントの ID は stage_run_id とプレイヤーの key から決まる（同じ走行・同じ人なら同じ ID）。
##   受け手の PlayerProgress は知っている ID を無視するので、何度送っても二重に付与しない
## - 通信が切れていた参加者の分は、部屋が残っている間は持ち続け、再接続で送る（docs/adr/0006 の 5）。
##   全員が抜けて部屋が消えた後は届けない（小さなサーバーを足すまでの保証範囲）
## - クリア後の退出で報酬を取り消さない
## - to_dict / from_dict で新しいホストへ引き継げる（ホスト移譲は P5）
##
## player key は通信の peer ID ではなく、再接続しても変わらない公開の識別子にする
## （Steam 版は SteamID。ENet 版の秘密の session_key をそのまま使わない: docs/adr/0008）。

## クリア成立時の参加者の状態（5.2 の行）
enum Status {
	ACTIVE,  ## 正式参加・生存して操作中 → 付与
	DEAD_SPECTATING,  ## 正式参加・死亡して観戦中 → 付与
	DISCONNECTED,  ## 正式参加・意図しない通信切断中 → 付与（再接続時に配達）
	WAITING_SPECTATOR,  ## 途中入室して操作参加前の待機観戦 → 対象外
	LEFT_BEFORE_CLEAR,  ## クリアより前に明示的に退出 → 対象外
	LEFT_AFTER_CLEAR,  ## クリア確定後に退出 → 確定済みの報酬を維持
}

const ELIGIBLE: Array[Status] = [
	Status.ACTIVE, Status.DEAD_SPECTATING, Status.DISCONNECTED, Status.LEFT_AFTER_CLEAR
]

var stage_id: String = ""
var stage_run_id: String = ""

var _settled: bool = false
var _cleared_at: int = 0
var _metrics: RunMetrics = null
## player key → Status（クリア時の状態。クリア後の退出だけ LEFT_AFTER_CLEAR に変わる）
var _status: Dictionary[String, int] = {}
## player key → 報酬イベント（対象者だけ）
var _events: Dictionary[String, Dictionary] = {}
## player key → 受け取り済みか
var _delivered: Dictionary[String, bool] = {}


func _init(p_stage_id: String = "", p_stage_run_id: String = "") -> void:
	stage_id = p_stage_id
	stage_run_id = p_stage_run_id


## 報酬イベントの ID（同じ走行・同じ人なら必ず同じ）。
static func make_event_id(run_id: String, player_key: String) -> String:
	return "%s/%s" % [run_id, player_key]


static func is_eligible_status(status: int) -> bool:
	return ELIGIBLE.has(status)


## クリアを確定する。statuses は player key → Status。走行1回につき1度だけで、
## 2回目以降（再送・新ホストでの重複）は何も変えずに false。
## metrics.party_size は報酬対象の人数で上書きする（仮の定義: docs/adr/0008）。
func settle(statuses: Dictionary[String, int], metrics: RunMetrics, cleared_at: int) -> bool:
	if _settled or stage_id.is_empty() or stage_run_id.is_empty():
		return false
	if metrics == null or not metrics.is_valid():
		return false
	var eligible := PackedStringArray()
	for key: String in statuses:
		var status: int = statuses[key]
		if key.is_empty() or status < 0 or status >= Status.size():
			continue
		_status[key] = status
		if is_eligible_status(status):
			eligible.append(key)
	_settled = true
	_cleared_at = cleared_at
	_metrics = metrics.duplicate_metrics()
	_metrics.party_size = maxi(1, eligible.size())
	for key: String in eligible:
		_events[key] = _make_event(key)
		_delivered[key] = false
	return true


func is_settled() -> bool:
	return _settled


func status_of(player_key: String) -> int:
	return int(_status.get(player_key, -1))


func is_eligible(player_key: String) -> bool:
	return _events.has(player_key)


## 報酬対象の player key（並べ替え済み）。
func eligible_keys() -> PackedStringArray:
	var result := PackedStringArray(_events.keys())
	result.sort()
	return result


## その人への報酬イベント（対象外なら空）。返すのは複製。
func event_for(player_key: String) -> Dictionary:
	if not _events.has(player_key):
		return {}
	return _events[player_key].duplicate(true)


func is_delivered(player_key: String) -> bool:
	return bool(_delivered.get(player_key, false))


## まだ受け取りの返事が無い対象者（並べ替え済み）。
func pending_keys() -> PackedStringArray:
	var result := PackedStringArray()
	for key: String in _delivered:
		if not _delivered[key]:
			result.append(key)
	result.sort()
	return result


## いま接続している人のうち、まだ受け取っていない人へ送るイベント。
## クリア直後と、誰かが再接続したときに呼ぶ。返事が来るまで何度呼んでも同じものを返す。
func events_to_send(connected_keys: PackedStringArray) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: String in pending_keys():
		if connected_keys.has(key):
			result.append(event_for(key))
	return result


## 受け取りの返事。正しい ID のときだけ受け取り済みにする（重複の返事は true のまま無害）。
func acknowledge(player_key: String, reward_event_id: String) -> bool:
	if not _events.has(player_key):
		return false
	if reward_event_id != str(_events[player_key]["reward_event_id"]):
		return false
	_delivered[player_key] = true
	return true


## クリア後に退出した。報酬は取り消さず、未受領なら配達待ちのまま持つ（部屋が残る間に戻れば届く）。
## 対象外の人（待機観戦・クリア前退出）の状態は変えない。
func mark_left_after_clear(player_key: String) -> void:
	if _settled and _events.has(player_key):
		_status[player_key] = Status.LEFT_AFTER_CLEAR


func metrics() -> RunMetrics:
	return null if _metrics == null else _metrics.duplicate_metrics()


func to_dict() -> Dictionary:
	var statuses: Dictionary = {}
	for key: String in _status:
		statuses[key] = Status.keys()[_status[key]]
	return {
		"stage_id": stage_id,
		"stage_run_id": stage_run_id,
		"settled": _settled,
		"cleared_at": _cleared_at,
		"metrics": {} if _metrics == null else _metrics.to_dict(),
		"statuses": statuses,
		"delivered": _delivered.duplicate(),
	}


## 辞書から復元する（新しいホストへの引き継ぎ用）。イベントは ID の規則から作り直すので、
## 引き継ぎ前と同じ ID になる。形が違えば null。
static func from_dict(data: Dictionary) -> StageRunRewards:
	var ledger := StageRunRewards.new(
		str(data.get("stage_id", "")), str(data.get("stage_run_id", ""))
	)
	var raw_statuses: Variant = data.get("statuses", {})
	var raw_delivered: Variant = data.get("delivered", {})
	if not (raw_statuses is Dictionary and raw_delivered is Dictionary):
		return null
	if not bool(data.get("settled", false)):
		return ledger
	var raw_metrics: Variant = data.get("metrics", {})
	var restored: RunMetrics = (
		RunMetrics.from_dict(raw_metrics as Dictionary) if raw_metrics is Dictionary else null
	)
	if restored == null:
		return null
	ledger._settled = true
	ledger._cleared_at = int(data.get("cleared_at", 0))
	ledger._metrics = restored
	for key: Variant in raw_statuses:
		var status := Status.keys().find(str((raw_statuses as Dictionary)[key]))
		if key is String and status >= 0:
			ledger._status[key as String] = status
			if is_eligible_status(status):
				ledger._events[key as String] = ledger._make_event(key as String)
				ledger._delivered[key as String] = bool(
					(raw_delivered as Dictionary).get(key, false)
				)
	return ledger


func _make_event(player_key: String) -> Dictionary:
	return {
		"reward_event_id": make_event_id(stage_run_id, player_key),
		"stage_id": stage_id,
		"stage_run_id": stage_run_id,
		"player_key": player_key,
		"cleared_at": _cleared_at,
		"metrics": _metrics.to_dict(),
	}
