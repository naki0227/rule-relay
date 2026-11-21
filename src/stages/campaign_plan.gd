class_name CampaignPlan
extends RefCounted
## キャンペーンの設計（ワールド・ステージの枠・能力の開放・広場の地方と建物・住む生き物）。純粋なデータ。
## 設計の理由と全体の表は docs/adr/0013-overworld-and-campaign.md と docs/campaign-plan.md。
##
## - ステージの枠（Slot）は、まだ作っていないステージの分もある。作ったら、その stage_id のステージを
##   StageCatalog.all_stages() に足すだけで、広場のその地方にポータルが現れる（並行で作る人のための入口）。
## - 能力の開放（grants）は「広場で使える能力」。ステージの開始時の能力はステージの定義が決める
##   （RewardTable の方針どおり、恒久的な強化でステージのパズルを崩さない）。
## - ワールドの地方は、opened_by のステージをクリアすると開く（橋が架かる・岩がどく・階段がせり上がる）。
##   opened_by のステージがまだ無ければ、前のワールドで最後に作ってあるステージで代わりに開く。
## - 目安時間はどれも仮。真ん中と最後のステージ（hard）は難しくする。寄り道のワールド（optional）は
##   進行に要らず、複雑な組み合わせで難しい。

## 広場で使える能力の名前 → 台帳の行動。まだ台帳に無い新しい能力（"FLOAT" など）は載せない。
const GRANT_ACTIONS: Dictionary[String, RuleAction.Kind] = {
	"THROW": RuleAction.Kind.THROW,
	"HIGH_JUMP": RuleAction.Kind.HIGH_JUMP,
	"CLIMB": RuleAction.Kind.CLIMB,
	"DASH": RuleAction.Kind.DASH,
}
## 新しいコードが要る能力・仕掛け（docs/campaign-plan.md の「要実装」）。
const NEEDS_CODE: PackedStringArray = [
	"FLOAT",
	"HEAVY",
	"SWIM",
	"timed_bell",
	"weight_plate",
	"wind",
	"ice",
	"warp_stone",
	"current",
	"switch_door"
]

static var _worlds: Array[World] = []
## 作ってあるステージの id → [表示名, 目安の分]（StageCatalog.all_stages() は毎回すべての定義を作るので、
## 一度だけ調べて覚える）
static var _built: Dictionary[String, Array] = {}


## ステージ1つ分の枠。
class Slot:
	var stage_id: String
	## 仮の題（まだ作っていないステージは、この題でポータルを出す予定）
	var title: String
	## このステージの新しい仕掛け・組み合わせ（短い説明）
	var gimmick: String
	## 真ん中・最後の難しいステージ
	var hard: bool = false
	## クリアで広場に開く能力（GRANT_ACTIONS のキーか、新しい能力の名前）。無ければ ""
	var grants: String = ""
	## クリアで広場に住む生き物の種類（OverworldResident.SPECIES のキー）と色
	var species: String = "bunny"
	var tint: Color = Color.WHITE
	## クリアで建つ建物のモデル名（"ow_house" など）
	var building: String = "ow_house"
	## ポータルの位置（地面の上。マスの中心）と、ポータルの正面の向き（ラジアン。0 は北を向く）
	var portal: Vector3 = Vector3.ZERO
	var facing: float = PI
	## ワールドの中の番号（1 から）
	var number: int = 0
	var world_id: String = ""

	func label() -> String:
		return "%s-%d" % [world_id.trim_prefix("w").to_upper(), number]


## ワールド1つ分。
class World:
	var id: String
	var display_name: String
	var optional: bool = false
	## この地方を開くステージ（"" なら最初から開いている）
	var opened_by: String = ""
	## 寄り道のワールドの入口の見つけ方（説明）
	var secret: String = ""
	var slots: Array[Slot] = []
	## 寄り道のワールドの入口（準備中の門）を置く位置
	var teaser: Vector3 = Vector3.ZERO

	func _init(p_id: String, p_name: String, p_opened_by: String) -> void:
		id = p_id
		display_name = p_name
		opened_by = p_opened_by


