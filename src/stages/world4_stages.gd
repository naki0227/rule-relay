class_name World4Stages
extends RefCounted
## ワールド 4「けものの森」の新しいステージ（4-1・4-2・4-4・4-5・4-6。4-3 けものの巣は OpenIslandsExtra）。
## 主役は生き物（願いは「高いところへ行きたい」。命令はできず、能力と地形で導く）。4-4 で「重い」と重さの板が出る。
## 計画は docs/campaign-plan.md と CampaignPlan。配置・目安時間はすべて仮（本人の試遊で直す）。
## どのステージも「島の条件＋願いを持つ動物を願いの場所へ＋生きている全員がゴールの窪みに集まる」。
## 数値の目安は CampaignKit の冒頭（ジャンプを持てる島では高さは関所にならないので、関所は空の幅と仕掛け）。

const NUT_TOSS_ID := "w4_nut_toss"
const LADDER_ID := "w4_creature_ladder"
const PLATES_ID := "w4_weight_plates"
const HERD_ID := "w4_herd_path"
const DEEP_FOREST_ID := "w4_deep_forest"

## 4-1 子どもの切り株（高さ 2）と、その北の柱の上の、木の実で鳴らす鐘。
const STUMP := Vector2i(0, -13)
const NUT_BELL := Vector3(0.5, 2.0, -15.5)
## 4-2 うさぎの原っぱ（崖の上、高さ 3）。
const MEADOW := Vector2i(-8, -8)
const MEADOW_SIZE := Vector2i(5, 4)
## 4-4 ひつじの台（高さ 2、2×2。上に重さの板）。
const DAIS := Vector2i(5, 1)
## 4-5 ひつじの牧場（石の囲いの中）。
const PASTURE := AABB(Vector3(-6.0, 0.5, -8.0), Vector3(7.0, 3.0, 7.0))
const HERD: PackedStringArray = ["lamb_a", "lamb_b", "lamb_c"]


static func stages() -> Array[StageDef]:
	return [nut_toss(), creature_ladder(), weight_plates(), herd_path(), DeepForest.build()]


## 4-1 木の実投げ（目安 6 分・仮）。原っぱ（高さ 0）の北に幅 9 の空があり、向こうの島に子どもの生き物と鐘がある
## （どちらも手が届かない）。鐘を鳴らし、子どもを切り株の上へ上げ、全員がゴールに集まる。
## 子どもはジャンプを持っていて木の実を抱えている。「投げる」の届き方で能力を投げ渡す:
## 1. D を投げ渡す → 北を向いたまま横歩きで東へ進み、願いで切り株（高さ 2）へ上がる。切り株の北の柱の上に
##    鐘があるので、そこへ「投げる」を投げ渡すと、木の実を投げて鳴らす（生き物の W/A/S/D は向いている向きが
##    基準。W を渡すと東を向いてしまう。先に「投げる」を渡すと、ふもとから北へ投げて外す）
## 2. 東の棚の発射台は鐘と 1 マスずれている。S を単発で投げ渡して 1 マス押し、「投げる」を投げ渡すと鐘を撃つ
##    （子どもには動く能力だけ渡せばよい）
## ゴール: 原っぱの西の丘（高さ 2）の窪み（高さ 1、3×2）。
static func nut_toss() -> StageDef:
	var def := CampaignKit.base(NUT_TOSS_ID, "木の実投げ", 6)
	var m := IslandMap.blank(Vector2i(-10, -18), 22, 28)
	m.fill(-7, -2, 7, 8, 0)
	m.fill(-7, 2, -3, 7, 2)
	m.fill(-2, 3, -2, 6, 1)
	var goal := OpenIslands.goal_hollow(m, -6, 4, -4, 5)
	# 北の島（幅 9 の向こう）: 子どもの切り株（1 段ずつ東へ）と、鐘と発射台の棚（高さ 2）
	m.fill(-4, -17, 6, -12, 0)
	m.fill(-1, -13, -1, -13, 1)
	m.fill(STUMP.x, STUMP.y, STUMP.x, STUMP.y, 2)
	m.fill(0, -16, 0, -16, 2)
	m.fill(3, -17, 6, -16, 2)
	def.terrain_boxes = m.boxes()
	var launcher := StageDef.BlockSpec.new("launcher", Vector3i(5, 2, -17))
	launcher.launcher_direction = Vector3i(-1, 0, 0)
	def.blocks.append(launcher)
	def.bells = [StageDef.BellSpec.new("nut_bell", NUT_BELL)]
	CampaignKit.wish_creature(
		def, "kit", Vector3(-1.5, 0.0, -12.5), Creature.MODEL_KIT, [RuleAction.Kind.JUMP], "木の実"
	)
	def.spawn_points = CampaignKit.spawns(Vector3(1.0, 0.0, 6.5))
	def.checkpoints = [Vector3(3.5, 0.0, 0.5)]
	def.clear_condition = CampaignKit.clear_with(
		goal, {"kit": CampaignKit.perch_box(STUMP, 2)}, PackedStringArray(["nut_bell"])
	)
	return def


