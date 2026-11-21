class_name OptionalWorldsO1
extends RefCounted
## 寄り道 O1「からくり工房」（スイッチ・重さの板・扉・時の鐘・ワープの石が主役）。どのステージも難しい。
## 共通の目安と方針は OptionalWorlds の冒頭。想定の解き方は docs/campaign-plan.md の O1 の表の下。

const W := RuleAction.Kind.FORWARD
const A := RuleAction.Kind.LEFT
const S := RuleAction.Kind.BACK
const D := RuleAction.Kind.RIGHT
const J := RuleAction.Kind.JUMP
## O1-1 の巣（生き物を連れていく 3 段目の台の上）
const COG_NEST := AABB(Vector3(-5.0, 2.5, -17.0), Vector3(2.0, 2.0, 2.0))
const CLOCK_NEST := AABB(Vector3(-5.0, 2.5, -23.0), Vector3(2.0, 2.0, 2.0))
const SCALE_NEST := AABB(Vector3(-6.0, 2.5, -28.0), Vector3(2.0, 2.0, 2.0))
const SIGN_NEST := AABB(Vector3(-6.0, 2.5, -27.0), Vector3(2.0, 2.0, 2.0))
const GRAND_NEST := AABB(Vector3(-6.0, 2.5, -16.0), Vector3(2.0, 2.0, 2.0))


## O1-1 歯車の渡し（目安 20 分・仮）。
## 南の島（出現）から北の島（ゴール）へは、谷の上の細い土手 1 本。土手の真ん中に高さ 6 の扉があり、
## 東の小島（幅 5 の空の先）の重さの板が押されている間だけ開く。小島へは、南の島のワープの石からだけ行ける。
## 手持ちは W とジャンプだけ（南の島に D が落ちている）。
## 想定の解き方:
## 1. 南の島の D を拾う。箱（cog）を東のワープの石へ押す（D を単発で渡して押す）と、箱は小島の石へ移る。
## 2. 箱が小島の石に乗ったままだと石がふさがり、自分は小島へ行けない（行き先の石に乗っていると移らない）。
##    箱を石から板へ動かすには、箱を送る前に W も箱に渡しておく（付いた能力は箱と一緒に移る）。
##    繰り返しで渡せば、箱は向こうで北へ進んで板に乗り、板の北の段で止まる。単発なら、着いてから W を押す
##    （単発はどこから押しても動き、押した人の手元へ戻る）。
## 3. 扉が開いたら土手を渡る。北の島の生き物（巣へ帰りたい）は、1 段目の台までしか上がれない。2 段目は
##    板（step_plate）を押している間だけせり上がる扉の段。生き物に D とジャンプを渡し、自分が板に乗ると、
##    生き物は 1 段目 → せり上がった段 → 巣（高さ 3）と跳んで上がる。
## 4. 巣の下で生き物からジャンプ（と D）を回収し、東の段々から北の台の窪み（ゴール）へ。
## 協力: 仲間がワープで小島へ行って板に乗れば、箱は要らない（板の上の仲間は、扉が開いている間に
##   土手を渡った人が戻る必要はない。箱を板に送ってから全員で渡る、でもよい）。
static func cog_crossing() -> StageDef:
	var def := OptionalWorlds.base("o1_1", "歯車の渡し", 20)
	OptionalWorlds.loadout(def, [W, J])
	var m := IslandMap.blank(Vector2i(-12, -27), 31, 41)
	m.fill(-6, 2, 6, 12, 0)  # 南の島
	m.fill(-1, -9, 0, 1, 0)  # 谷の上の土手（幅 2）
	m.fill(-8, -25, 8, -10, 0)  # 北の島
	m.fill(-8, -25, 8, -20, 2)  # 北の台
	m.fill(5, -19, 6, -19, 1)  # 北の台への段（1 段ずつ）
	m.fill(12, -3, 15, 1, 0)  # 東の小島
	m.fill(13, -2, 13, -2, 1)  # 板の北の段（箱を止める）
	# 巣: 1 段目（高さ 1）・せり上がる段（扉。下を空ける）・巣（高さ 3）
	m.fill(-4, -14, -4, -14, 1)
	m.fill(-4, -15, -4, -15, -1)
	m.fill(-5, -17, -4, -16, 3)
	# 南の島の箱の北の段（繰り返しで W を渡しても、南の島では箱が進まない）
	m.fill(3, 5, 4, 5, 1)
	var goal := OpenIslands.goal_hollow(m, -2, -24, 2, -23)
	def.terrain_boxes = m.boxes()
	OptionalWorlds.crate(def, "cog", Vector3i(3, 0, 6))
	OptionalWorlds.item(def, D, Vector3(-3.5, 0.0, 9.5))
	OptionalWorlds.warp(def, "warp_home", Vector3i(4, 0, 6), "warp_isle")
	OptionalWorlds.warp(def, "warp_isle", Vector3i(13, 0, 0), "warp_home")
	OptionalWorlds.plate(def, "gate_plate", Vector3i(13, 0, -1))
	OptionalWorlds.door(
		def,
		"cog_gate",
		Vector3i(-1, 0, -5),
		Vector3i(2, OptionalWorlds.GATE_HEIGHT, 1),
		PackedStringArray(["gate_plate"])
	)
	OptionalWorlds.plate(def, "step_plate", Vector3i(-3, 0, -15))
	var step := OptionalWorlds.door(
		def, "nest_step", Vector3i(-4, 0, -15), Vector3i(1, 2, 1), PackedStringArray(["step_plate"])
	)
	step.inverted = true  # 板が押されている間だけ、せり上がって段になる
	OptionalWorlds.creature(def, "wish", Vector3(-2.5, 0.0, -12.5), Creature.MODEL_WISH)
	def.spawn_points = OptionalWorlds.spawns(Vector3(0.0, 0.0, 10.5))
	def.checkpoints = [Vector3(2.5, 0.0, -11.5)]
	OptionalWorlds.nest_and_goal(def, "wish", COG_NEST, goal)
	return def


