class_name VisualQuality
extends RefCounted
## 画質（低・中・高）と、効果ごとの入り切り（docs/adr/0022-visual-direction-and-quality.md）。
## 見た目だけを変える。当たり判定・台帳・ルール・通信には何も効かないので、協力中に画質が人ごとに違っても
## 同じ遊びになる（どの画面も同じ定義・同じ音の合図から同じ効果を作る）。
##
## 効果を持つノードは GROUP に入り、apply_quality() で今の設定を読み直す（設定を変えたらすぐ反映）。

enum Level { LOW, MID, HIGH }

const GROUP := &"visual_quality"
const NAMES: PackedStringArray = ["低", "中", "高"]
const NOTES: PackedStringArray = [
	"軽さ優先。影はくっきり、光のにじみ・舞う花びら・草の揺れなし",
	"おすすめ。光のにじみ・遠くの雲・舞う花びら・草の揺れ・着地の土ぼこり",
	"中に加えて、すき間のやわらかい陰（SSAO）と、花びらを多めに",
]
## はじめての起動の画質。審査は普通の Windows PC（内蔵 GPU も含む）で遊ばれるので、重い SSAO は高だけ。
const DEFAULT_LEVEL := Level.MID

## 効果ごとの値。低・中・高の順。
const TABLE := {
	# 明るい所がふんわりにじむ（Environment.glow）
	"glow": [false, true, true],
	# すき間・角の陰（Environment.ssao。画面ごとの計算で、いちばん重い）
	"ssao": [false, false, true],
	# 影の縁をぼかす（DirectionalLight3D.shadow_blur）
	"soft_shadow": [false, true, true],
	# 島のまわりの遠い雲（球を組んだ数個のメッシュ。影を落とさない）
	"clouds": [true, true, true],
	# 舞う花びらと光の粒の数（カメラのまわりだけ）
	"motes": [0, 36, 90],
	# 草花・木の葉のそよぎ（頂点シェーダー）
	"sway": [false, true, true],
	# 渡す・着地・跳ぶ・クリアの粒（つぶれて戻る動きは低でも出す。手応えの合図なので）
	"burst": [false, true, true],
}

## 測るとき（tools/capture_quality.gd）だけ、効果を1つずつ入り切りする。空なら設定どおり。
static var _override: Dictionary = {}


## いまの効果の値（設定の画質＋ミニチュア風のぼかし＋測定用の上書き）。
static func flags() -> Dictionary:
	var settings := GameSettings.get_current()
	var level := clampi(settings.visual_quality, 0, NAMES.size() - 1)
	var result := {}
	for key: String in TABLE:
		result[key] = (TABLE[key] as Array)[level]
	result["dof"] = settings.miniature_dof
	result["level"] = level
	for key: String in _override:
		result[key] = _override[key]
	return result


static func flag(key: String) -> Variant:
	return flags().get(key)


## 測定用: 効果の値を上書きして、いまある効果へすぐ反映する。{} で設定どおりに戻す。
static func override(values: Dictionary, tree: SceneTree = null) -> void:
	_override = values.duplicate()
	apply_all(tree if tree != null else Engine.get_main_loop() as SceneTree)


## 設定を変えたあと、いまの島の効果に読み直させる。
static func apply_all(tree: SceneTree) -> void:
	if tree != null:
		tree.call_group(GROUP, &"apply_quality")


## 測る組み合わせ（名前, 上書き）。「なし」はすべて切った状態で、そこから1つずつ足した重さを見る。
static func measure_configs() -> Array:
	var none := {
		"glow": false,
		"ssao": false,
		"soft_shadow": false,
		"clouds": false,
		"motes": 0,
		"sway": false,
		"burst": false,
		"dof": false,
	}
	var configs: Array = [["すべて切る", none]]
	for key: String in ["glow", "ssao", "soft_shadow", "clouds", "sway", "dof"]:
		var one := none.duplicate()
		one[key] = true
		configs.append(["%s だけ" % key, one])
	var motes := none.duplicate()
	motes["motes"] = 90
	configs.append(["motes 90 だけ", motes])
	for level in NAMES.size():
		var preset := {}
		for key: String in TABLE:
			preset[key] = (TABLE[key] as Array)[level]
		preset["dof"] = false
		configs.append(["画質 %s" % NAMES[level], preset])
	var last: Array = configs[configs.size() - 1]
	var high_dof := (last[1] as Dictionary).duplicate()
	high_dof["dof"] = true
	configs.append(["画質 高＋ぼかし", high_dof])
	return configs
