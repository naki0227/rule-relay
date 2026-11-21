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
const NEST_ID := "creature_nest"
const GARDEN_ID := "ban_garden"
const EXPEDITION_ID := "long_expedition"

## 導入: 岩棚（上面 y = 2）と、その手前の窪みに収まったブロック（上面が地面と同じ y = 0）。
const INTRO_LEDGE_MIN := Vector3i(-5, 0, -10)
const INTRO_LEDGE_MAX := Vector3i(5, 1, -6)
const INTRO_STEP_MIN := Vector3i(-2, 0, -1)
const INTRO_STEP_MAX := Vector3i(2, 0, 0)
const INTRO_LIFT_CELL := Vector3i(0, -1, -5)
## 導入のゴール: 岩棚の奥の窪み（上面 y = 1。まわりの岩棚より 1 段低い）。
## 南（登り口の側）の縁は 2 マス（z = -7〜-6）。縁が 1 マスだと、窪みの南の列に立つカメラの回転の中心
## （足もと + 1.5）から、下の地面の仲間の頭へ照準が合った（docs/reports/2026-11-20-goal-probes.md G1）。
## 2026-11-20 決定: ルールは足さず、岩棚を北へ 1 マス広げて窪みを奥へ寄せる（地形だけで直す）。
const INTRO_GOAL_MIN := Vector3i(-2, 0, -9)
const INTRO_GOAL_MAX := Vector3i(2, 0, -8)

## 鐘の谷: 発射台（東向き）と、谷の向こうの小島の鐘。
const BELL_LAUNCHER_CELL := Vector3i(0, 0, 0)
const BELL_SHORE_MAX_X := 1
const BELL_AT := Vector3(6.5, 0.0, 0.5)

const _MOVES: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD, RuleAction.Kind.LEFT, RuleAction.Kind.BACK, RuleAction.Kind.RIGHT
]


## すべてのステージ（目安のクリア時間の短い順）。広場のポータルの場所は CampaignPlan の枠が決める。
## 新しいステージは、ここに足し、CampaignPlan の同じ stage_id の枠で広場に現れる。
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
		OpenIslandsExtra.creature_nest(),
		OpenIslandsExtra.ban_garden(),
		OpenIslandsLong.long_expedition(),
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
## 2〜4人では別解もある: ジャンプを1人に集めて自分で跳ぶ（×2 で届く想定）、
## 1人がブロックに乗り、もう1人が渡す など。地形は人数によらず同じで、人数別補助は置かない。
## クリアは、生きている全員が岩棚の上の窪み（ゴール）に集まること（docs/adr/0011 決定 9）。ひとりなら
## 岩棚へ上がって窪みに降りるだけ。窪みの縁が下の地面への光線を遮るので、窪みの中からは下の仲間へ
## 能力を渡せない（渡すなら岩棚の縁まで出る。ルールでは禁止しない）。
static func intro_jump_lend() -> StageDef:
	var def := StageDef.new()
	def.stage_id = INTRO_ID
	def.display_name = "跳ぶ力を貸す"
	def.target_minutes = 3
	def.terrain_boxes = [
		# 地面（窪みの1マスだけ抜く）と窪みの底
		[Vector3i(-5, -1, -10), Vector3i(5, -1, -6), "grass"],
		[Vector3i(-5, -1, -4), Vector3i(5, -1, 6), "grass"],
		[Vector3i(-5, -1, -5), Vector3i(-1, -1, -5), "grass"],
		[Vector3i(1, -1, -5), Vector3i(5, -1, -5), "grass"],
		[INTRO_LIFT_CELL + Vector3i(0, -1, 0), INTRO_LIFT_CELL + Vector3i(0, -1, 0), "rock"],
		# 自分で跳べる小段差（道の真ん中。横を回っても進める）
		[INTRO_STEP_MIN, INTRO_STEP_MAX, "sand"],
		# 跳べない岩棚（INTRO_LEDGE_MIN〜MAX）。奥を 1 段下げて、ゴールの窪みにする
		# （縁は南 2 マス・北 1 マス・東西 3 マス。北の下には誰も立てない）
		[Vector3i(-5, 0, -10), Vector3i(5, 1, -10), "rock"],
		[Vector3i(-5, 0, -7), Vector3i(5, 1, -6), "rock"],
		[Vector3i(-5, 0, -9), Vector3i(-3, 1, -8), "rock"],
		[Vector3i(3, 0, -9), Vector3i(5, 1, -8), "rock"],
		[INTRO_GOAL_MIN, INTRO_GOAL_MAX, "rock"],
	]
	def.spawn_points = _spawn_row(Vector3(0.0, 0.0, 4.5))
	def.blocks = [StageDef.BlockSpec.new("lift", INTRO_LIFT_CELL)]
	def.blocks[0].color = Color(0.7, 0.58, 0.86)
	def.set_loadout_for_all(_moves_and([RuleAction.Kind.JUMP]))
	# チェックポイントは、出現地点からブロックへ向かう道の上（小段差の先・ブロックの手前）。
	# 初めての人も必ず踏むので、「台座に触れるとチーム共通の再開地点になる」を道なりに知る
	def.checkpoints = [Vector3(0.5, 0.0, -2.0)]
	var goal_size := Vector3(INTRO_GOAL_MAX - INTRO_GOAL_MIN + Vector3i.ONE)
	var floor_y := float(INTRO_GOAL_MAX.y + 1)
	def.clear_condition = ClearCondition.all_at_goal(
		AABB(
			Vector3(INTRO_GOAL_MIN.x, floor_y - 0.1, INTRO_GOAL_MIN.z),
			Vector3(goal_size.x, 3.0, goal_size.z)
		)
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
## 岸の発射台へ「投げる」を渡すと玉を撃ち、玉が鐘に当たって鳴る。鐘が鳴り、生きている全員が
## 岸の北西の隅の旗（ゴール）に集まればクリア（ALL_OF。docs/adr/0011 決定 9）。
## 全員ジャンプ禁止の平らな岸なので、ゴールは窪みにしない（降りたら出られなくなる）。
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
	def.clear_condition = (
		ClearCondition
		. all_of(
			[
				ClearCondition.activate("valley_bell"),
				ClearCondition.all_at_goal(AABB(Vector3(-5.0, -0.1, -3.0), Vector3(3.0, 3.0, 3.0))),
			]
		)
	)
	return def


## ハブ = 広場（オーバーワールド。クリア条件なし）。2026-11-21 に一列の入口の広場から、歩き回れる
## ひとつながりの広場に変えた（docs/adr/0013）。中身は Overworld が OverworldState から組み立てる。
## ここで作るのは試遊の版の既定（ポータルと地方は全部開く・何もクリアしていない）。進行に合わせた広場は
## PartyDirector が Overworld.build(その時の状態) で作る。
static func hub() -> StageDef:
	return Overworld.build(OverworldState.new())


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