## O1-2 時計じかけの回廊（目安 25 分・仮）。
## 南の島 → 土手（扉 A）→ 真ん中の島 → 土手（扉 B）→ 北の島（ゴール）。扉はどれも高さ 6 で、谷の上の土手にある。
## - 扉 A は、南の島の奥（南西の端）の時の鐘（2.5 秒）が鳴っている間だけ開く。鳴らしてから走っても、
##   着く前に閉じる（約 19 m。走って 3.8 秒）。
## - 扉 B は、真ん中の島の重さの板（2 マス・重さ 2）が押されている間だけ開く。
## 手持ちは W とジャンプだけ（南の島に A が落ちている）。真ん中の島の子どもの生き物は、北の島の巣（高さ 3）へ帰りたい。
## 想定の解き方:
## 1. 扉は、閉じる箱の中に誰か・何かがいると閉じない（挟まない）。扉 A の手前の箱（cog_a）に W を
##    繰り返しで渡しておき、鐘を鳴らす。扉が開いた間に箱が戸口へ進み、戸口の北の段で止まる。
##    箱が戸口にいる間、扉は開いたまま。土手は幅 2 なので、空いている西の列を通る
##    （W を単発で渡して、鐘を鳴らしてから W を押す、でもよい）。
## 2. 板は重さ 2。自分が乗ると、自分は扉 B を通れない。箱を 2 つ板に乗せる:
##    真ん中の島の箱（cog_b）に W を繰り返しで渡すと北へ進み、板の北の段で止まる（板の 1 マス目）。
##    扉 A の戸口の箱を A（西）で 1 マスずらし、W で北へ送ると、土手を渡って cog_b の後ろ（板の 2 マス目）で止まる。
## 3. 扉 B が開いたら、生き物に A とジャンプを渡す。生き物は扉 B を通って、巣の段々を跳んで上がる。
## 4. 巣の下で回収し、北の段々から台の窪み（ゴール）へ。
## 協力: 仲間が W を 1 つくれれば（W×2 で速さ 2 倍）、鐘を鳴らしてから走って扉 A に間に合う。
##   板は 2 人で乗れば箱は要らない（1 人が乗って、もう 1 人が渡ったあとは、渡った人が…とはいかないので、
##   最後の人のために箱を 1 つ板に乗せる）。
static func clockwork_corridor() -> StageDef:
	var def := OptionalWorlds.base("o1_2", "時計じかけの回廊", 25)
	OptionalWorlds.loadout(def, [W, J])
	var m := IslandMap.blank(Vector2i(-12, -31), 25, 51)
	m.fill(-8, 4, 8, 18, 0)  # 南の島
	m.fill(-1, -4, 0, 3, 0)  # 土手 A
	m.fill(0, -1, 0, -1, 1)  # 扉 A の北の段（東の列だけ。箱を戸口で止める）
	m.fill(-8, -16, 8, -5, 0)  # 真ん中の島
	m.fill(-1, -13, -1, -13, 1)  # 板の北の段
	m.fill(-1, -19, 0, -17, 0)  # 土手 B
	m.fill(-7, -30, 7, -20, 0)  # 北の島
	m.fill(-7, -30, 7, -26, 2)  # 北の台
	m.fill(4, -25, 5, -25, 1)
	# 巣の段々（1・2・巣 3）
	m.fill(-2, -22, -2, -22, 1)
	m.fill(-3, -22, -3, -22, 2)
	m.fill(-5, -23, -4, -22, 3)
	var goal := OpenIslands.goal_hollow(m, -2, -29, 2, -28)
	def.terrain_boxes = m.boxes()
	OptionalWorlds.crate(def, "cog_a", Vector3i(0, 0, 2))
	OptionalWorlds.crate(def, "cog_b", Vector3i(-1, 0, -8))
	OptionalWorlds.item(def, A, Vector3(6.5, 0.0, 15.5))
	OptionalWorlds.timed_bell(def, "clock_a", Vector3(-7.5, 0.0, 17.5), 2.5)
	OptionalWorlds.door(
		def,
		"gate_a",
		Vector3i(-1, 0, 0),
		Vector3i(2, OptionalWorlds.GATE_HEIGHT, 1),
		PackedStringArray(["clock_a"])
	)
	OptionalWorlds.plate(def, "scale", Vector3i(-1, 0, -12), 2, Vector2i(1, 2))
	OptionalWorlds.door(
		def,
		"gate_b",
		Vector3i(-1, 0, -18),
		Vector3i(2, OptionalWorlds.GATE_HEIGHT, 1),
		PackedStringArray(["scale"])
	)
	OptionalWorlds.creature(def, "kit", Vector3(2.5, 0.0, -14.5), Creature.MODEL_KIT)
	def.spawn_points = OptionalWorlds.spawns(Vector3(0.0, 0.0, 8.5))
	def.checkpoints = [Vector3(4.5, 0.0, -7.5)]
	OptionalWorlds.nest_and_goal(def, "kit", CLOCK_NEST, goal)
	return def