static func worlds() -> Array[World]:
	if _worlds.is_empty():
		_worlds = _build()
	return _worlds


static func world(world_id: String) -> World:
	for w in worlds():
		if w.id == world_id:
			return w
	return null


static func main_worlds() -> Array[World]:
	var result: Array[World] = []
	for w in worlds():
		if not w.optional:
			result.append(w)
	return result


## すべての枠（ワールドの順・枠の順）。
static func slots() -> Array[Slot]:
	var result: Array[Slot] = []
	for w in worlds():
		result.append_array(w.slots)
	return result


static func slot(stage_id: String) -> Slot:
	for s in slots():
		if s.stage_id == stage_id:
			return s
	return null


static func stage_exists(stage_id: String) -> bool:
	return _built_stages().has(stage_id)


## 作ってあるステージの id（StageCatalog.all_stages() の順）。
static func built_ids() -> PackedStringArray:
	return PackedStringArray(_built_stages().keys())


## 作ってあるステージの表示名（無ければ ""）。
static func stage_name(stage_id: String) -> String:
	return String(_built_stages().get(stage_id, [""])[0])


## 作ってあるステージの目安の分（無ければ 0）。
static func stage_minutes(stage_id: String) -> int:
	return int(_built_stages().get(stage_id, ["", 0])[1])


static func _built_stages() -> Dictionary[String, Array]:
	if _built.is_empty():
		for def in StageCatalog.all_stages():
			_built[def.stage_id] = [def.display_name, def.target_minutes]
	return _built


## そのワールドで、もう作ってあるステージの枠（順番どおり）。
static func built_slots(w: World) -> Array[Slot]:
	var result: Array[Slot] = []
	for s in w.slots:
		if stage_exists(s.stage_id):
			result.append(s)
	return result


## 地方を開くのに要るステージ（"" なら最初から開いている）。opened_by がまだ無いステージなら、
## 前のワールドで最後に作ってあるステージで代わりに開く。
static func required_stage(w: World) -> String:
	if w.opened_by == "" or stage_exists(w.opened_by):
		return w.opened_by
	var mains := main_worlds()
	var source := slot(w.opened_by)
	var index := mains.find(world(source.world_id)) if source != null else -1
	while index >= 0:
		var built := built_slots(mains[index])
		if not built.is_empty():
			return built[-1].stage_id
		index -= 1
	return ""


static func is_region_open(w: World, cleared: PackedStringArray) -> bool:
	var needed := required_stage(w)
	return needed == "" or cleared.has(needed)


## 製品版の開き方: 地方が開いていて、同じワールドで前に作ってあるステージをクリアしていれば開く。
static func is_stage_open(stage_id: String, cleared: PackedStringArray) -> bool:
	var s := slot(stage_id)
	if s == null:
		return true  # 計画に無いステージ（試作など）は閉じない
	var w := world(s.world_id)
	if not is_region_open(w, cleared):
		return false
	var before := previous_built(stage_id)
	return before == null or cleared.has(before.stage_id)


## 同じワールドで、このステージの前に作ってあるステージ（最初なら null）。
static func previous_built(stage_id: String) -> Slot:
	var s := slot(stage_id)
	if s == null:
		return null
	var built := built_slots(world(s.world_id))
	var index := built.find(s)
	return built[index - 1] if index > 0 else null


## 閉じているときの説明（開いていれば ""）。
static func lock_reason(stage_id: String, cleared: PackedStringArray) -> String:
	if is_stage_open(stage_id, cleared):
		return ""
	var s := slot(stage_id)
	var w := world(s.world_id)
	if not is_region_open(w, cleared):
		var needed := stage_name(required_stage(w))
		return "「%s」をクリアすると、%s への道が開きます" % [needed, w.display_name]
	return "「%s」をクリアすると開きます" % stage_name(previous_built(stage_id).stage_id)


