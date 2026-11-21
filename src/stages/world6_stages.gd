class_name World6Stages
extends RefCounted
## ワールド 6「霧の峰」の新しいステージ（6-1〜6-5）。6-6 遠征は既存（OpenIslandsLong）。
## 主役は、ワープの石（6-1）・浮く（6-1 で開く）・泳ぐ（6-4 で開く）と、これまでの仕掛けの組み合わせ
## （時の鐘×ワープ・信号×ワープ×浮く・水と流れ×筏×泳ぐ・重い×風×水）。計画の表は docs/campaign-plan.md。
## どのステージも開けたひとつながりの島（ワープでつながる島を含む）で、ゴールへの道は何通りもある。
## 数値の目安（Tuning・NatureTuning）: 自分のジャンプ 1.3・ブーツ 2.3・ブロックのジャンプ 2.5・走って跳ぶと幅 3。
## 浮く ×1 は落ちる速さ 1.6 m/秒まで（高さ 3 から落ちる間に約 9 m 進む。ふつうに跳ぶと約 5 m）。
## 泳ぐ ×1 は 2.5 m/秒（流れ 3 m/秒には逆らえない）。重いは風に流されず、水に沈む。
## 受け入れた技（縁ちょうどの幅 4・ブロックの上昇＋自分のジャンプ・どの地面のセルも持ち上げ台）は止めない。
## クリアは「島の条件＋生きている全員がゴールの窪みに集まる」。各ステージに願いを持つ動物がいる。
## 配置・目安時間はすべて仮（本人の試遊で直す）。

const WARP_ID := "w6_warp_stones"
const MIST_ID := "w6_misty_terraces"
const PEAK_ID := "w6_peak_bells"
const RIVER_ID := "w6_river_run"
const RIDGE_ID := "w6_long_ridge"
## 6-2 の時の鐘が鳴る秒数（歩いては扉まで間に合わず、ワープか W×2 なら間に合う）。
const MIST_RING_TIME := 4.0
## 6-5 の尾根の風の強さ（歩く速さ 5 より強いので、重くなければ逆らえない）。
const RIDGE_WIND := 6.0


## 6-1 ワープの石（目安 8 分・仮）。南の広場（高さ 0）、北の島（0、谷 6）、東の高台（2、谷 7）。
## 新しいこと: ワープの石（乗ったものを対の石へ移す。ブロックも生き物も移る。片道の石もある）。
## - 広場の石に D を繰り返しで渡すと、東へ進んでワープの石に乗り、北の島へ移って、さらに東の岩（2）の
##   脇まで進む → 1 段の足場。自分もワープで島へ渡り、石 → 岩 → 岩の上の片道の石で東の高台へ
##   （島の石に先に石が乗っていると、降りるまで自分は移れない。待つか、投げるで石を動かす）
## - 広場の東の塔（1 段ずつ高さ 5）の上の風船（浮く）で、東の高台へゆっくり落ちながら渡る
## 願いを持つ動物: 東の高台の縁で木の実を持ったうさぎが北の鐘を向いている。願いは「木の実で鐘を鳴らしたい」。
##   広場や塔から「投げる」を投げて渡すと、谷越しに鐘を鳴らす（高台に上がって触ってもよい）。
## 協力の近道: ジャンプ×2 で北の島の岩（2）へ直接上がる（石を運ばない）。
## ゴール: 東の高台の北東の窪み（高さ 1、3×2）。
static func warp_stones() -> StageDef:
	var def := StageParts.base(WARP_ID, "ワープの石", 8)
	var m := IslandMap.blank(Vector2i(-10, -18), 34, 30)
	m.fill(-8, -2, 6, 10, 0)
	# 東の塔（幅 2 の階段で 1 段ずつ。上は 2×2 の高さ 5）
	for i in 4:
		m.fill(1 + i, -2, 1 + i, -1, i + 1)
	m.fill(5, -2, 6, -1, 5)
	# 北の島（谷 6）と岩（2）
	m.fill(-8, -16, 4, -9, 0)
	m.fill(-4, -11, -2, -9, 2)
	# 東の高台（谷 7）
	m.fill(14, -10, 22, 2, 2)
	var goal := OpenIslands.goal_hollow(m, 18, -9, 20, -8)
	def.terrain_boxes = m.boxes()
	StageParts.stone(def, "warp_crate", Vector3i(-8, 0, 4))
	def.mechanisms.warps = [
		MechanismSpecs.WarpSpec.new("plaza_warp", Vector3i(-5, 0, 4), "isle_warp"),
		MechanismSpecs.WarpSpec.new("isle_warp", Vector3i(-7, 0, -10), "plaza_warp"),
		MechanismSpecs.WarpSpec.new("rock_warp", Vector3i(-3, 2, -10), "terrace_exit"),
		MechanismSpecs.WarpSpec.new("terrace_exit", Vector3i(15, 2, -2)),
	]
	StageParts.animal(def, "warp_bunny", Vector3(17.5, 2.0, -3.5), "木の実")
	def.bells = [StageDef.BellSpec.new("terrace_bell", Vector3(17.5, 2.0, -6.5))]
	StageParts.item(def, RuleAction.Kind.FLOAT, Vector3(5.5, 5.0, -1.5), RuleVessel.Part.NONE, "風船")
	def.spawn_points = StageParts.spawns(Vector3(-1.0, 0.0, 7.5))
	def.checkpoints = [Vector3(-6.5, 0.0, 4.5), Vector3(-1.5, 0.0, -10.5)]
	def.clear_condition = StageParts.bells_and_goal(def, goal)
	return def


