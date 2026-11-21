class_name World7Stages
extends RefCounted
## ワールド 7「空の頂」（本編の最後のワールド。docs/campaign-plan.md）の前半 3 ステージ。
## 後半（7-4〜7-6）は World7Finale。どれも壁で区切った部屋にせず、ひとつながりの島にする（docs/adr/0011）。
## このワールドはキャンペーンの山場で、これまで覚えた仕組みを 2 つ・3 つ重ねる（新しいコードの仕組みは足さない）。
## 真ん中（7-3）と最後（7-6）は難しい。どの段差も、ピクセル単位の操作は要らない（余裕を 1 m 以上残す）。
##
## 数値の目安（Tuning・NatureTuning）:
## - 自分のジャンプ 1.3（1 段）・ブーツ 2.3（2 段）・ブロックのジャンプ 2.5・ジャンプ×2 は 2.6（2 段）
## - 走って跳ぶと幅 3 まで（幅 4 は縁ちょうど）。歩く速さ 5 m/秒
## - 浮く ×1 は落ちる速さが 1.6 m/秒まで。風は 3 m/秒で押す（空中でも）。重いは風に流されない
## - 浮いて走って跳ぶと、同じ高さへは約 5.8 m、1 段下へは約 9 m。追い風があると 1 段下へ約 13 m
## - 鐘は、触る距離（胸から 3.5 + 0.5）が下の段から届かないよう、段の縁から 4.5 m 以上離す
## 協力の近道は、仲間がくれた能力（ジャンプ×2・W×2 など）で、ひとりなら取りに行く回り道を省くもの。
## クリアはどれも「島の条件＋生きている全員がゴールの窪みに集まる」（docs/adr/0011 決定 9）。

const SUMMIT_1 := "w7_summit_1"
const SUMMIT_2 := "w7_summit_2"
const SUMMIT_3 := "w7_summit_3"

const LOADOUT: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD,
	RuleAction.Kind.LEFT,
	RuleAction.Kind.BACK,
	RuleAction.Kind.RIGHT,
	RuleAction.Kind.JUMP,
	RuleAction.Kind.THROW,
]
const LIFT_COLOR := Color(0.7, 0.58, 0.86)
const SIGN_COLOR := Color(0.72, 0.42, 0.3)
const CLOUD_COLOR := Color(0.93, 0.95, 1.0)
const STONE_COLOR := Color(0.62, 0.6, 0.56)

## 7-1 の追い風の通り道（空の谷の上。北へ吹く）。
const FOOT_LANE_MIN := Vector3i(-3, -3, -11)
const FOOT_LANE_MAX := Vector3i(3, 4, -1)
## 尾根の突風の強さ（m/秒）。歩く速さ 5 より強いので、吹いている間は逆らって歩いても流される（重いなら流されない）。
const GUST_STRENGTH := 6.0
## 7-3 の風の通り道（東へ吹き続ける）と、その出口の重さの板（風の外の最初のマス）・頂の時の鐘。
const CHANNEL_MIN := Vector3i(-20, 0, -2)
const CHANNEL_MAX := Vector3i(-9, 2, 0)
const CRATE_PLATE := Vector3i(-8, 0, -1)
const CHIME_AT := Vector3(-7.5, 4.0, -15.5)


