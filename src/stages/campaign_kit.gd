class_name CampaignKit
extends RefCounted
## ワールド 3・4 のステージ（World3Stages / World4Stages）が共通で使う組み立ての部品。
## OpenIslands と同じ考え方（ひとつながりの島・窪みのゴール・ルールは足さず地形で決める）。
## 並行で別のワールドを作る作業と共有ファイルでぶつからないように、自分のファイルに分けた。
##
## 数値の目安（2026-11-21 に測った。tests/integration/test_world3_probes.gd ほか）:
## - ふつうの走り跳び: 幅 3 まで（幅 4 は縁ちょうどだけ。受け入れた技）
## - 跳んでから空中でダッシュ: 幅 7 まで（同じ高さ。幅 8 は越えない）
## - W×2（協力）の走り跳び: 幅 7 まで
## - 地面のセルに単発のジャンプを貸して乗り、上昇中に自分でも跳ぶ（受け入れた技）: 足もとが 7 m 上がり、
##   同じ高さへは幅 7 まで跳べる。なので、ジャンプを持てる島では高さは関所にならない。
##   関所は「幅 8 以上の空」「ジャンプが無い（持ち込まない）島」「仕掛けの橋」で作る
## - 風（3 m/秒）の追い風の走り跳び: 幅 5 まで

const MOVES_AND_THROW: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD,
	RuleAction.Kind.LEFT,
	RuleAction.Kind.BACK,
	RuleAction.Kind.RIGHT,
	RuleAction.Kind.JUMP,
	RuleAction.Kind.THROW,
]
const LIFT_COLOR := Color(0.7, 0.58, 0.86)
const STONE_COLOR := Color(0.62, 0.6, 0.56)
const SHUTTLE_COLOR := Color(0.96, 0.78, 0.5)
const SIGNAL_COLOR := Color(0.55, 0.78, 0.86)


static func base(stage_id: String, display_name: String, minutes: int) -> StageDef:
	var def := StageDef.new()
	def.stage_id = stage_id
	def.display_name = display_name
	def.target_minutes = minutes  # 目安の分はすべて仮（本人の試遊で直す）
	def.provisional = true
	def.set_loadout_for_all(MOVES_AND_THROW)
	return def


## ジャンプを持ち込まない島のホットバー（W/A/S/D と投げる）。
static func no_jump_loadout() -> Array[RuleAction.Kind]:
	return [
		RuleAction.Kind.FORWARD,
		RuleAction.Kind.LEFT,
		RuleAction.Kind.BACK,
		RuleAction.Kind.RIGHT,
		RuleAction.Kind.THROW,
	]


## 窪みのブロック（上面がまわりと同じ高さ。跳べなくても乗れる持ち上げ台）。
static func lift(def: StageDef, m: IslandMap, at: Vector2i, key: String) -> StageDef.BlockSpec:
	var block := StageDef.BlockSpec.new(key, m.pit(at.x, at.y))
	block.color = LIFT_COLOR
	def.blocks.append(block)
	return block


static func stone(def: StageDef, key: String, cell: Vector3i) -> StageDef.BlockSpec:
	var block := StageDef.BlockSpec.new(key, cell)
	block.color = STONE_COLOR
	def.blocks.append(block)
	return block


## 往復足場: 2 マスの台座（rail）の上を、actions を繰り返しで交互に行き来するブロック。
## cell はブロックのいる最初のマス。台座は cell と、actions[0] の向きに 1 マス先（どちらも 1 段下）。
static func shuttle(
	def: StageDef,
	key: String,
	cell: Vector3i,
	actions: Array[RuleAction.Kind],
	mode: TriggerMode.Kind = TriggerMode.Kind.REPEAT
) -> StageDef.BlockSpec:
	var block := StageDef.BlockSpec.new(key, cell)
	block.color = SHUTTLE_COLOR if mode == TriggerMode.Kind.REPEAT else SIGNAL_COLOR
	for action in actions:
		block.tokens.append(StageDef.TokenSpec.new(action, false, mode))
	def.blocks.append(block)
	var other := cell + RuleAction.world_direction(actions[0])
	rail(def, cell)
	rail(def, other)
	return block


## ブロックのマスの 1 段下に、1 マスの台座（岩）を置く。まわりは空のまま（落ちたら島から落ちたのと同じ）。
static func rail(def: StageDef, block_cell: Vector3i) -> void:
	var below := block_cell + Vector3i(0, -1, 0)
	def.terrain_boxes.append([below, below, "rock"])


## 願いを持つ生き物（願いは「高いところへ行きたい」）。tokens は最初から持っている能力。
static func wish_creature(
	def: StageDef,
	key: String,
	at: Vector3,
	look: String = Creature.MODEL_WISH,
	tokens: Array[RuleAction.Kind] = [],
	held_item: String = ""
) -> StageDef.CreatureSpec:
	var creature := StageDef.CreatureSpec.new(key, at)
	creature.look = look
	creature.held_item = held_item
	for action in tokens:
		creature.tokens.append(StageDef.TokenSpec.new(action))
	def.creatures.append(creature)
	return creature


## 生き物の願いの行き先（1 マスの上面 top に立っている）を表す箱。
static func perch_box(cell: Vector2i, top: int, size: Vector2i = Vector2i.ONE) -> AABB:
	return AABB(Vector3(cell.x, top - 0.5, cell.y), Vector3(size.x, 2.0, size.y))


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


static func spawns(center: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for dx: float in [-1.5, -0.5, 0.5, 1.5]:
		result.append(center + Vector3(dx, 0.0, 0.0))
	return result


## 生き物を願いの場所へ連れていき（carry_object）、鐘を鳴らし、生きている全員がゴールに集まる。
static func clear_with(
	goal: AABB, wishes: Dictionary, bells: PackedStringArray = []
) -> ClearCondition:
	var parts: Array[ClearCondition] = []
	for key: String in wishes:
		parts.append(ClearCondition.carry_object(key, wishes[key] as AABB))
	for bell in bells:
		parts.append(ClearCondition.activate(bell))
	parts.append(ClearCondition.all_at_goal(goal))
	return ClearCondition.all_of(parts)


## 仕掛けの橋: 源（鐘・板・レバー）が作動している間だけ、空の上に架かる石の橋（逆向きの扉）。
## 閉じた（架かった）とき上面が top。作動していないときは thickness だけ沈む（深く沈むので、
## 沈んだ橋に落ちても島から落ちたのと同じく下へ抜けて戻れるよう、厚さは 13 以上にする）。
static func bridge(
	def: StageDef,
	key: String,
	min_cell: Vector2i,
	size: Vector2i,
	top: int,
	sources: PackedStringArray
) -> MechanismSpecs.DoorSpec:
	var thickness := 13
	var door := MechanismSpecs.DoorSpec.new(
		key, Vector3i(min_cell.x, top - thickness, min_cell.y), sources
	)
	door.size = Vector3i(size.x, thickness, size.y)
	door.inverted = true
	def.mechanisms.doors.append(door)
	return door