## O1-3 重さくらべの秤（目安 30 分・仮）。
## 南の島 → 土手（扉 1）→ 真ん中の島 → 土手（扉 2）→ 北の島（ゴール）。西の小島と東の小島は幅 5 の空の先。
## - 扉 1 は、南の島の重さの板（重さ 4）を押すたびに開く ↔ 閉じるが切り替わる（切り替えの扉）。
## - 扉 2 は、真ん中の島の重さの板（重さ 4）が押されていて、しかも東の小島の時の鐘（2.5 秒）が鳴っている
##   間だけ開く（両方）。鐘は空の向こうで手が届かない。
## 手持ちは W とジャンプだけ。南の島に「重い」（おもり）、真ん中の島に「投げる」と A。発射台は西の小島にある。
## 想定の解き方:
## 1. 「重い」を持つと重さ 4（BodyTraits.weight_units）。おもりを持って板 1 に乗ると扉 1 が開き、降りても開いたまま。
## 2. 真ん中の島の東のワープの石（m_out）で西の小島へ。発射台（東向き）を北の石（k_send）へ押すと、
##    真ん中の島の東の端の石（m_aim）へ移り、東の小島の鐘を向く。帰りは西の小島の北の石（k_home）から。
## 3. 発射台に「投げる」を渡すと、1.4 秒ごとに玉を撃ち、時の鐘は鳴りっぱなしになる。
## 4. 箱（scale_crate）に「重い」を渡して北へ送ると、板 2 に乗って北の段で止まる（重さ 4）→ 扉 2 が開く。
##    自分がおもりを持って板 2 に乗っても開くが、それでは自分が通れない。
## 5. 子どもの生き物（巣へ帰りたい）に A とジャンプを渡す。扉 2 を通って巣の段々を上がる。巣の下で回収してゴールへ。
## 協力: 2 人なら、1 人がおもりで板 1 を開け、もう 1 人は…と手分けできるが、扉 2 は最後の人のために
##   箱とおもりが要る（板の上の人は通れない）。4 人いれば、3 人と箱で板 2 を押して 1 人ずつ…とはならない
##   （板の上の人が通れない）。協力でも解き方の芯は同じ。
static func weighing_scale() -> StageDef:
	var def := OptionalWorlds.base("o1_3", "重さくらべの秤", 30)
	OptionalWorlds.loadout(def, [W, J])
	var m := IslandMap.blank(Vector2i(-16, -36), 31, 50)
	m.fill(-7, 2, 7, 13, 0)  # 南の島
	m.fill(-1, -5, 0, 1, 0)  # 土手 1
	m.fill(-8, -19, 6, -6, 0)  # 真ん中の島
	m.fill(2, -18, 2, -18, 1)  # 板 2 の北の段
	m.fill(-16, -15, -14, -10, 0)  # 西の小島（発射台）
	m.fill(12, -11, 14, -7, 0)  # 東の小島（時の鐘）
	m.fill(-1, -24, 0, -20, 0)  # 土手 2
	m.fill(-7, -35, 7, -25, 0)  # 北の島
	m.fill(-7, -35, 7, -31, 2)  # 北の台
	m.fill(4, -30, 5, -30, 1)
	m.fill(-3, -27, -3, -27, 1)  # 巣の段々（1・2・巣 3）
	m.fill(-4, -27, -4, -27, 2)
	m.fill(-6, -28, -5, -27, 3)
	var goal := OpenIslands.goal_hollow(m, -2, -34, 2, -33)
	def.terrain_boxes = m.boxes()
	OptionalWorlds.item(def, RuleAction.Kind.HEAVY, Vector3(-5.5, 0.0, 10.5))
	OptionalWorlds.item(def, RuleAction.Kind.THROW, Vector3(-5.5, 0.0, -8.5))
	OptionalWorlds.item(def, A, Vector3(-6.5, 0.0, -14.5))
	OptionalWorlds.crate(def, "scale_crate", Vector3i(2, 0, -12))
	var launcher := StageDef.BlockSpec.new("launcher", Vector3i(-15, 0, -11))
	launcher.launcher_direction = Vector3i(1, 0, 0)
	def.blocks.append(launcher)
	OptionalWorlds.plate(def, "plate_1", Vector3i(2, 0, 3), 4)
	var gate_1 := OptionalWorlds.door(
		def,
		"gate_1",
		Vector3i(-1, 0, -2),
		Vector3i(2, OptionalWorlds.GATE_HEIGHT, 1),
		PackedStringArray(["plate_1"])
	)
	gate_1.mode = MechanismSpecs.DoorMode.TOGGLE
	OptionalWorlds.plate(def, "plate_2", Vector3i(2, 0, -17), 4)
	OptionalWorlds.timed_bell(def, "chime", Vector3(12.5, 0.0, -8.5), 2.5)
	var gate_2 := OptionalWorlds.door(
		def,
		"gate_2",
		Vector3i(-1, 0, -22),
		Vector3i(2, OptionalWorlds.GATE_HEIGHT, 1),
		PackedStringArray(["plate_2", "chime"])
	)
	gate_2.require_all = true
	OptionalWorlds.warp(def, "m_out", Vector3i(4, 0, -12), "k_land")
	OptionalWorlds.warp(def, "k_land", Vector3i(-15, 0, -14))
	OptionalWorlds.warp(def, "k_send", Vector3i(-15, 0, -12), "m_aim")
	OptionalWorlds.warp(def, "m_aim", Vector3i(6, 0, -9))
	OptionalWorlds.warp(def, "k_home", Vector3i(-14, 0, -15), "m_back")
	OptionalWorlds.warp(def, "m_back", Vector3i(3, 0, -8))
	OptionalWorlds.creature(def, "kid", Vector3(-0.5, 0.0, -18.5), Creature.MODEL_KIT)
	def.spawn_points = OptionalWorlds.spawns(Vector3(0.0, 0.0, 9.5))
	def.checkpoints = [Vector3(-3.5, 0.0, -7.5)]
	OptionalWorlds.nest_and_goal(def, "kid", SCALE_NEST, goal)
	return def


