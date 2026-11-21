class_name OptionalWorldsO2
extends RefCounted
## 寄り道 O2「さかさ雲」（風・浮く・高さ・落ちることが主役）。どのステージも難しい。
## 共通の目安と方針は OptionalWorlds の冒頭。想定の解き方は docs/campaign-plan.md の O2 の表の下。
## 浮く（FLOAT ×1）の滑空の目安（測った値。走って縁から跳ぶ）: 着く所より h m 高い所から、無風で約 3.1h + 6 m、
## 追い風（3 m/秒）で約 5h + 10 m、向かい風で約 1.25h + 2.5 m。浮くが無ければ、高さ 6 からでも約 6 m。

const W := RuleAction.Kind.FORWARD
const A := RuleAction.Kind.LEFT
const S := RuleAction.Kind.BACK
const D := RuleAction.Kind.RIGHT
const J := RuleAction.Kind.JUMP
const FLOAT := RuleAction.Kind.FLOAT
const HEAVY := RuleAction.Kind.HEAVY
## O2-1 の巣
const VANE_NEST := AABB(Vector3(-1.0, 2.5, -40.0), Vector3(2.0, 2.0, 2.0))
## O2-2 の巣（見晴らしの南の端。段々を上がりきった所）
const RAFT_NEST := AABB(Vector3(1.0, 5.5, -18.0), Vector3(3.0, 2.0, 3.0))
const ISLES_NEST := AABB(Vector3(-26.0, 8.5, -26.0), Vector3(2.0, 2.0, 2.0))
const TOWER_NEST := AABB(Vector3(-6.0, 2.5, -37.0), Vector3(2.0, 2.0, 2.0))
const MAELSTROM_NEST := AABB(Vector3(-5.0, 8.5, -60.0), Vector3(2.0, 2.0, 2.0))


## O2-1 風見の段々（目安 25 分・仮）。
## 南の雲の島から、幅 35 の空の先の北の島（ゴール）へ渡る。橋もワープも無い。
## - 島の西に高さ 6 の見張り塔（段々で上がれる）。てっぺんに「浮く」（風船）。
## - 空の西半分には南向きの風（向かい風）、東の段（高さ 2）の先には北向きの風（追い風）が吹いている。
## 手持ちは W とジャンプだけ。東の段に D が落ちている。北の島の生き物（巣へ帰りたい）は、巣の段々の下にいる。
## 想定の解き方:
## 1. 塔に上がって風船（浮く）を拾う。塔の上から北へ滑空しても、向かい風で 10 m ほどしか進まない。
##    島の地面から持ち上げて（下の 2.）無風で滑空しても、約 28 m で届かない。
## 2. 追い風の東の段へ行く。段の縁から跳んで滑空しても、高さ 2 からでは約 20 m で届かない。
##    縁の地面のセルにジャンプを単発で渡して乗り、上がる途中で戻ったジャンプで自分も跳ぶ（受け入れた技。約 7 上がる）。
##    高いところから追い風に乗れば、北の島まで届く（塔の上から東へ回り込んで追い風に入ってもよい）。
## 3. 生き物に D とジャンプを渡すと、段々を跳んで巣（高さ 3）へ。巣の下で回収して、北の台の窪みへ。
## 協力: 浮くを 2 つ集めると落ちる速さが半分になり、段の縁から跳ぶだけで届く。
static func vane_steps() -> StageDef:
	var def := OptionalWorlds.base("o2_1", "風見の段々", 25)
	OptionalWorlds.loadout(def, [W, J])
	var m := IslandMap.blank(Vector2i(-12, -52), 30, 64)
	m.fill(-6, 0, 6, 10, 0)  # 南の雲の島
	m.fill(-6, 0, -3, 3, 6)  # 見張り塔
	for i in 5:
		m.fill(-2, 4 - i, -2, 4 - i, i + 1)  # 塔の段々
	m.fill(7, 3, 7, 4, 1)  # 東の段への一段
	m.fill(8, 0, 12, 6, 2)  # 東の段（追い風の入口）
	m.fill(-8, -50, 14, -36, 0)  # 北の島
	m.fill(-8, -50, 14, -45, 2)  # 北の台
	m.fill(8, -44, 9, -44, 1)
	m.fill(2, -39, 2, -39, 1)  # 巣の段々（1・2・巣 3）
	m.fill(1, -39, 1, -39, 2)
	m.fill(-1, -40, 0, -39, 3)
	var goal := OpenIslands.goal_hollow(m, 1, -49, 5, -48)
	def.terrain_boxes = m.boxes()
	def.nature.add_wind(Vector3i(-12, -2, -35), Vector3i(6, 20, -1), Vector3i(0, 0, 1))
	def.nature.add_wind(Vector3i(7, -2, -35), Vector3i(14, 20, -1), Vector3i(0, 0, -1))
	OptionalWorlds.item(def, FLOAT, Vector3(-4.5, 6.0, 1.5))
	OptionalWorlds.item(def, D, Vector3(10.5, 2.0, 5.5))
	OptionalWorlds.creature(def, "bunny", Vector3(4.5, 0.0, -38.5), Creature.MODEL_WISH)
	def.spawn_points = OptionalWorlds.spawns(Vector3(0.0, 0.0, 8.5))
	def.checkpoints = [Vector3(6.5, 0.0, -37.5)]
	OptionalWorlds.nest_and_goal(def, "bunny", VANE_NEST, goal)
	return def


