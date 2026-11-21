class_name OptionalWorldsO3
extends RefCounted
## 寄り道 O3「ひみつの温室」（札・生き物・水・氷が主役）。どのステージも難しい。
## 共通の目安と方針は OptionalWorlds の冒頭。想定の解き方は docs/campaign-plan.md の O3 の表の下。

const W := RuleAction.Kind.FORWARD
const A := RuleAction.Kind.LEFT
const S := RuleAction.Kind.BACK
const D := RuleAction.Kind.RIGHT
const J := RuleAction.Kind.JUMP
const THROW := RuleAction.Kind.THROW
const FLOAT := RuleAction.Kind.FLOAT
const SWIM := RuleAction.Kind.SWIM
const HEAVY := RuleAction.Kind.HEAVY
const ALL_MOVES: Array[RuleAction.Kind] = [W, A, S, D, J]
## O3-1 の氷の池（x 0〜6、z -10〜-4）と、池の中の石の柱（高さ 1）
const ICE_POND := Rect2i(0, -10, 7, 7)
const ICE_ROCKS: Array[Vector2i] = [
	Vector2i(0, -7),
	Vector2i(0, -5),
	Vector2i(1, -4),
	Vector2i(2, -7),
	Vector2i(4, -10),
	Vector2i(4, -4),
	Vector2i(5, -6),
	Vector2i(6, -10),
]
const ICE_NEST := AABB(Vector3(3.0, 3.5, -20.0), Vector3(2.0, 2.0, 2.0))
const CANAL_NEST := AABB(Vector3(3.0, 2.5, -18.0), Vector3(2.0, 2.0, 2.0))
const NURSERY_NEST := AABB(Vector3(3.0, 2.5, -28.0), Vector3(2.0, 2.0, 2.0))
## O3-4 の氷の池（x -2〜2、z -13〜-9）と柱（池の中、高さ 1）
const FROST_POND := Rect2i(-2, -13, 5, 5)
const FROST_ROCKS: Array[Vector2i] = [
	Vector2i(-1, -12),
	Vector2i(-1, -10),
	Vector2i(-1, -9),
	Vector2i(0, -13),
	Vector2i(1, -9),
	Vector2i(2, -10)
]
const FROST_NEST := AABB(Vector3(4.0, 3.5, -25.0), Vector3(2.0, 2.0, 2.0))
## O3-5 の氷の池（x 0〜4、z -20〜-16）と柱
const LANTERN_POND := Rect2i(0, -20, 5, 5)
const LANTERN_ROCKS: Array[Vector2i] = [
	Vector2i(1, -20), Vector2i(2, -19), Vector2i(2, -16), Vector2i(4, -18)
]
const GREENHOUSE_NEST := AABB(Vector3(10.0, 3.5, -11.0), Vector3(2.0, 2.0, 2.0))


