class_name World7Finale
extends RefCounted
## ワールド 7「空の頂」の後半 3 ステージ（7-4〜7-6）。前半と共通の考え方・数値の目安は World7Stages の冒頭。
## 7-6 はゲーム全体の最終ステージで、チェックポイントの多い長い登りと、ゴールでのささやかなお祝い
## （SummitFestival。これまでに願いをかなえた生き物が集まり、特別な知らせが出る）。

const SUMMIT_4 := "w7_summit_4"
const SUMMIT_5 := "w7_summit_5"
const SUMMIT_6 := "w7_summit_6"

const RAFT_COLOR := Color(0.86, 0.74, 0.55)
const EAST := Vector3i(1, 0, 0)
## 7-4 の川の小島（川の真ん中。どちらの岸からも鐘に触れない）。
const ISLET_MIN := Vector2i(-1, -8)
const ISLET_MAX := Vector2i(1, -4)
## 7-5 の石が止まる 2 枚の板（どちらも床の高さ 1）と、小山の上の板。
const WEST_PLATE := Vector3i(-2, 1, 2)
const EAST_PLATE := Vector3i(2, 1, 2)
const KNOLL_PLATE := Vector3i(-7, 2, 1)
## 7-6 の塔のふもとの風の通り道（東へ吹き続ける）と、その出口の重さの板。
const FESTIVAL_CHANNEL_MIN := Vector3i(-20, 0, -47)
const FESTIVAL_CHANNEL_MAX := Vector3i(-9, 2, -45)
const FESTIVAL_CRATE_PLATE := Vector3i(-8, 0, -46)


## 7-4 流れの上の鐘（目安 16 分・仮）。新しい組み合わせ: 水の流れ×浮く／泳ぐ×筏×投げる（生き物）。
## 南の岸（高さ 1）と北の岸（1）の間に、東へ流れる幅 11 の川（底なし。泳げなければ沈む）。川の真ん中の小島に鐘。
## 鐘を鳴らす道: 小島の南の端の生き物（願い: 鐘を鳴らしたい。木の実を持って北を向いている）へ、南の岸から
##   「投げる」を投げて渡す／泳いで小島へ上がり、触って鳴らす。鐘はどちらの岸からも触れない。
## 川を渡る道（どれでもよい）:
## 1. 風船（浮く）を持って川に入ると、浮いて流され、川の東の端の船着き場（1）に着く。水面から跳んで上がる
## 2. 足ひれ（泳ぐ）で北へ泳ぐ（流れに東へ運ばれながら、約 4.4 秒）。水面から跳んで北の岸へ上がる
## 3. 南の岸の西の筏（浮くが付いた木の台）に乗り、W を単発で渡して川へ押し出す。流れに乗って船着き場へ
## 船着き場は南の岸から幅 5 の空で隔てる（走って跳んでも届かない。浮いて跳べば届く）。
## 北の岸から高台（3）へは窪みのブロック。
## 協力の近道: 先に渡った人が足ひれ・風船を南の岸へ投げ返す（投げるの届き方 20 m）。高台へはジャンプ×2 で直接。
## ゴール: 高台の奥（北）の窪み（高さ 2、5×2）。鐘を鳴らし、全員がここに集まればクリア。
static func summit_4() -> StageDef:
	var def := World7Stages._base(SUMMIT_4, "流れの上の鐘", 16)
	var m := IslandMap.blank(Vector2i(-18, -32), 40, 42)
	m.fill(-10, 0, 10, 8, 1)
	m.fill(ISLET_MIN.x, ISLET_MIN.y, ISLET_MAX.x, ISLET_MAX.y, 1)
	m.fill(16, -11, 19, -1, 1)
	m.fill(-10, -20, 19, -12, 1)
	m.fill(-6, -30, 6, -21, 3)
	var goal := OpenIslands.goal_hollow(m, -2, -29, 2, -28)
	World7Stages._lift(def, m, Vector2i(0, -20), "terrace_lift")
	def.terrain_boxes = m.boxes()
	_river(def.nature, Vector2i(-14, -11), Vector2i(15, -1), 0, -6)
	var raft := StageDef.BlockSpec.new("raft", Vector3i(-8, 1, 0))
	raft.color = RAFT_COLOR
	raft.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.FLOAT))
	def.blocks.append(raft)
	def.bells = [StageDef.BellSpec.new("river_bell", Vector3(0.5, 1.0, -6.5))]
	var kit := World7Stages._nut_creature(def, "river_creature", Vector3(0.5, 1.0, -3.5))
	kit.look = Creature.MODEL_KIT  # 枠の住む生き物（kit）と同じ見た目
	World7Stages._item(
		def, RuleAction.Kind.SWIM, Vector3(6.5, 1.0, 4.5), RuleVessel.Part.NONE, "足ひれ"
	)
	World7Stages._item(def, RuleAction.Kind.FLOAT, Vector3(-4.5, 1.0, 5.5))
	def.spawn_points = World7Stages._spawns(Vector3(0.0, 1.0, 6.5))
	def.checkpoints = [Vector3(-3.5, 1.0, 2.5), Vector3(12.5, 1.0, -14.5)]
	def.clear_condition = World7Stages._bells_and_goal(def, goal)
	return def


