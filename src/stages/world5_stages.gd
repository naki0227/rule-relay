class_name World5Stages
extends RefCounted
## ワールド 5「札の庭」の新しいステージ（5-1・5-2・5-4・5-5）。5-3 札の庭・5-6 砦跡は既存（OpenIslandsExtra・
## OpenIslandsMore）。主役は札（禁止）で、ワールドの後半はこれまでの仕掛け（氷・重い・重さの板）と組み合わせる。
## 計画の表は docs/campaign-plan.md。どのステージも開けたひとつながりの島で、ゴールへの道は何通りもある。
## 数値の目安（Tuning）: 自分のジャンプ 1.3（2 段は無理）・ブーツ 2.3・ブロックのジャンプ 2.5・走って跳ぶと幅 3。
## 受け入れた技（縁ちょうどの幅 4・ブロックの上昇＋自分のジャンプ・どの地面のセルも持ち上げ台）は止めない。
## クリアは「島の条件＋生きている全員がゴールの窪み（OpenIslands.goal_hollow）に集まる」。
## 各ステージに願いを持つ動物がいて、その願いが解き方の一部になる（クリアすると広場に住む）。
## 配置・目安時間はすべて仮（本人の試遊で直す）。

const FIRST_ID := "w5_first_signs"
const RANGE_ID := "w5_range_signs"
## 5-2: 生き物が乗る小山（高さ 1）の上の板。生き物がここにいることが島の条件。
const RANGE_MOUND := Vector2i(-10, -4)
const RANGE_NEST := AABB(Vector3(-10.2, 0.8, -4.2), Vector3(1.4, 1.6, 1.4))
const ICE_ID := "w5_ice_garden"
## 5-4: 石を止める杭と、台地の崖の棚（高さ 2）の列。
const ICE_POST := Vector2i(5, 2)
const ICE_PIER_X := 4
const RELAY_ID := "w5_sign_relay"
## 5-5: もこもこが乗る小山（高さ 1。上に 4 人分の重さの板）。
const RELAY_MOUND := Vector2i(-8, 4)
const RELAY_NEST := AABB(Vector3(-8.2, 0.8, 3.8), Vector3(1.4, 1.6, 1.4))


## 5-1 はじめての札（目安 7 分・仮）。原っぱ（高さ 0）と段（2）。段の上の鐘を鳴らし、段の奥の窪みに集まる。
## 新しいこと: 置かれた札（禁止）を F で回収すると自分に来る。手放す（ホットバーへ移して何かへ渡す）と使える。
## - 段の手前の持ち上げ台には「ジャンプ禁止」の札。回収して手放してから、ジャンプを貸して乗る
## - 原っぱの石には「W 禁止」の札。回収すると自分が前へ歩けなくなるので手放し、W を繰り返しで渡すと、
##   石が段の壁まで進んで 1 段の足場になる
## 願いを持つ動物: 段の縁で木の実を持ったうさぎが鐘の方（北）を向いている。願いは「木の実で鐘を鳴らしたい」。
##   ただし「投げる禁止」の札が付いていて、投げるを渡しても投げない。原っぱから F で札を回収してから
##   「投げる」を触って渡すと、木の実で鐘を鳴らす（札が来たので投げるの届き方は使えなくなる）。
## 協力の近道: ジャンプ×2 で段差 2 を直接跳ぶ（札に触らずに済む）。
## ゴール: 段の奥（北）の窪み（高さ 1、5×2）。
static func first_signs() -> StageDef:
	var def := StageParts.base(FIRST_ID, "はじめての札", 7)
	var m := IslandMap.blank(Vector2i(-14, -20), 29, 31)
	m.fill(-12, -4, 12, 9, 0)
	m.fill(-12, -18, 12, -5, 2)
	var goal := OpenIslands.goal_hollow(m, -2, -17, 2, -16)
	var lift := StageParts.lift(def, m, Vector2i(-6, -4), "sign_lift", StageParts.SIGN_COLOR)
	StageParts.sign(lift.tokens, RuleAction.Kind.JUMP)
	def.terrain_boxes = m.boxes()
	var walker := StageParts.stone(def, "sign_stone", Vector3i(6, 0, 2), StageParts.SIGN_COLOR)
	StageParts.sign(walker.tokens, RuleAction.Kind.FORWARD)
	var bunny := StageParts.animal(def, "sign_bunny", Vector3(0.5, 2.0, -6.5), "木の実")
	StageParts.sign(bunny.tokens, RuleAction.Kind.THROW)
	def.bells = [StageDef.BellSpec.new("terrace_bell", Vector3(0.5, 2.0, -9.5))]
	def.spawn_points = StageParts.spawns(Vector3(0.0, 0.0, 6.5))
	def.checkpoints = [Vector3(-9.5, 0.0, 3.5)]
	def.clear_condition = StageParts.bells_and_goal(def, goal)
	return def


