class_name World3Stages
extends RefCounted
## ワールド 3「ふわふわ浮島」の新しいステージ（3-1・3-2・3-4・3-5・3-6。3-3 浮島めぐりは OpenIslands）。
## 計画は docs/campaign-plan.md と CampaignPlan。配置・目安時間はすべて仮（本人の試遊で直す）。
## どのステージも「島の条件＋願いを持つ動物を願いの場所へ＋生きている全員がゴールの窪みに集まる」。
## 動物の願いは「高いところへ行きたい」（CreatureMind）。動けるように能力を渡すと、自分で高い所へ向かう。
## 数値の目安は CampaignKit の冒頭（ジャンプを持てる島では高さは関所にならないので、関所は空の幅と仕掛け）。

const DASH_BEACH_ID := "w3_dash_beach"
const SHUTTLE_COVE_ID := "w3_shuttle_cove"
const WIND_PATH_ID := "w3_wind_path"
const GAP_RELAY_ID := "w3_gap_relay"
const CLOUD_CORRIDOR_ID := "w3_cloud_corridor"

## 3-1 うさぎの砂丘のてっぺん（高さ 3）。
const BEACH_PERCH := Vector2i(-4, 0)
## 3-2 ひつじの岩のてっぺん（高さ 5）。
const COVE_PERCH := Vector2i(6, -16)
## 3-4 うさぎの見晴らし（高さ 3）。
const WIND_PERCH := Vector2i(6, -12)
## 3-5 ひつじの見張り岩（高さ 3）と、その北の柱の上の鐘。
const RELAY_PERCH := Vector2i(3, -12)
const RELAY_BELL := Vector3(3.5, 3.0, -14.5)


static func stages() -> Array[StageDef]:
	return [dash_beach(), shuttle_cove(), wind_path(), gap_relay(), CloudCorridor.build()]


## 3-1 ダッシュの浜（目安 6 分・仮）。ダッシュの初出: 跳んでから空中でダッシュして、幅 5〜6 の空を越える。
## 浜（高さ 0）から、北東のゴールの島へ渡る。道（どれでもよい）:
## 1. 西: 浜の北から幅 5 を越えて西の小島へ、小島の東から幅 5 を越えてゴールの島へ（どちらも空中ダッシュ）
## 2. 東: 浜の東の崖（高さ 1）へ上がり、北へ幅 6 を越えてゴールの島へ（1 段降りるので届く）
## 願い: 浜のうさぎは砂丘のてっぺん（高さ 3）へ行きたい。動く能力（W/A/S/D のどれか）とジャンプを渡すと
##   1 段ずつ跳んで上がる。自分のジャンプが無いと空中ダッシュができないので、砂丘のふもとで F で取り戻す
##   （ふもとから届く）。てっぺんで能力が無くなったうさぎは、そのまま景色を眺めて待つ。
## 協力: ダッシュは 1 つ。渡った人が「投げる」の届き方で仲間へダッシュを投げ返す（または W×2 で跳ぶ）。
## ゴール: ゴールの島の丘（高さ 2）の窪み（高さ 1、3×2）。窪みの縁が下の浜・崖への光線を遮る。
static func dash_beach() -> StageDef:
	var def := CampaignKit.base(DASH_BEACH_ID, "ダッシュの浜", 6)
	var m := IslandMap.blank(Vector2i(-10, -16), 22, 24)
	m.fill(-5, -1, 2, 6, 0)
	# うさぎの砂丘（1 段ずつ。てっぺんは高さ 3）
	m.fill(-4, 2, -4, 2, 1)
	m.fill(-4, 1, -4, 1, 2)
	m.fill(BEACH_PERCH.x, BEACH_PERCH.y, BEACH_PERCH.x, BEACH_PERCH.y, 3)
	# 東の崖（高さ 1）・西の小島（浜の北、幅 5）・ゴールの島（小島の東に幅 5、崖の北に幅 6）
	m.fill(3, 0, 8, 4, 1)
	m.fill(-6, -12, -2, -7, 0)
	m.fill(4, -15, 10, -7, 0)
	m.fill(5, -15, 9, -10, 2)
	m.fill(5, -9, 9, -9, 1)
	var goal := OpenIslands.goal_hollow(m, 6, -14, 8, -13)
	def.terrain_boxes = m.boxes()
	CampaignKit.wish_creature(def, "bunny", Vector3(-2.5, 0.0, 2.5))
	CampaignKit.item(def, RuleAction.Kind.DASH, Vector3(1.5, 0.0, 2.5))
	def.spawn_points = CampaignKit.spawns(Vector3(0.0, 0.0, 5.5))
	def.checkpoints = [Vector3(-4.5, 0.0, -9.5), Vector3(6.5, 0.0, -7.5)]
	def.clear_condition = CampaignKit.clear_with(
		goal, {"bunny": CampaignKit.perch_box(BEACH_PERCH, 3)}
	)
	return def


