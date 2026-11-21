class_name StageParts
extends RefCounted
## ワールド 5・6 のステージ（World5Stages・World6Stages）が共有する組み立ての部品（純粋なデータだけ）。
## OpenIslands などの各ファイルが持っている小さな部品と同じ形を、1 か所にまとめた
## （並行で作る他のワールドのファイルには触らないため、新しいクラスにした）。

const LIFT_COLOR := Color(0.7, 0.58, 0.86)
const STONE_COLOR := Color(0.62, 0.6, 0.56)
const SIGN_COLOR := Color(0.72, 0.42, 0.3)
const RAFT_COLOR := Color(0.78, 0.62, 0.42)
## W5・W6 の基本の手持ち（W/A/S/D・ジャンプ・投げる）。
const LOADOUT: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD,
	RuleAction.Kind.LEFT,
	RuleAction.Kind.BACK,
	RuleAction.Kind.RIGHT,
	RuleAction.Kind.JUMP,
	RuleAction.Kind.THROW,
]


static func base(stage_id: String, display_name: String, minutes: int) -> StageDef:
	var def := StageDef.new()
	def.stage_id = stage_id
	def.display_name = display_name
	def.target_minutes = minutes
	def.set_loadout_for_all(LOADOUT)
	return def


## 窪みのブロック（上面がまわりと同じ高さ。跳べなくても乗れる持ち上げ台）。
static func lift(
	def: StageDef, m: IslandMap, at: Vector2i, key: String, color: Color = LIFT_COLOR
) -> StageDef.BlockSpec:
	var block := StageDef.BlockSpec.new(key, m.pit(at.x, at.y))
	block.color = color
	def.blocks.append(block)
	return block


static func stone(
	def: StageDef, key: String, cell: Vector3i, color: Color = STONE_COLOR
) -> StageDef.BlockSpec:
	var block := StageDef.BlockSpec.new(key, cell)
	block.color = color
	def.blocks.append(block)
	return block


## ブロック・生き物に札（禁止）を付ける。
static func sign(tokens: Array[StageDef.TokenSpec], action: RuleAction.Kind) -> void:
	tokens.append(StageDef.TokenSpec.new(action, true))


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


static func boots(def: StageDef, at: Vector3) -> void:
	item(def, RuleAction.Kind.HIGH_JUMP, at, RuleVessel.Part.FEET, "ジャンプブーツ")


static func gloves(def: StageDef, at: Vector3) -> void:
	item(def, RuleAction.Kind.CLIMB, at, RuleVessel.Part.HANDS, "クライミンググローブ")


## 願いを持つ生き物。held_item があれば「投げる」をもらうと向いている方（北）へ投げる。
## 能力が無ければ置いた場所で北を向いて待つ。
static func animal(
	def: StageDef, key: String, at: Vector3, held_item: String = "", look: String = ""
) -> StageDef.CreatureSpec:
	var creature := StageDef.CreatureSpec.new(key, at)
	creature.held_item = held_item
	if look != "":
		creature.look = look
	def.creatures.append(creature)
	return creature


## 氷の床（上面 top）。地図のその範囲は空けておき、氷の箱を足す（地図の後で呼ぶ）。
static func ice(def: StageDef, from: Vector2i, to: Vector2i, top: int = 0) -> void:
	def.terrain_boxes.append(
		[Vector3i(from.x, mini(-1, top - 1), from.y), Vector3i(to.x, top - 1, to.y), "ice"]
	)


static func spawns(center: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for dx: float in [-1.5, -0.5, 0.5, 1.5]:
		result.append(center + Vector3(dx, 0.0, 0.0))
	return result


## 鐘を全部鳴らし（extra の条件も満たし）、生きている全員がゴールに集まる。
static func bells_and_goal(
	def: StageDef, goal: AABB, extra: Array[ClearCondition] = []
) -> ClearCondition:
	var parts: Array[ClearCondition] = []
	for bell in def.bells:
		parts.append(ClearCondition.activate(bell.key))
	parts.append_array(extra)
	parts.append(ClearCondition.all_at_goal(goal))
	return ClearCondition.all_of(parts)