## 5-2 まとめて渡す札（目安 9 分・仮）。中庭（高さ 0）と北の台地（2）。台地へ上がる階段（1）の上に扉がある。
## 新しいこと: 範囲で渡す（右クリック。半径 5 の同じ高さのブロックに 1 つの能力・禁止がまとめて効く）。
## 扉は 3 枚の重さの板が全部押されている間だけ開く（スイッチの扉、HELD・全部）。
## - 中庭の 2 枚の板: すぐ南の石 2 つを北へ 1 マス動かす。W を範囲で単発に渡せば 1 回で 2 つとも乗る
##   （1 つずつ単発で渡してもよい。単発は使うと手元に戻る）
## - 西の小山（高さ 1）の上の板: 願いを持つ動物（もこもこの子）が乗る
## 願いを持つ動物: 小山のそばのもこもこ。願いは「高いところへ行きたい」。移動を 1 つとジャンプを渡すと、
##   小山（まわりでいちばん高い所）へ跳び乗って板を押す。乗ったら F で能力を取り戻してよい（降りない）。
##   小山に乗っていることがクリアの条件（いないと、全員がゴールに集まってもクリアしない）。
## 協力の近道: ジャンプ×2 で段差 2 を直接跳ぶ（扉を開けない）。動物の願いは協力でも要る。
## ゴール: 台地の奥（北）の窪み（高さ 1、5×2）。
static func range_signs() -> StageDef:
	var def := StageParts.base(RANGE_ID, "まとめて渡す札", 9)
	var m := IslandMap.blank(Vector2i(-14, -24), 29, 37)
	m.fill(-12, -10, 12, 10, 0)
	m.fill(-12, -22, 12, -11, 2)
	# 台地への階段（高さ 1）と、西の小山（高さ 1）
	m.fill(7, -10, 9, -10, 1)
	m.fill(RANGE_MOUND.x, RANGE_MOUND.y, RANGE_MOUND.x, RANGE_MOUND.y, 1)
	var goal := OpenIslands.goal_hollow(m, -2, -21, 2, -20)
	def.terrain_boxes = m.boxes()
	StageParts.stone(def, "stone_west", Vector3i(-1, 0, -1))
	StageParts.stone(def, "stone_east", Vector3i(1, 0, -1))
	var lamb := StageParts.animal(def, "mound_lamb", Vector3(-10.5, 0.0, -1.5))
	lamb.look = Creature.MODEL_KIT
	var mech := def.mechanisms
	mech.plates = [
		MechanismSpecs.PlateSpec.new("plate_west", Vector3i(-1, 0, -2)),
		MechanismSpecs.PlateSpec.new("plate_east", Vector3i(1, 0, -2)),
		MechanismSpecs.PlateSpec.new("plate_mound", Vector3i(RANGE_MOUND.x, 1, RANGE_MOUND.y)),
	]
	var gate := MechanismSpecs.DoorSpec.new(
		"stair_gate", Vector3i(7, 2, -11), ["plate_west", "plate_east", "plate_mound"]
	)
	gate.size = Vector3i(3, 2, 1)
	gate.require_all = true
	mech.doors = [gate]
	def.spawn_points = StageParts.spawns(Vector3(0.0, 0.0, 7.5))
	def.checkpoints = [Vector3(5.5, 0.0, 4.5)]
	def.clear_condition = ClearCondition.all_of(
		[ClearCondition.carry_object("mound_lamb", RANGE_NEST), ClearCondition.all_at_goal(goal)]
	)
	return def


