class_name OpenIslandsW1
extends RefCounted
## はじまりの草原（W1）の新しいステージ（docs/campaign-plan.md・docs/adr/0013）。開けた島で、壁で区切らない。
## どちらのステージにも願いを持つ動物がいて、その願い（高いところの巣へ行きたい）を叶えることがクリアの条件の
## 一部になる。動物は命令できず、渡した能力と地形で自分から高い所へ向かう（CreatureMind。1 段ずつしか
## 跳べず、谷は越えられず、持ち上げ台にも乗らない）。だから動物の道は、プレイヤーの移動の技（縁ちょうどの
## 幅 4・ブロックの上昇＋自分のジャンプ・地面のセルの持ち上げ台。どれも受け入れた技）で崩れない関門になる。
## 数値の目安（Tuning）: 自分のジャンプ 1.3（2 段は無理）・ブロックのジャンプ 2.5・走って跳ぶと幅 4 は縁ちょうど。
## 上昇中のブロックの上で自分も跳ぶ技（受け入れた技）は、足もとのセルから 7 m 上がり、同じ高さへ 8.4 m 飛ぶ。
## クリアは「島の条件＋生きている全員がゴールの窪み（OpenIslands.goal_hollow）に集まる」。
## 配置・目安時間はすべて仮（本人の試遊で直す）。

const MOVES: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD, RuleAction.Kind.LEFT, RuleAction.Kind.BACK, RuleAction.Kind.RIGHT
]
const MOVES_AND_JUMP: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD,
	RuleAction.Kind.LEFT,
	RuleAction.Kind.BACK,
	RuleAction.Kind.RIGHT,
	RuleAction.Kind.JUMP,
]
const LIFT_COLOR := Color(0.7, 0.58, 0.86)
const STONE_COLOR := Color(0.62, 0.6, 0.56)
## 持ち上げ台の段々: 動物（願いを持つ生き物）の巣（頂の西の小山の上。高さ 5）。
const STEPS_NEST := AABB(Vector3(-5.0, 4.5, -14.0), Vector3(2.0, 2.0, 2.0))
## 押し石の小道: 子どもの生き物の巣（花畑の奥の真ん中の小山の上。高さ 4）。生き物が探すのは 8 マス先までなので、
## 溝をどこで埋めても花畑から見える真ん中に置いた。
const PATH_NEST := AABB(Vector3(-1.0, 3.5, -14.0), Vector3(2.0, 2.0, 2.0))


## 持ち上げ台の段々（1-3。★難しい。目安 14 分・仮）。浜（高さ 0）・段（2）・頂（4）。頂の西の小山（5）が巣。
## 新しいこと（docs/w1-teaching.md）: まず「ブロックの W/A/S/D」（浜から石 1 を単発の S で押す。繰り返しだと
## 止まらず島の外まで滑る）、次に「動物」（移動とジャンプをあげると巣へ向かう）。1-1 の「ブロックにジャンプを貸す」と
## 1-2 の「F で取る・仲間へ回す」は、ここではもう知っていることとして使う。だれも最初はジャンプを持っていない（W/A/S/D だけ）。
## - 浜の動物がジャンプを 1 つ持っている（移動が無いので待っている）。F で回収すると自分のジャンプになる
## - 頂の東の隅に、もう 1 つのジャンプが落ちている
## - 動物は 1 段ずつしか跳べない。浜 → 段も段 → 頂も 2 段なので、石の段が 2 つ要る。石は段の上（石 1）と
##   頂の上（石 2）に置いてあり、縁から押し落とすと、ちょうど下の段の壁ぎわに落ちて 1 段の足場になる
##   （繰り返しで押すと止まらず、下の段も越えて島の外まで滑っていく。単発で 1 マスずつ押す）
## 解き方の例（ひとり）: 動物のジャンプを借りる → 窪みのブロック（どの地面のセルでもよい）で段・頂へ →
##   落ちているジャンプを拾う → 石 2・石 1 を縁から押し落とす → 浜へ降りて、動物にジャンプ 1 つと移動を渡す
##   → 動物が石の段で巣まで上がる → 残りのジャンプで頂へ戻り、窪みへ。
## 先にジャンプを全部動物に渡すと、自分は浜から上がれない（動物が段の縁にいる間は F で取り戻せる。
## 巣まで行ってしまったら、メニューの「このステージを最初から」でやり直す。test_finding_steps_* に記録）。
## 協力（2 人以上）: 能力の合計は人数によらない（ジャンプ 2 つ）。1 つを動物に渡し、残り 1 つを段の縁から
## 下の仲間へ順に渡して全員が上がる（受け渡し）。繰り返しで渡した持ち上げ台を全員で使ってもよい。
## ゴール: 頂の東の窪み（高さ 3、4×2）。巣（頂の西）と動物の道（西の列）から離した。
static func lift_steps() -> StageDef:
	var def := _base("w1_lift_steps", "持ち上げ台の段々", 14, MOVES)
	var m := IslandMap.blank(Vector2i(-10, -18), 21, 28)
	m.fill(-8, 0, 8, 8, 0)
	m.fill(-8, -7, 8, -1, 2)
	m.fill(-6, -16, 6, -8, 4)
	# 巣の小山（高さ 5）
	m.fill(-5, -14, -4, -13, 5)
	var goal := OpenIslands.goal_hollow(m, 1, -15, 4, -14)
	_lift(def, m, Vector2i(4, 0), "shore_lift")
	_lift(def, m, Vector2i(4, -7), "terrace_lift")
	def.terrain_boxes = m.boxes()
	_stone(def, "stone_low", Vector3i(-4, 2, -3))
	_stone(def, "stone_high", Vector3i(-4, 4, -10))
	var critter := StageDef.CreatureSpec.new("critter", Vector3(-3.5, 0.0, 4.5))
	critter.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.JUMP))
	def.creatures.append(critter)
	_item(def, RuleAction.Kind.JUMP, Vector3(4.5, 4.0, -11.5))
	def.spawn_points = _spawns(Vector3(0.0, 0.0, 6.5))
	def.checkpoints = [Vector3(6.5, 0.0, 5.5), Vector3(6.5, 2.0, -4.5)]
	# 教える場所: 段の上の石 1 の真下で「石に S を渡して押す」（docs/w1-teaching.md）
	def.hint_spots = [
		StageDef.HintSpot.new("push", Vector3(-3.5, 0.0, 0.8), 2.4, "左クリック", "石にSを渡す"),
	]
	def.clear_condition = ClearCondition.all_of(
		[ClearCondition.carry_object("critter", STEPS_NEST), ClearCondition.all_at_goal(goal)]
	)
	return def


