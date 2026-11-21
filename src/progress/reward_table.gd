class_name RewardTable
extends RefCounted
## ステージごとの報酬の表（データ）。報酬の中身は未決（引き継ぎ仕様 5.1【提案】・7-10）なので、
## `provisional()` の ID はすべて仮（`tmp_` で始まる）。docs/adr/0008-progress-and-rewards.md
##
## 表の形（ステージ ID → 次の辞書）:
##   "first_clear": {"areas": [...], "hub": [...], "cosmetics": [...]}  初回クリアで一度だけ渡す
##   "conditions": [{"id", "kind", "axis", "at_most"}]  特殊条件。満たしたクリアで一度だけ渡す
##   "collectibles": [...]  そのステージで拾える収集品。拾ったクリアで渡す（何回目でもよい）
## 渡せる種類は見た目・記録・収集だけにする。恒久的な能力の強化（ジャンプ×4 など）は
## パズルの初期能力の制約を壊すので、表に書いても `errors()` で拒否する（5.1【提案】）。

const FIRST_CLEAR_KEYS: PackedStringArray = ["areas", "hub", "cosmetics"]
const CONDITION_KINDS: PackedStringArray = ["cosmetic", "collectible"]
## 条件に使える走行指標（RunMetrics の項目名）
const CONDITION_AXES: PackedStringArray = [
	"clear_seconds", "abilities_used", "hand_offs", "party_size"
]

var _stages: Dictionary = {}
var _errors: PackedStringArray = PackedStringArray()


func _init(stages: Dictionary = {}) -> void:
	_stages = stages.duplicate(true)
	_errors = _check(_stages)


## 仮の報酬表。ステージ ID は試作の島だけ。中身はすべて仮の ID で、見た目・収集品だけ。
static func provisional() -> RewardTable:
	return (
		RewardTable
		. new(
			{
				"prototype_island":
				{
					"first_clear":
					{
						"areas": ["tmp_area_second_island"],
						"hub": ["tmp_hub_bridge_1", "tmp_hub_lantern_1"],
						"cosmetics": ["tmp_cosmetic_leaf_scarf"],
					},
					"conditions":
					[
						{
							"id": "tmp_collectible_light_hands",
							"kind": "collectible",
							"axis": "abilities_used",
							"at_most": 3,
						},
						{
							"id": "tmp_cosmetic_solo_badge",
							"kind": "cosmetic",
							"axis": "party_size",
							"at_most": 1,
						},
					],
					"collectibles": ["tmp_collectible_shell_1", "tmp_collectible_shell_2"],
				},
				"intro_jump_lend": _stage_rewards("intro", "tmp_hub_lantern_intro"),
				"relay_carry": _stage_rewards("relay", "tmp_hub_bridge_relay"),
				"bell_valley": _stage_rewards("bell", "tmp_hub_bell_tower"),
				"hill_top": _stage_rewards("hill", "tmp_hub_flag"),
				"quarry": _stage_rewards("quarry", "tmp_hub_workshop"),
				"three_bells": _stage_rewards("bells3", "tmp_hub_belfry"),
				"floating_isles": _stage_rewards("isles", "tmp_hub_lighthouse"),
				"windy_ridge": _stage_rewards("ridge", "tmp_hub_windmill"),
				"ruined_fort": _stage_rewards("fort", "tmp_hub_gatehouse"),
				"creature_nest": _stage_rewards("nest", "tmp_hub_nest_box"),
				"ban_garden": _stage_rewards("garden", "tmp_hub_sign_post"),
				"long_expedition": _stage_rewards("expedition", "tmp_hub_camp"),
				"w5_first_signs": _stage_rewards("w5_1", "tmp_hub_w5_1"),
				"w5_range_signs": _stage_rewards("w5_2", "tmp_hub_w5_2"),
				"w5_ice_garden": _stage_rewards("w5_4", "tmp_hub_w5_4"),
				"w5_sign_relay": _stage_rewards("w5_5", "tmp_hub_w5_5"),
				"w6_warp_stones": _stage_rewards("w6_1", "tmp_hub_w6_1"),
				"w6_misty_terraces": _stage_rewards("w6_2", "tmp_hub_w6_2"),
				"w6_peak_bells": _stage_rewards("w6_3", "tmp_hub_w6_3"),
				"w6_river_run": _stage_rewards("w6_4", "tmp_hub_w6_4"),
				"w6_long_ridge": _stage_rewards("w6_5", "tmp_hub_w6_5"),
			}
		)
	)