## クリアしたステージで広場に開いた能力（台帳にある行動だけ。開いた順）。
static func unlocked_actions(cleared: PackedStringArray) -> Array[RuleAction.Kind]:
	var result: Array[RuleAction.Kind] = []
	for s in slots():
		if cleared.has(s.stage_id) and GRANT_ACTIONS.has(s.grants):
			var action: RuleAction.Kind = GRANT_ACTIONS[s.grants]
			if not result.has(action):
				result.append(action)
	return result


## 能力の開放の予定（枠の順）: [[枠, 能力の名前], ...]。
static func ability_schedule() -> Array:
	var result: Array = []
	for s in slots():
		if s.grants != "":
			result.append([s, s.grants])
	return result


# --- データ ----------------------------------------------------------------------


static func _build() -> Array[World]:
	var result: Array[World] = []
	result.append(_meadow())
	result.append(_bell_vale())
	result.append(_floating())
	result.append(_forest())
	result.append(_garden())
	result.append(_peaks())
	result.append(_summit())
	result.append(_optional("o1", "からくり工房", StageCatalog.WINDY_ID, Vector3(19.5, 0.0, -13.5)))
	result.append(_optional("o2", "さかさ雲", "w3_cloud_corridor", Vector3(61.5, 0.0, -48.5)))
	result.append(_optional("o3", "ひみつの温室", StageCatalog.FORT_ID, Vector3(-14.5, 0.0, 18.5)))
	result[7].secret = "はじまりの草原の北東、鐘で開く扉の奥（鐘を鳴らす・扉のブロックに W を渡す）"
	result[8].secret = "浮島の東の端から、幅 5 の空を越えた小島（跳んでから空中ダッシュ・ブーツ）"
	result[9].secret = "はじまりの草原の南西、札の門の奥（門の札を回収して手放してから A を渡す）"
	return result


static func _slot(
	w: World, stage_id: String, title: String, gimmick: String, at: Vector2, extra: Dictionary = {}
) -> void:
	var s := Slot.new()
	s.stage_id = stage_id
	s.title = title
	s.gimmick = gimmick
	s.portal = Vector3(at.x, float(extra.get("y", 0)), at.y)
	s.hard = bool(extra.get("hard", false))
	s.grants = str(extra.get("grants", ""))
	s.species = str(extra.get("species", "bunny"))
	s.tint = extra.get("tint", Color.WHITE) as Color
	s.building = str(extra.get("building", "ow_house"))
	s.facing = float(extra.get("facing", PI))
	s.world_id = w.id
	s.number = w.slots.size() + 1
	w.slots.append(s)


static func _meadow() -> World:
	var w := World.new("w1", "はじまりの草原", "")
	_slot(
		w,
		StageCatalog.INTRO_ID,
		"跳ぶ力を貸す",
		"ブロックにジャンプを貸す（単発・繰り返し）",
		Vector2(0.5, 5.5),
		{"species": "bunny", "building": "ow_garden"}
	)
	_slot(
		w,
		StageCatalog.RELAY_ID,
		"みんなで回す",
		"拾った能力を仲間へ回す（受け渡し）",
		Vector2(-6.5, 2.5),
		{"species": "lamb", "building": "ow_house"}
	)
	_slot(
		w,
		StageCatalog.HILL_ID,
		"丘の上の旗",
		"装備（ブーツ・グローブ）と何通りもの道",
		Vector2(7.5, 2.5),
		{"hard": true, "grants": "HIGH_JUMP", "species": "wish", "building": "ow_windmill"}
	)
	_slot(
		w,
		"w1_push_path",
		"押し石の小道",
		"地形のセルに W/A/S/D を渡して押し、道を作る",
		Vector2(-9.5, -4.5),
		{"species": "bunny", "tint": Color("#f3d9b8"), "building": "ow_stall"}
	)
	_slot(
		w,
		"w1_lift_steps",
		"持ち上げ台の段々",
		"繰り返しの持ち上げ台を何段もつなぐ",
		Vector2(10.5, -4.5),
		{"species": "lamb", "building": "ow_fountain"}
	)
	_slot(
		w,
		StageCatalog.QUARRY_ID,
		"採石場",
		"石を押して段を作る・禁止付きの持ち上げ台",
		Vector2(0.5, -9.5),
		{"hard": true, "grants": "CLIMB", "species": "kit", "building": "ow_lookout"}
	)
	return w


