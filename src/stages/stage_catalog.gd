class_name StageCatalog
extends RefCounted
## 具体的なステージの定義（すべて仮の配置。プレイテスト用の小さな置き場所）。
## 座標は PrototypeIsland と同じ（1ブロック = 1m、北 = -Z、地面の上面 y = 0）。
## 跳べる高さなどの調整値は Tuning（プレイヤーのジャンプ 1.3、ブロックのジャンプ 2.5）。

const HUB_ID := "hub"
const INTRO_ID := "intro_jump_lend"
const RELAY_ID := "relay_carry"
const BELL_ID := "bell_valley"
const HILL_ID := "hill_top"
const QUARRY_ID := "quarry"
const THREE_BELLS_ID := "three_bells"
const FLOATING_ID := "floating_isles"
const WINDY_ID := "windy_ridge"
const FORT_ID := "ruined_fort"

## 導入: 岩棚（上面 y = 2）と、その手前の窪みに収まったブロック（上面が地面と同じ y = 0）。
const INTRO_LEDGE_MIN := Vector3i(-5, 0, -9)
const INTRO_LEDGE_MAX := Vector3i(5, 1, -6)
const INTRO_STEP_MIN := Vector3i(-2, 0, -1)
const INTRO_STEP_MAX := Vector3i(2, 0, 0)
const INTRO_LIFT_CELL := Vector3i(0, -1, -5)

## 鐘の谷: 発射台（東向き）と、谷の向こうの小島の鐘。
const BELL_LAUNCHER_CELL := Vector3i(0, 0, 0)
const BELL_SHORE_MAX_X := 1
const BELL_AT := Vector3(6.5, 0.0, 0.5)

const _MOVES: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD, RuleAction.Kind.LEFT, RuleAction.Kind.BACK, RuleAction.Kind.RIGHT
]


## すべてのステージ（目安のクリア時間の短い順）。ハブの入口もこの順に並ぶ。
static func all_stages() -> Array[StageDef]:
	var stages: Array[StageDef] = [
		intro_jump_lend(),
		bell_valley(),
		relay_carry(),
		OpenIslands.hill_top(),
		OpenIslands.quarry(),
		OpenIslands.three_bells(),
		OpenIslands.floating_isles(),
		OpenIslandsMore.windy_ridge(),
		OpenIslandsMore.ruined_fort(),
	]
	stages.sort_custom(
		func(a: StageDef, b: StageDef) -> bool: return a.target_minutes < b.target_minutes
	)
	return stages


## stage_id から定義を作る（ハブも含む）。無ければ null。
static func by_id(stage_id: String) -> StageDef:
	if stage_id == HUB_ID:
		return hub()
	for def in all_stages():
		if def.stage_id == stage_id:
			return def
	return null


## 導入ステージ（引き継ぎ仕様 6 の提案。配置は仮）。
## 地面から小段差（高さ 1）は自分で跳べる。岩棚（高さ 2）は跳べない（1.3 < 2）。
## 岩棚の手前の窪みにブロックがあり、上面が地面と同じ高さなので、跳べなくなってもそのまま乗れる。
## ジャンプをブロックへ渡す（単発・繰り返し）→ 乗って持ち上げられる（2.5）→ 岩棚へ。
## 地面から降りずに済むので、渡した後もブロックへ歩いて戻って F で回収できる（詰まない）。
## 2〜4人では別解もある: ジャンプを1人に集めて自分で跳ぶ（×2 で届く想定。ジャンプ×n の高さは未決）、
## 1人がブロックに乗り、もう1人が渡す など。地形は人数によらず同じで、人数別補助は置かない。
static func intro_jump_lend() -> StageDef:
	var def := StageDef.new()
	def.stage_id = INTRO_ID
	def.display_name = "跳ぶ力を貸す"
	def.target_minutes = 3
	def.terrain_boxes = [
		# 地面（窪みの1マスだけ抜く）と窪みの底
		[Vector3i(-5, -1, -9), Vector3i(5, -1, -6), "grass"],
		[Vector3i(-5, -1, -4), Vector3i(5, -1, 6), "grass"],
		[Vector3i(-5, -1, -5), Vector3i(-1, -1, -5), "grass"],
		[Vector3i(1, -1, -5), Vector3i(5, -1, -5), "grass"],
		[INTRO_LIFT_CELL + Vector3i(0, -1, 0), INTRO_LIFT_CELL + Vector3i(0, -1, 0), "rock"],
		# 自分で跳べる小段差（道の真ん中。横を回っても進める）
		[INTRO_STEP_MIN, INTRO_STEP_MAX, "sand"],
		# 跳べない岩棚（ゴール）
		[INTRO_LEDGE_MIN, INTRO_LEDGE_MAX, "rock"],
	]
	def.spawn_points = _spawn_row(Vector3(0.0, 0.0, 4.5))
	def.blocks = [StageDef.BlockSpec.new("lift", INTRO_LIFT_CELL)]
	def.blocks[0].color = Color(0.7, 0.58, 0.86)
	def.set_loadout_for_all(_moves_and([RuleAction.Kind.JUMP]))
	def.checkpoints = [Vector3(3.5, 0.0, -2.5)]
	var top := float(INTRO_LEDGE_MAX.y + 1)
	def.clear_condition = ClearCondition.reach_height(
		_top_area(INTRO_LEDGE_MIN, INTRO_LEDGE_MAX), top
	)
	return def