## 7-5 みんなの橋（目安 18 分・仮）。新しい組み合わせ: 重さの板 2 枚×範囲で渡す×生き物×ワープの石。
## 南の島（高さ 1）の北に、高さ 4 の岩囲い。中にワープの石があり、幅 10 の空の向こうの北の島（1）へ渡る。
## 囲いの南の壁に扉が 3 つ:
## - 二つ板の扉（西）: 平らな板 2 枚（西・東）が両方押されている間だけ開く
## - 小山の扉（真ん中）: 小山（高さ 2）の上の板と、東の平らな板が両方押されている間だけ開く
## - 内の扉（東）: 囲いの中の板が押されている間だけ開く（先に入った人が仲間を入れる）
## 板を押す道（ひとりで）:
## 1. 範囲で渡す: 板の南の 2 つの石に、範囲で W を繰り返しで渡すと、2 つとも北へすべり、石垣で止まって
##    2 枚の板に乗る → 二つ板の扉
## 2. 生き物（願い: もっと高い所へ）に移動とジャンプを渡すと小山へ跳び乗って板を押し続ける。東の石だけを
##    すべらせて東の板へ → 小山の扉
## 協力の近道: 人が板に立つ（2 人なら、1 人と石 1 つ）。先に入った人が内の板に立てば、外の人も入れる。
## 北の島: 窪みのブロックで高台（3）へ。鐘を鳴らし、全員が高台の奥の窪みに集まればクリア。
static func summit_5() -> StageDef:
	var def := World7Stages._base(SUMMIT_5, "みんなの橋", 18)
	var m := IslandMap.blank(Vector2i(-16, -38), 34, 48)
	m.fill(-10, -2, 10, 8, 1)
	# 小山（2）と、石を止める石垣（4）
	m.fill(KNOLL_PLATE.x, KNOLL_PLATE.z, KNOLL_PLATE.x, KNOLL_PLATE.z, 2)
	m.fill(WEST_PLATE.x, 1, WEST_PLATE.x, 1, 4)
	m.fill(EAST_PLATE.x, 1, EAST_PLATE.x, 1, 4)
	# 岩囲い（壁 4・床 1）と、南の壁の扉の 3 マス
	m.fill(-3, -10, 3, -3, 4)
	m.fill(-2, -9, 2, -4, 1)
	m.fill(-1, -3, 1, -3, 1)
	# 北の島（1）と高台（3）
	m.fill(-8, -30, 8, -20, 1)
	m.fill(-6, -36, 6, -31, 3)
	var goal := OpenIslands.goal_hollow(m, -2, -35, 2, -34)
	World7Stages._lift(def, m, Vector2i(0, -30), "isle_lift")
	def.terrain_boxes = m.boxes()
	for spec: Array in [["west_stone", Vector3i(-2, 1, 6)], ["east_stone", Vector3i(2, 1, 6)]]:
		var stone := StageDef.BlockSpec.new(String(spec[0]), spec[1] as Vector3i)
		stone.color = World7Stages.STONE_COLOR
		def.blocks.append(stone)
	_bridge_mechanisms(def.mechanisms)
	def.creatures.append(StageDef.CreatureSpec.new("knoll_creature", Vector3(-5.5, 1.0, 2.5)))
	def.bells = [StageDef.BellSpec.new("bridge_bell", Vector3(4.5, 3.0, -34.5))]
	def.spawn_points = World7Stages._spawns(Vector3(0.0, 1.0, 7.5))
	def.checkpoints = [Vector3(-7.5, 1.0, 6.5), Vector3(5.5, 1.0, -22.5)]
	def.clear_condition = World7Stages._bells_and_goal(def, goal)
	return def