## 押し石の小道（1-4。目安 7 分・仮）。原っぱ（高さ 0）・段（2）・溝（1）・花畑（3）。花畑の奥の小山（4）が巣。
## 新しい仕掛け: 地形のセルに W/A/S/D を渡して押し、道を作る。
## 子どもの生き物はジャンプを 1 つ持っている（移動が無いので待っている）。移動を 1 つ渡せば巣へ向かうが、
## 1 段ずつしか跳べず、谷（溝の向こうの 2 段）も越えられない。生き物の道は地形を押して作る:
## 1. 段の縁のセル（上面のセル）に S（後ろ＝南）を単発で渡して押すと、原っぱへ落ちて 1 段の足場になり、
##    削れた縁と合わせて 0 → 1 → 1 → 2 の階段になる（風の尾根と同じ形）
## 2. 段と花畑の間の溝（幅 1。段より 1 低く、花畑より 2 低い）に、段の北の縁のセルを W で押し込むか、
##    花畑の南の縁のセルを S で押し込むと、溝が埋まって 2 → 2 → 3 の道になる
## 自分の道: ふつうのジャンプでは段（2）に上がれない。削った階段を跳んで上がる／窪みのブロック／
##   地面のセルの持ち上げ台。ゴールは段の上なので、溝と花畑は生き物のための場所。
## 協力: 2 人なら「押す人」と「生き物に移動を渡す人」に分かれる（能力の合計は人数によらない）。
## ゴール: 段の東の窪み（高さ 1、5×2）。原っぱからの登り口との間に、縁が 3 マス残る。
static func push_path() -> StageDef:
	# 投げるは 1-5 で教えるので、ここではまだ持たせない（docs/w1-teaching.md）
	var def := _base("w1_push_path", "押し石の小道", 7, MOVES_AND_JUMP)
	var m := IslandMap.blank(Vector2i(-9, -17), 19, 26)
	m.fill(-7, 0, 7, 7, 0)
	m.fill(-7, -6, 7, -1, 2)
	m.fill(-7, -7, 7, -7, 1)
	m.fill(-7, -15, 7, -8, 3)
	# 巣の小山（高さ 4）
	m.fill(-1, -14, 0, -13, 4)
	var goal := OpenIslands.goal_hollow(m, 2, -5, 6, -4)
	_lift(def, m, Vector2i(-5, 0), "meadow_lift")
	def.terrain_boxes = m.boxes()
	var kit := StageDef.CreatureSpec.new("kit", Vector3(-2.5, 0.0, 3.5))
	kit.look = Creature.MODEL_KIT
	kit.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.JUMP))
	def.creatures.append(kit)
	def.spawn_points = _spawns(Vector3(1.0, 0.0, 5.5))
	def.checkpoints = [Vector3(5.5, 0.0, 5.5), Vector3(-5.5, 2.0, -3.5)]
	# 教える場所: 段のふちの下で「地面にも渡せる」、溝のそばで「まとめて渡す」（どちらも慣れたら出ない）
	def.hint_spots = [
		StageDef.HintSpot.new("ground", Vector3(-2.5, 0.0, 1.2), 3.0, "左クリック", "地面にも渡せる"),
		StageDef.HintSpot.new("range", Vector3(0.5, 2.0, -5.0), 2.5, "右クリック", "まとめて渡す"),
	]
	def.clear_condition = ClearCondition.all_of(
		[ClearCondition.carry_object("kit", PATH_NEST), ClearCondition.all_at_goal(goal)]
	)
	return def


static func _base(
	stage_id: String, display_name: String, minutes: int, loadout: Array[RuleAction.Kind]
) -> StageDef:
	var def := StageDef.new()
	def.stage_id = stage_id
	def.display_name = display_name
	def.target_minutes = minutes
	def.set_loadout_for_all(loadout)
	return def


## 窪みのブロック（上面がまわりと同じ高さ。跳べなくても乗れる持ち上げ台）。
static func _lift(def: StageDef, m: IslandMap, at: Vector2i, key: String) -> void:
	var block := StageDef.BlockSpec.new(key, m.pit(at.x, at.y))
	block.color = LIFT_COLOR
	def.blocks.append(block)


static func _stone(def: StageDef, key: String, cell: Vector3i) -> void:
	var block := StageDef.BlockSpec.new(key, cell)
	block.color = STONE_COLOR
	def.blocks.append(block)


static func _item(def: StageDef, action: RuleAction.Kind, at: Vector3) -> void:
	def.world_items.append(StageDef.PlacementSpec.in_world(action, at))


static func _spawns(center: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for dx: float in [-1.5, -0.5, 0.5, 1.5]:
		result.append(center + Vector3(dx, 0.0, 0.0))
	return result
