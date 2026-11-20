class_name OpenIslands
extends RefCounted
## ひとつながりの開けた島のステージ（Human: Fall Flat のように、壁で区切らず、ゴールへの道が何通りもある）。
## 2026-11-20 本人: 「部屋で区切る作りは嫌。参考にしたいのは長さだけ。オープンワールドみたいな感じがいい」。
## 配置・目安時間はすべて仮（docs/adr/0011）。数値の目安（Tuning）:
## - 自分のジャンプ 1.3（1 段は上がれる、2 段は無理）、ジャンプブーツ 2.3（2 段まで）
## - ブロックのジャンプ 2.5（窪みのブロックに乗れば 2 段上へ）、ジャンプ×2 なら 2 倍
## - 走って跳べば 3 マスの谷まで越えられる。4 マスの谷は、跳んでから空中でダッシュする・ブーツ・
##   協力で W×2（速さ 2 倍）などで越える
## - クライミンググローブなら、どの崖も登れる
## - 生き物はプレイヤーとぶつからない（足場にはならない）。持っている木の実は、「投げる」を
##   1匹に渡すと、待っているときに向いている方へ投げる（届くのは同じ高さの約 4 マス先まで）
## 協力の近道（ジャンプ×2 = 2.6 で 2 段の崖を直接、W×2 = 速さ 2 倍で幅 5〜6 の谷や遠い段へ）は、
## ひとりでも島の装備（ブーツ・グローブ・ダッシュ）を取りに行けば通れることがある。協力なら
## 取りに行く回り道を省ける、という意味の近道にしている（tests/integration/test_open_islands_coop.gd）。
## クリアはどの島も「島の条件＋生きている全員がゴールに集まる」（2026-11-20 本人の判断。docs/adr/0011 決定 9）。
## ゴールは縁より 1 段低い窪み（goal_hollow）にして、窪みの中からは下の段の仲間を狙えない地形にする。
## 「ゴールから能力を渡せない」というルールは足さない（本人: 妨害をシステムで止めると自由な発想を妨げる）。

const LOADOUT: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD,
	RuleAction.Kind.LEFT,
	RuleAction.Kind.BACK,
	RuleAction.Kind.RIGHT,
	RuleAction.Kind.JUMP,
	RuleAction.Kind.THROW,
]


## 丘の上の旗（目安 8 分・仮）。南の浜から、真ん中の丘の頂上（高さ 4）へ上がる。
## 頂上への道（どれでもよい）:
## 1. 段丘（高さ 2）の窪みのブロックにジャンプを貸し、乗って上がる
## 2. 東の見張り台（高さ 3）の上のジャンプブーツで、段丘から跳ぶ
## 3. 西の谷（幅 4）の向こうの小島のクライミンググローブで、崖を登る（谷は空中ダッシュかブーツで越える）
## 4. 協力ならジャンプを集めて跳ぶ（×2 で 2.6）
## 協力の近道: 東の見張り台（高さ 3）から、幅 4 の空中を越えて頂上へ跳び移る（W×2。空中ダッシュでも届く）。
## 落ちても下の段丘に着くだけなので、何度でも試せる。
## ゴール: 頂上の奥（北）の窪み（高さ 3、3×2）。全員がここに集まればクリア。窪みの縁（高さ 4）が、
## 下の段丘への光線を遮るので、下の仲間へ能力を渡すには頂上の縁まで出る。
static func hill_top() -> StageDef:
	var def := _base("hill_top", "丘の上の旗", 8)
	var m := IslandMap.blank(Vector2i(-16, -10), 27, 19)
	m.fill(-9, -9, 9, 7, 0)
	m.fill(-6, -8, 6, 2, 1)
	m.fill(-4, -8, 4, -1, 2)
	m.fill(-2, -8, 2, -4, 4)
	# 東の見張り台と、そこへ上がる階段（1 段ずつ）
	m.fill(8, 1, 8, 2, 1)
	m.fill(8, -2, 8, 0, 2)
	m.fill(7, -6, 8, -3, 3)
	# 西の小島（谷の幅 4）
	m.fill(-16, -6, -14, -3, 0)
	var goal := goal_hollow(m, -1, -7, 1, -6)
	_lift(def, m, Vector2i(0, -3), "lift")
	def.terrain_boxes = m.boxes()
	_item(def, RuleAction.Kind.HIGH_JUMP, Vector3(7.5, 3.0, -5.5), RuleVessel.Part.FEET, "ジャンプブーツ")
	_item(
		def, RuleAction.Kind.CLIMB, Vector3(-14.5, 0.0, -4.5), RuleVessel.Part.HANDS, "クライミンググローブ"
	)
	_item(def, RuleAction.Kind.DASH, Vector3(3.5, 0.0, 5.5))
	def.spawn_points = _spawns(Vector3(0.0, 0.0, 5.5))
	def.checkpoints = [Vector3(-3.5, 2.0, -1.5)]
	def.clear_condition = ClearCondition.all_at_goal(goal)
	return def


