class_name RunMetrics
extends RefCounted
## 1回のステージ走行の指標（ホストが数えてクリア時に確定する）。
## 記録は1つの総合スコアにまとめず、項目ごとに別々に比べる（引き継ぎ仕様 5.1【確定】）。
## 正確な計測の定義は未決（7-10）。いまの定義は仮で docs/adr/0008 に書いた。

## ステージ開始からクリアまでの秒数（仮: 一時停止・ホスト移譲中を含むかは未決）
var clear_seconds: float = 0.0
## 能力を発動・付与した回数（仮）
var abilities_used: int = 0
## プレイヤー間で能力を受け渡した回数（仮）
var hand_offs: int = 0
## クリア時の正式参加人数（StageRunRewards.settle が報酬対象の人数で上書きする）
var party_size: int = 1
## この走行で拾った収集品の ID
var collectibles: PackedStringArray = PackedStringArray()


static func create(
	seconds: float, abilities: int, hand_off_count: int, picked: PackedStringArray = []
) -> RunMetrics:
	var metrics := RunMetrics.new()
	metrics.clear_seconds = seconds
	metrics.abilities_used = abilities
	metrics.hand_offs = hand_off_count
	metrics.collectibles = picked
	return metrics


func is_valid() -> bool:
	return clear_seconds >= 0.0 and abilities_used >= 0 and hand_offs >= 0 and party_size >= 1


## 条件判定用に、項目名で値を読む（知らない名前は INF）。
func axis_value(axis: String) -> float:
	match axis:
		"clear_seconds":
			return clear_seconds
		"abilities_used":
			return float(abilities_used)
		"hand_offs":
			return float(hand_offs)
		"party_size":
			return float(party_size)
	return INF


func duplicate_metrics() -> RunMetrics:
	return RunMetrics.from_dict(to_dict())


func to_dict() -> Dictionary:
	return {
		"clear_seconds": clear_seconds,
		"abilities_used": abilities_used,
		"hand_offs": hand_offs,
		"party_size": party_size,
		"collectibles": Array(collectibles),
	}


## 辞書から作る。JSON を通ると整数が小数になるので int に戻す。形が違えば null。
static func from_dict(data: Dictionary) -> RunMetrics:
	for key: String in ["clear_seconds", "abilities_used", "hand_offs", "party_size"]:
		if not (data.get(key) is int or data.get(key) is float):
			return null
	var picked: Variant = data.get("collectibles", [])
	if not picked is Array:
		return null
	var metrics := RunMetrics.new()
	metrics.clear_seconds = float(data["clear_seconds"])
	metrics.abilities_used = int(data["abilities_used"])
	metrics.hand_offs = int(data["hand_offs"])
	metrics.party_size = int(data["party_size"])
	for item: Variant in picked:
		if item is String:
			metrics.collectibles.append(item as String)
	return metrics if metrics.is_valid() else null