## O1-4 札の歯車（目安 30 分・仮）。全員が最初から「ジャンプ禁止」の札を持っている（工房の決まり）。
## 禁止を持っていると、自分で跳べず、自分が渡したジャンプの単発も起動できない（繰り返し・信号は動く）。
## 南の島 → 土手（扉 1）→ 真ん中の島 → 土手（扉 2）→ 北の島（ゴール）。扉はどれも高さ 6。
## - 扉 1 は切り替えの扉。板 1 の上の「跳ね箱」（繰り返しのジャンプが付いている）が着地するたびに、
##   開く ↔ 閉じるが入れ替わる。
## - 扉 2 は、真ん中の島の板 2 が押されている間だけ開く。板 2 へ送れる箱には「W 禁止」の札が付いている。
## 手持ちは W・D・ジャンプ。生き物（巣へ帰りたい）は真ん中の島にいる。
## 想定の解き方:
## 1. 跳ね箱が着地して扉 1 が開いたところで、跳ね箱を止める。いちばん良いのは、自分のジャンプ禁止の札を
##    跳ね箱に渡すこと（跳ね箱は跳べなくなり、自分は跳べるようになる）。跳ね箱のジャンプを F で回収しても止まる。
##    南の島には札を捨てられる場所が他に無い（地面のセルは下が空で落ち、札は手元へ戻る）。
## 2. 真ん中の島の札付きの箱を F で回収すると、W 禁止の札が自分に来る（前へ歩けない。D で歩く）。
##    札をどこかへ渡す（生き物に渡しても、生き物は D で歩くので困らない）。
##    箱に W を繰り返しで渡すと北へ進んで板 2 に乗り、北の段で止まる → 扉 2 が開く。W は回収しておく。
## 3. 生き物に D とジャンプを渡す。扉 2 を通って巣へ。巣の下で回収し（札も戻ってくる）、北の台の窪みへ。
##    ジャンプ禁止を手元に残したままだと、北の台へ上がれない（どこかへ渡す）。
## 協力: 仲間がいれば、1 人が板 2 に乗って扉 2 を開け、札付きの箱を動かさずに済む…が、最後の人のために
##   結局箱が要る。跳ね箱は誰か 1 人の札で止めればよい（札は人数分あるので、捨て場所の工夫が増える）。
static func sign_gears() -> StageDef:
	var def := OptionalWorlds.base("o1_4", "札の歯車", 30)
	OptionalWorlds.loadout(def, [W, D, J])
	def.prohibitions = [J]
	var m := IslandMap.blank(Vector2i(-12, -34), 25, 46)
	m.fill(-6, 2, 6, 10, 0)  # 南の島（高い地形は置かない。札の捨て場所を作らない）
	m.fill(-1, -5, 0, 1, 0)  # 土手 1
	m.fill(-8, -18, 8, -6, 0)  # 真ん中の島
	m.fill(3, -15, 3, -15, 1)  # 板 2 の北の段
	m.fill(-1, -23, 0, -19, 0)  # 土手 2
	m.fill(-7, -33, 7, -24, 0)  # 北の島
	m.fill(-7, -33, 7, -30, 2)  # 北の台
	m.fill(4, -29, 5, -29, 1)
	m.fill(-3, -26, -3, -26, 1)  # 巣の段々（1・2・巣 3）
	m.fill(-4, -26, -4, -26, 2)
	m.fill(-6, -27, -5, -26, 3)
	var goal := OpenIslands.goal_hollow(m, -2, -32, 2, -31)
	def.terrain_boxes = m.boxes()
	var hopper := OptionalWorlds.crate(def, "hopper", Vector3i(2, 0, 3), OptionalWorlds.LIFT_COLOR)
	hopper.tokens.append(StageDef.TokenSpec.new(J, false, TriggerMode.Kind.REPEAT))
	var signed := OptionalWorlds.crate(def, "signed", Vector3i(3, 0, -9), OptionalWorlds.SIGN_COLOR)
	signed.tokens.append(StageDef.TokenSpec.new(W, true))
	OptionalWorlds.plate(def, "plate_1", Vector3i(2, 0, 3))
	var gate_1 := OptionalWorlds.door(
		def,
		"gate_1",
		Vector3i(-1, 0, -2),
		Vector3i(2, OptionalWorlds.GATE_HEIGHT, 1),
		PackedStringArray(["plate_1"])
	)
	gate_1.mode = MechanismSpecs.DoorMode.TOGGLE
	OptionalWorlds.plate(def, "plate_2", Vector3i(3, 0, -14))
	OptionalWorlds.door(
		def,
		"gate_2",
		Vector3i(-1, 0, -21),
		Vector3i(2, OptionalWorlds.GATE_HEIGHT, 1),
		PackedStringArray(["plate_2"])
	)
	OptionalWorlds.creature(def, "bunny", Vector3(-0.5, 0.0, -17.5), Creature.MODEL_WISH)
	def.spawn_points = OptionalWorlds.spawns(Vector3(-2.0, 0.0, 7.5))
	def.checkpoints = [Vector3(-4.5, 0.0, -8.5)]
	OptionalWorlds.nest_and_goal(def, "bunny", SIGN_NEST, goal)
	return def