## 4-2 生き物のはしご（目安 8 分・仮）。原っぱ（高さ 0）の北西の崖の上（高さ 3）が、うさぎの行きたい原っぱ。
## うさぎは何も持っていない。動く能力と、上がる手段を渡して導く:
## 1. はしご: 崖の手前に段（高さ 2）と低い石垣（高さ 1）がある。原っぱの石に A を繰り返しで渡すと西へすべり、
##    石垣で止まって段の手前の足場（高さ 1）になる。うさぎにジャンプと動く能力を渡すと、石 → 段 → 崖と跳ぶ
##    （自分のジャンプはうさぎが持っていくので、崖のふもとから F で取り戻す）
## 2. グローブ: 東の段（高さ 2）の上にグローブがある（窪みのブロックにジャンプを貸して上がる）。
##    グローブ（登る）と動く能力を渡すと、うさぎはどの崖も登る
## ゴール: 東の段の窪み（高さ 1、3×2）。
static func creature_ladder() -> StageDef:
	var def := CampaignKit.base(LADDER_ID, "生き物のはしご", 8)
	var m := IslandMap.blank(Vector2i(-10, -10), 20, 20)
	m.fill(-8, -8, 8, 8, 0)
	m.fill(MEADOW.x, MEADOW.y, MEADOW.x + MEADOW_SIZE.x - 1, MEADOW.y + MEADOW_SIZE.y - 1, 3)
	m.fill(-6, -4, -6, -4, 2)
	m.fill(-7, -3, -7, -3, 1)
	m.fill(4, -8, 8, -3, 2)
	var goal := OpenIslands.goal_hollow(m, 5, -7, 7, -6)
	CampaignKit.lift(def, m, Vector2i(5, -2), "ledge_lift")
	def.terrain_boxes = m.boxes()
	CampaignKit.stone(def, "ladder_stone", Vector3i(-2, 0, -3))
	CampaignKit.wish_creature(def, "bunny", Vector3(-5.5, 0.0, -1.5))
	CampaignKit.item(
		def, RuleAction.Kind.CLIMB, Vector3(7.5, 2.0, -3.5), RuleVessel.Part.HANDS, "クライミンググローブ"
	)
	def.spawn_points = CampaignKit.spawns(Vector3(0.0, 0.0, 6.5))
	def.checkpoints = [Vector3(1.5, 0.0, 2.5)]
	def.clear_condition = CampaignKit.clear_with(
		goal, {"bunny": CampaignKit.perch_box(MEADOW, 3, MEADOW_SIZE)}
	)
	return def


## 4-4 重さの板（目安 8 分・仮）。「重い」と重さの板の初出。島はどれも高さ 1。
## 原っぱと北の島のあいだは幅 9 の空。空の橋は、重さの板（4 人分）が押されている間だけ架かる。
## ひとりと 1 匹では 4 人分にならないので、拾える「重い」（おもり）を使う（重い ×1 = 4 人分）:
## 1. ひつじにジャンプ・動く能力・重いを渡す → 願いで台（高さ 2）の上の板へ上がって押す。自分はジャンプ
##    なしで橋を渡る（北の島は平らで、窪みへは歩いて降りられる）
## 2. 石に重いを渡し、D を単発で渡して 1 マス押し、原っぱの板に載せる。ひつじにはジャンプと動く能力だけ
##    渡して台へ上げ、ふもとから F で取り戻して渡る
## 北の島にも小さな板（1 人分）があり、乗っている間は橋が架かる（協力で後から来る人のため）。
## 願い: ひつじが台に上がること。
## ゴール: 北の島の窪み（高さ 0、5×2）。手前の岩の尾根（高さ 3）が原っぱへの光線を遮る。
static func weight_plates() -> StageDef:
	var def := CampaignKit.base(PLATES_ID, "重さの板", 8)
	var m := IslandMap.blank(Vector2i(-10, -20), 22, 30)
	m.fill(-7, 0, 7, 8, 1)
	m.fill(DAIS.x, DAIS.y, DAIS.x + 1, DAIS.y + 1, 2)
	m.fill(-6, -18, 6, -10, 1)
	m.fill(-3, -13, 3, -13, 3)
	var goal := OpenIslands.goal_hollow(m, -2, -16, 2, -15)
	def.terrain_boxes = m.boxes()
	var dais := MechanismSpecs.PlateSpec.new("dais_plate", Vector3i(DAIS.x, 2, DAIS.y))
	dais.size = Vector2i(2, 2)
	dais.required_weight = 4
	var ground := MechanismSpecs.PlateSpec.new("ground_plate", Vector3i(-3, 1, 2))
	ground.required_weight = 4
	def.mechanisms.plates = [
		dais, ground, MechanismSpecs.PlateSpec.new("far_plate", Vector3i(3, 1, -11))
	]
	CampaignKit.bridge(
		def,
		"plate_bridge",
		Vector2i(-1, -9),
		Vector2i(2, 9),
		1,
		PackedStringArray(["dais_plate", "ground_plate", "far_plate"])
	)
	CampaignKit.stone(def, "weight_stone", Vector3i(-4, 1, 2))
	CampaignKit.wish_creature(def, "lamb", Vector3(7.5, 1.0, 1.5))
	CampaignKit.item(def, RuleAction.Kind.HEAVY, Vector3(-5.5, 1.0, 5.5))
	def.spawn_points = CampaignKit.spawns(Vector3(0.0, 1.0, 6.5))
	def.checkpoints = [Vector3(2.5, 1.0, 4.5), Vector3(-4.5, 1.0, -11.5)]
	def.clear_condition = CampaignKit.clear_with(
		goal, {"lamb": CampaignKit.perch_box(DAIS, 2, Vector2i(2, 2))}
	)
	return def