## O2-2 雲の筏（目安 30 分・仮）。
## 真ん中の雲の島（出現）・西の小島（強い横風の細い橋の先）・北の高い見晴らし（高さ 6、段々の先）・北の島（ゴール）。
## 見晴らしから北の島までは幅 50 の空。浮くで滑空しても、まっすぐでは届かない（見晴らしの地面のセルで持ち上げて
## 自分も跳び、高さ 13 ほどから滑空しても約 46 m）。
## 空の途中の「雲の段」（3×3、高さ 3）は、島の重さの板（重さ 4）が押されている間だけ、下からせり上がる
## （押されていない間は、ずっと下まで沈んでいる。乗ろうとすると落ちる）。
## - 島の東の風の通り道に、「重い」の付いた箱（おもりで動かない）。風下の端に重さの板と止めの壁。
## - 西の小島へは、北向きの強い横風（6 m/秒。歩く速さより強く、斜めに歩いても流される）が吹く幅 1 の橋だけ。
##   小島に「浮く」（風船）。
## 重いと浮くは数で打ち消し合う（両方ホットバーにあると、どちらも効かない）。ホットバーにある能力だけが効く。
## 手持ちは W・D・ジャンプ。生き物（巣へ帰りたい）は見晴らしへの段々の最後の段（高さ 5）にいる。
## 想定の解き方:
## 1. 風の通り道の箱から「重い」を F で回収する（自分が重くなる）。箱は風で風下へ流れ、板の上で壁に止まる（まだ重さ 1）。
## 2. 重いを持って横風の橋を渡り、風船を拾う。風船はかばんに入れたまま（ホットバーに置くと重いが消えて流される）。
## 3. 戻って、板の上の箱に重いを渡す（重さ 4）→ 雲の段がせり上がる。
## 4. 段々を上がって見晴らしへ。生き物に D とジャンプを渡すと、見晴らし（巣）へ跳んで上がる。巣で回収する。
## 5. 風船をホットバーへ。雲の段は見晴らしから 34 m 先。ふつうに跳んで滑空しても届かないので、見晴らしの北の縁の
##    地面のセルで持ち上げて自分も跳び、高い所から雲の段へ滑空する（行き過ぎないよう、上で止まって降りる）。
##    雲の段（扉なので持ち上げには使えない）の北の縁から跳んで、13 m 先の北の島へ滑空する。北の台の窪みへ。
## 協力: 浮くを 2 つ集めると、見晴らしから北の島へまっすぐ届く。板は 4 人で乗っても上がるが、その人たちは渡れない。
static func cloud_raft() -> StageDef:
	var def := OptionalWorlds.base("o2_2", "雲の筏", 30)
	OptionalWorlds.loadout(def, [W, D, J])
	var m := IslandMap.blank(Vector2i(-24, -82), 44, 94)
	m.fill(-6, -10, 10, 10, 0)  # 真ん中の雲の島
	m.fill(9, -6, 9, -6, 2)  # 風の通り道の止めの壁
	m.fill(-15, -2, -7, -2, 0)  # 横風の橋（幅 1）
	m.fill(-21, -5, -16, 1, 0)  # 西の小島
	for i in 5:
		m.fill(2, -11 - i, 2, -11 - i, i + 1)  # 見晴らしへの段々
	m.fill(-2, -20, 6, -16, 6)  # 北の高い見晴らし
	m.fill(-8, -80, 12, -69, 0)  # 北の島
	m.fill(-8, -80, 12, -76, 2)  # 北の台
	m.fill(8, -75, 9, -75, 1)
	var goal := OpenIslands.goal_hollow(m, 0, -79, 4, -78)
	def.terrain_boxes = m.boxes()
	def.nature.add_wind(Vector3i(0, -1, -6), Vector3i(8, 3, -6), Vector3i(1, 0, 0))
	def.nature.add_wind(Vector3i(-15, -1, -9), Vector3i(-7, 12, 5), Vector3i(0, 0, -1), 6.0)
	var anchor := OptionalWorlds.crate(def, "anchor", Vector3i(0, 0, -6))
	anchor.tokens.append(StageDef.TokenSpec.new(HEAVY))
	OptionalWorlds.plate(def, "cloud_plate", Vector3i(8, 0, -6), 4)
	var step := OptionalWorlds.door(
		def, "cloud_step", Vector3i(1, -13, -55), Vector3i(3, 16, 3), PackedStringArray(["cloud_plate"])
	)
	step.inverted = true  # 板が押されている間だけ、せり上がって雲の段になる
	OptionalWorlds.item(def, FLOAT, Vector3(-19.5, 0.0, -2.5))
	OptionalWorlds.creature(def, "lamb", Vector3(2.5, 5.0, -14.5), Creature.MODEL_WISH)
	def.spawn_points = OptionalWorlds.spawns(Vector3(0.0, 0.0, 7.5))
	def.checkpoints = [Vector3(-3.5, 0.0, 3.5)]
	OptionalWorlds.nest_and_goal(def, "lamb", RAFT_NEST, goal)
	return def


