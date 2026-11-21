class_name OpenIslandsMore
extends RefCounted
## 開けた島のステージの続き（目安 15 分と 25 分の間を埋める。docs/adr/0011）。
## OpenIslands と同じく、壁で区切った部屋や一本道にしない。ゴールへの道は何通りもあり、協力なら手分けできる。
## ほかの島ではまだ主役になっていない仕組みを中心にする:
## - 風の尾根: 鐘の音で動く台（信号）・繰り返し、置かれた禁止を取り除いて押し付ける、地形のセルを押し出す
## - 砦跡: 要石を押して運ぶ（CARRY_OBJECT）、崩れた壁を地形ごと動かす、発射台、鐘との ALL_OF
## 配置・目安時間はすべて仮。数値の目安は OpenIslands の冒頭と同じ（Tuning）:
## 自分のジャンプ 1.3（2 段は無理）・ブーツ 2.3・ブロックのジャンプ 2.5（×2 で 5.0）・走って跳ぶと 3 マスまで。
## 鐘は、触る距離（胸から 3.5 + 0.5）が下の段から届かないよう、段の縁から 4.5 マス以上離す。
## クリアは「島の条件＋生きている全員がゴールに集まる」。ゴールは縁より 1 段低い窪み
## （OpenIslands.goal_hollow。窪みの中からは下の段の仲間を狙えない）。

const LOADOUT: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD,
	RuleAction.Kind.LEFT,
	RuleAction.Kind.BACK,
	RuleAction.Kind.RIGHT,
	RuleAction.Kind.JUMP,
	RuleAction.Kind.THROW,
]
const STONE_COLOR := Color(0.62, 0.6, 0.56)
const RUSTY_COLOR := Color(0.72, 0.42, 0.3)
const WIND_COLOR := Color(0.55, 0.78, 0.86)


## 風の尾根（目安 15 分・仮）。南の浜（高さ 0）から、段（2）・肩（4）を経て頂（6）へ上がる。
## 段差はどれも 2（自分のジャンプでは上がれない）。頂への道（ひとりで。どれを組み合わせてもよい）:
## 1. 札と鐘: 浜の錆びた台には「ジャンプ禁止」の札が付いている。F で取ると札が自分に移り、
##    自分で跳べず単発も起動できなくなる → 台へ繰り返しで渡して上がる。段の風鈴（鐘）を鳴らすと、
##    信号で渡した風の台が鳴っている間だけ跳ねて肩へ。札をどこかへ押し付けてから、肩の台に単発で頂へ
## 2. 崖を崩す: 段の縁の地形のセルに S（後ろ＝南）を渡して押し出すと、1 段ずつの階段になる
## 3. ブーツ: 浜のダッシュを拾い、跳んでから空中でダッシュして西の小島（谷の幅 4）へ。ブーツで各段を跳ぶ
## 4. グローブ: 段の東の端から、幅 1 の谷を跳んだ先の風車の丘にある。肩と頂の崖を登る
## 協力: ジャンプ×2（2.6）なら段差 2 をそのまま跳べる。東の谷筋の「突風の台」は頂の崖（高さ 4）の下にあり、
## ジャンプ×2 を単発で渡す（5.0）と頂へ直接上がれる近道（ひとりのジャンプ 1 個では 2.5 しか上がらない）。
## ゴール: 頂の奥（北）の窪み（高さ 5、5×2）。全員がここに集まればクリア。
static func windy_ridge() -> StageDef:
	var def := _base("windy_ridge", "風の尾根", 15)
	var m := IslandMap.blank(Vector2i(-20, -26), 38, 35)
	m.fill(-12, -6, 12, 8, 0)
	m.fill(-12, -13, 12, -7, 2)
	m.fill(-10, -20, 2, -14, 4)
	m.fill(-6, -26, 2, -21, 6)
	# 東の谷筋（段と同じ高さ 2。頂の東の崖は高さ 4）と、幅 1 の谷の先の風車の丘
	m.fill(3, -26, 12, -14, 2)
	m.fill(14, -12, 17, -8, 2)
	# 西の小島（谷の幅 4）
	m.fill(-20, -4, -17, 2, 0)
	var goal := OpenIslands.goal_hollow(m, -4, -25, 0, -24)
	var rusty := _lift(def, m, Vector2i(6, -6), "rusty_lift", RUSTY_COLOR)
	rusty.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.JUMP, true))
	_lift(def, m, Vector2i(-7, -13), "wind_lift_a", WIND_COLOR)
	_lift(def, m, Vector2i(-4, -13), "wind_lift_b", WIND_COLOR)
	_lift(def, m, Vector2i(-2, -20), "summit_lift")
	_lift(def, m, Vector2i(3, -23), "gust_lift", WIND_COLOR)
	def.terrain_boxes = m.boxes()
	def.bells = [StageDef.BellSpec.new("wind_bell", Vector3(-5.5, 2.0, -10.5))]
	_item(def, RuleAction.Kind.DASH, Vector3(10.5, 0.0, 6.5))
	_item(
		def, RuleAction.Kind.HIGH_JUMP, Vector3(-18.5, 0.0, -0.5), RuleVessel.Part.FEET, "ジャンプブーツ"
	)
	_item(
		def, RuleAction.Kind.CLIMB, Vector3(16.0, 2.0, -10.0), RuleVessel.Part.HANDS, "クライミンググローブ"
	)
	def.spawn_points = _spawns(Vector3(0.0, 0.0, 5.5))
	def.checkpoints = [Vector3(9.5, 2.0, -9.5), Vector3(-8.5, 4.0, -16.5)]
	def.clear_condition = ClearCondition.all_at_goal(goal)
	return def