## 6-2 霧の段丘（目安 10 分・仮）。南の原（高さ 0）と、尾根（3）の向こうの段丘（2）。尾根の門（扉）は、
## 時の鐘が鳴っている間（4 秒）だけ開く。
## 新しいこと（組み合わせ）: 時の鐘 × ワープの石。
## - 原の西の端の時の鐘を鳴らし、すぐ脇のワープの石に乗ると、門の前の石（片道の出口）へ移って間に合う
##   （歩くと門まで 26 m で、5 秒かかって閉まってしまう。門の前の石は出口だけなので、踏んでも戻されない）
## - 門の東の岩棚（3）で、木の実を持ったうさぎが岩棚の時の鐘を向いている。「投げる」を投げて渡すと
##   木の実で鐘を鳴らし、門のそばで待っていれば歩いて間に合う（木の実は 1 回きり。外したらワープで）
## 願いを持つ動物: 岩棚のうさぎ。願いは「木の実で鐘を鳴らしたい」。
## 協力の近道: 仲間の W で W×2（速さ 2 倍）なら、西の鐘から門まで 4 秒の間に走って間に合う。
## ゴール: 段丘の奥（北）の窪み（高さ 1、5×2）。
static func misty_terraces() -> StageDef:
	var def := StageParts.base(MIST_ID, "霧の段丘", 10)
	var m := IslandMap.blank(Vector2i(-24, -20), 43, 34)
	m.fill(-22, -2, 16, 12, 0)
	m.fill(-22, -4, 16, -3, 3)
	m.fill(2, -4, 4, -3, 0)
	# 門の東の岩棚（3。尾根とつながる）
	m.fill(7, -2, 13, 2, 3)
	# 尾根の向こう: 地面の列（0）・階段（1）・段丘（2）
	m.fill(-22, -5, 16, -5, 0)
	m.fill(-10, -18, 14, -6, 2)
	m.fill(2, -6, 4, -6, 1)
	var goal := OpenIslands.goal_hollow(m, -2, -17, 2, -16)
	def.terrain_boxes = m.boxes()
	var mech := def.mechanisms
	mech.timed_bells = [
		MechanismSpecs.TimedBellSpec.new("mist_bell", Vector3(-20.5, 0.0, 8.5), MIST_RING_TIME),
		MechanismSpecs.TimedBellSpec.new("shelf_bell", Vector3(10.5, 3.0, -1.5), MIST_RING_TIME),
	]
	var gate := MechanismSpecs.DoorSpec.new(
		"mist_gate", Vector3i(2, 0, -4), ["mist_bell", "shelf_bell"]
	)
	gate.size = Vector3i(3, 3, 2)
	mech.doors = [gate]
	mech.warps = [
		MechanismSpecs.WarpSpec.new("bell_warp", Vector3i(-22, 0, 6), "gate_warp"),
		MechanismSpecs.WarpSpec.new("gate_warp", Vector3i(3, 0, -1)),
	]
	StageParts.animal(def, "mist_bunny", Vector3(10.5, 3.0, 1.5), "木の実")
	def.spawn_points = StageParts.spawns(Vector3(-6.0, 0.0, 9.5))
	def.checkpoints = [Vector3(-12.5, 0.0, 4.5), Vector3(8.5, 2.0, -9.5)]
	def.clear_condition = ClearCondition.all_at_goal(goal)
	return def


