class_name OpenIslandsW2
extends RefCounted
## 鐘の谷（W2）の新しいステージ（docs/campaign-plan.md・docs/adr/0013）。開けた島で、壁で区切らない。
## どのステージにも願いを持つ子どもの生き物がいて、高いところの巣へ連れていくことがクリアの条件の一部になる
## （CreatureMind。1 段ずつしか跳べず、谷は越えられず、持ち上げ台にも乗らない）。生き物の段を作る手段に、
## 鐘の音（信号の方式）と発射台を使う。
## 信号の方式（企画書 5.2）: 鐘が鳴っている間（1 回 5 秒・Tuning.BELL_RING_TIME）だけ、音波の届く 6 m
## （Tuning.SIGNAL_RADIUS）の中の信号のブロックが、繰り返しと同じ 1.4 秒ごとに動く。鳴りやむと周期の途中で
## 休み、また鳴ると続きから動く。ここでは、最初から信号の能力が付いたブロック（石・持ち上げ台）を置いた。
## 発射台の玉は 1 個の「投げる」で約 6.4 m、2 個で約 12.9 m 届く（玉の重力は 6）。
## 数値の目安は OpenIslands の冒頭と同じ。上昇中のブロックの上で自分も跳ぶ技（受け入れた技）は、
## 同じ高さへ 8.4 m 飛ぶので、それで届かない場所（谷の幅 10）を「歩いては行けない場所」にした。
## 2-5 は計画では「時の鐘」だったが、並行の作業の新しい仕掛け（時の鐘など）を使わず、今ある信号の方式と発射台で
## 「鳴っている間だけ」を作った。
## クリアは「島の条件＋生きている全員がゴールの窪み（OpenIslands.goal_hollow）に集まる」。配置・目安時間は仮。

const LIFT_COLOR := Color(0.7, 0.58, 0.86)
const STONE_COLOR := Color(0.62, 0.6, 0.56)
const ECHO_COLOR := Color(0.55, 0.78, 0.86)
## こだまの鐘: 子どもの生き物の巣（頂の西の小山。高さ 5）。
const ECHO_NEST := AABB(Vector3(-5.0, 4.5, -14.0), Vector3(2.0, 2.0, 2.0))
## 転がる玉: 子どもの生き物の巣（台地の西の小山。高さ 3）。
const ROLLING_NEST := AABB(Vector3(-9.0, 2.5, -8.0), Vector3(2.0, 2.0, 2.0))
## 鳴りつづける鐘: 子どもの生き物の巣（台地の東の小山。高さ 3）。
const RINGING_NEST := AABB(Vector3(3.0, 2.5, -8.0), Vector3(2.0, 2.0, 2.0))


## こだまの鐘（2-2。目安 6 分・仮）。下の原（高さ 0）・中の段（2）・頂（4）。頂の西の小山（5）が巣。
## 新しい仕掛け: 信号の方式。最初から「信号のジャンプ」が付いた持ち上げ台が 2 つ、「信号の S（南へ動く）」が
## 付いた石が 2 つある。鐘を鳴らすと、音波の届く石と台だけが、鳴っている間だけ動く。
## - 鐘 1（中の段の縁）: 持ち上げ台 1 に乗ったまま手が届く。鳴ると台 1（と台 2）が跳ね、石 1 が南へ動く。
##   石 1 は 5 マス先で中の段の縁から下の原へ落ち、出っ張り（高さ 1）に当たって壁ぎわで止まる。
##   1 回（5 秒）では 3 マスしか動かないので、2 回鳴らす
## - 鐘 2（頂の縁）: 持ち上げ台 2 に乗ったまま手が届く。鳴ると台 2 が跳ね、石 2 が南へ 4 マス動いて中の段へ落ち、
##   出っ張り（高さ 3）に当たって頂の壁ぎわで止まる
## 生き物はジャンプを 1 つ持っている。移動を 1 つ渡せば、石の段を 1 段ずつ跳んで巣へ向かう。
## 別の道: 石は自分で押してもよい（単発の S で 1 マスずつ）。台の信号のジャンプを F で回収して、
## 単発・繰り返しで使ってもよい。自分のジャンプがあるので、地面のセルを持ち上げ台にしてもよい（受け入れた技）。
## 協力: 1 人が台に乗り、もう 1 人が鐘を鳴らす（鐘から離れた所でも乗っていられる）。
## ゴール: 頂の東の窪み（高さ 3、4×2）。
static func echo_bells() -> StageDef:
	var def := _base("w2_echo_bells", "こだまの鐘", 6)
	var m := IslandMap.blank(Vector2i(-10, -18), 21, 28)
	m.fill(-8, 0, 8, 8, 0)
	m.fill(-8, -7, 8, -1, 2)
	m.fill(-6, -16, 6, -8, 4)
	m.fill(-5, -14, -4, -13, 5)
	# 石を止める出っ張り（下の原は高さ 1、中の段は高さ 3）
	m.fill(-4, 1, -4, 1, 1)
	m.fill(-4, -6, -4, -6, 3)
	var goal := OpenIslands.goal_hollow(m, 1, -15, 4, -14)
	_signal_lift(def, m, Vector2i(2, 0), "echo_lift_1")
	_signal_lift(def, m, Vector2i(2, -7), "echo_lift_2")
	def.terrain_boxes = m.boxes()
	_signal_stone(def, "echo_stone_1", Vector3i(-4, 2, -5), RuleAction.Kind.BACK)
	_signal_stone(def, "echo_stone_2", Vector3i(-4, 4, -11), RuleAction.Kind.BACK)
	def.bells = [
		StageDef.BellSpec.new("echo_bell_1", Vector3(1.5, 2.0, -2.5)),
		StageDef.BellSpec.new("echo_bell_2", Vector3(1.5, 4.0, -9.5)),
	]
	_kit(def, Vector3(-3.5, 0.0, 4.5))
	def.spawn_points = _spawns(Vector3(0.0, 0.0, 6.5))
	def.checkpoints = [Vector3(6.5, 0.0, 5.5), Vector3(6.5, 2.0, -4.5)]
	def.clear_condition = _kit_and_goal(ECHO_NEST, goal)
	return def