static func _bell_vale() -> World:
	var w := World.new("w2", "鐘の谷", StageCatalog.QUARRY_ID)
	_slot(
		w,
		StageCatalog.BELL_ID,
		"鐘の谷",
		"発射台に「投げる」を渡して鐘を鳴らす（禁止の初出）",
		Vector2(33.5, 8.5),
		{"grants": "THROW", "species": "wish", "building": "ow_house"}
	)
	_slot(
		w,
		"w2_echo_bells",
		"こだまの鐘",
		"信号の方式: 鐘が鳴る間だけ動くブロック",
		Vector2(41.5, 10.5),
		{"species": "bunny", "building": "ow_garden"}
	)
	_slot(
		w,
		StageCatalog.THREE_BELLS_ID,
		"三つの鐘の島",
		"鐘 3 つを手分け・生き物の木の実",
		Vector2(49.5, 6.5),
		{"hard": true, "species": "wish", "building": "ow_fountain"}
	)
	_slot(
		w,
		"w2_rolling_shots",
		"転がる玉",
		"発射台そのものを押して向き・位置を変える",
		Vector2(53.5, -2.5),
		{"species": "lamb", "building": "ow_stall"}
	)
	_slot(
		w,
		"w2_timed_bells",
		"時の鐘",
		"鳴っている間だけ開く道（要実装: 時間の鐘）",
		Vector2(46.5, -11.5),
		{"species": "bunny", "tint": Color("#e8d4f0"), "building": "ow_house"}
	)
	_slot(
		w,
		StageCatalog.WINDY_ID,
		"風の尾根",
		"札を取って繰り返し・風鈴の信号・セルを押し出す",
		Vector2(37.5, -15.5),
		{"hard": true, "species": "wish", "building": "ow_windmill"}
	)
	return w


static func _floating() -> World:
	var w := World.new("w3", "ふわふわ浮島", StageCatalog.WINDY_ID)
	_slot(
		w,
		"w3_dash_beach",
		"ダッシュの浜",
		"ダッシュの初出: 谷を跳んでから空中でダッシュ",
		Vector2(31.5, -37.5),
		{"grants": "DASH", "species": "bunny", "building": "ow_house"}
	)
	_slot(
		w,
		"w3_shuttle_cove",
		"往復足場の入り江",
		"往復する足場に乗り継ぐ（既存の往復足場）",
		Vector2(41.5, -40.5),
		{"species": "lamb", "building": "ow_stall"}
	)
	_slot(
		w,
		StageCatalog.FLOATING_ID,
		"浮島めぐり",
		"谷の幅で跳ぶ・ダッシュ・ブーツ・発射台を使い分け",
		Vector2(49.5, -35.5),
		{"hard": true, "species": "wish", "building": "ow_lookout"}
	)
	_slot(
		w,
		"w3_wind_path",
		"風の通り道",
		"風で押し流される床（要実装: 風）",
		Vector2(49.5, -48.5),
		{"species": "bunny", "tint": Color("#d8ecf6"), "building": "ow_windmill"}
	)
	_slot(
		w,
		"w3_gap_relay",
		"谷越えリレー",
		"谷の向こうへ能力を投げ渡して進む",
		Vector2(41.5, -55.5),
		{"species": "lamb", "building": "ow_garden"}
	)
	_slot(
		w,
		"w3_cloud_corridor",
		"雲の回廊",
		"ダッシュ×往復足場×信号の長い組み合わせ",
		Vector2(31.5, -51.5),
		{"hard": true, "species": "wish", "building": "ow_fountain"}
	)
	return w