## O3-1 氷の温室（目安 25 分・仮）。
## 温室の床（高さ 1）の真ん中に、1 段低い氷の池（7×7）。池の中に石の柱が 8 本。氷の上のブロックは、
## 押すと止まるまですべる（柱・池の縁・ほかのブロックで止まる）。池の北寄りの氷の上に重さの板、その東隣に
## 苗の箱（seed_box）。箱には「A 禁止」（西へ動けない）の札が付いている。
## 板が押されている間、北の谷に架かる土手の扉（高さ 9）が開き、奥の庭（ゴール）へ行ける。
## 手持ちは W・A・S・D・ジャンプ。温室の南西の隅に「投げる」（遠くの物へ渡せる）。
## 生き物（巣へ帰りたい）は土手の手前にいる。巣は奥の庭の段々の上。
## 想定の解き方:
## 1. 箱は板のすぐ東にあるが、西へ押すと板を通りすぎて柱まですべる（止まる物が無い）。しかも札で西へは押せない。
## 2. 札を F で回収する（A 禁止が自分に来る。自分が渡した A の単発も起動できなくなる）。
##    札をどこかへ渡す（生き物は D で歩けるので、生き物に預けてよい）。
## 3. 「投げる」で池の縁から箱へ単発の移動を渡して押す。すべって止まる所を読み、S・A・S・A・W・D・W の 7 回で
##    板の上に止める（柱の並びがこの順だけを許す。最短）。
## 4. 扉が開いたら、生き物に D とジャンプを渡す。生き物は土手を渡って巣の段々を上がる。
## 5. 巣の下で回収し、奥の庭の台の窪み（ゴール）へ。
## 協力: 仲間がいても箱は 1 つ。手分けして「投げる」と押す役に分かれるくらい（解き方は同じ）。
static func ice_greenhouse() -> StageDef:
	var def := OptionalWorlds.base("o3_1", "氷の温室", 25)
	OptionalWorlds.loadout(def, ALL_MOVES)
	var m := IslandMap.blank(Vector2i(-10, -36), 26, 46)
	m.fill(-8, -11, 14, 8, 1)  # 温室の床
	m.fill(ICE_POND.position.x, ICE_POND.position.y, ICE_POND.end.x - 1, ICE_POND.end.y - 1, 0)
	for rock in ICE_ROCKS:
		m.fill(rock.x, rock.y, rock.x, rock.y, 1)
	m.fill(3, -16, 4, -12, 1)  # 北の谷の土手
	m.fill(-8, -34, 14, -17, 1)  # 奥の庭
	m.fill(-8, -34, 14, -29, 3)  # 奥の台
	m.fill(9, -28, 10, -28, 2)
	m.fill(5, -18, 5, -18, 2)  # 巣の段々（2・3・巣 4）
	m.fill(5, -19, 5, -19, 3)
	m.fill(3, -20, 4, -19, 4)
	var goal := OpenIslands.goal_hollow(m, 0, -33, 4, -32)
	def.terrain_boxes = m.boxes()
	OptionalWorlds.freeze(def.terrain_boxes, ICE_POND, 0)
	var seed_box := OptionalWorlds.crate(def, "seed_box", Vector3i(5, 0, -9))
	seed_box.tokens.append(StageDef.TokenSpec.new(A, true))
	OptionalWorlds.plate(def, "pond_plate", Vector3i(4, 0, -9))
	OptionalWorlds.door(
		def,
		"garden_gate",
		Vector3i(3, 1, -14),
		Vector3i(2, OptionalWorlds.GATE_HEIGHT, 1),
		PackedStringArray(["pond_plate"])
	)
	OptionalWorlds.item(def, THROW, Vector3(-5.5, 1.0, 4.5))
	OptionalWorlds.creature(def, "bunny", Vector3(5.5, 1.0, -10.5), Creature.MODEL_WISH)
	def.spawn_points = OptionalWorlds.spawns(Vector3(2.0, 1.0, 5.5))
	def.checkpoints = [Vector3(-4.5, 1.0, -1.5)]
	OptionalWorlds.nest_and_goal(def, "bunny", ICE_NEST, goal)
	return def