## ステージごとの仮の報酬（初回: ハブの発展1つ・見た目1つ、周回: 少ない能力で解く・ひとりで解く）。
static func _stage_rewards(short: String, hub_item: String) -> Dictionary:
	return {
		"first_clear": {"areas": [], "hub": [hub_item], "cosmetics": ["tmp_cosmetic_%s" % short]},
		"conditions":
		[
			{
				"id": "tmp_collectible_%s_light" % short,
				"kind": "collectible",
				"axis": "abilities_used",
				"at_most": 2,
			},
			{
				"id": "tmp_cosmetic_%s_solo" % short,
				"kind": "cosmetic",
				"axis": "party_size",
				"at_most": 1,
			},
		],
		"collectibles": [],
	}


## 表の誤り（空なら正しい）。誤りのある表でも読み込みは止めず、誤った項目だけ渡さない。
func errors() -> PackedStringArray:
	return _errors


func has_stage(stage_id: String) -> bool:
	return _stages.has(stage_id)


## 初回クリアの報酬。key は FIRST_CLEAR_KEYS。表に無い・誤った項目は空。
func first_clear_rewards(stage_id: String, key: String) -> PackedStringArray:
	if not FIRST_CLEAR_KEYS.has(key):
		return PackedStringArray()
	var first: Dictionary = _section(stage_id, "first_clear", {})
	return _string_list(first.get(key, []))


## 特殊条件の一覧（正しい形のものだけ）。
func conditions(stage_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Array = _section(stage_id, "conditions", [])
	for entry: Variant in raw:
		if entry is Dictionary and _condition_error(entry as Dictionary).is_empty():
			result.append(entry as Dictionary)
	return result


## そのステージで拾える収集品。表に無い ID は報酬として受け取らない。
func collectibles(stage_id: String) -> PackedStringArray:
	return _string_list(_section(stage_id, "collectibles", []))


## 条件を走行の指標が満たすか。
static func condition_met(condition: Dictionary, metrics: RunMetrics) -> bool:
	var axis := str(condition.get("axis", ""))
	var limit := float(condition.get("at_most", -1.0))
	return CONDITION_AXES.has(axis) and metrics.axis_value(axis) <= limit


func _section(stage_id: String, key: String, fallback: Variant) -> Variant:
	var stage: Variant = _stages.get(stage_id, {})
	if not stage is Dictionary:
		return fallback
	var value: Variant = (stage as Dictionary).get(key, fallback)
	if typeof(value) != typeof(fallback):
		return fallback
	return value


static func _string_list(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if not value is Array:
		return result
	for item: Variant in value:
		if item is String and not (item as String).is_empty():
			result.append(item as String)
	return result


static func _check(stages: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	for stage_id: Variant in stages:
		var stage: Variant = stages[stage_id]
		if not stage is Dictionary:
			found.append("%s: stage entry is not a dictionary" % str(stage_id))
			continue
		var first: Variant = (stage as Dictionary).get("first_clear", {})
		if first is Dictionary:
			for key: Variant in first:
				if not FIRST_CLEAR_KEYS.has(str(key)):
					found.append("%s: unknown first_clear reward kind '%s'" % [stage_id, key])
		var raw_conditions: Variant = (stage as Dictionary).get("conditions", [])
		if raw_conditions is Array:
			for entry: Variant in raw_conditions:
				var problem := (
					_condition_error(entry as Dictionary)
					if entry is Dictionary
					else "condition is not a dictionary"
				)
				if not problem.is_empty():
					found.append("%s: %s" % [stage_id, problem])
	return found


static func _condition_error(entry: Dictionary) -> String:
	var problem := ""
	if str(entry.get("id", "")).is_empty():
		problem = "condition without id"
	elif not CONDITION_KINDS.has(str(entry.get("kind", ""))):
		problem = "condition kind '%s' is not allowed" % str(entry.get("kind", ""))
	elif not CONDITION_AXES.has(str(entry.get("axis", ""))):
		problem = "condition axis '%s' is unknown" % str(entry.get("axis", ""))
	elif not (entry.get("at_most") is int or entry.get("at_most") is float):
		problem = "condition without numeric at_most"
	return problem