## 3-2 往復足場の入り江（目安 8 分・仮）。この入り江ではジャンプを持ち込まない（W/A/S/D と投げるだけ）。
## 島はどれも高さ 1。島のあいだの幅 2〜4 の空を、1 段下の台座の上を 1 マスずつ行き来する往復足場で渡る
## （上面が島と同じ高さ。乗っていれば運ばれ、隣に来たら歩いて降りる）。足場から落ちても台座の外は空なので、
## 島から落ちたのと同じく戻れる（詰まない）。道（どれでもよい）:
## 1. 西: 浜 → 北の足場 → 中の島 → 2 つの足場を乗り継いで（向かい合って隣り合う瞬間に乗り換える）→ 北の島
## 2. 東: 浜 → 東の足場 → 東の島 → 西へ戻る足場 → 北の島
## 願い: 北の島のひつじは岩のてっぺん（高さ 4）へ行きたい。ジャンプは自分で持っているので、動く能力を 1 つ
##   渡せば 1 段ずつ跳んで上がる（ひつじのジャンプを F で取れば自分も跳べるが、ひつじは上がれなくなる）。
## ゴール: 北の島の窪み（高さ 0、5×2）。ジャンプが無いと窪みから出られないので、ひつじは窪みの中からも
##   触って渡せる所に置いた。窪みと浜のあいだの岩の尾根（高さ 3）が光線を遮る。
static func shuttle_cove() -> StageDef:
	var def := CampaignKit.base(SHUTTLE_COVE_ID, "往復足場の入り江", 8)
	def.set_loadout_for_all(CampaignKit.no_jump_loadout())
	var m := IslandMap.blank(Vector2i(-8, -18), 24, 28)
	m.fill(-6, 2, 6, 8, 1)
	m.fill(-6, -5, 3, -1, 1)
	m.fill(-6, -17, 6, -10, 1)
	m.fill(9, -13, 13, 6, 1)
	# 北の島の岩の尾根（窪みを浜から隠す）と、ひつじの岩（1 段ずつ）
	m.fill(-4, -12, 4, -12, 3)
	m.fill(6, -14, 6, -14, 2)
	m.fill(6, -15, 6, -15, 3)
	m.fill(COVE_PERCH.x, COVE_PERCH.y, COVE_PERCH.x, COVE_PERCH.y, 4)
	var goal := OpenIslands.goal_hollow(m, -2, -15, 2, -14)
	def.terrain_boxes = m.boxes()
	var fwd_back: Array[RuleAction.Kind] = [RuleAction.Kind.FORWARD, RuleAction.Kind.BACK]
	var back_fwd: Array[RuleAction.Kind] = [RuleAction.Kind.BACK, RuleAction.Kind.FORWARD]
	var east_west: Array[RuleAction.Kind] = [RuleAction.Kind.RIGHT, RuleAction.Kind.LEFT]
	var west_east: Array[RuleAction.Kind] = [RuleAction.Kind.LEFT, RuleAction.Kind.RIGHT]
	CampaignKit.shuttle(def, "north_shuttle", Vector3i(-4, 0, 1), fwd_back)
	CampaignKit.shuttle(def, "twin_south", Vector3i(0, 0, -6), fwd_back)
	CampaignKit.shuttle(def, "twin_north", Vector3i(0, 0, -9), back_fwd)
	CampaignKit.shuttle(def, "east_shuttle", Vector3i(7, 0, 4), east_west)
	CampaignKit.shuttle(def, "return_shuttle", Vector3i(8, 0, -11), west_east)
	CampaignKit.wish_creature(
		def, "lamb", Vector3(5.5, 1.0, -13.5), Creature.MODEL_WISH, [RuleAction.Kind.JUMP]
	)
	def.spawn_points = CampaignKit.spawns(Vector3(0.0, 1.0, 6.5))
	def.checkpoints = [Vector3(-1.5, 1.0, -3.5), Vector3(11.5, 1.0, -2.5)]
	def.clear_condition = CampaignKit.clear_with(
		goal, {"lamb": CampaignKit.perch_box(COVE_PERCH, 4)}
	)
	return def