## O3-2 水路の花壇（目安 30 分・仮）。
## 南の花壇（出現）と北の花壇（ゴール）の間に、東へ流れる幅 5 の水路（底なし。流れの先は空へ落ちる）。
## 泳ぐは無い。北の花壇の中にも東へ流れる幅 1 の小さな水路（東の端は高さ 2 の石垣）があり、
## 生き物（巣へ帰りたい）は渡れない。
## - 南の花壇の水辺に植木箱（planter）。南の花壇に「浮く」（風船）が 1 つだけ。
## - 北の花壇の小さな水路の手前に、「W 禁止」の札の付いた箱（stepping）。
## 浮くを渡したブロックは水に浮く筏になり、流れで止まっている間 0.9 秒ごとに 1 マス運ばれる（上面は岸とそろう）。
## 筏が流されている最中は、筏の W/A/S/D は動けない（繰り返しで渡すと、流れの拍子とぶつかって進めない）。
## 手持ちは W・A・D・ジャンプ。
## 想定の解き方:
## 1. 植木箱の上に乗り、浮くを渡し、W を単発で渡して押す。箱は北の水に入って筏になる（自分も乗ったまま）。
## 2. 筏が止まっている間に W を単発で渡して押す、をくり返して北へ漕ぐ（流されながら 5 マス）。
##    北の岸に着いたら跳び移り、岸から筏に触って浮くを回収する（筏は沈んで元の場所へ戻る。取りそこねても、
##    筏は流れの先で空へ落ちて元の場所へ戻り、渡していた浮くは手元へ戻る）。
## 3. 北の箱の札を F で回収する（W 禁止が自分に来る。W の単発が使えない）。札を生き物に預ける
##    （生き物は D で歩く）。
## 4. 箱に浮くを渡して北へ押す（W の単発）。筏は東へ流れ、小さな水路の東の端で止まって橋になる。
## 5. 生き物に D とジャンプを渡す。生き物は筏の橋を渡って巣の段々を上がる。回収して、北の台の窪みへ。
## 協力: 浮くは 1 つ。1 人が漕ぎ、もう 1 人は筏に乗って一緒に渡る（筏は 1 マスなので 2 人まで乗れる）。
static func canal_garden() -> StageDef:
	var def := OptionalWorlds.base("o3_2", "水路の花壇", 30)
	OptionalWorlds.loadout(def, [W, A, D, J])
	var m := IslandMap.blank(Vector2i(-14, -30), 26, 42)
	m.fill(-10, 0, 8, 10, 0)  # 南の花壇
	m.fill(-10, -28, 8, -6, 0)  # 北の花壇
	m.fill(-10, -13, 4, -13, -1)  # 北の花壇の小さな水路（下は空）
	m.fill(5, -13, 8, -13, 2)  # 小さな水路の東の端の石垣（筏を止める。生き物は越えられない）
	m.fill(-10, -28, 8, -23, 2)  # 北の台
	m.fill(5, -22, 6, -22, 1)
	m.fill(4, -15, 4, -15, 1)  # 巣の段々（1・2・巣 3）
	m.fill(4, -16, 4, -16, 2)
	m.fill(3, -18, 4, -17, 3)
	var goal := OpenIslands.goal_hollow(m, -2, -27, 2, -26)
	def.terrain_boxes = m.boxes()
	def.nature.add_current(Vector3i(-10, -3, -5), Vector3i(9, -1, -1), Vector3i(1, 0, 0))
	def.nature.add_current(Vector3i(-10, -3, -13), Vector3i(4, -1, -13), Vector3i(1, 0, 0))
	OptionalWorlds.crate(def, "planter", Vector3i(-6, 0, 0))
	var stepping := OptionalWorlds.crate(
		def, "stepping", Vector3i(-8, 0, -12), OptionalWorlds.SIGN_COLOR
	)
	stepping.tokens.append(StageDef.TokenSpec.new(W, true))
	OptionalWorlds.item(def, FLOAT, Vector3(2.5, 0.0, 6.5))
	OptionalWorlds.creature(def, "lamb", Vector3(0.5, 0.0, -9.5), Creature.MODEL_WISH)
	def.spawn_points = OptionalWorlds.spawns(Vector3(0.0, 0.0, 7.5))
	def.checkpoints = [Vector3(5.5, 0.0, -8.5)]
	OptionalWorlds.nest_and_goal(def, "lamb", CANAL_NEST, goal)
	return def