## 能力を回して全員で上がる（配置は仮）。開始時は誰もジャンプを持たない。
## 段（高さ 1）の上がゴールで、動ける全員が入ればクリア（ALL_AT_GOAL）。
## ジャンプは人数別補助として世界に置く: 1人 1個、2人 1個、3人 1個、4人 2個（仮。共通式にはしない）。
## 拾ったジャンプで1人が上がり、下の仲間へ渡す（受け渡し）。順に回せば全員上がれる。
## 台のブロックへ繰り返しで渡して昇降機にする解法もある。ソロは補助の1個で上がれる。
static func relay_carry() -> StageDef:
	var def := StageDef.new()
	def.stage_id = RELAY_ID
	def.display_name = "みんなで回す"
	def.target_minutes = 5
	var goal_min := Vector3i(-5, 0, -6)
	var goal_max := Vector3i(5, 0, -4)
	def.terrain_boxes = [
		[Vector3i(-5, -1, -6), Vector3i(5, -1, 6), "grass"],
		[goal_min, goal_max, "rock"],
	]
	def.spawn_points = _spawn_row(Vector3(0.0, 0.0, 3.5))
	def.blocks = [StageDef.BlockSpec.new("stool", Vector3i(3, 0, -2))]
	def.set_loadout_for_all(_moves_and([]))
	var one := [StageDef.PlacementSpec.in_world(RuleAction.Kind.JUMP, Vector3(-1.5, 0.0, 1.5))]
	var two := one.duplicate()
	two.append(StageDef.PlacementSpec.in_world(RuleAction.Kind.JUMP, Vector3(1.5, 0.0, 1.5)))
	def.helpers = {1: one, 2: one.duplicate(), 3: one.duplicate(), 4: two}
	def.checkpoints = [Vector3(-3.5, 0.0, 4.5)]
	var goal := AABB(Vector3(goal_min) + Vector3(0.0, 0.9, 0.0), Vector3(11.0, 3.0, 3.0))
	def.clear_condition = ClearCondition.all_at_goal(goal)
	return def


## 鐘の谷（配置は仮）。このステージは全員ジャンプ禁止（ステージの禁止）。
## 谷（底なし、幅 4）の向こうの小島に鐘があり、岸からは触って鳴らせない（届く距離の外）。
## 岸の発射台へ「投げる」を渡すと玉を撃ち、玉が鐘に当たって鳴る → クリア（ACTIVATE）。
static func bell_valley() -> StageDef:
	var def := StageDef.new()
	def.stage_id = BELL_ID
	def.display_name = "鐘の谷"
	def.target_minutes = 4
	def.terrain_boxes = [
		[Vector3i(-5, -1, -3), Vector3i(BELL_SHORE_MAX_X, -1, 5), "grass"],
		[Vector3i(6, -1, -1), Vector3i(8, -1, 1), "grass"],
	]
	def.spawn_points = _spawn_row(Vector3(-2.0, 0.0, 3.5))
	var launcher := StageDef.BlockSpec.new("launcher", BELL_LAUNCHER_CELL)
	launcher.launcher_direction = Vector3i(1, 0, 0)
	def.blocks = [launcher]
	def.bells = [StageDef.BellSpec.new("valley_bell", BELL_AT)]
	def.set_loadout_for_all(_moves_and([RuleAction.Kind.THROW]))
	def.prohibitions = [RuleAction.Kind.JUMP]
	def.checkpoints = [Vector3(-4.0, 0.0, 0.5)]
	def.clear_condition = ClearCondition.activate("valley_bell")
	return def


## ハブ（のんびり歩ける広場。クリア条件なし）。入口は歩いて見つける（引き継ぎ仕様 2-2）。
static func hub() -> StageDef:
	var def := StageDef.new()
	def.stage_id = HUB_ID
	def.display_name = "ハブ"
	def.spawn_points = _spawn_row(Vector3(0.0, 0.0, 3.5))
	def.set_loadout_for_all(_moves_and([RuleAction.Kind.JUMP]))
	# 入口は目安のクリア時間の短い順に、西から東へ一列（本人が順番に試して比べられるように）
	# ステージが増えても入口が広場からはみ出さないよう、広場の東端を入口の数に合わせて伸ばす
	var stages := all_stages()
	var east := maxi(12, ceili(-10.5 + 3.5 * (stages.size() - 1)) + 2)
	def.terrain_boxes = [[Vector3i(-12, -1, -9), Vector3i(east, -1, 9), "grass"]]
	for i in stages.size():
		var x := -10.5 + 3.5 * i
		def.entrances.append(_entrance(stages[i].stage_id, Vector3(x, 0.0, -6.5)))
	return def


static func _entrance(stage_id: String, at: Vector3) -> StageDef.EntranceSpec:
	var area := AABB(at - Vector3(1.0, 0.0, 1.0), Vector3(2.0, 2.5, 2.0))
	return StageDef.EntranceSpec.new(stage_id, at, area)


## 4人分の出現位置（中心から東西に 1m ずつ）。
static func _spawn_row(center: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for dx: float in [-1.5, -0.5, 0.5, 1.5]:
		result.append(center + Vector3(dx, 0.0, 0.0))
	return result


static func _moves_and(extra: Array[RuleAction.Kind]) -> Array[RuleAction.Kind]:
	var result: Array[RuleAction.Kind] = _MOVES.duplicate()
	result.append_array(extra)
	return result


## 箱の上面の水平な範囲（REACH_HEIGHT 用。y は上面の少し下から）。
static func _top_area(cell_min: Vector3i, cell_max: Vector3i) -> AABB:
	var size := Vector3(cell_max - cell_min + Vector3i.ONE)
	return AABB(Vector3(cell_min.x, cell_max.y + 0.9, cell_min.z), Vector3(size.x, 3.0, size.z))