## 3-4 風の通り道（目安 8 分・仮）。風の初出: 決まった向きに押し流す風（人・ブロック・生き物を運ぶ）。
## 浜（高さ 0）から、北の丘の島へ渡る。道（どれでもよい）:
## 1. 追い風: 浜の真ん中の先の空に、北向きの風（4 秒ごとに 2 秒吹く。木の葉が流れる）。吹いている間に
##    走り跳ぶと、風に運ばれて幅 5 の空を越えられる（風が無いと幅 3 まで）
## 2. 横風の橋: 浜の西から北の島へ、幅 2 の橋がかかっている。西向きの横風（3 秒ごとに 1.5 秒）が吹くと
##    橋から押し出されるので、止んでいる間に渡るか、D を押して風に向かって歩く
## 願い: 北の島のうさぎは見晴らしの岩（高さ 3）へ行きたい。動く能力とジャンプを渡すと上がる
##   （岩のふもとから F で取り戻せる）。
## ゴール: 北の島の丘（高さ 2）の窪み（高さ 1、3×2）。
static func wind_path() -> StageDef:
	var def := CampaignKit.base(WIND_PATH_ID, "風の通り道", 8)
	var m := IslandMap.blank(Vector2i(-12, -20), 26, 30)
	m.fill(-7, 0, 7, 8, 0)
	m.fill(-7, -16, 7, -6, 0)
	# 西の張り出しと横風の橋（幅 2）
	m.fill(-10, 0, -8, 3, 0)
	m.fill(-10, -8, -8, -6, 0)
	m.fill(-10, -5, -9, -1, 0)
	# うさぎの見晴らし（1 段ずつ）とゴールの丘
	m.fill(4, -12, 4, -12, 1)
	m.fill(5, -12, 5, -12, 2)
	m.fill(WIND_PERCH.x, WIND_PERCH.y, WIND_PERCH.x, WIND_PERCH.y, 3)
	m.fill(-5, -16, -1, -12, 2)
	m.fill(-5, -11, -1, -11, 1)
	var goal := OpenIslands.goal_hollow(m, -4, -15, -2, -14)
	def.terrain_boxes = m.boxes()
	# 風の範囲は地面の 1 段下から（足もとがわずかに沈んでも風の中に入るように）。追い風は空の上だけに吹かせる
	# （浜の上まで吹くと、待っている人を崖から押し出してしまう）
	def.nature.add_pulsing_wind(
		Vector3i(-3, -1, -5), Vector3i(-1, 2, -1), Vector3i(0, 0, -1), 4.0, 2.0
	)
	# 横風は橋の西の空まで吹かせる（橋の縁にかかった人が、風の外で止まらずに押し出される）
	def.nature.add_pulsing_wind(
		Vector3i(-12, -1, -5), Vector3i(-9, 2, -1), Vector3i(-1, 0, 0), 3.0, 1.5
	)
	CampaignKit.wish_creature(def, "bunny", Vector3(2.5, 0.0, -11.5))
	def.spawn_points = CampaignKit.spawns(Vector3(2.0, 0.0, 6.5))
	def.checkpoints = [Vector3(4.5, 0.0, 2.5), Vector3(2.5, 0.0, -8.5)]
	def.clear_condition = CampaignKit.clear_with(
		goal, {"bunny": CampaignKit.perch_box(WIND_PERCH, 3)}
	)
	return def