## 6-3 峰の鐘（目安 16 分・仮。難しい）。南の野営地（0）・東の島（0、ワープか谷 5）・東の高台（2）・
## 北の峰（4）・西の尖塔（1、峰から谷 7）。3 つの鐘を鳴らし、峰の奥の窪みに集まる。
## 新しいこと（組み合わせ）: ワープの石 × 信号の方式 × 浮く。
## - こだま石（野営地の石）には、最初から「ジャンプ（信号）」が付いている（近くで鐘が鳴る間だけ跳ねる）。
##   D を繰り返しで渡すと東へ進み、ワープで東の島へ移って、高台の崖の下まで進む
## - 東の高台の縁のうさぎに「投げる」を投げて渡すと、木の実でこだまの鐘を鳴らし、近くのこだま石が跳ねる。
##   石に乗っていれば高台（2）へ上がれる（島のブーツでも上がれる）
## - 高台の風船（浮く）を持って、尾根の持ち上げ台で峰へ。峰の西の縁からゆっくり落ちて尖塔へ渡り、尖塔の鐘。
##   尖塔の片道の石で峰へ戻る（浮かずに跳ぶと谷に届かない）
## 願いを持つ動物: 東の高台のうさぎ。願いは「木の実で鐘を鳴らしたい」（こだまの鐘）。
## 協力の近道: 仲間の W で W×2 なら、野営地から東の島へ（谷 5）・峰から尖塔へ（谷 7）を走って跳べる
##   （ワープと風船が要らない）。
## ゴール: 峰の奥（北）の窪み（高さ 3、5×2）。
static func peak_bells() -> StageDef:
	var def := StageParts.base(PEAK_ID, "峰の鐘", 16)
	var m := IslandMap.blank(Vector2i(-20, -26), 52, 42)
	m.fill(-12, 2, 12, 14, 0)
	# 東の島（0）と高台（2）、高台から峰へ続く尾根（2）
	m.fill(18, -4, 22, 4, 0)
	m.fill(23, -14, 30, 6, 2)
	m.fill(9, -14, 30, -12, 2)
	# 北の峰（4）と西の尖塔（1、谷 7）
	m.fill(-8, -24, 8, -8, 4)
	m.fill(-18, -16, -16, -14, 1)
	var goal := OpenIslands.goal_hollow(m, -2, -23, 2, -22)
	StageParts.lift(def, m, Vector2i(9, -13), "peak_lift")
	def.terrain_boxes = m.boxes()
	var echo := StageParts.stone(def, "echo_stone", Vector3i(5, 0, 8), StageParts.LIFT_COLOR)
	echo.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.JUMP, false, TriggerMode.Kind.SIGNAL))
	def.mechanisms.warps = [
		MechanismSpecs.WarpSpec.new("camp_warp", Vector3i(9, 0, 8), "isle_warp"),
		MechanismSpecs.WarpSpec.new("isle_warp", Vector3i(19, 0, 0), "camp_warp"),
		MechanismSpecs.WarpSpec.new("spire_warp", Vector3i(-18, 1, -16), "peak_return"),
		MechanismSpecs.WarpSpec.new("peak_return", Vector3i(-6, 4, -12)),
	]
	StageParts.animal(def, "echo_bunny", Vector3(27.0, 2.0, 1.0), "木の実")
	def.bells = [
		StageDef.BellSpec.new("echo_bell", Vector3(27.0, 2.0, -2.0)),
		StageDef.BellSpec.new("spire_bell", Vector3(-17.5, 1.0, -14.5)),
		StageDef.BellSpec.new("peak_bell", Vector3(0.5, 4.0, -14.5)),
	]
	StageParts.boots(def, Vector3(21.5, 0.0, -3.5))
	StageParts.item(
		def, RuleAction.Kind.FLOAT, Vector3(28.5, 2.0, -8.5), RuleVessel.Part.NONE, "風船"
	)
	def.spawn_points = StageParts.spawns(Vector3(0.0, 0.0, 11.5))
	def.checkpoints = [Vector3(-6.5, 0.0, 9.5), Vector3(28.5, 2.0, 4.5), Vector3(4.5, 4.0, -10.5)]
	def.clear_condition = StageParts.bells_and_goal(def, goal)
	return def