## O1-5 大からくり（目安 40 分・仮）。からくり工房の最後。真ん中の広場の島から、西の島（扉 W の奥）・
## 東の小島（ワープ）・北東の小島（時の鐘）・北の島（ゴール。扉 F の奥）へ。
## 扉 F は、次の 3 つが全部そろっている間だけ開く（両方ではなく、3 つとも）:
## - 東の小島の重さの板（重さ 4）が押されている
## - 北東の小島の時の鐘（2.5 秒）が鳴っている（空の向こう。手は届かない）
## - 西の島のレバーが入っている
## 扉 W は、広場の島の南東の端の時の鐘（2.5 秒）が鳴っている間だけ開く（鳴らしてから走っても間に合わない）。
## 手持ちは W・A・ジャンプ。西の島に「重い」、東の小島に「投げる」。発射台（北向き）には「投げる禁止」の札。
## 東の小島の生き物（巣へ帰りたい）は、北の島の巣へ。
## 想定の解き方:
## 1. 扉 W の手前の箱（cog）に A を繰り返しで渡し、南東の時の鐘を鳴らす。開いた間に箱が戸口へ進み、
##    戸口の西の段で止まる（扉は閉じない）。空いた列から西の島へ。レバーを入れ、「重い」を拾う。
## 2. 発射台の札を F で回収する（投げる禁止が自分に来る。触って渡すのはできる）。
## 3. ワープで東の小島へ。「投げる」を拾う。箱（weight_crate）を北へ送って板に乗せ、W を回収してから
##    「重い」を渡す（重さ 4）。生き物に A とジャンプを渡すと、北の段へ向かう途中でワープの石を踏み、
##    広場の島へ移って、扉 F の前の段（高さ 2）で待つ。自分もワープで戻る。
## 4. 発射台に「投げる」を触って渡す。時の鐘が鳴り続け、扉 F が開く。生き物が巣へ上がる。
## 5. 巣の下で回収し、北の台の窪みへ。
## 協力: 鐘を鳴らしてから W×2 で走れば扉 W に間に合う。板は 4 人で乗っても開くが、その人たちは扉 F を通れない。
static func grand_contraption() -> StageDef:
	var def := OptionalWorlds.base("o1_5", "大からくり", 40)
	OptionalWorlds.loadout(def, [W, A, J])
	var m := IslandMap.blank(Vector2i(-21, -27), 41, 37)
	m.fill(-7, -7, 7, 8, 0)  # 広場の島
	m.fill(-12, 0, -8, 1, 0)  # 西の土手（扉 W）
	m.fill(-11, 1, -11, 1, 1)  # 扉 W の西の段（南の列だけ。箱を戸口で止める）
	m.fill(-20, -4, -13, 5, 0)  # 西の島
	m.fill(13, -4, 18, 3, 0)  # 東の小島
	m.fill(16, -4, 16, -4, 1)  # 板の北の段
	m.fill(14, -4, 14, -4, 1)  # 生き物の誘い（ワープの石の北）
	m.fill(7, -15, 9, -13, 0)  # 北東の小島（時の鐘）
	m.fill(-1, -13, 0, -8, 0)  # 北の土手（扉 F）
	m.fill(0, -7, 0, -7, 1)  # 扉 F の前の段々（東の列。生き物が待つ。発射台の上より高い）
	m.fill(0, -8, 0, -8, 2)
	m.fill(-7, -26, 7, -14, 0)  # 北の島
	m.fill(-7, -26, 7, -22, 2)  # 北の台
	m.fill(4, -21, 5, -21, 1)
	m.fill(-3, -15, -3, -15, 1)  # 巣の段々（1・2・巣 3）
	m.fill(-4, -15, -4, -15, 2)
	m.fill(-6, -16, -5, -15, 3)
	var goal := OpenIslands.goal_hollow(m, -2, -25, 2, -24)
	def.terrain_boxes = m.boxes()
	OptionalWorlds.crate(def, "cog", Vector3i(-9, 0, 1))
	OptionalWorlds.crate(def, "weight_crate", Vector3i(16, 0, 0))
	var launcher := StageDef.BlockSpec.new("launcher", Vector3i(7, 0, -7))
	launcher.launcher_direction = Vector3i(0, 0, -1)
	launcher.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.THROW, true))
	def.blocks.append(launcher)
	OptionalWorlds.item(def, RuleAction.Kind.HEAVY, Vector3(-18.5, 0.0, -2.5))
	OptionalWorlds.item(def, RuleAction.Kind.THROW, Vector3(17.5, 0.0, 2.5))
	OptionalWorlds.timed_bell(def, "west_clock", Vector3(6.5, 0.0, 7.5), 2.5)
	OptionalWorlds.timed_bell(def, "far_chime", Vector3(7.5, 0.0, -12.5), 2.5)
	OptionalWorlds.lever(def, "west_lever", Vector3(-16.5, 0.0, 3.5))
	OptionalWorlds.plate(def, "east_plate", Vector3i(16, 0, -3), 4)
	OptionalWorlds.door(
		def,
		"west_gate",
		Vector3i(-10, 0, 0),
		Vector3i(1, OptionalWorlds.GATE_HEIGHT, 2),
		PackedStringArray(["west_clock"])
	)
	var final_gate := OptionalWorlds.door(
		def,
		"final_gate",
		Vector3i(-1, 0, -10),
		Vector3i(2, OptionalWorlds.GATE_HEIGHT, 1),
		PackedStringArray(["east_plate", "far_chime", "west_lever"])
	)
	final_gate.require_all = true
	OptionalWorlds.warp(def, "hub_stone", Vector3i(5, 0, -4), "east_stone")
	OptionalWorlds.warp(def, "east_stone", Vector3i(14, 0, -3), "hub_stone")
	OptionalWorlds.creature(def, "elder", Vector3(14.5, 0.0, 0.5), Creature.MODEL_WISH)
	def.spawn_points = OptionalWorlds.spawns(Vector3(0.0, 0.0, 5.5))
	def.checkpoints = [Vector3(-4.5, 0.0, -4.5)]
	OptionalWorlds.nest_and_goal(def, "elder", GRAND_NEST, goal)
	return def
