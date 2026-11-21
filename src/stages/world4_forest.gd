class_name DeepForest
extends RefCounted
## 4-6 森の奥（ワールド 4 の最後。難しい★。目安 15 分・仮）。生き物×重さの板×投げるの組み合わせ。島はどれも高さ 1。
## 東のゴールの島へは幅 10 の空。橋は、台の上の重さの板（4 人分）か、原っぱの石の板（4 人分）か、ゴールの島の
## 小さな板（1 人分）が押されている間だけ架かる。4 人分にするには「重い」が要るが、おもりは西の岩の檻の中。
## 檻の扉は、北の島（幅 9 の向こう、手が届かない）の時の鐘（8 秒）が鳴っている間だけ開く。
##
## 檻を開ける（どちらか）:
## - 北の島の子ども（ジャンプと木の実を持っている）に D を「投げる」の届き方で投げ渡す → 北を向いたまま
##   横歩きで東の岩（高さ 2）へ上がる。そこへ「投げる」を投げ渡すと、北の柱の上の鐘を木の実で鳴らす
##   （8 秒のうちにおもりを取る）
## - 北の島の棚の発射台は鐘と 1 マスずれている。S を単発で投げ渡して 1 マス押し、「投げる」を投げ渡すと、
##   周期ごとに鐘を撃ち続けて檻が開いたままになる
## 橋を架ける（どちらか）:
## - 願いの動物にジャンプ・動く能力・重いを渡す → 願いで台へ上がって板を押す（自分はジャンプなしで渡る）
## - 石に重いを渡し、D を単発で渡して石の板へ 1 マス押す。願いの動物にはジャンプと動く能力を渡して台へ
##   上げ、ふもとから F で取り戻して渡る
## 動く能力は 4 つ。子どもと願いの動物に 1 つずつ投げ渡すと、残りは 2 つ（W を残せば歩ける）。
## 願い: 動物が台に上がること。
## ゴール: 東の島の窪み（高さ 0、2×4）。手前の岩の尾根（高さ 3）が原っぱへの光線を遮る。

const ID := "w4_deep_forest"
const DAIS := Vector2i(5, 1)
const CAGE_BELL := Vector3(-5.5, 2.0, -14.5)
const HEAVY_AT := Vector3(-6.5, 1.0, 2.5)


static func build() -> StageDef:
	var def := CampaignKit.base(ID, "森の奥", 15)
	var m := IslandMap.blank(Vector2i(-10, -18), 37, 30)
	m.fill(-8, 0, 8, 10, 1)
	# 西の岩の檻（高さ 5）。奥行き 2 の穴（床は高さ 1、屋根つき）に、おもりがある。東の口が扉
	m.fill(-8, 0, -5, 3, 5)
	m.fill(-7, 2, -5, 2, 1)
	m.fill(DAIS.x, DAIS.y, DAIS.x + 1, DAIS.y + 1, 2)
	# 北の島（幅 9）: 子どもの岩と鐘の柱。発射台の棚は東に 1 マス離れた小島（ブロックの上も「立てる高さ」
	# なので、つながっていると子どもが発射台の上へ上がってしまう）
	m.fill(-8, -16, -5, -10, 1)
	m.fill(-6, -12, -6, -12, 2)
	m.fill(-6, -15, -6, -15, 2)
	m.fill(-3, -16, -2, -15, 2)
	# 東のゴールの島（幅 10）
	m.fill(19, 1, 25, 10, 1)
	m.fill(21, 3, 21, 8, 3)
	var goal := OpenIslands.goal_hollow(m, 23, 4, 24, 7)
	def.terrain_boxes = m.boxes()
	# 檻の穴の屋根（岩の上から重ね跳びで穴へ降りられないように、上面を岩とそろえて塞ぐ。中は高さ 3）
	def.terrain_boxes.append([Vector3i(-7, 4, 2), Vector3i(-6, 4, 2), "rock"])
	var launcher := StageDef.BlockSpec.new("launcher", Vector3i(-3, 2, -16))
	launcher.launcher_direction = Vector3i(-1, 0, 0)
	def.blocks.append(launcher)
	CampaignKit.stone(def, "weight_stone", Vector3i(1, 1, 6))
	_add_mechanisms(def.mechanisms)
	CampaignKit.bridge(
		def,
		"forest_bridge",
		Vector2i(9, 5),
		Vector2i(10, 2),
		1,
		PackedStringArray(["dais_plate", "stone_plate", "far_plate"])
	)
	CampaignKit.wish_creature(
		def, "kit", Vector3(-7.5, 1.0, -11.5), Creature.MODEL_KIT, [RuleAction.Kind.JUMP], "木の実"
	)
	CampaignKit.wish_creature(def, "forest_wish", Vector3(4.5, 1.0, 1.5))
	CampaignKit.item(def, RuleAction.Kind.HEAVY, HEAVY_AT)
	def.spawn_points = CampaignKit.spawns(Vector3(0.0, 1.0, 8.5))
	def.checkpoints = [Vector3(-1.5, 1.0, 5.5), Vector3(20.5, 1.0, 2.5)]
	def.clear_condition = CampaignKit.clear_with(
		goal, {"forest_wish": CampaignKit.perch_box(DAIS, 2, Vector2i(2, 2))}
	)
	return def


static func _add_mechanisms(mech: MechanismSpecs) -> void:
	mech.timed_bells = [MechanismSpecs.TimedBellSpec.new("cage_bell", CAGE_BELL, 8.0)]
	var cage := MechanismSpecs.DoorSpec.new(
		"cage_door", Vector3i(-5, 1, 2), PackedStringArray(["cage_bell"])
	)
	cage.size = Vector3i(1, 4, 1)
	mech.doors = [cage]
	var dais := MechanismSpecs.PlateSpec.new("dais_plate", Vector3i(DAIS.x, 2, DAIS.y))
	dais.size = Vector2i(2, 2)
	dais.required_weight = 4
	var stone := MechanismSpecs.PlateSpec.new("stone_plate", Vector3i(2, 1, 6))
	stone.required_weight = 4
	mech.plates = [dais, stone, MechanismSpecs.PlateSpec.new("far_plate", Vector3i(20, 1, 9))]