## 砦跡（目安 25 分・仮）。下の郭（高さ 0）と上の郭（2）、その真ん中の物見櫓（4）からなる崩れた砦。
## 櫓の上の鐘を鳴らし、上の郭の奥に転がる要石を下の郭の「礎の窪み」へはめる（両方でクリア。ALL_OF）。
## 協力なら、鐘と要石を手分けできる。
## 上の郭へ: 下の郭の窪みのブロック／西の崩れた階段に石を押し当てて段にする／縁のセルを押し出す／
##           西の崩れ塔のブーツ／砦の裏（北の地面）のグローブ
## 鐘へ: 櫓の縁の発射台に、東の郭の下から「投げる」を渡す／東の郭の窪みのブロック／ブーツ／グローブ／
##       櫓の縁のセルを押し出す
## 要石を窪みへ: (1) 東へ押して柱で止め、壁の切れ目から南へ押す (2) 西へ押して櫓の壁で止め、櫓の脇から
##   南へ落とし、下の郭で東へ押す (3) 要石の正面の崩れた壁を地形ごと南へ押し出してから、まっすぐ南へ押す
## 協力: 櫓の正面（下の郭）の窪みのブロックにジャンプ×2 を単発で渡す（5.0）と、上の郭を飛ばして櫓へ直接。
## ゴール: 櫓の上の奥（北）の窪み（高さ 3、5×2）。鐘と要石に加えて、全員がここに集まればクリア。
static func ruined_fort() -> StageDef:
	var def := _base("ruined_fort", "砦跡", 25)
	var m := IslandMap.blank(Vector2i(-20, -24), 39, 37)
	m.fill(-18, -22, 18, 12, 0)
	m.fill(-12, -18, 12, -7, 2)
	m.fill(-4, -16, 4, -7, 4)
	# 東の郭の崩れた壁（切れ目は x = 10）と、要石を止める柱
	m.fill(6, -12, 9, -12, 3)
	m.fill(11, -12, 12, -12, 3)
	m.fill(11, -16, 12, -16, 3)
	# 西の郭の崩れた壁（飾り。跳べば越えられる）
	m.fill(-10, -14, -8, -14, 3)
	# 下の郭の南の低い壁（高さ 1。跳べば越えられる）
	m.fill(-12, 6, 12, 6, 1)
	# 西の崩れ塔（1 段ずつ上がれる。上にブーツ）
	m.fill(-15, 2, -15, 2, 1)
	m.fill(-16, 2, -16, 2, 2)
	m.fill(-18, 1, -17, 2, 3)
	# 礎の窪み（3×3。要石が落ちてはまる）
	for x in range(8, 11):
		for z in range(3, 6):
			m.pit(x, z)
	var goal := OpenIslands.goal_hollow(m, -2, -15, 2, -14)
	_lift(def, m, Vector2i(6, -6), "court_lift")
	_lift(def, m, Vector2i(0, -6), "gate_lift")
	_lift(def, m, Vector2i(5, -14), "keep_lift")
	def.terrain_boxes = m.boxes()
	var launcher := StageDef.BlockSpec.new("launcher", Vector3i(4, 4, -12))
	launcher.launcher_direction = Vector3i(-1, 0, 0)
	def.blocks.append(launcher)
	_stone(def, "keystone", Vector3i(8, 2, -16))
	_stone(def, "stair_stone", Vector3i(-17, 0, -12))
	def.bells = [StageDef.BellSpec.new("keep_bell", Vector3(0.5, 4.0, -11.5))]
	_item(def, RuleAction.Kind.HIGH_JUMP, Vector3(-17.5, 3.0, 1.5), RuleVessel.Part.FEET, "ジャンプブーツ")
	_item(def, RuleAction.Kind.CLIMB, Vector3(0.5, 0.0, -20.5), RuleVessel.Part.HANDS, "クライミンググローブ")
	def.spawn_points = _spawns(Vector3(0.0, 0.0, 9.5))
	def.checkpoints = [Vector3(-6.5, 0.0, 0.5), Vector3(-8.5, 2.0, -9.5)]
	def.clear_condition = (
		ClearCondition
		. all_of(
			[
				ClearCondition.activate("keep_bell"),
				ClearCondition.carry_object(
					"keystone", AABB(Vector3(8.0, -1.2, 3.0), Vector3(3.0, 1.0, 3.0))
				),
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
static func _lift(
	def: StageDef, m: IslandMap, at: Vector2i, key: String, color: Color = Color(0.7, 0.58, 0.86)
) -> StageDef.BlockSpec:
	var block := StageDef.BlockSpec.new(key, m.pit(at.x, at.y))
	block.color = color
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