## 3-5 谷越えリレー（目安 10 分・仮）。浜（高さ 0）と北の島のあいだは幅 9 の空（跳んでも届かない）。
## 北の島の時の鐘（6 秒）が鳴っている間か、北の島のレバーが入っている間だけ、空に石の橋が架かる。
## 鐘は柱の上（高さ 3）で浜からは届かない。谷の向こうへ能力を「投げる」の届き方で投げ渡して鳴らす:
## 1. 東の小島（高さ 3）の発射台に「投げる」を投げ渡す → 発射台が周期ごとに鐘を撃ち、橋が架かり続ける
## 2. 北の島のひつじ（ジャンプと木の実を持っている）に D を投げ渡す → 北を向いたまま横歩きで東へ進み、
##    願いで見張り岩（高さ 3）へ上がる。岩の北の柱の上に鐘があるので、そこへ「投げる」を投げ渡すと、
##    向いている北へ木の実を投げて鐘を鳴らす（6 秒）→ 橋が架かっている間に走って渡る
##    （生き物の W/A/S/D は向いている向きが基準。W を渡すと進む向きを向くので、岩の上で東を向いてしまう。
##    「投げる」を先に渡すと、ひつじはその場で北へ木の実を投げてしまう）
## 渡ったら、北の島のレバーで橋を架けたままにできる（協力で後から来る人・戻る人のため）。
## 願い: ひつじが見張り岩に上がること（道 1 でも、渡ってから触って動く能力を渡す）。
## ゴール: 北の島の西の丘（高さ 2）の窪み（高さ 1、3×2）。
static func gap_relay() -> StageDef:
	var def := CampaignKit.base(GAP_RELAY_ID, "谷越えリレー", 10)
	var m := IslandMap.blank(Vector2i(-10, -22), 26, 32)
	m.fill(-6, 0, 6, 8, 0)
	m.fill(-6, -20, 6, -10, 0)
	# ひつじの見張り岩（1 段ずつ東へ）と、その北の鐘の柱
	m.fill(1, -12, 1, -12, 1)
	m.fill(2, -12, 2, -12, 2)
	m.fill(RELAY_PERCH.x, RELAY_PERCH.y, RELAY_PERCH.x, RELAY_PERCH.y, 3)
	m.fill(3, -15, 3, -15, 3)
	# 東の小島（発射台、高さ 3）
	m.fill(9, -17, 12, -12, 3)
	# 西の丘（ゴール）
	m.fill(-6, -20, -2, -15, 2)
	m.fill(-6, -14, -2, -14, 1)
	var goal := OpenIslands.goal_hollow(m, -5, -19, -3, -18)
	def.terrain_boxes = m.boxes()
	var launcher := StageDef.BlockSpec.new("launcher", Vector3i(9, 3, -15))
	launcher.launcher_direction = Vector3i(-1, 0, 0)
	def.blocks.append(launcher)
	def.mechanisms.timed_bells = [MechanismSpecs.TimedBellSpec.new("bridge_bell", RELAY_BELL, 6.0)]
	def.mechanisms.levers = [
		MechanismSpecs.LeverSpec.new("bridge_lever", Vector3(-2.5, 0.0, -11.5))
	]
	CampaignKit.bridge(
		def,
		"relay_bridge",
		Vector2i(-1, -9),
		Vector2i(2, 9),
		0,
		PackedStringArray(["bridge_bell", "bridge_lever"])
	)
	CampaignKit.wish_creature(
		def, "lamb", Vector3(0.5, 0.0, -11.5), Creature.MODEL_WISH, [RuleAction.Kind.JUMP], "木の実"
	)
	def.spawn_points = CampaignKit.spawns(Vector3(0.0, 0.0, 6.5))
	def.checkpoints = [Vector3(-4.5, 0.0, 3.5), Vector3(-0.5, 0.0, -14.5)]
	def.clear_condition = CampaignKit.clear_with(
		goal, {"lamb": CampaignKit.perch_box(RELAY_PERCH, 3)}
	)
	return def
