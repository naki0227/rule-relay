class_name OpenIslandsExtra
extends RefCounted
## 開けた島のステージの続き（目安 8〜12 分と 15〜20 分の間を埋める。docs/adr/0011）。
## OpenIslands と同じく、壁で区切った部屋や一本道にしない。ゴールへの道は何通りもあり、協力なら近道がある。
## ほかの島ではまだ主役になっていない仕組みを中心にする:
## - けものの巣: 生き物に移動・ジャンプ・登るを渡して、生き物が自分の願い（高いところへ）で巣まで上がる。
##   生き物を「巣へ連れていく」こと自体が島の条件（これまでの生き物は木の実を投げるだけだった）
## - 札の庭: 全員が最初から「ジャンプ禁止」を持っている（庭の決まり）。禁止を持ったまま行ける道
##   （グローブで登る・発射台）と、禁止を手放して行く道（窪みのブロック・ダッシュ）を選ぶ。
##   発射台と社への持ち上げ台にも札（禁止）が付いている
## 配置・目安時間はすべて仮。数値の目安は OpenIslands の冒頭と同じ（Tuning）:
## 自分のジャンプ 1.3（2 段は無理）・ブーツ 2.3・ブロックのジャンプ 2.5・走って跳ぶと幅 4 は縁ちょうどで越える。
## 生き物は、いまより高く立てるマス（探す範囲 8 マス）への道があれば自分で進む。歩いて上がれるのは
## 0.45 まで、ジャンプがあれば 1 段（1.1 まで）、登るがあればどの段も上がれる（CreatureMind）。
## クリアは「島の条件＋生きている全員がゴールに集まる」。ゴールは縁より 1 段低い窪み（OpenIslands.goal_hollow）。

const LOADOUT: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD,
	RuleAction.Kind.LEFT,
	RuleAction.Kind.BACK,
	RuleAction.Kind.RIGHT,
	RuleAction.Kind.JUMP,
	RuleAction.Kind.THROW,
]
const LIFT_COLOR := Color(0.7, 0.58, 0.86)
const STONE_COLOR := Color(0.62, 0.6, 0.56)
const SIGN_COLOR := Color(0.72, 0.42, 0.3)
## けものの巣: 生き物を連れていく巣（台地の西の小山の上。高さ 5）。
const NEST := AABB(Vector3(-8.0, 4.5, -16.0), Vector3(2.0, 2.0, 2.0))


## けものの巣（目安 10 分・仮）。浜（高さ 0）・段（2）・台地（4）。台地の西の小山（5）が巣。
## 浜の子どもの生き物（何も持たない、能力もない）を巣へ連れていき、全員が台地の奥の窪みに集まる。
## 生き物は命令できない。渡した能力と地形で、自分から高い所へ向かう（移動の能力が1つ要る。A か D を渡せば、
## 自分の W は手元に残る）。
## 生き物の道:
## 1. グローブ: 浜の東に落ちているグローブを装備せずにホットバーへ置き、「登る」と移動を渡す → 崖を登る
## 2. 石と瓦礫の段: 浜の石を西へ押して段の張り出しに寄せる（1 段の足場）。ジャンプと移動を渡すと、
##    石 → 張り出し → 段 → 瓦礫（3）→ 台地 → 巣と 1 段ずつ跳ぶ。ただし自分のジャンプは生き物が持っていく
## 自分の道: 窪みのブロック 2 つ（浜 → 段、段 → 台地）／グローブで登る（ジャンプが無くても登れる）／
##   西の小島（谷 4。空中ダッシュか縁ちょうどの跳び）のブーツ／石と瓦礫の段（ジャンプがあれば）
## 協力の近道: ジャンプ×2 なら、1 個を生き物に渡してもう 1 個で自分も石と瓦礫の段を上がれる
##   （ひとりだとジャンプを渡したらグローブを取りに行く回り道が要る）。ジャンプ×2 で段差 2 を直接跳ぶこともできる。
## ゴール: 台地の北東の窪み（高さ 3、5×2）。巣（台地の西）と主な登り口（浜の窪みのブロック）から離した。
static func creature_nest() -> StageDef:
	var def := _base("creature_nest", "けものの巣", 10)
	var m := IslandMap.blank(Vector2i(-20, -22), 37, 31)
	m.fill(-12, -5, 12, 8, 0)
	m.fill(-12, -10, 12, -6, 2)
	m.fill(-10, -20, 8, -11, 4)
	# 段の西の張り出し（石を寄せる壁）と、段から台地への瓦礫（高さ 3。1 段ずつ）
	m.fill(-12, -5, -11, -2, 2)
	m.fill(-10, -10, -9, -10, 3)
	# 巣の小山（高さ 5）
	m.fill(-8, -16, -7, -15, 5)
	# 西の小島（谷の幅 4）
	m.fill(-19, -1, -17, 3, 0)
	var goal := OpenIslands.goal_hollow(m, 2, -19, 6, -18)
	_lift(def, m, Vector2i(3, -5), "shore_lift")
	_lift(def, m, Vector2i(3, -10), "terrace_lift")
	def.terrain_boxes = m.boxes()
	_stone(def, "step_stone", Vector3i(-6, 0, -3))
	var kit := StageDef.CreatureSpec.new("kit", Vector3(-8.5, 0.0, -1.5))
	kit.look = Creature.MODEL_KIT  # 巣へ運ぶ子ども（小さく、芽がまだつぼみ）
	def.creatures.append(kit)
	_item(def, RuleAction.Kind.CLIMB, Vector3(9.5, 0.0, 4.5), RuleVessel.Part.HANDS, "クライミンググローブ")
	_item(def, RuleAction.Kind.DASH, Vector3(-9.5, 0.0, 6.5))
	_item(def, RuleAction.Kind.HIGH_JUMP, Vector3(-18.5, 0.0, 1.5), RuleVessel.Part.FEET, "ジャンプブーツ")
	def.spawn_points = _spawns(Vector3(0.0, 0.0, 5.5))
	def.checkpoints = [Vector3(-4.5, 0.0, 3.5), Vector3(8.5, 2.0, -8.5)]
	def.clear_condition = (ClearCondition.all_of(
		[ClearCondition.carry_object("kit", NEST), ClearCondition.all_at_goal(goal)]
	))
	return def