## 7-5 の仕掛け: 板 4 枚（西・東・小山・囲いの中）と扉 3 つ、ワープの石の対。
static func _bridge_mechanisms(mech: MechanismSpecs) -> void:
	mech.plates = [
		MechanismSpecs.PlateSpec.new("west_plate", WEST_PLATE),
		MechanismSpecs.PlateSpec.new("east_plate", EAST_PLATE),
		MechanismSpecs.PlateSpec.new("knoll_plate", KNOLL_PLATE),
		MechanismSpecs.PlateSpec.new("inner_plate", Vector3i(2, 1, -5)),
	]
	var twin := MechanismSpecs.DoorSpec.new(
		"twin_gate", Vector3i(-1, 1, -3), PackedStringArray(["west_plate", "east_plate"])
	)
	twin.require_all = true
	var knoll := MechanismSpecs.DoorSpec.new(
		"knoll_gate", Vector3i(0, 1, -3), PackedStringArray(["knoll_plate", "east_plate"])
	)
	knoll.require_all = true
	var inner := MechanismSpecs.DoorSpec.new(
		"inner_gate", Vector3i(1, 1, -3), PackedStringArray(["inner_plate"])
	)
	mech.doors = [twin, knoll, inner]
	for door: MechanismSpecs.DoorSpec in mech.doors:
		door.size = Vector3i(1, 3, 1)  # 上面を壁と同じ高さ 4 にする
	mech.warps = [
		MechanismSpecs.WarpSpec.new("cage_warp", Vector3i(0, 1, -7), "isle_warp"),
		MechanismSpecs.WarpSpec.new("isle_warp", Vector3i(0, 1, -22), "cage_warp"),
	]