## O3-3 札の苗床（目安 30 分・仮）。
## 南の苗床（出現）→ 土手（扉 1、高さ 9）→ 真ん中の苗床 → 土手（扉 2）→ 北の庭（ゴール）。
## - 扉 1 は、南の苗床の小山の上の重さの板が押されている間だけ開く。南の苗床には箱が無い。
##   小山のそばに、もぐらの生き物（mole。巣は無い）が座っている。
## - 扉 2 は切り替えの扉。土手の途中の板（土手の幅いっぱい）を踏むたびに開く ↔ 閉じる。
## - 真ん中の苗床の子どもの生き物（kit。巣へ帰りたい）には「ジャンプ禁止」の札が付いている。
## 生き物は能力が無いと動かない。渡した能力を回収しても、その場にとどまる。
## 手持ちは W・A・D・ジャンプ。
## 想定の解き方:
## 1. もぐらに A とジャンプを渡す。もぐらは小山（いちばん高い所）の板に上がる → 扉 1 が開く。
##    もぐらから A とジャンプを回収する（もぐらは板の上にとどまり、扉 1 は開いたまま）。
## 2. 子どもの札を F で回収する（ジャンプ禁止が自分に来る）。札をもぐらに渡す（もう動かなくてよい）。
##    先にもぐらへ札を渡すと、もぐらが小山へ跳べなくなる（順番が大事）。
## 3. 子どもに D とジャンプを渡す。子どもは土手の段（板の先、扉の手前）へ向かう途中で板を踏み、扉 2 が開く。
##    扉が開くと、その先の巣の段々へ上がる。
##    自分が先に板を踏んで扉 2 を開けておくと、子どもが踏んだときに閉じてしまう（もう一度踏めば開く）。
## 4. 巣の下で回収して、北の台の窪みへ。
## 協力: 1 人が板 1 に乗れば、もぐらは要らない（最後の人のためにもぐらで押さえる）。札は人数分は無い。
static func sign_nursery() -> StageDef:
	var def := OptionalWorlds.base("o3_3", "札の苗床", 30)
	OptionalWorlds.loadout(def, [W, A, D, J])
	var m := IslandMap.blank(Vector2i(-12, -42), 25, 54)
	m.fill(-8, 0, 8, 10, 0)  # 南の苗床
	m.fill(5, 2, 6, 3, 1)  # 小山（上に板）
	m.fill(-1, -6, 0, -1, 0)  # 土手 1
	m.fill(-8, -20, 8, -7, 0)  # 真ん中の苗床
	m.fill(-1, -26, 0, -21, 0)  # 土手 2
	m.fill(0, -23, 0, -23, 1)  # 土手 2 の板の先の段（東の列。子どもを誘う）
	m.fill(-8, -40, 8, -27, 0)  # 北の庭
	m.fill(-8, -40, 8, -35, 2)  # 北の台
	m.fill(-6, -34, -5, -34, 1)
	m.fill(1, -27, 1, -27, 1)  # 巣の段々（1・2・巣 3）
	m.fill(2, -27, 2, -27, 2)
	m.fill(3, -28, 4, -27, 3)
	var goal := OpenIslands.goal_hollow(m, -2, -39, 2, -38)
	def.terrain_boxes = m.boxes()
	OptionalWorlds.plate(def, "knoll_plate", Vector3i(5, 1, 2), 1, Vector2i(2, 2))
	OptionalWorlds.door(
		def,
		"gate_1",
		Vector3i(-1, 0, -4),
		Vector3i(2, OptionalWorlds.GATE_HEIGHT, 1),
		PackedStringArray(["knoll_plate"])
	)
	OptionalWorlds.plate(def, "path_plate", Vector3i(-1, 0, -22), 1, Vector2i(2, 1))
	var gate_2 := OptionalWorlds.door(
		def,
		"gate_2",
		Vector3i(-1, 0, -24),
		Vector3i(2, OptionalWorlds.GATE_HEIGHT, 1),
		PackedStringArray(["path_plate"])
	)
	gate_2.mode = MechanismSpecs.DoorMode.TOGGLE
	OptionalWorlds.creature(def, "mole", Vector3(3.5, 0.0, 4.5), Creature.MODEL_WISH)
	var kit := OptionalWorlds.creature(def, "kit", Vector3(0.5, 0.0, -18.5), Creature.MODEL_KIT)
	kit.tokens.append(StageDef.TokenSpec.new(J, true))
	def.spawn_points = OptionalWorlds.spawns(Vector3(-2.0, 0.0, 7.5))
	def.checkpoints = [Vector3(-4.5, 0.0, -9.5)]
	OptionalWorlds.nest_and_goal(def, "kit", NURSERY_NEST, goal)
	return def