## 6-4 流れる川（目安 10 分・仮）。南の岸（0）と北の台地（2）の間を、東へ流れる川（幅 5、底なし）が通る。
## 北の岸は東の端（x 8〜12）だけ低い船着き場（0）で、階段（1）から台地へ上がる。川の東の端は岩の堰。
## 新しいこと: 泳ぐ（水の中を進む。流れ 3 m/秒には ×1 では逆らえず、流されながら渡る）。
## - 岸の足ひれ（泳ぐ）を持って川に入り、北へ泳ぐと、流されて船着き場に着く
## - 岸の筏（「浮く」の付いた木箱）に W を単発で渡すと川に浮かぶ。乗ったまま W を単発で渡して押すたびに
##   1 マス北へ進み、流されて堰の手前の船着き場の脇で止まる（筏の「浮く」を F で取ると沈む）
## 願いを持つ動物: 台地の縁で木の実を持ったうさぎが北の鐘を向いている。願いは「木の実で鐘を鳴らしたい」。
##   南の岸から「投げる」を投げて渡すと、川越しに鐘を鳴らす。
## 協力の近道: 仲間の W で W×2 なら、川（幅 5）を船着き場へ走って跳べる。
## ゴール: 台地の奥（北）の窪み（高さ 1、5×2）。
static func river_run() -> StageDef:
	var def := StageParts.base(RIVER_ID, "流れる川", 10)
	var m := IslandMap.blank(Vector2i(-14, -18), 29, 32)
	m.fill(-12, 3, 12, 12, 0)
	m.fill(-12, -16, 12, -3, 2)
	m.fill(8, -6, 12, -3, 0)
	m.fill(8, -7, 12, -7, 1)
	# 川の東の端の岩の堰（3。歩いては越えられない）
	m.fill(13, -2, 13, 2, 3)
	var goal := OpenIslands.goal_hollow(m, -2, -15, 2, -14)
	def.terrain_boxes = m.boxes()
	def.nature.add_current(Vector3i(-12, -2, -2), Vector3i(12, -1, 2), Vector3i(1, 0, 0))
	var raft := StageParts.stone(def, "raft", Vector3i(-4, 0, 3), StageParts.RAFT_COLOR)
	raft.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.FLOAT))
	StageParts.item(def, RuleAction.Kind.SWIM, Vector3(-8.5, 0.0, 6.5), RuleVessel.Part.NONE, "足ひれ")
	StageParts.animal(def, "river_bunny", Vector3(-4.5, 2.0, -6.5), "木の実")
	def.bells = [StageDef.BellSpec.new("river_bell", Vector3(-4.5, 2.0, -9.5))]
	def.spawn_points = StageParts.spawns(Vector3(0.0, 0.0, 9.5))
	def.checkpoints = [Vector3(-8.5, 0.0, 8.5), Vector3(10.5, 2.0, -10.5)]
	def.clear_condition = StageParts.bells_and_goal(def, goal)
	return def