## 転がる玉（2-4。目安 9 分・仮）。浜（高さ 0）の北西に台地（2）。台地の西の小山（3）が巣。
## 新しい仕掛け: 発射台そのものに W/A/S/D を渡して押し、狙いを合わせる（発射台の向きは東のまま変わらない）。
## 東の小島の鐘は、浜の東の端から谷の幅 10 の先（歩いても跳んでも行けない）。発射台を鐘と同じ列
## （z = -1）の浜の東の端まで押し、「投げる」を 2 つ渡すと玉が届く（1 つでは約 6.4 m で届かない）。
## 2 つ目の「投げる」は台地の東の端に落ちている。
## 生き物はジャンプを 1 つ持っているが、台地（2 段）へは上がれない。鐘を鳴らしたあと、発射台を台地の壁ぎわへ
## 押し戻せば 1 段の足場になる（台地の南の壁に沿って繰り返しの A で西へ押すと、壁の角でちょうど止まる）。
## 台地の南の縁のセルを押し落として階段にしてもよい（押し石の小道と同じ）。
## 協力: 1 人が発射台を押し、もう 1 人が台地の「投げる」を取ってくる。
## ゴール: 台地の北の窪み（高さ 1、3×2）。
static func rolling_shots() -> StageDef:
	var def := _base("w2_rolling_shots", "転がる玉", 9)
	var m := IslandMap.blank(Vector2i(-12, -15), 34, 25)
	m.fill(-10, -13, 6, 8, 0)
	m.fill(-10, -13, -2, -5, 2)
	m.fill(-9, -8, -8, -7, 3)
	# 東の小島（浜の東の端から谷の幅 10）
	m.fill(17, -3, 19, 1, 0)
	var goal := OpenIslands.goal_hollow(m, -7, -12, -5, -11)
	var lift := StageDef.BlockSpec.new("plateau_lift", m.pit(-1, -8))
	lift.color = LIFT_COLOR
	def.blocks.append(lift)
	def.terrain_boxes = m.boxes()
	var launcher := StageDef.BlockSpec.new("launcher", Vector3i(2, 0, 4))
	launcher.launcher_direction = Vector3i(1, 0, 0)
	def.blocks.append(launcher)
	def.bells = [StageDef.BellSpec.new("isle_bell", Vector3(17.5, 0.0, -0.5))]
	_item(def, RuleAction.Kind.THROW, Vector3(-3.5, 2.0, -6.5))
	_kit(def, Vector3(0.5, 0.0, 2.5))
	def.spawn_points = _spawns(Vector3(-2.0, 0.0, 6.5))
	def.checkpoints = [Vector3(-7.5, 0.0, 5.5), Vector3(-7.5, 2.0, -6.5)]
	def.clear_condition = (
		ClearCondition
		. all_of(
			[
				ClearCondition.activate("isle_bell"),
				ClearCondition.carry_object("kit", ROLLING_NEST),
				ClearCondition.all_at_goal(goal),
			]
		)
	)
	return def