## 採石場（目安 12 分・仮）。すり鉢の底（高さ 0）から、縁（高さ 5）のどこかへ上がる。
## 底 → 段（高さ 2）: 底のブロックを横へ動かして段の壁に寄せ、足場にする／ブロックに乗ってジャンプを貸す／
##                   ブーツ（底の隅）
## 段 → 縁: 北の出っ張り（高さ 3）の窪みのブロックにジャンプを貸す／ブーツで出っ張りから跳ぶ／
##          東の段のグローブで登る／南のズリ山（高さ 3）の窪みのブロックを使う。ただし、
##          このブロックにはジャンプ禁止が付いている。F で回収すると禁止が手元に来て自分も跳べなくなるので、
##          ホットバーへ移して別の物（石など）に渡してから、ジャンプを貸して乗る
## 協力の近道: 底から段へジャンプ×2 で直接上がり（石を動かさない）、ズリ山から縁へもジャンプ×2 で上がる
## ゴール: 北の縁の外側に張り出した見晴らし（高さ 5）の窪み（高さ 4、7×3）。縁のどこへ出ても、
## 縁づたいに歩いて集まる。窪みの縁が、すり鉢の中（段・底）への光線を遮る。
static func quarry() -> StageDef:
	var def := _base("quarry", "採石場", 12)
	var m := IslandMap.blank(Vector2i(-11, -14), 23, 26)
	m.fill(-11, -11, 11, 11, 5)
	m.fill(-4, -14, 4, -12, 5)
	m.fill(-8, -8, 8, 8, 2)
	m.fill(-5, -5, 5, 5, 0)
	m.fill(-2, -8, 2, -7, 3)
	# 南のズリ山（高さ 3。縁のすぐ手前）。東のマスは禁止付きの持ち上げ台
	m.fill(0, 8, 1, 8, 3)
	var goal := goal_hollow(m, -3, -13, 3, -11)
	_lift(def, m, Vector2i(0, -7), "ledge_lift")
	_lift(def, m, Vector2i(1, 8), "banned_lift")
	def.blocks[-1].tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.JUMP, true))
	def.terrain_boxes = m.boxes()
	for spec: Array in [["stone_a", Vector3i(-2, 0, 1)], ["stone_b", Vector3i(2, 0, -2)]]:
		var block := StageDef.BlockSpec.new(String(spec[0]), spec[1] as Vector3i)
		block.color = Color(0.82, 0.72, 0.55)
		def.blocks.append(block)
	_item(def, RuleAction.Kind.HIGH_JUMP, Vector3(-4.5, 0.0, 4.5), RuleVessel.Part.FEET, "ジャンプブーツ")
	_item(def, RuleAction.Kind.CLIMB, Vector3(7.0, 2.0, 0.5), RuleVessel.Part.HANDS, "クライミンググローブ")
	def.spawn_points = _spawns(Vector3(0.0, 0.0, 3.5))
	def.checkpoints = [Vector3(-6.5, 2.0, 6.5)]
	def.clear_condition = ClearCondition.all_at_goal(goal)
	return def