## 5-4 氷の庭（目安 10 分・仮）。南の岸（高さ 0）・氷の池（0、止まれない床）・北の台地（3）。
## 台地の崖は高さ 3 で、東寄り（x = 3〜5）の 3 マスだけ高さ 2 の棚が張り出している（棚から台地へは 1 段）。
## 新しいこと: 氷の上ではブロックも人もすべり、塞がれるか氷が終わるまで止まらない。
## - 池の石には「D 禁止」の札。回収して手放し、D を単発で渡すと東へすべって石の杭で止まる（x = 4）。
##   W を単発で渡すと北へすべり、棚の下の崖で止まる（x = 4） → 石（1）→ 棚（2）→ 台地（3）の階段になる。
##   まっすぐ北へすべらせると棚のない列で止まり、崖（3）には届かない。
##   札を持っている間は D で歩けないが、氷の上なら勢いで右へすべっていける（札は行動だけを止める）
## - 岸の東の隅のブーツ（2.3）なら、池から棚（2）へ跳べる
## 願いを持つ動物: 台地の縁で木の実を持ったうさぎが北の鐘を向いている。願いは「木の実で鐘を鳴らしたい」。
##   池から「投げる」を投げて渡す（遠くへ渡す）か、台地に上がって触って渡すと、木の実で鐘を鳴らす。
## 協力の近道: ジャンプ×2 で池から棚へ直接跳ぶ（石を動かさない）。
## ゴール: 台地の奥（北）の窪み（高さ 2、5×2）。
static func ice_garden() -> StageDef:
	var def := StageParts.base(ICE_ID, "氷の庭", 10)
	var m := IslandMap.blank(Vector2i(-14, -22), 29, 36)
	m.fill(-10, 5, 10, 11, 0)
	m.fill(-10, -20, 10, -8, 3)
	m.fill(ICE_PIER_X - 1, -8, ICE_PIER_X + 1, -8, 2)
	# 石の杭（高さ 1）
	m.fill(ICE_POST.x, ICE_POST.y, ICE_POST.x, ICE_POST.y, 1)
	var goal := OpenIslands.goal_hollow(m, -2, -19, 2, -18)
	def.terrain_boxes = m.boxes()
	StageParts.ice(def, Vector2i(-10, -7), Vector2i(10, 1))
	StageParts.ice(def, Vector2i(-10, 2), Vector2i(ICE_POST.x - 1, 2))
	StageParts.ice(def, Vector2i(ICE_POST.x + 1, 2), Vector2i(10, 2))
	StageParts.ice(def, Vector2i(-10, 3), Vector2i(10, 4))
	var slider := StageParts.stone(def, "ice_stone", Vector3i(-5, 0, 2), StageParts.SIGN_COLOR)
	StageParts.sign(slider.tokens, RuleAction.Kind.RIGHT)
	StageParts.animal(def, "ice_bunny", Vector3(-5.5, 3.0, -9.5), "木の実")
	def.bells = [StageDef.BellSpec.new("ice_bell", Vector3(-5.5, 3.0, -12.5))]
	StageParts.boots(def, Vector3(9.5, 0.0, 9.5))
	def.spawn_points = StageParts.spawns(Vector3(0.0, 0.0, 8.5))
	def.checkpoints = [Vector3(-7.5, 0.0, 8.5)]
	def.clear_condition = StageParts.bells_and_goal(def, goal)
	return def