## 7-6 頂の祭り（目安 45 分・仮。★ 難しい。ゲームの最終ステージ）。ワールド 7 の仕掛けを全部重ねた、
## チェックポイント 5 つの長い登り。南の雲の野原（1）→ 空の谷 → 川の南の岸（0）→ 川 → 塔のふもと（0）→
## 塔の段（2）→ 上の段（4）→ 頂（6）。頂の奥の窪みがゴールで、全員がそろうと祭りが始まる（SummitFestival）。
## 1. 空の谷（幅 11）: 風船（浮く）で追い風の通り道に乗る／風船とダッシュを重ねてどこでも越える／
##    おもり（重い）を持って西の尾根の突風を歩く（やむ間に進んでもよい）
## 2. 川（幅 11、東へ流れる）: 足ひれで泳ぐ／浮いて東の端の氷の船着き場まで流される／筏に乗って押し出す。
##    川の小島の鐘は、小島の生き物に「投げる」を投げ渡すか、泳いで上がって触る
## 3. 塔の段: 風の通り道の木箱（重い付き）を風に運ばせて 4 人分の板に乗せ、重いを渡し直して石段の扉を開ける／
##    札付きの台の札を手放して乗る
## 4. 上の段: 突風の棚を、重いを持って（またはやむ間に）登る
## 5. 頂: 時の鐘（3.5 秒）で開く扉。自分で鳴らして走るか、時の鐘のそばの生き物に「投げる」を投げ渡す
## 組み合わせの読み合い:
## - 「投げる」は 1 つ。川の生き物に渡すと、小島へ泳いで行かない限り取り戻せない（頂の生き物には使えない）
## - 浮くと重いは数で打ち消し合う。風船を持ったまま重いを持つと、突風に流される（風船はかばんへ戻す）
## 協力の近道: W×2 で浮けば空の谷のどこでも越える。風船・足ひれは谷・川越しに投げ返せる。重いを持った人が
##   板に立って扉を開けておく。段差 2 はジャンプ×2。頂の扉は先に入った人が内側の板に立つ。
## ゴール: 頂の奥（北）の窪み（高さ 5、5×2）。川の鐘と時の鐘を鳴らし、全員がここに集まればクリア。
static func summit_6() -> StageDef:
	var def := World7Stages._base(SUMMIT_6, "頂の祭り", 45)
	def.festival = true
	var m := IslandMap.blank(Vector2i(-24, -82), 50, 94)
	_festival_south(def, m)
	_festival_north(def, m)
	var goal := OpenIslands.goal_hollow(m, -3, -78, 1, -77)
	var signed := World7Stages._lift(def, m, Vector2i(4, -46), "signed_lift")
	signed.color = World7Stages.SIGN_COLOR
	signed.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.JUMP, true))
	def.terrain_boxes = m.boxes()
	# 氷の船着き場（東の端。川から上がったら北へすべって進む）
	def.terrain_boxes.append([Vector3i(18, -1, -35), Vector3i(21, -1, -25), "ice"])
	_river(def.nature, Vector2i(-18, -35), Vector2i(17, -25), -1, -30)
	_festival_winds(def.nature)
	_festival_blocks(def)
	_festival_mechanisms(def.mechanisms)
	def.bells = [StageDef.BellSpec.new("river_bell", Vector3(0.5, 0.0, -30.5))]
	World7Stages._nut_creature(def, "river_creature", Vector3(0.5, 0.0, -27.5))
	World7Stages._nut_creature(def, "chime_creature", Vector3(-7.5, 4.0, -56.5))
	World7Stages._item(def, RuleAction.Kind.FLOAT, Vector3(4.5, 1.0, 4.5))
	World7Stages._item(def, RuleAction.Kind.HEAVY, Vector3(-5.5, 1.0, 5.5))
	World7Stages._item(def, RuleAction.Kind.DASH, Vector3(6.5, 1.0, 7.5))
	World7Stages._item(
		def, RuleAction.Kind.SWIM, Vector3(6.5, 0.0, -14.5), RuleVessel.Part.NONE, "足ひれ"
	)
	def.spawn_points = World7Stages._spawns(Vector3(0.0, 1.0, 7.5))
	def.checkpoints = [
		Vector3(-2.5, 1.0, 3.5),
		Vector3(-6.5, 0.0, -14.5),
		Vector3(-3.5, 0.0, -40.5),
		Vector3(2.5, 2.0, -51.5),
		Vector3(2.5, 4.0, -60.5),
	]
	def.clear_condition = World7Stages._bells_and_goal(def, goal)
	return def


## 7-6 の南半分: 雲の野原（1）と西の尾根、川の南の岸（0）、川の小島（0）、東の船着き場（0）。
static func _festival_south(_def: StageDef, m: IslandMap) -> void:
	m.fill(-8, 0, 8, 10, 1)
	m.fill(-14, 2, -9, 2, 1)
	m.fill(-14, -11, -14, 2, 1)
	m.fill(-16, -7, -14, -5, 1)
	m.fill(-16, -24, 12, -12, 0)
	m.fill(-1, -32, 1, -28, 0)
	m.fill(18, -35, 21, -25, 0)


## 7-6 の北半分: 塔のふもと（0）と風の通り道、塔の段（2）と石段、突風の棚、上の段（4）、頂（6）と石段。
static func _festival_north(_def: StageDef, m: IslandMap) -> void:
	m.fill(-16, -46, 21, -36, 0)
	m.fill(-20, -47, -9, -45, 0)
	m.fill(-8, -55, 10, -47, 2)
	m.fill(-7, -47, -7, -47, 0)
	m.fill(-7, -48, -7, -48, 1)
	m.fill(10, -64, 10, -56, 3)
	m.fill(9, -60, 11, -59, 3)
	m.fill(7, -64, 9, -64, 4)
	m.fill(-8, -67, 6, -56, 4)
	m.fill(-6, -79, 4, -68, 6)
	m.fill(-1, -68, -1, -68, 4)
	m.fill(-1, -69, -1, -69, 5)


