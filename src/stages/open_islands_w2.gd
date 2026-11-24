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
## 2-5 は時の鐘（docs/adr/0014）を初めて出すステージ（2026-11-21 本人の判断で作り直した）。
## クリアは「島の条件＋生きている全員がゴールの窪み（OpenIslands.goal_hollow）に集まる」。配置・目安時間は仮。

const LIFT_COLOR := Color(0.7, 0.58, 0.86)
const STONE_COLOR := Color(0.62, 0.6, 0.56)
const ECHO_COLOR := Color(0.55, 0.78, 0.86)
## こだまの鐘: 子どもの生き物の巣（頂の西の小山。高さ 5）。
const ECHO_NEST := AABB(Vector3(-5.0, 4.5, -14.0), Vector3(2.0, 2.0, 2.0))
## 転がる玉: 子どもの生き物の巣（台地の西の小山。高さ 3）。
const ROLLING_NEST := AABB(Vector3(-9.0, 2.5, -8.0), Vector3(2.0, 2.0, 2.0))
## 鳴りつづける鐘: 子どもの生き物の巣（北の台地の小山。高さ 5）。
const RINGING_NEST := AABB(Vector3(-2.0, 4.5, -18.0), Vector3(2.0, 2.0, 2.0))
## 鳴りつづける鐘: 時の鐘（鐘の段の東。橋のたもとから F が届く）と、鳴る秒数。
const RINGING_BELL := "timed_bell"
const RINGING_BELL_AT := Vector3(3.5, 2.0, -1.5)
const RINGING_BELL_TIME := 5.0
## 鳴りつづける鐘: 信号の石の最初のセル（西へ 5 マス歩いて (0, 0, 1) で止まる）。
const RINGING_STONE_START := Vector3i(5, 0, 1)


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
	# 2-2 の新しいことは信号（docs/w2-w3-teaching.md）。鐘 1 の真下の青い台のそばでだけ、台に乗ったまま鐘を
	# 鳴らす案内を出す（台の信号のジャンプを取った後は出さない）。鳴ると台が跳ねるのは見て分かる
	def.hint_spots = [
		StageDef.HintSpot.new("signal", Vector3(2.5, 0.0, 0.5), 1.8, "F", "乗ったまま鐘を鳴らす"),
	]
	def.hint_spots[0].while_holding = "echo_lift_1"
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


## 鳴りつづける鐘（2-5。目安 10 分・仮。時の鐘の初出。2026-11-21 本人の判断で時の鐘を使って作り直した）。
## 南の浜（高さ 0）・鐘の段（2）・幅 10 の谷・北の台地（4）。台地の巣の小山（5）が生き物の巣。
## 新しい仕掛け: 時の鐘（MechanismSpecs.TimedBellSpec。5 秒。足もとの輪が縮んで残りを見せる）。
## 鳴っている間だけ、谷の底から橋（逆向きのスイッチの扉 2 枚。高さ 2 の短い板と高さ 3 の長い板）がせり上がり、
## 浜の石（信号の A。西へ歩く）が 1.4 秒ごとに 1 マス進む。鳴りやむと橋は谷の底へ沈む（上にいれば落ちる）。
## - 谷の幅 10 は、走って跳んでも、受け入れた重ね跳び（同じ高さへ約 8.4 m）でも越えない（関所）
## - 沈んだ橋の上面は落下の境（-12）より下（落ちた人・生き物・ブロックは戻される。谷底に立って詰まない）
## - 石は鐘の段の壁ぞいを 5 マス歩き、出っ張りで止まって生き物の 1 段の足場になる。鐘 1 回では 3 マスで、
##   まだ生き物が探す 8 マスの外（2 回目の途中で生き物が気づく）
## 生き物はジャンプを 1 つ持っている。移動を渡すと、石の段で鐘の段へ上がり、橋が架かれば短い板 → 長い板 →
## 北の台地 → 巣の小山と 1 段ずつ上がる。橋を渡りきるまで 6 秒以上かかるので、鐘 1 回（5 秒）では途中で落ちる。
## 鳴らしつづける方法は自由:
## - 鐘のそばで、鳴りやむ前に F で鳴らし直す（鳴らすたびに残りが 5 秒に戻る）
## - 発射台を鐘の列（z = -2）へ押し、鐘の届く所（西へ 1 マス）まで寄せて「投げる」を渡す（1.4 秒ごとに玉が当たる）
## プレイヤーは、鳴らしてから 5 秒の間に走って渡る（橋のたもとからでも鐘に F が届く）。発射台が鳴らしつづければ歩いて渡れる。
## 石は自分で押してもよい（地形のセルを押して段にするなど、ほかの作り方も止めない）。
## 協力: 1 人が鐘を鳴らしつづけ、ほかの人が生き物と一緒に渡る。最後の人は走って渡る（または発射台に任せる）。
## ゴール: 北の台地の窪み（高さ 3、4×2）。北にチェックポイントは置かない（取り残されても谷へ落ちれば南へ戻る）。
static func ringing_bell() -> StageDef:
	var def := _base("w2_timed_bells", "鳴りつづける鐘", 10)
	var m := IslandMap.blank(Vector2i(-10, -27), 24, 38)
	m.fill(-8, 1, 12, 8, 0)
	m.fill(-8, -3, 12, 0, 2)
	# 石を止める出っ張り（鐘の段と同じ高さ 2。生き物はここへは上がれない）
	m.fill(-1, 1, -1, 1, 2)
	# 北の台地（谷 z = -13〜-4 の先）と巣の小山
	m.fill(-8, -25, 6, -14, 4)
	m.fill(-2, -18, -1, -17, 5)
	var goal := OpenIslands.goal_hollow(m, 1, -23, 4, -22)
	def.terrain_boxes = m.boxes()
	_signal_stone(def, "walking_stone", RINGING_STONE_START, RuleAction.Kind.LEFT)
	var launcher := StageDef.BlockSpec.new("launcher", Vector3i(11, 2, -3))
	launcher.launcher_direction = Vector3i(-1, 0, 0)
	def.blocks.append(launcher)
	_timed_bridge(def.mechanisms)
	_kit(def, Vector3(-6.5, 0.0, 1.5))
	def.spawn_points = _spawns(Vector3(-2.0, 0.0, 6.5))
	def.checkpoints = [Vector3(-5.5, 0.0, 6.5), Vector3(-5.5, 2.0, -1.5)]
	def.clear_condition = _kit_and_goal(RINGING_NEST, goal)
	return def


## 時の鐘と、鳴っている間だけ架かる橋（逆向きの扉。開く = 谷の底へ沈む、閉じる = せり上がる）。
## 沈んだときの上面が落下の境（Tuning.FALL_LIMIT_Y = -12）より下になる高さにした。
static func _timed_bridge(m: MechanismSpecs) -> void:
	m.timed_bells = [
		MechanismSpecs.TimedBellSpec.new(RINGING_BELL, RINGING_BELL_AT, RINGING_BELL_TIME)
	]
	var short_span := MechanismSpecs.DoorSpec.new(
		"bridge_low", Vector3i(0, -14, -5), PackedStringArray([RINGING_BELL])
	)
	short_span.size = Vector3i(2, 16, 2)
	var long_span := MechanismSpecs.DoorSpec.new(
		"bridge_high", Vector3i(0, -13, -13), PackedStringArray([RINGING_BELL])
	)
	long_span.size = Vector3i(2, 16, 8)
	for span: MechanismSpecs.DoorSpec in [short_span, long_span]:
		span.inverted = true
		m.doors.append(span)


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