## 5-5 札の受け渡し（目安 12 分・仮）。南の庭（0）・生け垣（3）・中の原（0）・北の台地（2）。
## 生け垣の門（扉 A）は、東の小島の「重い」石が板を押している間は閉じている（逆の扉）。台地への階段の
## 扉 B は、南の庭の小山の板（4 人分の重さ）が押されている間だけ開く。
## 新しいこと（組み合わせ）: 札を遠くの石・生き物へ渡す × 重い × 重さの板。
## - 扉 A: 小島の石は谷（幅 5）の向こうで、F（触る距離）が届かない。
##   (1) もこもこに付いた「重い禁止」の札を回収し、投げる届き方で石へ投げ渡す → 石が軽くなり門が開く
##   (2) ダッシュを拾い、跳んでから空中でダッシュして小島へ渡り、石の「重い」を F で回収する
## - 扉 B: もこもこに「重い」・移動・ジャンプを渡すと、願いどおり小山（いちばん高い所）へ跳び乗り、
##   4 人分の重さで板を押す。重いは庭のおもり（拾える物）か、小島の石から回収したもの
## 願いを持つ動物: 南の庭のもこもこ。願いは「高いところへ行きたい」（「重い禁止」の札を持っている）。
##   小山の上にいることがクリアの条件。
## 協力の近道: 仲間の W で W×2（速さ 2 倍）にすれば、ダッシュを拾わずに幅 5 を走って跳べる。
## ゴール: 台地の奥（北）の窪み（高さ 1、5×2）。
static func sign_relay() -> StageDef:
	var def := StageParts.base(RELAY_ID, "札の受け渡し", 12)
	var m := IslandMap.blank(Vector2i(-16, -30), 38, 44)
	m.fill(-12, -2, 12, 11, 0)
	m.fill(-12, -4, 12, -3, 3)
	m.fill(-1, -4, 1, -3, 0)
	m.fill(-12, -16, 12, -5, 0)
	m.fill(-12, -28, 12, -17, 2)
	m.fill(7, -16, 9, -16, 1)
	m.fill(RELAY_MOUND.x, RELAY_MOUND.y, RELAY_MOUND.x, RELAY_MOUND.y, 1)
	# 東の小島（谷の幅 5）
	m.fill(18, 3, 20, 6, 0)
	var goal := OpenIslands.goal_hollow(m, -2, -27, 2, -26)
	var heavy := StageParts.lift(def, m, Vector2i(19, 4), "heavy_stone", StageParts.STONE_COLOR)
	heavy.tokens.append(StageDef.TokenSpec.new(RuleAction.Kind.HEAVY))
	def.terrain_boxes = m.boxes()
	var lamb := StageParts.animal(def, "relay_lamb", Vector3(-9.5, 0.0, 6.5))
	lamb.look = Creature.MODEL_KIT
	StageParts.sign(lamb.tokens, RuleAction.Kind.HEAVY)
	var mech := def.mechanisms
	var island_plate := MechanismSpecs.PlateSpec.new("island_plate", Vector3i(19, -1, 4))
	island_plate.required_weight = 2
	var mound_plate := MechanismSpecs.PlateSpec.new(
		"mound_plate", Vector3i(RELAY_MOUND.x, 1, RELAY_MOUND.y)
	)
	mound_plate.required_weight = 4
	mech.plates = [island_plate, mound_plate]
	var hedge_gate := MechanismSpecs.DoorSpec.new(
		"hedge_gate", Vector3i(-1, 0, -4), ["island_plate"]
	)
	hedge_gate.size = Vector3i(3, 3, 2)
	hedge_gate.inverted = true
	var stair_gate := MechanismSpecs.DoorSpec.new(
		"stair_gate", Vector3i(7, 2, -17), ["mound_plate"]
	)
	stair_gate.size = Vector3i(3, 2, 1)
	mech.doors = [hedge_gate, stair_gate]
	StageParts.item(def, RuleAction.Kind.HEAVY, Vector3(-4.5, 0.0, 8.5))
	StageParts.item(def, RuleAction.Kind.DASH, Vector3(8.5, 0.0, 9.5))
	def.spawn_points = StageParts.spawns(Vector3(0.0, 0.0, 8.5))
	def.checkpoints = [Vector3(3.5, 0.0, 8.5), Vector3(5.5, 0.0, -8.5)]
	def.clear_condition = ClearCondition.all_of(
		[ClearCondition.carry_object("relay_lamb", RELAY_NEST), ClearCondition.all_at_goal(goal)]
	)
	return def