## 6-5 長い尾根（目安 14 分・仮）。南の広場から北のゴールまで、風の尾根・池・谷を越える長い道。
## 新しいこと（組み合わせ）: 重い × 風 × 水 × 浮く の持ち回り。重いと浮くは数で打ち消し合い、重いと水に沈む。
## ホットバーに置いた物だけが効くので、区間ごとに置き換える（広場に、おもり・足ひれ・風船・ブーツ）。
## - 風の尾根（幅 3、長さ 16）: 東へ強い風（6 m/秒。歩く速さより強い）が 4 秒ごとに 2 秒吹く。
##   重ければ流されない。重くなければ、風の止んでいる間に 1 区間ずつ渡る（真ん中に風の無い所がある）
## - 池（幅 5、底なし）: 重いと沈む。重いを外して泳ぐ（足ひれ）か、真ん中に浮かぶ筏へ跳び移って渡る
## - 谷（幅 7）: 谷の上には北への追い風が吹いている。重くなければ、見晴らし（3）から跳ぶと追い風で届く。
##   風船（浮く）でゆっくり落ちても届く（重いと浮くを両方置くと打ち消し合う）
## - 最後の台地（2）: 持ち上げ台かブーツ
## 願いを持つ動物: 台地の縁で木の実を持ったうさぎが北の鐘を向いている。願いは「木の実で鐘を鳴らしたい」。
## 協力の近道: ジャンプ×2 で最後の台地へ直接跳ぶ。
## ゴール: 台地の奥（北）の窪み（高さ 1、5×2）。
static func long_ridge() -> StageDef:
	var def := StageParts.base(RIDGE_ID, "長い尾根", 14)
	var m := IslandMap.blank(Vector2i(-8, -26), 17, 66)
	m.fill(-5, 30, 5, 38, 0)
	m.fill(-1, 14, 1, 29, 0)
	m.fill(-5, 8, 5, 13, 0)
	# 池の北の岸と見晴らし（1 段ずつ高さ 3）
	m.fill(-5, -4, 5, 2, 0)
	m.fill(-5, -1, 5, -1, 1)
	m.fill(-5, -2, 5, -2, 2)
	m.fill(-5, -4, 5, -3, 3)
	# 谷（幅 7）の向こうの原（0）と台地（2）
	m.fill(-6, -16, 6, -12, 0)
	m.fill(-6, -24, 6, -17, 2)
	var goal := OpenIslands.goal_hollow(m, -2, -23, 2, -22)
	StageParts.lift(def, m, Vector2i(0, -16), "ridge_lift")
	def.terrain_boxes = m.boxes()
	# 風の範囲は床の 1 段下から（縁で足が床よりわずかに沈んでも風の外に出ない。docs/campaign-plan.md の所見）
	for zone: Array in [[24, 28], [15, 19]]:
		var gust := def.nature.add_pulsing_wind(
			Vector3i(-1, -1, int(zone[0])),
			Vector3i(3, 3, int(zone[1])),
			Vector3i(1, 0, 0),
			4.0,
			2.0
		)
		gust.strength = RIDGE_WIND
	def.nature.add_wind(Vector3i(-5, -3, -11), Vector3i(5, 6, -5), Vector3i(0, 0, -1), RIDGE_WIND)
	def.nature.add_water(Vector3i(-5, -2, 3), Vector3i(5, -1, 7))
	var raft := StageParts.stone(def, "pond_raft", Vector3i(0, -1, 5), StageParts.RAFT_COLOR)
	raft.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.FLOAT))
	StageParts.item(
		def, RuleAction.Kind.HEAVY, Vector3(-3.5, 0.0, 32.5), RuleVessel.Part.NONE, "おもり"
	)
	StageParts.item(def, RuleAction.Kind.SWIM, Vector3(3.5, 0.0, 32.5), RuleVessel.Part.NONE, "足ひれ")
	StageParts.item(
		def, RuleAction.Kind.FLOAT, Vector3(-3.5, 0.0, 36.5), RuleVessel.Part.NONE, "風船"
	)
	StageParts.boots(def, Vector3(3.5, 0.0, 36.5))
	StageParts.animal(def, "ridge_bunny", Vector3(-3.5, 2.0, -18.5), "木の実")
	def.bells = [StageDef.BellSpec.new("ridge_bell", Vector3(-3.5, 2.0, -21.5))]
	def.spawn_points = StageParts.spawns(Vector3(0.0, 0.0, 35.5))
	def.checkpoints = [Vector3(3.5, 0.0, 10.5), Vector3(3.5, 0.0, 1.5), Vector3(4.5, 0.0, -13.5)]
	def.clear_condition = StageParts.bells_and_goal(def, goal)
	return def
