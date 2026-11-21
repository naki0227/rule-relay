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
	var stepping := OptionalWorlds.crate(def, "stepping", Vector3i(-8, 0, -12), OptionalWorlds.SIGN_COLOR)
	stepping.tokens.append(StageDef.TokenSpec.new(W, true))
	OptionalWorlds.item(def, FLOAT, Vector3(2.5, 0.0, 6.5))
	OptionalWorlds.creature(def, "lamb", Vector3(0.5, 0.0, -9.5), Creature.MODEL_WISH)
	def.spawn_points = OptionalWorlds.spawns(Vector3(0.0, 0.0, 7.5))
	def.checkpoints = [Vector3(5.5, 0.0, -8.5)]
	OptionalWorlds.nest_and_goal(def, "lamb", CANAL_NEST, goal)
	return def