## O2-3 落ちる島々（目安 30 分・仮）。
## 南の高い雲（高さ 8、出現）から北の雲の段（高さ 2、東寄り）へ滑空して降り、その北の高い段（高さ 6）へ登り直し、
## 西の空の先（幅 18）の高い島（高さ 8、ゴール）へ滑空する。
## - 高い段の東半分とその上の空には、東向きの強い風（6 m/秒。歩く速さより強い）。重くないと空へ吹き飛ばされる。
##   段の西半分は風が無い。
## - 高い段の西の空には、西向きの強い風（西の島への追い風）。
## - 重いと浮くは数で打ち消し合う（両方ホットバーにあると、どちらも効かない）。ホットバーにある能力だけが効く。
## 手持ちは W・ジャンプ・浮く。雲の段に「重い」と D が落ちている。西の島の生き物（巣へ帰りたい）は巣の小山の下。
## （地図の高さは 1 桁まで。IslandMap は 1 文字で高さを書く）
## 想定の解き方:
## 1. 浮くで南の雲から北の雲の段へ滑空して降りる（高い段へも西の島へも、ここからは届かない）。
## 2. 「重い」と D を拾う。重いをホットバーへ、浮くをかばんへ（入れ替える）。
## 3. 雲の段の北の縁の地面のセルにジャンプを単発で渡して乗り、上がる途中で自分も跳んで高い段の東半分へ
##    （受け入れた技）。重いので強い風に飛ばされない。風の無い西半分へ歩く。
## 4. 風の無い所で、浮くをホットバーへ、重いをかばんへ。もう一度、地面のセルで持ち上げて自分も跳び、
##    高い所から追い風に乗って西の島へ滑空する（ふつうに跳ぶだけでは、着く前に島より低くなる）。
## 5. 生き物に D とジャンプを渡して巣へ。回収して、島の窪み（ゴール）へ。
## 協力: 浮くを 2 つ集めると、落ちる速さが半分になり、高い段からふつうに跳んでも届く。
static func falling_isles() -> StageDef:
	var def := OptionalWorlds.base("o2_3", "落ちる島々", 30)
	OptionalWorlds.loadout(def, [W, J, FLOAT])
	var m := IslandMap.blank(Vector2i(-34, -36), 42, 44)
	m.fill(-4, 0, 4, 6, 8)  # 南の高い雲（出現）
	m.fill(3, -22, 5, -10, 2)  # 北の雲の段（東寄り）
	m.fill(-5, -26, 5, -23, 6)  # 高い段（東半分は強い風、西半分は無風）
	m.fill(-32, -34, -24, -24, 8)  # 西の高い島（ゴール）
	m.fill(-26, -26, -25, -25, 9)  # 巣の小山
	var goal := OpenIslands.goal_hollow(m, -31, -32, -29, -31)
	def.terrain_boxes = m.boxes()
	def.nature.add_wind(Vector3i(0, 3, -27), Vector3i(9, 20, -23), Vector3i(1, 0, 0), 6.0)
	def.nature.add_wind(Vector3i(-23, 0, -34), Vector3i(-6, 20, -20), Vector3i(-1, 0, 0), 6.0)
	OptionalWorlds.item(def, HEAVY, Vector3(4.5, 2.0, -12.5))
	OptionalWorlds.item(def, D, Vector3(3.5, 2.0, -14.5))
	OptionalWorlds.creature(def, "kit", Vector3(-24.5, 8.0, -28.5), Creature.MODEL_KIT)
	def.spawn_points = OptionalWorlds.spawns(Vector3(0.0, 8.0, 3.5))
	def.checkpoints = [Vector3(4.5, 2.0, -16.5)]
	OptionalWorlds.nest_and_goal(def, "kit", ISLES_NEST, goal)
	return def