## O3-4 凍った池（目安 35 分・仮）。
## 南の岸（出現）→ 東へ流れる幅 10 の川（底なし）→ 氷の島（真ん中に 1 段低い 5×5 の氷の池）→ 土手（扉、高さ 9）
## → 北の庭（ゴール）。
## - 南の岸に「泳ぐ」（足ひれ）と「重い」（おもり）。泳いでいても、重いと沈む（ホットバーにある能力だけが効く）。
## - 氷の池の真ん中の下寄りに、霜の箱（frost_box）。「S 禁止」（南へ動けない）の札。そのすぐ北に重さの板（重さ 4）。
##   板が押されている間、北の土手の扉が開く。
## 手持ちは W・A・S・D・ジャンプ。生き物（巣へ帰りたい）は氷の島にいる。巣は北の庭の段々の上。
## 想定の解き方:
## 1. 足ひれをホットバーへ、おもりはかばんに入れたまま川を泳いで渡る（流されながら。対岸で水面から跳び上がる）。
##    おもりをホットバーに置いたまま泳ぐと沈む。
## 2. 霜の箱の札を F で回収する（S 禁止が自分に来る。S の単発が使えない）。札を池の石の柱か生き物に渡す。
## 3. おもりをホットバーへ移して箱に渡す（重さ 4）。
## 4. 箱を北へ押すと、板を通りすぎて柱まですべる。W・D・W・A・S・A の 6 回で板の上に止める（柱の並びが許す最短）。
## 5. 扉が開いたら、生き物に D とジャンプを渡して巣へ。回収して、北の台の窪みへ。
## 協力: 2 人なら、1 人が板に乗っても重さは 1（おもりを持てば 4）。板の上の人は渡れないので、箱とおもりが要る。
static func frozen_pond() -> StageDef:
	var def := OptionalWorlds.base("o3_4", "凍った池", 35)
	OptionalWorlds.loadout(def, ALL_MOVES)
	var m := IslandMap.blank(Vector2i(-16, -34), 32, 49)
	m.fill(-8, 4, 8, 12, 1)  # 南の岸
	m.fill(-8, -17, 8, -7, 1)  # 氷の島
	m.fill(
		FROST_POND.position.x, FROST_POND.position.y, FROST_POND.end.x - 1, FROST_POND.end.y - 1, 0
	)
	for rock in FROST_ROCKS:
		m.fill(rock.x, rock.y, rock.x, rock.y, 1)
	m.fill(-1, -22, 0, -18, 1)  # 北の土手
	m.fill(-8, -33, 8, -23, 1)  # 北の庭
	m.fill(-8, -33, 8, -29, 3)  # 北の台
	m.fill(5, -28, 6, -28, 2)
	m.fill(2, -24, 2, -24, 2)  # 巣の段々（2・3・巣 4）
	m.fill(3, -24, 3, -24, 3)
	m.fill(4, -25, 5, -24, 4)
	var goal := OpenIslands.goal_hollow(m, -2, -32, 2, -31)
	def.terrain_boxes = m.boxes()
	OptionalWorlds.freeze(def.terrain_boxes, FROST_POND, 0)
	def.nature.add_current(Vector3i(-16, -3, -6), Vector3i(15, 0, 3), Vector3i(1, 0, 0))
	var frost := OptionalWorlds.crate(
		def, "frost_box", Vector3i(0, 0, -9), OptionalWorlds.SIGN_COLOR
	)
	frost.tokens.append(StageDef.TokenSpec.new(S, true))
	OptionalWorlds.plate(def, "frost_plate", Vector3i(0, 0, -10), 4)
	OptionalWorlds.door(
		def,
		"garden_gate",
		Vector3i(-1, 1, -20),
		Vector3i(2, OptionalWorlds.GATE_HEIGHT, 1),
		PackedStringArray(["frost_plate"])
	)
	OptionalWorlds.item(def, SWIM, Vector3(-5.5, 1.0, 6.5))
	OptionalWorlds.item(def, HEAVY, Vector3(5.5, 1.0, 6.5))
	OptionalWorlds.creature(def, "bunny", Vector3(4.5, 1.0, -15.5), Creature.MODEL_WISH)
	def.spawn_points = OptionalWorlds.spawns(Vector3(0.0, 1.0, 9.5))
	def.checkpoints = [Vector3(-5.5, 1.0, -9.5)]
	OptionalWorlds.nest_and_goal(def, "bunny", FROST_NEST, goal)
	return def