## 7-1 頂のふもと（目安 12 分・仮）。新しい組み合わせ: 浮く×風（追い風に乗って空の谷を渡る）。
## 南の雲の野原（高さ 1）と、北のふもとの段（0）の間に、幅 11 の空の谷がある。段の北が頂のふもとの台（2）。
## 谷を渡る道（どれでもよい）:
## 1. 風船（浮く）を拾い、谷の真ん中の「追い風の通り道」（かざぐるまの列。北へ吹く）へ走って跳ぶ。
##    浮くだけなら約 9 m で落ちるが、追い風に乗ると約 13 m 進んで向こうの段に着く
## 2. 西の尾根（幅 1）を歩く。尾根には西へ吹く突風が脈打つ（6 秒ごとに 3.5 秒。6 m/秒で、歩いて逆らえない）。
##    おもり（重い）を持てば流されない。持たなくても、風のやむ 2.5 秒の間に 1 区間（5 m）ずつ進み、
##    途中の岩の張り出し（風の外）で次のやむ間を待てば渡れる
## ふもとの段から台へは窪みのブロック（ジャンプを貸す）。台の南の縁に、木の実を持った生き物が鐘の方（北）を
## 向いて座っている（願い: 鐘を鳴らして頂へ知らせたい）。段から「投げる」を投げて渡すと木の実で鐘を鳴らす。
## 台に上がって触ってもよい。
## 協力の近道: 仲間の W で W×2 にすると、浮いて跳ぶだけで谷のどこでも越える（追い風の通り道を探さない）。
##   台へはジャンプ×2 で直接（窪みのブロックを使わない）。風船は谷越しに投げ渡せる（投げるの届き方 20 m）。
## ゴール: 台の奥（北）の窪み（高さ 1、5×2）。鐘を鳴らし、全員がここに集まればクリア。
static func summit_1() -> StageDef:
	var def := _base(SUMMIT_1, "頂のふもと", 12)
	var m := IslandMap.blank(Vector2i(-20, -34), 40, 46)
	# 雲の野原（1）
	m.fill(-8, 0, 8, 10, 1)
	# ふもとの段（0）と台（2）
	m.fill(-16, -24, 10, -12, 0)
	m.fill(-8, -33, 6, -25, 2)
	# 西の尾根（幅 1・高さ 1）と、途中の岩の張り出し（風の外）
	m.fill(-14, 2, -9, 2, 1)
	m.fill(-14, -11, -14, 2, 1)
	m.fill(-16, -7, -14, -5, 1)
	var goal := OpenIslands.goal_hollow(m, -3, -32, 1, -31)
	_lift(def, m, Vector2i(2, -24), "foot_lift")
	def.terrain_boxes = m.boxes()
	def.nature.add_wind(FOOT_LANE_MIN, FOOT_LANE_MAX, Vector3i(0, 0, -1))
	for span: Array in [[-11, -8], [-4, -1]]:
		var gust := def.nature.add_pulsing_wind(
			Vector3i(-14, -3, int(span[0])),
			Vector3i(-13, 4, int(span[1])),
			Vector3i(-1, 0, 0),
			6.0,
			3.5
		)
		gust.strength = GUST_STRENGTH
	def.bells = [StageDef.BellSpec.new("foot_bell", Vector3(-1.5, 2.0, -29.5))]
	_nut_creature(def, "foot_creature", Vector3(-1.5, 2.0, -25.5))
	_item(def, RuleAction.Kind.FLOAT, Vector3(4.5, 1.0, 4.5))
	_item(def, RuleAction.Kind.HEAVY, Vector3(-5.5, 1.0, 5.5))
	def.spawn_points = _spawns(Vector3(0.0, 1.0, 7.5))
	def.checkpoints = [Vector3(-2.5, 1.0, 3.5), Vector3(-6.5, 0.0, -14.5)]
	def.clear_condition = _bells_and_goal(def, goal)
	return def


## 7-2 雲の階段（目安 15 分・仮）。新しい組み合わせ: 浮く×ダッシュ（跳んで空中でダッシュし、浮いてゆっくり降りる）
## と、ワープの石×重さの板×生き物。南の雲の小島（高さ 1）から、幅 10 の空の谷を越えて中の島（0）、
## 窪みのブロックで頂の島（2）へ上がり、鐘を鳴らして奥の窪みに集まる。
## 谷を越える道（どれでもよい）:
## 1. ダッシュと風船（浮く）を拾い、走って跳んで頂点で空中ダッシュ、あとは浮いて降りる（約 12 m）。
##    浮くだけ（約 9 m）・ダッシュだけ（約 7 m）では届かない
## 2. 小島の西の岩囲いの中にワープの石（中の島の石と対）。囲いの扉は、小山（高さ 2、1 マス）の上の重さの板を
##    押している間だけ開く。小山のそばの生き物（願い: もっと高い所へ）に移動とジャンプを渡すと、自分から
##    小山へ跳び乗って板を押し続ける。F で回収しても生き物は板の上に残る（ジャンプは手元に戻る）
## 協力の近道: 1 人が小山の板に立って扉を開けておく（生き物を使わない）。W×2 なら浮くだけで谷を越える（約 18 m）。
##   頂の島へはジャンプ×2 で直接。
## ゴール: 頂の島の奥（北）の窪み（高さ 1、5×2）。
static func summit_2() -> StageDef:
	var def := _base(SUMMIT_2, "雲の階段", 15)
	var m := IslandMap.blank(Vector2i(-16, -36), 34, 46)
	# 雲の小島（1）と小山（2）、西の岩囲い（壁 4・床 1。小山からも跳び移れない高さ）
	m.fill(-6, 0, 6, 8, 1)
	m.fill(-5, 6, -5, 6, 2)
	m.fill(-11, 0, -7, 6, 4)
	m.fill(-10, 1, -8, 5, 1)
	m.fill(-7, 3, -7, 3, 1)
	# 中の島（0）と頂の島（2）
	m.fill(-8, -22, 8, -11, 0)
	m.fill(-6, -34, 6, -23, 2)
	var goal := OpenIslands.goal_hollow(m, -2, -33, 2, -32)
	_lift(def, m, Vector2i(0, -22), "cloud_lift")
	def.terrain_boxes = m.boxes()
	def.mechanisms.plates = [MechanismSpecs.PlateSpec.new("knoll_plate", Vector3i(-5, 2, 6))]
	var gate := MechanismSpecs.DoorSpec.new(
		"nook_gate", Vector3i(-7, 1, 3), PackedStringArray(["knoll_plate"])
	)
	gate.size = Vector3i(1, 3, 1)  # 上面を壁と同じ高さ 4 にする（扉の上から囲いへ入れない）
	def.mechanisms.doors = [gate]
	def.mechanisms.warps = [
		MechanismSpecs.WarpSpec.new("nook_warp", Vector3i(-9, 1, 3), "isle_warp"),
		MechanismSpecs.WarpSpec.new("isle_warp", Vector3i(-6, 0, -14), "nook_warp"),
	]
	def.bells = [StageDef.BellSpec.new("cloud_bell", Vector3(3.5, 2.0, -28.5))]
	var lamb := StageDef.CreatureSpec.new("knoll_creature", Vector3(-3.5, 1.0, 6.5))
	def.creatures.append(lamb)
	_item(def, RuleAction.Kind.DASH, Vector3(3.5, 1.0, 5.5))
	_item(def, RuleAction.Kind.FLOAT, Vector3(1.5, 1.0, 2.5))
	def.spawn_points = _spawns(Vector3(0.0, 1.0, 6.5))
	def.checkpoints = [Vector3(4.5, 1.0, 1.5), Vector3(4.5, 0.0, -14.5)]
	def.clear_condition = _bells_and_goal(def, goal)
	return def