## O2-4 さかさまの塔（目安 30 分・仮）。
## 高い塔のてっぺん（高さ 9）から始まり、下の島へ降りていく。塔の北の空には、北の島（ゴール）との間に
## 南向きの強い風の壁が 2 枚（厚さ 2、どの高さも、島の幅いっぱい。6 m/秒で、浮いて滑空しても押し戻される）。
## 壁と壁の間に小さな雲の足場（高さ 2）がある。
## 手持ちは W・ジャンプ・浮く。塔のてっぺんにダッシュ、北の島に D。
## ダッシュは風を受けずにまっすぐ 3 マス進むが、床に着くまで 1 回しか使えない（W/A/D が要る）。
## 想定の解き方:
## 1. ダッシュを拾い、塔から北へ滑空する。風の壁の手前でダッシュすると、壁を抜けられる。
## 2. 1 回のダッシュで 2 枚目は抜けられないので、間の雲の足場に降りる（行き過ぎないよう、上で止まって降りる）。
##    床に着くと、またダッシュできる。
## 3. 足場は低い（高さ 2）。ふつうに跳ぶだけでは 2 枚目の壁の手前で低くなりすぎる…ことはないが、
##    足場の地面のセルで持ち上げて自分も跳ぶと、高い所から余裕をもって 2 枚目の壁へ向かえる。壁の手前でダッシュ。
## 4. 北の島の生き物（巣へ帰りたい）に D とジャンプを渡して巣へ。回収して、北の台の窪みへ。
## 協力: ダッシュを 2 つ集めると 6 マス進むが、壁と壁は離れているので、足場に降りる手順は同じ。
static func upside_tower() -> StageDef:
	var def := OptionalWorlds.base("o2_4", "さかさまの塔", 30)
	OptionalWorlds.loadout(def, [W, J, FLOAT])
	var m := IslandMap.blank(Vector2i(-20, -46), 41, 54)
	m.fill(-3, 0, 3, 6, 9)  # 高い塔（出現）
	m.fill(-2, -20, 2, -16, 2)  # 壁の間の雲の足場
	m.fill(-8, -44, 8, -34, 0)  # 北の島
	m.fill(-8, -44, 8, -40, 2)  # 北の台
	m.fill(5, -39, 6, -39, 1)
	m.fill(-3, -36, -3, -36, 1)  # 巣の段々（1・2・巣 3）
	m.fill(-4, -36, -4, -36, 2)
	m.fill(-6, -37, -5, -36, 3)
	var goal := OpenIslands.goal_hollow(m, -2, -43, 2, -42)
	def.terrain_boxes = m.boxes()
	def.nature.add_wind(Vector3i(-20, -6, -11), Vector3i(20, 24, -10), Vector3i(0, 0, 1), 6.0)
	def.nature.add_wind(Vector3i(-20, -6, -27), Vector3i(20, 24, -26), Vector3i(0, 0, 1), 6.0)
	OptionalWorlds.item(def, RuleAction.Kind.DASH, Vector3(-1.5, 9.0, 4.5))
	OptionalWorlds.item(def, D, Vector3(4.5, 0.0, -35.5))
	OptionalWorlds.creature(def, "wish", Vector3(0.5, 0.0, -35.5), Creature.MODEL_WISH)
	def.spawn_points = OptionalWorlds.spawns(Vector3(0.0, 9.0, 2.5))
	def.checkpoints = [Vector3(0.5, 2.0, -18.5)]
	OptionalWorlds.nest_and_goal(def, "wish", TOWER_NEST, goal)
	return def


