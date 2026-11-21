class_name OverworldScenery
extends RefCounted
## 広場の置物（木・草花・小石・街灯・ベンチ）の場所を決める（純粋なデータ。固定シードで毎回同じ）。
## 地方ごとに雰囲気を変える（草原は花、森は木、庭は鉢植え、峰は小石）。どれも見た目だけで当たり判定はない。
## ポータル・建物の予定地・出現地点の前・小さな仕掛けの上には置かない。

const SEED := 20261121
## 出現地点から東へ歩く帯と、導入のポータルまでの道（足もとの小さな草花・小石だけ置く。木や鉢植えで
## 導入のポータルを隠さない）。
const SPAWN_LANE := Rect2(-3.0, 4.0, 24.0, 12.0)
const SMALL: PackedStringArray = ["flower", "grass_tuft", "pebbles"]

## 地方ごとの置物: [中心, 半径, 確率, 置物の種類...]
const REGIONS: Array = [
	[Vector2(2, 3), Vector2(21, 19), 0.1, ["flower", "flower", "grass_tuft", "pebbles"]],
	[Vector2(43, -4), Vector2(15, 18), 0.06, ["grass_tuft", "flower", "tree_round", "pebbles"]],
	[Vector2(41, -46), Vector2(13, 12), 0.05, ["grass_tuft", "flower", "tree_tall"]],
	[Vector2(-41, -6), Vector2(15, 18), 0.09, ["tree_round", "tree_tall", "grass_tuft", "flower"]],
	[Vector2(-41, -48), Vector2(15, 15), 0.06, ["hub_planter", "flower", "flower", "grass_tuft"]],
	[Vector2(0, -38), Vector2(20, 17), 0.05, ["pebbles", "tree_tall", "grass_tuft"]],
	[Vector2(0, -68), Vector2(13, 7), 0.06, ["flower", "grass_tuft"]],
]
## 地方の縁（中心からの距離の割合がこれより外）には、木を多めに置く。
const EDGE := 0.72


static func scatter(layout: OverworldLayout, field: HeightField, def: StageDef) -> void:
	var keep_out := _keep_out(layout, def)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for region: Array in REGIONS:
		var center := region[0] as Vector2
		var radius := region[1] as Vector2
		var chance := float(region[2])
		var kinds := region[3] as Array
		for z in range(floori(center.y - radius.y), ceili(center.y + radius.y) + 1):
			for x in range(floori(center.x - radius.x), ceili(center.x + radius.x) + 1):
				var roll := rng.randf()
				var pick := rng.randi()
				var spin := rng.randf() * TAU
				var size := rng.randf_range(0.8, 1.25)
				var h := field.top(x, z)
				if h < 0 or roll > chance * 2.0:
					continue
				var at := Vector3(x + 0.5, float(h), z + 0.5)
				if _blocked(at, keep_out) or not _flat_around(field, x, z, h):
					continue
				var d := (
					Vector2((at.x - center.x) / radius.x, (at.z - center.y) / radius.y).length()
				)
				var kind := String(kinds[pick % kinds.size()])
				if d > EDGE and roll < chance * 0.6:
					kind = "tree_round" if pick % 3 != 0 else "tree_tall"
				elif roll > chance:
					continue
				if SPAWN_LANE.has_point(Vector2(at.x, at.z)) and not SMALL.has(kind):
					continue
				layout.props.append(OverworldLayout.PropSpec.new(kind, at, spin, size))
	_furnish(layout)
	_island_bases(layout)


## 地方ごとに、浮かぶ島の底の岩を置く（地方の楕円の内側に収まる大きさ）。
static func _island_bases(layout: OverworldLayout) -> void:
	var islands: Array = []
	for i in REGIONS.size():
		if i != 2:  # 浮島は 1 つずつ（島のあいだの空を埋めない）
			islands.append([REGIONS[i][0], REGIONS[i][1]])
	for center: Vector2 in Overworld.ISLES:
		islands.append([center + Vector2(0.5, 0.5), Overworld.ISLE_RADIUS])
	for island: Array in islands:
		var center := island[0] as Vector2
		var radius := island[1] as Vector2
		var base := OverworldLayout.PropSpec.new(
			"island_base", Vector3(center.x, -0.98, center.y), 0.0
		)
		base.size = Vector3(radius.x * 1.5, 11.0, radius.y * 1.5)
		layout.props.append(base)


## 置かない場所: [中心, 半径]（水平の距離）と、長方形。
static func _keep_out(layout: OverworldLayout, def: StageDef) -> Array:
	var spots: Array = []
	for s in CampaignPlan.slots():
		spots.append([s.portal, 2.4])
		spots.append([s.portal + Overworld.BUILDING_OFFSET, 2.0])
		spots.append([s.portal + Overworld.HOME_OFFSET, 1.4])
	for w in CampaignPlan.worlds():
		if w.optional:
			spots.append([w.teaser, 3.0])
	for sign in layout.signs:
		spots.append([sign.position, 1.2])
	for b in def.blocks:
		spots.append([Vector3(b.cell) + Vector3(0.5, 0.0, 0.5), 2.0])
	for bell in def.bells:
		spots.append([bell.position, 1.5])
	return spots


static func _blocked(at: Vector3, keep_out: Array) -> bool:
	for spot: Array in keep_out:
		var c := spot[0] as Vector3
		if Vector2(at.x - c.x, at.z - c.z).length() < float(spot[1]):
			return true
	return false


## 四方が同じ高さの地面か（崖の縁・道の上に置かない）。
static func _flat_around(field: HeightField, x: int, z: int, h: int) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if field.top(x + d.x, z + d.y) != h:
			return false
	return true


## ポータルのわきの街灯と、出現地点の近くのベンチ・鉢植え（人が手入れしている場所に見せる）。
static func _furnish(layout: OverworldLayout) -> void:
	for p in layout.portals:
		var turn := Basis(Vector3.UP, p.facing - PI)
		layout.props.append(
			OverworldLayout.PropSpec.new(
				"hub_lamp", p.position + turn * Vector3(1.7, 0.0, 0.7), 0.0
			)
		)
	var spawn := Overworld.SPAWN_CENTER
	layout.props.append(
		OverworldLayout.PropSpec.new("hub_bench", spawn + Vector3(-0.5, 0.0, 4.0), 0.0)
	)
	for dx: float in [-5.5, 5.5]:
		layout.props.append(
			OverworldLayout.PropSpec.new("hub_planter", spawn + Vector3(dx, 0.0, -0.6), dx)
		)
		layout.props.append(
			OverworldLayout.PropSpec.new("hub_lamp", spawn + Vector3(dx, 0.0, -1.4), 0.0)
		)
	# 高台の上の見晴らし（ベンチと花）
	var top := Vector3(-16.0, 2.0, 8.5)
	layout.props.append(OverworldLayout.PropSpec.new("hub_bench", top, PI * 0.5))
	for k in 5:
		var at := top + Vector3(-1.2 + 0.6 * k, 0.0, 1.6 - (k % 2) * 3.2)
		layout.props.append(OverworldLayout.PropSpec.new("flower", at, float(k), 1.2))