## 三つの鐘の島（目安 20 分・仮）。広い島の西の丘・北の崖・東の小島の鐘を全部鳴らす。協力なら手分けできる。
## 西の丘（台地 高さ 3）: 裾（高さ 1）の窪みのブロック／ブーツ
## 北の崖（台地 高さ 5）: 東側の階段で段（高さ 3）へ → 段の窪みのブロック／グローブ
## 東の小島（谷の幅 4）: 岸の発射台に「投げる」を渡して鐘を撃つ／空中ダッシュ・ブーツで渡って F で鳴らす
## 北の崖のもう1つの道: 台地の南の縁に、木の実を持った生き物が鐘の方（北）を向いて座っている。
##   下の原っぱから「投げる」を投げて渡すと、木の実を投げて鐘を鳴らす（1回きり。投げるは発射台と取り合い）
## 鐘は台地の真ん中（下からは手が届かない広さにしてある）。
## 協力の近道: 北の崖の下の落石（高さ 2）へジャンプ×2 で上がり、段 → 台地もジャンプ×2（階段の回り道を省く）
## ゴール: 北の崖の台地の奥の窪み（高さ 4、5×2）。3つの鐘を鳴らし、全員がここに集まればクリア。
static func three_bells() -> StageDef:
	var def := _base("three_bells", "三つの鐘の島", 20)
	var m := IslandMap.blank(Vector2i(-24, -26), 45, 40)
	m.fill(-14, -14, 12, 12, 0)
	# 西の丘
	m.fill(-22, -6, -14, 4, 1)
	m.fill(-24, -5, -16, 3, 3)
	# 北の崖と、東側の階段
	m.fill(-6, -24, 4, -15, 3)
	m.fill(-5, -26, 3, -18, 5)
	m.fill(5, -16, 6, -15, 1)
	m.fill(5, -18, 6, -17, 2)
	# 北の崖の下の落石（高さ 2。段のすぐ手前）
	m.fill(-3, -14, -2, -14, 2)
	# 東の小島（谷の幅 4）
	m.fill(17, -4, 20, 3, 0)
	var goal := goal_hollow(m, -3, -25, 1, -24)
	_lift(def, m, Vector2i(-15, -1), "west_lift")
	_lift(def, m, Vector2i(-1, -17), "north_lift")
	def.terrain_boxes = m.boxes()
	var launcher := StageDef.BlockSpec.new("launcher", Vector3i(11, 0, 0))
	launcher.launcher_direction = Vector3i(1, 0, 0)
	def.blocks.append(launcher)
	def.bells = [
		StageDef.BellSpec.new("west_bell", Vector3(-19.5, 3.0, -0.5)),
		StageDef.BellSpec.new("north_bell", Vector3(-0.5, 5.0, -22.5)),
		StageDef.BellSpec.new("east_bell", Vector3(17.5, 0.0, 0.5)),
	]
	_nut_creature(def, "cliff_creature", Vector3(-0.5, 5.0, -19.5))
	_item(def, RuleAction.Kind.HIGH_JUMP, Vector3(-10.5, 0.0, 9.5), RuleVessel.Part.FEET, "ジャンプブーツ")
	_item(def, RuleAction.Kind.CLIMB, Vector3(8.5, 0.0, 9.5), RuleVessel.Part.HANDS, "クライミンググローブ")
	_item(def, RuleAction.Kind.DASH, Vector3(2.5, 0.0, 4.5))
	def.spawn_points = _spawns(Vector3(0.0, 0.0, 6.5))
	def.checkpoints = [Vector3(-12.5, 0.0, 2.5), Vector3(3.5, 0.0, -12.5), Vector3(9.5, 0.0, 3.5)]
	def.clear_condition = _bells_and_goal(def, goal)
	return def