## 4-5 群れの道（目安 10 分・仮）。3 匹のひつじ（どれもジャンプを持っている）を、石の囲いの牧場へ同時に導く。
## 牧場の門は、原っぱの東の板（1 人分）が押されている間だけ開く。牧場の中の秤の台（高さ 2）の板は 3 匹分で、
## 押されている間、東のゴールの島への橋（幅 9 の空）が架かる。ブロックの上も「立てる高さ」なので、
## 門の板と石は、ひつじの見回す範囲（8 マス）の外に置いた（石の上へ上がってしまわないように）。
## 3 匹に動く能力を 1 つずつ渡す（A・S・D を渡しても、W が残れば歩ける）と、門が開いたときに願いで
## 牧場の秤の台へ上がる（門が閉じている間は、高い所へ行けないので待っている）。門を開けておく方法:
## 1. 自分が門の板に乗って、3 匹が入りきるまで待つ（降りると門は閉じるが、中の 3 匹は秤の上に残る）
## 2. 板の隣の石に A を単発で渡して板へ載せる（自分は自由に動ける）
## 拾える「重い」を 1 匹に渡せば、その 1 匹だけで秤が沈む（4 人分）。ただし願いは 3 匹とも牧場に入ること。
## ゴール: 東の島の窪み（高さ 0、2×5）。手前の岩の尾根（高さ 3）が原っぱへの光線を遮る。
static func herd_path() -> StageDef:
	var def := CampaignKit.base(HERD_ID, "群れの道", 10)
	var m := IslandMap.blank(Vector2i(-10, -12), 36, 22)
	m.fill(-8, 0, 8, 8, 1)
	# 牧場（床は高さ 1）と囲い（高さ 4）、門の 2 マス、秤の台
	m.fill(-7, -9, 1, -1, 4)
	m.fill(-6, -8, 0, -2, 1)
	m.fill(-4, -1, -3, -1, 1)
	m.fill(-3, -6, -2, -5, 2)
	# 東のゴールの島
	m.fill(18, -2, 24, 10, 1)
	m.fill(20, 1, 20, 8, 3)
	var goal := OpenIslands.goal_hollow(m, 22, 2, 23, 6)
	def.terrain_boxes = m.boxes()
	var scale := MechanismSpecs.PlateSpec.new("scale_plate", Vector3i(-3, 2, -6))
	scale.size = Vector2i(2, 2)
	scale.required_weight = 3
	def.mechanisms.plates = [scale, MechanismSpecs.PlateSpec.new("gate_plate", Vector3i(7, 1, 4))]
	var gate := MechanismSpecs.DoorSpec.new(
		"pasture_gate", Vector3i(-4, 1, -1), PackedStringArray(["gate_plate"])
	)
	gate.size = Vector3i(2, 3, 1)
	def.mechanisms.doors = [gate]
	CampaignKit.bridge(
		def, "herd_bridge", Vector2i(9, 4), Vector2i(9, 2), 1, PackedStringArray(["scale_plate"])
	)
	CampaignKit.stone(def, "gate_stone", Vector3i(8, 1, 4))
	var spots: Array[Vector3] = [
		Vector3(-6.5, 1.0, 2.5), Vector3(-4.5, 1.0, 1.5), Vector3(-1.5, 1.0, 1.5)
	]
	var wishes := {}
	for i in HERD.size():
		CampaignKit.wish_creature(
			def, HERD[i], spots[i], Creature.MODEL_WISH, [RuleAction.Kind.JUMP]
		)
		wishes[HERD[i]] = PASTURE
	CampaignKit.item(def, RuleAction.Kind.HEAVY, Vector3(6.5, 1.0, 6.5))
	def.spawn_points = CampaignKit.spawns(Vector3(0.0, 1.0, 6.5))
	def.checkpoints = [Vector3(0.5, 1.0, 4.5)]
	def.clear_condition = CampaignKit.clear_with(goal, wishes)
	return def