## 札の庭（目安 18 分・仮）。庭（高さ 0）・上の庭（2）・社の台（4）。全員が最初から「ジャンプ禁止」を
## 持っている（庭の決まり。ステージの禁止）。東の小島の鐘と社の鐘を鳴らし、全員が社の奥の窪みに集まる。
## 禁止を持ったままの道:
## - 庭の西のグローブ（登るはジャンプではないので禁止に縛られない）で上の庭・社へ登る
## - 東の岸の発射台には「投げる禁止」の札が付いている。F で取ると札が自分に来て「投げる」の届き方が
##   使えなくなるが、触って「投げる」を渡すことはできる → 発射台が鐘を撃つ
## 禁止を手放す道: 手元の禁止をホットバーへ移して、どこか（地面のセルなど）へ渡す。そのあとは
## - 庭のダッシュで、跳んでから空中でダッシュして東の小島（谷 4）へ渡り、触って鐘を鳴らす（小島にブーツ）
## - 庭の窪みのブロックで上の庭へ。社への持ち上げ台には「ジャンプ禁止」の札が付いている。
##   F で取ると札がまた自分に来るので、もう一度どこかへ渡してから乗る
## 協力の近道: 禁止を手放したあと、ジャンプ×2 で段差 2 を直接跳ぶ（窪みのブロックも札付きの台も要らない）。
## 社の鐘は台の真ん中（上の庭の縁から 5.8 m）で、下からは触れない。
## ゴール: 社の奥（北）の窪み（高さ 3、5×2）。禁止を持ったまま降りても、禁止を足もとへ渡せば跳んで出られる。
static func ban_garden() -> StageDef:
	var def := _base("ban_garden", "札の庭", 18)
	def.prohibitions = [RuleAction.Kind.JUMP]
	var m := IslandMap.blank(Vector2i(-20, -26), 43, 36)
	m.fill(-14, -7, 14, 8, 0)
	m.fill(-14, -15, 14, -8, 2)
	m.fill(-6, -24, 6, -16, 4)
	# 東の小島（谷の幅 4）
	m.fill(19, -3, 21, 3, 0)
	var goal := OpenIslands.goal_hollow(m, -2, -23, 2, -22)
	_lift(def, m, Vector2i(-4, -7), "garden_lift")
	var signed := _lift(def, m, Vector2i(3, -15), "shrine_lift")
	signed.color = SIGN_COLOR
	signed.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.JUMP, true))
	def.terrain_boxes = m.boxes()
	var launcher := StageDef.BlockSpec.new("launcher", Vector3i(14, 0, 0))
	launcher.launcher_direction = Vector3i(1, 0, 0)
	launcher.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.THROW, true))
	def.blocks.append(launcher)
	def.bells = [
		StageDef.BellSpec.new("east_bell", Vector3(20.5, 0.0, 0.5)),
		StageDef.BellSpec.new("shrine_bell", Vector3(0.5, 4.0, -20.5)),
	]
	_item(def, RuleAction.Kind.CLIMB, Vector3(-11.5, 0.0, 5.5), RuleVessel.Part.HANDS, "クライミンググローブ")
	_item(def, RuleAction.Kind.DASH, Vector3(10.5, 0.0, 6.5))
	_item(def, RuleAction.Kind.HIGH_JUMP, Vector3(21.5, 0.0, 2.5), RuleVessel.Part.FEET, "ジャンプブーツ")
	def.spawn_points = _spawns(Vector3(0.0, 0.0, 5.5))
	def.checkpoints = [Vector3(-8.5, 0.0, 0.5), Vector3(8.5, 2.0, -11.5)]
	def.clear_condition = (
		ClearCondition
		. all_of(
			[
				ClearCondition.activate("east_bell"),
				ClearCondition.activate("shrine_bell"),
				ClearCondition.all_at_goal(goal),
			]
		)
	)
	return def


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


static func _stone(def: StageDef, key: String, cell: Vector3i) -> void:
	var block := StageDef.BlockSpec.new(key, cell)
	block.color = STONE_COLOR
	def.blocks.append(block)


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


static func _spawns(center: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for dx: float in [-1.5, -0.5, 0.5, 1.5]:
		result.append(center + Vector3(dx, 0.0, 0.0))
	return result
