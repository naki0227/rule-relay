class_name CloudCorridor
extends RefCounted
## 3-6 雲の回廊（ワールド 3 の最後。難しい★。目安 15 分・仮）。ダッシュ×往復足場×信号の組み合わせ。
## 雲の上ではジャンプを持ち込まない（W/A/S/D と投げる。ダッシュは港で拾う）。ダッシュは地上のダッシュだけで、
## 幅 2 の空を越える（3 マス進む。床に着くまで 1 回）。雲はどれも高さ 1。
##
## 1. 港（出発）→ 中の雲: どちらか
##    - 港の時の鐘（8 秒）を鳴らすと、信号の往復足場 2 つが鳴っている間だけ動く。向かい合って隣り合う瞬間に
##      乗り換えて、幅 4 の空を渡る
##    - 港の東から幅 2 を地上のダッシュで東の細い雲へ、そこから幅 2 をもう一度ダッシュで中の雲へ
## 2. 中の雲 → 鐘の雲: 往復足場（繰り返し）に乗るか、幅 2 を地上のダッシュで越える。中の雲にグローブ
## 3. 鐘の雲 → ゴールの雲（幅 10 の空）: 空の橋は、鐘の雲の北の柱の上の時の鐘（6 秒）か、東の小島の鐘が
##    鳴っている間だけ架かる。どちらか:
##    - 願いの動物（木の実を持っている）にグローブ（登る）と D を渡すと、北を向いたまま横歩きで東の段々の岩
##      （高さ 2〜6）を登る。そこへ「投げる」を渡すと、北の柱の上の鐘を木の実で鳴らす → 6 秒のうちに走って渡る
##    - 鐘の雲の発射台は東の小島の鐘と 1 マスずれている。S を渡して 1 マス押し、「投げる」を渡すと、
##      周期ごとに鐘を撃ち続け、橋が架かったままになる
##    - 自分でグローブを着けて柱を登り、鐘を鳴らしてから 6 秒のうちに走る（あとでグローブを動物に渡す）
## 願い: 動物が高い岩に上がること（どの道でも要る。動物にはグローブと動く能力が要る）。
## ゴールの雲にジャンプが 1 つ落ちている（窪みから出るため。ここまで来たら使ってよい）。
## ゴール: ゴールの雲の窪み（高さ 0、5×2）。手前の岩の尾根（高さ 3）が、来た道の雲への光線を遮る。

const ID := "w3_cloud_corridor"
## 願いの動物の高い岩（雲の北の縁、高さ 6。東へ 1 段ずつ）と、その北の空に立つ鐘の柱（高さ 6。雲から 1 マス
## 離す。岩のてっぺんからは触って届き、雲の地面・橋からは届かない）。
## 生き物は 1 マス進むのに 1.2 秒より長くかかると別の道を探すので、高い壁を一度に登らせない（段は 1 ずつ）。
## 鐘の上も「立てる高さ」に数えるので、柱が雲につながっていると、登る動物は岩より柱を目指してしまう。
const PERCH := Vector2i(-1, -14)
const PERCH_TOP := 6
const SKY_BELL := Vector3(-0.5, 6.0, -15.5)
const HARBOR_BELL := Vector3(-3.5, 1.0, 5.5)
const FAR_BELL := Vector3(12.5, 1.0, -11.5)


static func build() -> StageDef:
	var def := CampaignKit.base(ID, "雲の回廊", 15)
	def.set_loadout_for_all(CampaignKit.no_jump_loadout())
	var m := IslandMap.blank(Vector2i(-8, -31), 24, 43)
	m.fill(-6, 4, 6, 10, 1)
	m.fill(-6, -6, 6, -1, 1)
	m.fill(9, -3, 10, 8, 1)
	m.fill(-6, -14, 6, -9, 1)
	for step in 4:
		m.fill(-5 + step, PERCH.y, -5 + step, PERCH.y, 2 + step)
	m.fill(PERCH.x, PERCH.y, PERCH.x, PERCH.y, PERCH_TOP)
	m.fill(PERCH.x, -16, PERCH.x, -16, PERCH_TOP)
	m.fill(11, -13, 13, -10, 1)
	m.fill(-6, -30, 6, -25, 1)
	m.fill(-3, -27, 3, -27, 3)
	var goal := OpenIslands.goal_hollow(m, -2, -29, 2, -28)
	def.terrain_boxes = m.boxes()
	var fwd_back: Array[RuleAction.Kind] = [RuleAction.Kind.FORWARD, RuleAction.Kind.BACK]
	var back_fwd: Array[RuleAction.Kind] = [RuleAction.Kind.BACK, RuleAction.Kind.FORWARD]
	var on_bell := TriggerMode.Kind.SIGNAL
	CampaignKit.shuttle(def, "harbor_south", Vector3i(-3, 0, 3), fwd_back, on_bell)
	CampaignKit.shuttle(def, "harbor_north", Vector3i(-3, 0, 0), back_fwd, on_bell)
	CampaignKit.shuttle(def, "cloud_shuttle", Vector3i(3, 0, -7), fwd_back)
	var launcher := StageDef.BlockSpec.new("launcher", Vector3i(5, 1, -13))
	launcher.launcher_direction = Vector3i(1, 0, 0)
	def.blocks.append(launcher)
	def.bells = [StageDef.BellSpec.new("far_bell", FAR_BELL)]
	def.mechanisms.timed_bells = [
		MechanismSpecs.TimedBellSpec.new("harbor_bell", HARBOR_BELL, 8.0),
		MechanismSpecs.TimedBellSpec.new("sky_bell", SKY_BELL, 6.0),
	]
	CampaignKit.bridge(
		def,
		"sky_bridge",
		Vector2i(1, -24),
		Vector2i(2, 10),
		1,
		PackedStringArray(["sky_bell", "far_bell"])
	)
	CampaignKit.wish_creature(
		def, "cloud_wish", Vector3(-5.5, 1.0, -13.5), Creature.MODEL_WISH, [], "木の実"
	)
	CampaignKit.item(def, RuleAction.Kind.DASH, Vector3(3.5, 1.0, 6.5))
	CampaignKit.item(
		def, RuleAction.Kind.CLIMB, Vector3(-4.5, 1.0, -3.5), RuleVessel.Part.HANDS, "クライミンググローブ"
	)
	CampaignKit.item(def, RuleAction.Kind.JUMP, Vector3(4.5, 1.0, -26.5))
	def.spawn_points = CampaignKit.spawns(Vector3(0.0, 1.0, 8.5))
	def.checkpoints = [Vector3(0.5, 1.0, -3.5), Vector3(2.5, 1.0, -10.5), Vector3(-4.5, 1.0, -26.5)]
	def.clear_condition = CampaignKit.clear_with(
		goal, {"cloud_wish": CampaignKit.perch_box(PERCH, PERCH_TOP)}
	)
	return def