static func _forest() -> World:
	var w := World.new("w4", "けものの森", "w3_cloud_corridor")
	_slot(
		w,
		"w4_nut_toss",
		"木の実投げ",
		"生き物に「投げる」を渡して木の実で鐘を鳴らす",
		Vector2(-31.5, 6.5),
		{"species": "kit", "building": "ow_garden"}
	)
	_slot(
		w,
		"w4_creature_ladder",
		"生き物のはしご",
		"生き物に移動と上がる手段を渡して導く",
		Vector2(-39.5, 8.5),
		{"species": "bunny", "building": "ow_house"}
	)
	_slot(
		w,
		StageCatalog.NEST_ID,
		"けものの巣",
		"子どもの生き物を巣へ（生き物の願いを使う）",
		Vector2(-47.5, 4.5),
		{"hard": true, "species": "kit", "building": "ow_lookout"}
	)
	_slot(
		w,
		"w4_weight_plates",
		"重さの板",
		"乗ると沈む板と「重い」（要実装: 重さの板・重い）",
		Vector2(-52.5, -5.5),
		{"grants": "HEAVY", "species": "lamb", "building": "ow_stall"}
	)
	_slot(
		w,
		"w4_herd_path",
		"群れの道",
		"何匹もの生き物を同時に導く",
		Vector2(-45.5, -16.5),
		{"species": "lamb", "tint": Color("#f0e2cc"), "building": "ow_garden"}
	)
	_slot(
		w,
		"w4_deep_forest",
		"森の奥",
		"生き物×重さの板×投げるの組み合わせ",
		Vector2(-34.5, -18.5),
		{"hard": true, "species": "wish", "building": "ow_fountain"}
	)
	return w


static func _garden() -> World:
	var w := World.new("w5", "札の庭", "w4_deep_forest")
	_slot(
		w,
		"w5_first_signs",
		"はじめての札",
		"置かれた禁止を回収して手放す",
		Vector2(-31.5, -38.5),
		{"species": "bunny", "building": "ow_garden"}
	)
	_slot(
		w,
		"w5_range_signs",
		"まとめて渡す札",
		"範囲で能力・禁止をまとめて渡す",
		Vector2(-40.5, -36.5),
		{"species": "lamb", "building": "ow_house"}
	)
	_slot(
		w,
		StageCatalog.GARDEN_ID,
		"札の庭",
		"全員ジャンプ禁止の庭で、持ったまま行くか手放すか",
		Vector2(-50.5, -40.5),
		{"hard": true, "species": "kit", "building": "ow_fountain"}
	)
	_slot(
		w,
		"w5_ice_garden",
		"氷の庭",
		"止まれない氷の床（要実装: 氷）",
		Vector2(-52.5, -52.5),
		{"species": "bunny", "tint": Color("#dbeef7"), "building": "ow_stall"}
	)
	_slot(
		w,
		"w5_sign_relay",
		"札の受け渡し",
		"禁止を仲間・生き物へ渡して道を開ける",
		Vector2(-42.5, -58.5),
		{"species": "lamb", "building": "ow_garden"}
	)
	_slot(
		w,
		StageCatalog.FORT_ID,
		"砦跡",
		"鐘と要石・壁を地形ごと動かす",
		Vector2(-32.5, -55.5),
		{"hard": true, "species": "wish", "building": "ow_lookout"}
	)
	return w