## 7-3 風と札の塔（目安 22 分・仮。★ 難しい）。新しい組み合わせ: 風×重い×重さの板、突風×重い（またはやむ間）、
## 札（禁止）×持ち上げ台、時の鐘×生き物。南の広場（高さ 0）から、塔の段（2）・上の段（4）・頂（6）へ上がる。
## 1. 広場 → 塔の段（扉と石段、または札付きの台）:
##    - 西の風の通り道（東へ吹き続ける）の奥に、重い（おもり）が付いた木箱。重いので風に動かない。F で回収すると
##      箱が風に運ばれ、通り道の出口の重さの板（4 人分）の上で止まる。板は箱だけでは沈まない → 箱に重いを渡し直すと
##      4 人分になり、塔の段の石段の扉が開く。扉の内側から箱へ手が届くので、通った後に重いを取り戻せる
##    - 札付きの台: 窪みのブロックに「ジャンプ禁止」の札。F で取ると札が自分に来るので、どこかへ渡してから乗る
## 2. 塔の段 → 上の段: 東の細い棚（幅 1）を登る。棚には東へ吹く突風（6 m/秒・6 秒ごとに 3.5 秒）が 2 か所。
##    重いを持てば流されない。持たなくても、やむ間に 1 区間ずつ進み、途中の岩の張り出しで待てば渡れる
## 3. 上の段 → 頂: 頂の石段の扉は、時の鐘（3.5 秒鳴る）が鳴っている間か、扉の内側の板が押されている間だけ開く。
##    時の鐘は上の段の南西の隅（扉から約 9 m）。自分で鳴らして走る（約 1.9 秒）か、時の鐘の南の生き物
##    （願い: 鐘を鳴らしたい。木の実を持って北を向いている）に、扉の前から「投げる」を投げて渡す
## 協力の近道: 重いを持った 1 人が板に立って扉を開けておく。段差 2 はジャンプ×2 で直接。頂の扉は 1 人が先に入り、
##   内側の板に立って開けておく。受け入れた技（地面のセルを持ち上げ台にする）でも段差 2 は越えられる（止めない）。
## ゴール: 頂の奥（北）の窪み（高さ 5、5×2）。時の鐘を鳴らし、全員がここに集まればクリア。
static func summit_3() -> StageDef:
	var def := _base(SUMMIT_3, "風と札の塔", 22)
	var m := IslandMap.blank(Vector2i(-22, -36), 36, 48)
	# 広場（0）と西の風の通り道（0）
	m.fill(-8, -1, 10, 10, 0)
	m.fill(-20, -2, -9, 0, 0)
	# 塔の段（2）。西の端に石段（扉 0 → 1 → 段）
	m.fill(-8, -10, 10, -2, 2)
	m.fill(-7, -2, -7, -2, 0)
	m.fill(-7, -3, -7, -3, 1)
	# 東の棚（3）と岩の張り出し（3）、上の段への渡り（4）
	m.fill(10, -19, 10, -11, 3)
	m.fill(9, -15, 11, -14, 3)
	m.fill(7, -19, 9, -19, 4)
	# 上の段（4）と頂（6）。頂の南の端に石段（扉 4 → 5 → 頂）
	m.fill(-8, -22, 6, -11, 4)
	m.fill(-6, -34, 4, -23, 6)
	m.fill(-1, -23, -1, -23, 4)
	m.fill(-1, -24, -1, -24, 5)
	var goal := OpenIslands.goal_hollow(m, -3, -33, 1, -32)
	var signed := _lift(def, m, Vector2i(4, -1), "signed_lift")
	signed.color = SIGN_COLOR
	signed.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.JUMP, true))
	def.terrain_boxes = m.boxes()
	var crate := StageDef.BlockSpec.new("crate", Vector3i(-19, 0, -1))
	crate.color = STONE_COLOR
	crate.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.HEAVY))
	def.blocks.append(crate)
	def.nature.add_wind(CHANNEL_MIN, CHANNEL_MAX, Vector3i(1, 0, 0))
	for span: Array in [[-13, -11], [-19, -16]]:
		var gust := def.nature.add_pulsing_wind(
			Vector3i(10, 2, int(span[0])),
			Vector3i(11, 6, int(span[1])),
			Vector3i(1, 0, 0),
			6.0,
			3.5
		)
		gust.strength = GUST_STRENGTH
	_tower_mechanisms(def.mechanisms)
	_nut_creature(def, "chime_creature", Vector3(-7.5, 4.0, -11.5))
	def.spawn_points = _spawns(Vector3(2.0, 0.0, 7.5))
	def.checkpoints = [Vector3(-3.5, 0.0, 4.5), Vector3(2.5, 2.0, -6.5), Vector3(2.5, 4.0, -15.5)]
	def.clear_condition = _bells_and_goal(def, goal)
	return def