## 鳴りつづける鐘（2-5。目安 11 分・仮。計画の「時の鐘」を今ある仕組みで置き換えた）。
## 浜（高さ 0）の北に台地（2）。台地の東の小山（3）が巣（石が着く壁ぎわから 8 マス以内）。東の岩（谷の幅 3 の先）に鐘がある。
## 新しい組み合わせ: 2-1 の発射台・2-2 の信号・2-4 の発射台を押す。
## 浜の南東の石には「信号の W（北へ動く）」が付いていて、鐘が鳴っている間だけ北へ進み、9 マス先の台地の壁で
## 止まって生き物の 1 段の足場になる。鐘 1 回（5 秒）では 3 マスしか進まない。
## - 発射台を北へ 5 マス押して鐘と同じ列に合わせ、「投げる」を渡すと、1.4 秒ごとに玉が当たって鐘が鳴りつづける
## - または谷を跳んで岩に渡り、鳴りやむたびに鐘を鳴らし直す（3 回）
## 生き物はジャンプを 1 つ持っている。移動を渡せば、石が壁ぎわに着いたら巣へ向かう。
## 協力: 1 人が岩で鐘を鳴らし続け、もう 1 人が生き物と発射台を受け持つ。
## ゴール: 台地の西の窪み（高さ 1、4×2）。
static func ringing_bell() -> StageDef:
	var def := _base("w2_timed_bells", "鳴りつづける鐘", 11)
	var m := IslandMap.blank(Vector2i(-10, -14), 24, 23)
	m.fill(-8, -3, 6, 8, 0)
	m.fill(-8, -12, 6, -4, 2)
	m.fill(3, -8, 4, -7, 3)
	# 東の岩（谷の幅 3）
	m.fill(10, 1, 12, 3, 0)
	var goal := OpenIslands.goal_hollow(m, -5, -11, -2, -10)
	var lift := StageDef.BlockSpec.new("plateau_lift", m.pit(0, -3))
	lift.color = LIFT_COLOR
	def.blocks.append(lift)
	def.terrain_boxes = m.boxes()
	_signal_stone(def, "walking_stone", Vector3i(6, 0, 6), RuleAction.Kind.FORWARD)
	var launcher := StageDef.BlockSpec.new("launcher", Vector3i(4, 0, 7))
	launcher.launcher_direction = Vector3i(1, 0, 0)
	def.blocks.append(launcher)
	def.bells = [StageDef.BellSpec.new("rock_bell", Vector3(10.5, 0.0, 2.5))]
	# 生き物は台地の壁の近く（発射台の最初の位置は、生き物が探す 8 マスの外。乗って待ってしまわない）
	_kit(def, Vector3(2.5, 0.0, -1.5))
	def.spawn_points = _spawns(Vector3(-2.0, 0.0, 6.5))
	def.checkpoints = [Vector3(-6.5, 0.0, 5.5), Vector3(-6.5, 2.0, -6.5)]
	def.clear_condition = _kit_and_goal(RINGING_NEST, goal)
	return def


static func _base(stage_id: String, display_name: String, minutes: int) -> StageDef:
	var def := StageDef.new()
	def.stage_id = stage_id
	def.display_name = display_name
	def.target_minutes = minutes
	def.set_loadout_for_all(OpenIslands.LOADOUT)
	return def


static func _kit_and_goal(nest: AABB, goal: AABB) -> ClearCondition:
	return ClearCondition.all_of(
		[ClearCondition.carry_object("kit", nest), ClearCondition.all_at_goal(goal)]
	)


## 子どもの生き物（ジャンプを 1 つ持っている。移動が無いので、渡されるまで待つ）。
static func _kit(def: StageDef, at: Vector3) -> void:
	var kit := StageDef.CreatureSpec.new("kit", at)
	kit.look = Creature.MODEL_KIT
	kit.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.JUMP))
	def.creatures.append(kit)


## 窪みの持ち上げ台に、最初から信号のジャンプを付ける（鐘が鳴っている間だけ跳ねる）。
static func _signal_lift(def: StageDef, m: IslandMap, at: Vector2i, key: String) -> void:
	var block := StageDef.BlockSpec.new(key, m.pit(at.x, at.y))
	block.color = ECHO_COLOR
	block.tokens.append(
		StageDef.TokenSpec.new(RuleAction.Kind.JUMP, false, TriggerMode.Kind.SIGNAL)
	)
	def.blocks.append(block)


## 最初から信号の移動（action の向き）が付いた石。
static func _signal_stone(
	def: StageDef, key: String, cell: Vector3i, action: RuleAction.Kind
) -> void:
	var block := StageDef.BlockSpec.new(key, cell)
	block.color = STONE_COLOR
	block.tokens.append(StageDef.TokenSpec.new(action, false, TriggerMode.Kind.SIGNAL))
	def.blocks.append(block)


static func _item(def: StageDef, action: RuleAction.Kind, at: Vector3) -> void:
	def.world_items.append(StageDef.PlacementSpec.in_world(action, at))


static func _spawns(center: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for dx: float in [-1.5, -0.5, 0.5, 1.5]:
		result.append(center + Vector3(dx, 0.0, 0.0))
	return result