static func _peaks() -> World:
	var w := World.new("w6", "霧の峰", StageCatalog.FORT_ID)
	_slot(
		w,
		"w6_warp_stones",
		"ワープの石",
		"ステージの中の対になった石で移る（要実装: ワープの石）",
		Vector2(-12.5, -27.5),
		{"y": 4, "grants": "FLOAT", "species": "bunny", "building": "ow_house"}
	)
	_slot(
		w,
		"w6_misty_terraces",
		"霧の段丘",
		"見えない段を鐘の音波で探す",
		Vector2(-3.5, -31.5),
		{"y": 4, "species": "lamb", "building": "ow_garden"}
	)
	_slot(
		w,
		"w6_peak_bells",
		"峰の鐘",
		"ワープの石×信号×浮くの組み合わせ",
		Vector2(8.5, -28.5),
		{"y": 4, "hard": true, "species": "wish", "building": "ow_windmill"}
	)
	_slot(
		w,
		"w6_river_run",
		"流れる川",
		"流れに乗る・逆らう（要実装: 水の流れ・泳ぐ）",
		Vector2(14.5, -40.5),
		{"y": 4, "grants": "SWIM", "species": "kit", "building": "ow_fountain"}
	)
	_slot(
		w,
		"w6_long_ridge",
		"長い尾根",
		"長い道のりでの装備の持ち回り",
		Vector2(5.5, -49.5),
		{"y": 4, "species": "lamb", "building": "ow_stall"}
	)
	_slot(
		w,
		StageCatalog.EXPEDITION_ID,
		"遠征",
		"4 つの鐘を好きな順に・地方ごとのチェックポイント",
		Vector2(-10.5, -47.5),
		{"y": 4, "hard": true, "species": "wish", "building": "ow_lookout"}
	)
	return w


static func _summit() -> World:
	var w := World.new("w7", "空の頂", StageCatalog.EXPEDITION_ID)
	var spots: Array[Vector2] = [
		Vector2(-8.5, -65.5),
		Vector2(0.5, -64.5),
		Vector2(8.5, -65.5),
		Vector2(8.5, -71.5),
		Vector2(0.5, -72.5),
		Vector2(-8.5, -71.5)
	]
	var titles: PackedStringArray = ["頂のふもと", "雲の階段", "風と札の塔", "流れの上の鐘", "みんなの橋", "頂の祭り"]
	var gimmicks: PackedStringArray = [
		"これまでの能力の総まとめ（ひとりの道）",
		"浮く×ダッシュ×往復足場",
		"風×禁止×繰り返し",
		"水の流れ×信号×投げる",
		"4 人で能力を回す長い協力の道",
		"すべての仕掛けの組み合わせ（最終ステージ）"
	]
	var kinds: PackedStringArray = ["bunny", "lamb", "wish", "kit", "lamb", "wish"]
	var buildings: PackedStringArray = [
		"ow_house", "ow_garden", "ow_windmill", "ow_stall", "ow_fountain", "ow_lookout"
	]
	for i in spots.size():
		_slot(
			w,
			"w7_summit_%d" % (i + 1),
			titles[i],
			gimmicks[i],
			spots[i],
			{"y": 7, "hard": i == 2 or i == 5, "species": kinds[i], "building": buildings[i]}
		)
	return w


static func _optional(id: String, title: String, opened_by: String, teaser: Vector3) -> World:
	var w := World.new(id, title, opened_by)
	w.optional = true
	w.teaser = teaser
	var gimmicks: PackedStringArray = [
		"これまでの仕掛けを 2 つずつ重ねる", "3 つの仕掛けの組み合わせ", "協力の近道が無い長い道", "禁止と生き物の読み合い", "すべてを使う最難関"
	]
	for i in gimmicks.size():
		_slot(
			w,
			"%s_%d" % [id, i + 1],
			"%s その%d" % [title, i + 1],
			gimmicks[i],
			Vector2(teaser.x, teaser.z),
			{"y": int(teaser.y), "hard": true, "species": "wish"}
		)
	return w