## 浮島めぐり（目安 30 分・仮）。真ん中の島から、谷で隔てた浮島をめぐって3つの鐘を鳴らす。
## 南の浮島（谷 2・跳べば渡れる）にダッシュとブーツ。西の浮島（谷 4）は空中ダッシュかブーツ、
## 北の浮島は高い（高さ 2）ので、真ん中の島の塔（高さ 2）へ窪みのブロックで上がってから谷 3 を跳ぶ、
## 東の浮島（谷 5）は発射台で鐘を撃つか、空中ダッシュ・協力で W×2（速さ 2 倍）で跳ぶ。
## 西の浮島のもう1つの道: 南の端に、木の実を持った生き物が鐘の方（北）を向いて座っている。
##   真ん中の島の西の岸から「投げる」を投げて渡すと、木の実を投げて鐘を鳴らす（谷を渡らずに済む）
## 協力の近道: 真ん中の島の北の岸から、ジャンプ×2 で谷 3 と 2 段を一度に越えて北の浮島へ（塔を使わない）
## ゴール: 北の浮島の奥の窪み（高さ 1、5×2）。3つの鐘を鳴らし、全員がここに集まればクリア。
static func floating_isles() -> StageDef:
	var def := _base("floating_isles", "浮島めぐり", 30)
	var m := IslandMap.blank(Vector2i(-24, -24), 49, 47)
	m.fill(-6, -6, 6, 6, 0)
	# 真ん中の塔（高さ 2）と、北の浮島（高さ 2。谷 3）
	m.fill(-2, -6, 2, -4, 2)
	m.fill(-4, -18, 4, -10, 2)
	# 南の浮島（谷 2）
	m.fill(-4, 9, 4, 17, 0)
	# 西の浮島（谷 4）
	m.fill(-19, -4, -11, 4, 0)
	# 東の浮島（谷 5）
	m.fill(12, -3, 18, 3, 0)
	var goal := goal_hollow(m, -2, -17, 2, -16)
	_lift(def, m, Vector2i(0, -3), "tower_lift")
	def.terrain_boxes = m.boxes()
	var launcher := StageDef.BlockSpec.new("launcher", Vector3i(6, 0, 0))
	launcher.launcher_direction = Vector3i(1, 0, 0)
	def.blocks.append(launcher)
	def.bells = [
		StageDef.BellSpec.new("north_bell", Vector3(0.5, 2.0, -14.5)),
		StageDef.BellSpec.new("west_bell", Vector3(-15.5, 0.0, 0.5)),
		StageDef.BellSpec.new("east_bell", Vector3(12.5, 0.0, 0.5)),
	]
	_nut_creature(def, "isle_creature", Vector3(-15.5, 0.0, 4.5))
	_item(def, RuleAction.Kind.DASH, Vector3(-2.5, 0.0, 14.5))
	_item(def, RuleAction.Kind.HIGH_JUMP, Vector3(2.5, 0.0, 14.5), RuleVessel.Part.FEET, "ジャンプブーツ")
	_item(def, RuleAction.Kind.CLIMB, Vector3(-15.5, 0.0, 3.5), RuleVessel.Part.HANDS, "クライミンググローブ")
	def.spawn_points = _spawns(Vector3(0.0, 0.0, 3.5))
	def.checkpoints = [Vector3(-4.5, 0.0, 4.5), Vector3(0.5, 0.0, 12.5), Vector3(-14.5, 0.0, -2.5)]
	def.clear_condition = _bells_and_goal(def, goal)
	return def


## ゴールの窪み（docs/adr/0011 決定 10）。(x0, z0)〜(x1, z1) を、まわりより 1 段下げる。
## 窪みの中に立つ人の胸（足もと + 1.0）がまわりの縁の上面と同じ高さになるので、縁より低い所にいる
## 仲間への光線は地形が遮る（窪みの中からは、下の仲間を狙って能力を渡せない）。渡すなら縁まで出るか、
## 段を降りる。ルールで禁止するのではなく、地形だけで難しくする。入るのは歩いて降りるだけ、
## 出るのは自分のジャンプ（1.3）で上がれる深さ。まわりに 1 マス以上の縁が残るように置く。
## 返り値はゴールの箱（ClearCondition.all_at_goal に渡す。床の少し下から高さ 3）。
static func goal_hollow(m: IslandMap, x0: int, z0: int, x1: int, z1: int) -> AABB:
	var floor_y := m.height(x0, z0) - 1
	m.fill(x0, z0, x1, z1, floor_y)
	return AABB(Vector3(x0, floor_y - 0.1, z0), Vector3(x1 - x0 + 1, 3.0, z1 - z0 + 1))


## 鐘を全部鳴らし、生きている全員がゴールに集まる。
static func _bells_and_goal(def: StageDef, goal: AABB) -> ClearCondition:
	var parts: Array[ClearCondition] = []
	for bell in def.bells:
		parts.append(ClearCondition.activate(bell.key))
	parts.append(ClearCondition.all_at_goal(goal))
	return ClearCondition.all_of(parts)


static func _base(stage_id: String, display_name: String, minutes: int) -> StageDef:
	var def := StageDef.new()
	def.stage_id = stage_id
	def.display_name = display_name
	def.target_minutes = minutes
	def.set_loadout_for_all(LOADOUT)
	return def


## 窪みのブロック（上面がまわりと同じ高さ。跳べなくても乗れる持ち上げ台）。
static func _lift(def: StageDef, m: IslandMap, at: Vector2i, key: String) -> void:
	var block := StageDef.BlockSpec.new(key, m.pit(at.x, at.y))
	block.color = Color(0.7, 0.58, 0.86)
	def.blocks.append(block)


## 木の実を持った、能力のない生き物（歩けないので、置いた場所で北を向いて待つ）。
## 移動・ジャンプの能力を持たせないのは、F で回収したときに W×2・ジャンプ×2 がひとりで揃って、
## 段差と谷の関門が崩れるのを防ぐため。
static func _nut_creature(def: StageDef, key: String, at: Vector3) -> void:
	var creature := StageDef.CreatureSpec.new(key, at)
	creature.held_item = "木の実"
	def.creatures.append(creature)


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