## O3-5 大温室（目安 45 分・仮）。ひみつの温室の最後。
## 南の岸（出現）→ 東へ流れる幅 10 の川 → 大温室の床（高さ 1）→ 土手（扉、高さ 9）→ 北の庭（ゴール）。
## 大温室の床の東には、南へ流れる幅 1 の水路（両端は高さ 2 の石垣）があり、その東が巣の島（生き物は渡れない）。
## - 南の岸に「泳ぐ」と「重い」。泳いでいても、重いと沈む（ホットバーにある能力だけが効く）。
## - 床の西に重さの板（重さ 4）と鉄の箱（anvil）。板が押されている間、北の扉が開く。
## - 床の真ん中の 1 段低い 5×5 の氷の池に、灯りの箱（lantern。「A 禁止」の札）。池の東の縁に 1 マスの切れ目があり、
##   そこから箱をすべらせると、水路に落ちる。
## - 床の北西に「浮く」。
## 手持ちは W・A・S・D・ジャンプ。生き物（巣へ帰りたい）は床の南東にいる。
## 想定の解き方:
## 1. 泳ぐをホットバー、重いをかばんにして川を渡る（流されながら。対岸で水面から跳び上がる）。
## 2. 鉄の箱に W を繰り返しで渡して北の段まで送り（板の上）、W を回収してから重いを渡す（重さ 4）→ 扉が開く。
## 3. 灯りの箱の札を回収して生き物に預け、浮くを渡す（筏にするため）。
## 4. 池で S・A・W・D・S・D の 6 回押す（柱の並びが許す最短）。最後の D で切れ目から水路へすべり落ちて筏になり、
##    南へ流れて水路の南の端で止まる → 生き物の橋。
## 5. 生き物に D とジャンプを渡す。生き物は筏を渡って巣の段々へ。自分も筏を渡って巣の下で回収し、
##    土手の扉を通って北の台の窪みへ。
## 協力: 1 人が板に乗っても重さは 1。重いを持った仲間が板に乗れば箱は要らないが、その人は扉を通れない。
static func grand_greenhouse() -> StageDef:
	var def := OptionalWorlds.base("o3_5", "大温室", 45)
	OptionalWorlds.loadout(def, ALL_MOVES)
	var m := IslandMap.blank(Vector2i(-16, -44), 32, 57)
	m.fill(-8, 4, 8, 12, 1)  # 南の岸
	m.fill(-8, -24, 5, -7, 1)  # 大温室の床
	m.fill(
		LANTERN_POND.position.x,
		LANTERN_POND.position.y,
		LANTERN_POND.end.x - 1,
		LANTERN_POND.end.y - 1,
		0
	)
	for rock in LANTERN_ROCKS:
		m.fill(rock.x, rock.y, rock.x, rock.y, 1)
	m.fill(5, -19, 5, -19, 0)  # 池の東の縁の切れ目
	m.fill(-4, -13, -4, -13, 2)  # 板の北の段
	m.fill(6, -23, 6, -23, 2)  # 水路の北の石垣
	m.fill(6, -8, 6, -8, 2)  # 水路の南の石垣（筏が止まる）
	m.fill(7, -23, 12, -8, 1)  # 巣の島
	m.fill(8, -10, 8, -10, 2)  # 巣の段々（2・3・巣 4）
	m.fill(9, -10, 9, -10, 3)
	m.fill(10, -11, 11, -10, 4)
	m.fill(-1, -29, 0, -25, 1)  # 北の土手
	m.fill(-8, -42, 8, -30, 1)  # 北の庭
	m.fill(-8, -42, 8, -37, 3)  # 北の台
	m.fill(5, -36, 6, -36, 2)
	var goal := OpenIslands.goal_hollow(m, -2, -41, 2, -40)
	def.terrain_boxes = m.boxes()
	OptionalWorlds.freeze(def.terrain_boxes, LANTERN_POND, 0)
	OptionalWorlds.freeze(def.terrain_boxes, Rect2i(5, -19, 1, 1), 0)
	def.nature.add_current(Vector3i(-16, -3, -6), Vector3i(15, 0, 3), Vector3i(1, 0, 0))
	def.nature.add_current(Vector3i(6, -3, -22), Vector3i(6, 0, -9), Vector3i(0, 0, 1))
	var lantern := OptionalWorlds.crate(
		def, "lantern", Vector3i(4, 0, -17), OptionalWorlds.SIGN_COLOR
	)
	lantern.tokens.append(StageDef.TokenSpec.new(A, true))
	OptionalWorlds.crate(def, "anvil", Vector3i(-4, 1, -9), OptionalWorlds.STONE_COLOR)
	OptionalWorlds.plate(def, "anvil_plate", Vector3i(-4, 1, -12), 4)
	OptionalWorlds.door(
		def,
		"garden_gate",
		Vector3i(-1, 1, -27),
		Vector3i(2, OptionalWorlds.GATE_HEIGHT, 1),
		PackedStringArray(["anvil_plate"])
	)
	OptionalWorlds.item(def, SWIM, Vector3(-5.5, 1.0, 6.5))
	OptionalWorlds.item(def, HEAVY, Vector3(5.5, 1.0, 6.5))
	OptionalWorlds.item(def, FLOAT, Vector3(-5.5, 1.0, -20.5))
	OptionalWorlds.creature(def, "elder", Vector3(3.5, 1.0, -10.5), Creature.MODEL_WISH)
	def.spawn_points = OptionalWorlds.spawns(Vector3(0.0, 1.0, 9.5))
	def.checkpoints = [Vector3(-6.5, 1.0, -9.5)]
	OptionalWorlds.nest_and_goal(def, "elder", GREENHOUSE_NEST, goal)
	return def