## 7-6 の風: 空の谷の追い風（北へ）、西の尾根の突風、塔のふもとの風の通り道（東へ）、突風の棚。
static func _festival_winds(nature: NatureLayout) -> void:
	nature.add_wind(World7Stages.FOOT_LANE_MIN, World7Stages.FOOT_LANE_MAX, Vector3i(0, 0, -1))
	var gusts: Array = [
		[Vector3i(-14, -3, -11), Vector3i(-13, 4, -8), Vector3i(-1, 0, 0)],
		[Vector3i(-14, -3, -4), Vector3i(-13, 4, -1), Vector3i(-1, 0, 0)],
		[Vector3i(10, 2, -58), Vector3i(11, 6, -56), EAST],
		[Vector3i(10, 2, -64), Vector3i(11, 6, -61), EAST],
	]
	nature.add_wind(FESTIVAL_CHANNEL_MIN, FESTIVAL_CHANNEL_MAX, EAST)
	for g: Array in gusts:
		var gust := nature.add_pulsing_wind(
			g[0] as Vector3i, g[1] as Vector3i, g[2] as Vector3i, 6.0, 3.5
		)
		gust.strength = World7Stages.GUST_STRENGTH


## 7-6 のブロック: 筏（川の南の岸の西）と、風の通り道の奥の木箱（重い付き）。
static func _festival_blocks(def: StageDef) -> void:
	var raft := StageDef.BlockSpec.new("raft", Vector3i(-8, 0, -24))
	raft.color = RAFT_COLOR
	raft.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.FLOAT))
	var crate := StageDef.BlockSpec.new("crate", Vector3i(-19, 0, -46))
	crate.color = World7Stages.STONE_COLOR
	crate.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.HEAVY))
	def.blocks.append_array([raft, crate])


## 7-6 の仕掛け: 風の通り道の出口の板（4 人分）と石段の扉、頂の時の鐘と扉・内側の板（7-3 と同じ形）。
static func _festival_mechanisms(mech: MechanismSpecs) -> void:
	var plate := MechanismSpecs.PlateSpec.new("crate_plate", FESTIVAL_CRATE_PLATE)
	plate.required_weight = 4
	var inner := MechanismSpecs.PlateSpec.new("gate_plate", Vector3i(-1, 5, -69))
	mech.plates = [plate, inner]
	mech.timed_bells = [
		MechanismSpecs.TimedBellSpec.new("summit_chime", Vector3(-7.5, 4.0, -60.5), 3.5)
	]
	mech.doors = [
		MechanismSpecs.DoorSpec.new(
			"stair_gate", Vector3i(-7, 0, -47), PackedStringArray(["crate_plate"])
		),
		MechanismSpecs.DoorSpec.new(
			"summit_gate", Vector3i(-1, 4, -68), PackedStringArray(["summit_chime", "gate_plate"])
		),
	]


## 東へ流れる川（底なし）。from〜to（x・z、両端を含む）を水にし、小島（x は ISLET_MIN〜MAX、z は
## islet_center_z の前後 2 マス）の上だけ空ける（水の下に地形を置けないので、小島のまわりを 4 つに分ける）。
## top_cell は岸の地面のいちばん上のセル（水面はその上面より少し下）。
static func _river(
	nature: NatureLayout, from: Vector2i, to: Vector2i, top_cell: int, islet_center_z: int
) -> void:
	var lo := top_cell - 2
	var islet_lo := Vector2i(ISLET_MIN.x, islet_center_z - 2)
	var islet_hi := Vector2i(ISLET_MAX.x, islet_center_z + 2)
	var pieces: Array = [
		[Vector2i(from.x, from.y), Vector2i(islet_lo.x - 1, to.y)],
		[Vector2i(islet_hi.x + 1, from.y), Vector2i(to.x, to.y)],
		[Vector2i(islet_lo.x, from.y), Vector2i(islet_hi.x, islet_lo.y - 1)],
		[Vector2i(islet_lo.x, islet_hi.y + 1), Vector2i(islet_hi.x, to.y)],
	]
	for piece: Array in pieces:
		var a := piece[0] as Vector2i
		var b := piece[1] as Vector2i
		nature.add_current(Vector3i(a.x, lo, a.y), Vector3i(b.x, top_cell, b.y), EAST)