## 7-3 の仕掛け: 風の通り道の出口の板（4 人分）と石段の扉、頂の時の鐘と扉・内側の板。
static func _tower_mechanisms(mech: MechanismSpecs) -> void:
	var plate := MechanismSpecs.PlateSpec.new("crate_plate", CRATE_PLATE)
	plate.required_weight = 4
	var inner := MechanismSpecs.PlateSpec.new("gate_plate", Vector3i(-1, 5, -24))
	mech.plates = [plate, inner]
	mech.timed_bells = [MechanismSpecs.TimedBellSpec.new("summit_chime", CHIME_AT, 3.5)]
	mech.doors = [
		MechanismSpecs.DoorSpec.new(
			"stair_gate", Vector3i(-7, 0, -2), PackedStringArray(["crate_plate"])
		),
		MechanismSpecs.DoorSpec.new(
			"summit_gate", Vector3i(-1, 4, -23), PackedStringArray(["summit_chime", "gate_plate"])
		),
	]


# --- 部品 ------------------------------------------------------------------------


static func _base(stage_id: String, display_name: String, minutes: int) -> StageDef:
	var def := StageDef.new()
	def.stage_id = stage_id
	def.display_name = display_name
	def.target_minutes = minutes
	def.set_loadout_for_all(LOADOUT)
	return def


## 窪みのブロック（上面がまわりと同じ高さ。跳べなくても乗れる持ち上げ台）。
static func _lift(def: StageDef, m: IslandMap, at: Vector2i, key: String) -> StageDef.BlockSpec:
	var block := StageDef.BlockSpec.new(key, m.pit(at.x, at.y))
	block.color = LIFT_COLOR
	def.blocks.append(block)
	return block


## 木の実を持った、能力のない生き物（置いた場所で北を向いて待つ。「投げる」を渡すと北へ木の実を投げる）。
static func _nut_creature(def: StageDef, key: String, at: Vector3) -> StageDef.CreatureSpec:
	var creature := StageDef.CreatureSpec.new(key, at)
	creature.held_item = "木の実"
	def.creatures.append(creature)
	return creature


static func _item(
	def: StageDef,
	action: RuleAction.Kind,
	at: Vector3,
	part: RuleVessel.Part = RuleVessel.Part.NONE,
	item_name: String = ""
) -> void:
	var spec := StageDef.PlacementSpec.in_world(action, at)
	spec.part = part
	spec.item_name = item_name
	def.world_items.append(spec)


## 鐘（時の鐘も）を全部鳴らし、生きている全員がゴールに集まる。
static func _bells_and_goal(def: StageDef, goal: AABB) -> ClearCondition:
	var parts: Array[ClearCondition] = []
	for bell in def.bells:
		parts.append(ClearCondition.activate(bell.key))
	for timed in def.mechanisms.timed_bells:
		parts.append(ClearCondition.activate(timed.key))
	parts.append(ClearCondition.all_at_goal(goal))
	return ClearCondition.all_of(parts)


static func _spawns(center: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for dx: float in [-1.5, -0.5, 0.5, 1.5]:
		result.append(center + Vector3(dx, 0.0, 0.0))
	return result
