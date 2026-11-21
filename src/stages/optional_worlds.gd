class_name OptionalWorlds
extends RefCounted
## 寄り道のワールド（O1 からくり工房・O2 さかさ雲・O3 ひみつの温室）のステージの共通部品。
## ステージの中身は OptionalWorldsO1 / O2 / O3。計画（題・ポータル・開き方）は OptionalWorldPlan。
##
## 本人の方針（2026-11-21）: 寄り道のワールドは「ほんとに複雑に組み合わせて難しく」。どのステージも、
## 仕掛けと能力をいくつもつないで考えないと解けない。難しさは考えることから来るようにし、
## 指先の正確さ（ぴったりの踏み切り・速い連打）は求めない。
## 守ること（ADR 0013）: 部屋で区切らない開けた島・地形で関所を作る（システムのルールで止めない）・
## クリアは島の条件＋生きている全員がゴールの窪みに集まる・受け入れた技（縁ちょうどの幅 4・ブロックの
## 上昇＋自分のジャンプ・どの地面のセルも持ち上げ台）は残す・ダッシュは W/A/D が要り床に着くまで 1 回。
##
## 関所の目安（測った値。tests/integration/test_island_probes.gd ほか）:
## - ひとりで上がれる高さ: ジャンプ 1 つで約 4（地面のセルに単発で貸して乗り、戻ってきたジャンプで
##   上昇中に自分でも跳ぶ）。だから、ひとりの関所の壁・扉は高さ 6 にする。2 人でジャンプを集めると約 7.5
## - 跳べる幅: 走って 3（縁ちょうどで 4）。跳んでから空中ダッシュで約 6.5。浮くは同じ高さで約 6、
##   1 m 下りるごとに約 3 m 延びる
## - 島はどれも厚さ 1 の地面（下は底なし）。地面のセルに能力を渡すと動くブロックになり、下が空なので落ちる
## - 扉（スイッチの扉）は能力を渡せない地形の体。谷の上の細い土手に置いた扉は、回り込めない関所になる

const MOVES: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD, RuleAction.Kind.LEFT, RuleAction.Kind.BACK, RuleAction.Kind.RIGHT
]
const CRATE_COLOR := Color(0.78, 0.6, 0.4)
const STONE_COLOR := Color(0.62, 0.6, 0.56)
const SIGN_COLOR := Color(0.72, 0.42, 0.3)
const LIFT_COLOR := Color(0.7, 0.58, 0.86)
const RAFT_COLOR := Color(0.55, 0.78, 0.86)
## 関所の扉の高さ（ひとりのジャンプ 1 つでは越えられない。上の目安）
const GATE_HEIGHT: int = 6


static func base(stage_id: String, display_name: String, minutes: int) -> StageDef:
	var def := StageDef.new()
	def.stage_id = stage_id
	def.display_name = display_name
	def.target_minutes = minutes
	return def


static func loadout(def: StageDef, actions: Array[RuleAction.Kind]) -> void:
	def.set_loadout_for_all(actions)


static func item(
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


static func crate(
	def: StageDef, key: String, cell: Vector3i, color: Color = CRATE_COLOR
) -> StageDef.BlockSpec:
	var block := StageDef.BlockSpec.new(key, cell)
	block.color = color
	def.blocks.append(block)
	return block


## 窪みのブロック（上面がまわりと同じ高さ。跳べなくても乗れる持ち上げ台）。
static func lift(def: StageDef, m: IslandMap, at: Vector2i, key: String) -> StageDef.BlockSpec:
	return crate(def, key, m.pit(at.x, at.y), LIFT_COLOR)


## 願いを持つ生き物（「高いところへ行きたい」。能力を渡すと自分で高い所へ向かう）。
static func creature(def: StageDef, key: String, at: Vector3, look: String) -> StageDef.CreatureSpec:
	var c := StageDef.CreatureSpec.new(key, at)
	c.look = look
	def.creatures.append(c)
	return c


static func plate(
	def: StageDef, key: String, cell: Vector3i, weight: int = 1, size: Vector2i = Vector2i.ONE
) -> MechanismSpecs.PlateSpec:
	var p := MechanismSpecs.PlateSpec.new(key, cell)
	p.required_weight = weight
	p.size = size
	def.mechanisms.plates.append(p)
	return p


static func door(
	def: StageDef, key: String, cell: Vector3i, size: Vector3i, sources: PackedStringArray
) -> MechanismSpecs.DoorSpec:
	var d := MechanismSpecs.DoorSpec.new(key, cell, sources)
	d.size = size
	def.mechanisms.doors.append(d)
	return d


static func lever(def: StageDef, key: String, at: Vector3) -> MechanismSpecs.LeverSpec:
	var l := MechanismSpecs.LeverSpec.new(key, at)
	def.mechanisms.levers.append(l)
	return l


static func warp(def: StageDef, key: String, cell: Vector3i, partner: String = "") -> void:
	def.mechanisms.warps.append(MechanismSpecs.WarpSpec.new(key, cell, partner))


static func timed_bell(
	def: StageDef, key: String, at: Vector3, seconds: float
) -> MechanismSpecs.TimedBellSpec:
	var b := MechanismSpecs.TimedBellSpec.new(key, at, seconds)
	def.mechanisms.timed_bells.append(b)
	return b


## 生き物を巣へ連れていき、生きている全員がゴールに集まる（寄り道のどのステージにも願いを持つ生き物がいる）。
static func nest_and_goal(
	def: StageDef, creature_key: String, nest: AABB, goal: AABB, extra: Array[ClearCondition] = []
) -> void:
	var parts: Array[ClearCondition] = [ClearCondition.carry_object(creature_key, nest)]
	parts.append_array(extra)
	parts.append(ClearCondition.all_at_goal(goal))
	def.clear_condition = ClearCondition.all_of(parts)


static func spawns(center: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for dx: float in [-1.5, -0.5, 0.5, 1.5]:
		result.append(center + Vector3(dx, 0.0, 0.0))
	return result
