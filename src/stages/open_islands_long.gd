class_name OpenIslandsLong
extends RefCounted
## 長い遠征の島（目安 40 分。いまの島でいちばん長い。docs/adr/0011）。
## 部屋や一本道にはしない。ひとつながりの大きな島に、性格の違う地方（西の段丘・東の岬・森の台地・北の峰）を
## 置き、4 つの鐘をどの順で鳴らしてもよい。地方ごとにチェックポイントを置く。
## これまでの島で覚えた仕組みを組み合わせる:
## - 「投げる」は 1 つしかなく、東の岬の発射台と森の台地の生き物で取り合いになる（片方は別の道で解く）
## - 段差 2 の崖が 4 か所あり、どれも窪みのブロック／ブーツ／グローブ／協力のジャンプ×2 で上がれる
## - 北東の物見への持ち上げ台には札（ジャンプ禁止）が付いている
## 配置・目安時間はすべて仮。数値の目安は OpenIslands の冒頭と同じ（Tuning）:
## 自分のジャンプ 1.3（2 段は無理）・ブーツ 2.3・ブロックのジャンプ 2.5・走って跳ぶと幅 4 は縁ちょうどで越える。
## 幅 5 は、跳んでから空中でダッシュする・協力の W×2（速さ 2 倍）で越える。
## 鐘は、触る距離（胸から 4.0）が下の段から届かないよう、段の縁から 5 m 以上離す。

const LOADOUT: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD,
	RuleAction.Kind.LEFT,
	RuleAction.Kind.BACK,
	RuleAction.Kind.RIGHT,
	RuleAction.Kind.JUMP,
	RuleAction.Kind.THROW,
]
const LIFT_COLOR := Color(0.7, 0.58, 0.86)
const SIGN_COLOR := Color(0.72, 0.42, 0.3)


## 遠征（目安 40 分・仮）。南の浜と野原（高さ 0）から、4 つの鐘を鳴らして北の峰（7）の奥の窪みに集まる。
## - 西の段丘（1）と台地（3）: 台地の真ん中に西の鐘。段丘の窪みのブロック／段丘のブーツ／グローブ
## - 東の岬（谷の幅 5）: 岬の西の端に東の鐘。野原の東の岸の発射台に「投げる」を渡して撃つ／
##   浜のダッシュを拾い、跳んでから空中でダッシュして岬へ渡って触る。岬にグローブ
## - 森の台地（3）: 台地の南の縁に、木の実を持った生き物が鐘の方（北）を向いて座っている。野原から
##   「投げる」を投げて渡すと木の実で鐘を鳴らす（「投げる」は発射台と取り合い）／
##   台地の下の岩棚（1）の窪みのブロック・ブーツ・グローブで台地へ上がって触る
## - 北の峰: 森の台地（3）→ 上の段（5）→ 峰（7）。上の段から北東の物見（7）に峰の鐘。
##   物見への窪みのブロックには札（ジャンプ禁止）が付いている（F で取ってどこかへ渡してから使う）
## 協力の近道: 東の谷 5 を W×2 で跳ぶ（ダッシュを拾いに浜へ戻らない）／岩棚から上は、段差 2 をジャンプ×2 で
##   直接（窪みのブロックを探さない・札を動かさない）。
## ゴール: 峰の奥（北）の窪み（高さ 6、5×2）。4 つの鐘を鳴らし、全員がここに集まればクリア。
static func long_expedition() -> StageDef:
	var def := _base("long_expedition", "遠征", 40)
	var m := IslandMap.blank(Vector2i(-36, -56), 64, 70)
	# 浜と野原
	m.fill(-12, -20, 12, 12, 0)
	# 西の段丘（1）と台地（3）
	m.fill(-24, -16, -13, -4, 1)
	m.fill(-34, -14, -25, -6, 3)
	# 東の岬（谷の幅 5）
	m.fill(18, -14, 26, -4, 0)
	# 森の台地（3）と、その下の岩棚（1）
	m.fill(-12, -30, 12, -21, 3)
	m.fill(4, -20, 8, -19, 1)
	# 上の段（5）・峰（7）・北東の物見（7）
	m.fill(-10, -42, 10, -31, 5)
	m.fill(-6, -54, 6, -43, 7)
	m.fill(11, -40, 19, -34, 7)
	var goal := OpenIslands.goal_hollow(m, -2, -53, 2, -52)
	_lift(def, m, Vector2i(-24, -10), "west_lift")
	_lift(def, m, Vector2i(6, -20), "forest_lift")
	_lift(def, m, Vector2i(-3, -30), "ridge_lift")
	_lift(def, m, Vector2i(0, -42), "summit_lift")
	var signed := _lift(def, m, Vector2i(10, -37), "lookout_lift")
	signed.color = SIGN_COLOR
	signed.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.JUMP, true))
	def.terrain_boxes = m.boxes()
	var launcher := StageDef.BlockSpec.new("launcher", Vector3i(12, 0, -10))
	launcher.launcher_direction = Vector3i(1, 0, 0)
	def.blocks.append(launcher)
	def.bells = [
		StageDef.BellSpec.new("west_bell", Vector3(-29.5, 3.0, -9.5)),
		StageDef.BellSpec.new("east_bell", Vector3(18.5, 0.0, -9.5)),
		StageDef.BellSpec.new("forest_bell", Vector3(0.5, 3.0, -25.5)),
		StageDef.BellSpec.new("lookout_bell", Vector3(16.5, 7.0, -36.5)),
	]
	var creature := StageDef.CreatureSpec.new("forest_creature", Vector3(0.5, 3.0, -22.5))
	creature.held_item = "木の実"
	def.creatures.append(creature)
	_item(def, RuleAction.Kind.DASH, Vector3(5.5, 0.0, 10.5))
	_item(
		def, RuleAction.Kind.HIGH_JUMP, Vector3(-20.5, 1.0, -14.5), RuleVessel.Part.FEET, "ジャンプブーツ"
	)
	_item(def, RuleAction.Kind.CLIMB, Vector3(24.5, 0.0, -6.5), RuleVessel.Part.HANDS, "クライミンググローブ")
	def.spawn_points = _spawns(Vector3(0.0, 0.0, 9.5))
	def.checkpoints = [
		Vector3(-16.5, 1.0, -10.5),
		Vector3(9.5, 0.0, -14.5),
		Vector3(9.5, 3.0, -27.5),
		Vector3(-7.5, 5.0, -38.5),
	]
	var parts: Array[ClearCondition] = []
	for bell in def.bells:
		parts.append(ClearCondition.activate(bell.key))
	parts.append(ClearCondition.all_at_goal(goal))
	def.clear_condition = ClearCondition.all_of(parts)
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