## O2-5 空の大渦（目安 45 分・仮）。さかさ雲の最後。
## 雲の島（出現）・西の小島（強い横風の細い橋の先）・北東の高い塔（高さ 9。島のワープの石からだけ行ける）・
## 塔の北の空に浮かぶ「雲の段」（3×3、高さ 7。島の重さの板＝重さ 4 が押されている間だけ、下からせり上がる）・
## はるか北の高い島（高さ 8、ゴール。雲の段の上のワープの石からだけ行ける）。
## 塔と雲の段の間には、南向きの強い風の壁（厚さ 2、どの高さも。6 m/秒）。
## - 島の東の風の通り道に「重い」付きの箱、風下に重さの板と止めの壁（O2-2 と同じ仕組み）。
## - 西の小島に「浮く」とダッシュ。重いと浮くは打ち消し合う。ホットバーにある能力だけが効く。
## 手持ちは W・D・ジャンプ。北の島の生き物（巣へ帰りたい）は巣の小山の下。
## 想定の解き方:
## 1. 箱の「重い」を回収する（自分が重くなる）。箱は風で板の上へ流れる（重さ 1）。
## 2. 重いを持って横風の橋を渡り、ダッシュ（ホットバー）と浮く（かばん）を拾って戻る。
## 3. 板の上の箱に重いを渡す（重さ 4）→ 雲の段がせり上がる。
## 4. ワープで塔のてっぺんへ。浮くをホットバーへ。北へ滑空し、風の壁の手前でダッシュして抜け、雲の段に降りる
##    （行き過ぎないよう、上で止まって降りる）。
## 5. 雲の段のワープの石で北の島へ（塔から滑空しても、北の島は遠くて高い）。
## 6. 生き物に D とジャンプを渡して巣へ。回収して、島の窪み（ゴール）へ。
## 協力: 浮くを 2 つ集めても、北の島へはワープでしか行けない。板は 4 人で乗っても上がるが、その人たちは塔へ行けない。
static func sky_maelstrom() -> StageDef:
	var def := OptionalWorlds.base("o2_5", "空の大渦", 45)
	OptionalWorlds.loadout(def, [W, D, J])
	var m := IslandMap.blank(Vector2i(-24, -70), 50, 82)
	m.fill(-6, -6, 8, 10, 0)  # 雲の島（出現）
	m.fill(7, -3, 7, -3, 2)  # 風の通り道の止めの壁
	m.fill(-15, 1, -7, 1, 0)  # 横風の橋（幅 1）
	m.fill(-21, -2, -16, 4, 0)  # 西の小島
	m.fill(10, -14, 14, -10, 9)  # 北東の高い塔
	m.fill(-8, -68, 8, -56, 8)  # はるか北の高い島（ゴール）
	m.fill(-5, -60, -4, -59, 9)  # 巣の小山
	var goal := OpenIslands.goal_hollow(m, -2, -66, 2, -65)
	def.terrain_boxes = m.boxes()
	def.nature.add_wind(Vector3i(0, -1, -3), Vector3i(6, 3, -3), Vector3i(1, 0, 0))
	def.nature.add_wind(Vector3i(-15, -1, -5), Vector3i(-7, 14, 7), Vector3i(0, 0, -1), 6.0)
	def.nature.add_wind(Vector3i(-24, -6, -17), Vector3i(25, 24, -16), Vector3i(0, 0, 1), 6.0)
	var anchor := OptionalWorlds.crate(def, "anchor", Vector3i(0, 0, -3))
	anchor.tokens.append(StageDef.TokenSpec.new(HEAVY))
	OptionalWorlds.plate(def, "sky_plate", Vector3i(6, 0, -3), 4)
	var step := OptionalWorlds.door(
		def, "sky_step", Vector3i(11, -13, -26), Vector3i(3, 20, 3), PackedStringArray(["sky_plate"])
	)
	step.inverted = true  # 板が押されている間だけ、せり上がって雲の段になる
	OptionalWorlds.warp(def, "isle_stone", Vector3i(4, 0, 5), "tower_stone")
	OptionalWorlds.warp(def, "tower_stone", Vector3i(12, 9, -12), "isle_stone")
	OptionalWorlds.warp(def, "step_stone", Vector3i(12, 7, -25), "far_stone")
	OptionalWorlds.warp(def, "far_stone", Vector3i(0, 8, -58))
	OptionalWorlds.item(def, FLOAT, Vector3(-19.5, 0.0, 0.5))
	OptionalWorlds.item(def, RuleAction.Kind.DASH, Vector3(-18.5, 0.0, 2.5))
	OptionalWorlds.creature(def, "elder", Vector3(2.5, 8.0, -59.5), Creature.MODEL_WISH)
	def.spawn_points = OptionalWorlds.spawns(Vector3(0.0, 0.0, 7.5))
	def.checkpoints = [Vector3(-3.5, 0.0, 3.5)]
	OptionalWorlds.nest_and_goal(def, "elder", MAELSTROM_NEST, goal)
	return def
