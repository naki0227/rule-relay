class_name Overworld
extends RefCounted
## 広場（オーバーワールド）の定義を、OverworldState（ホストの進行）から組み立てる（docs/adr/0013）。
## ステージの id は従来のハブと同じ StageCatalog.HUB_ID。地形は文字の地図（IslandMap）＋箱で作る。
##
## - はじまりの草原（W1）が真ん中。出現地点の真正面に導入のポータル（docs/onboarding.md）
## - ほかのワールドの地方は谷・岩で隔て、開いたら橋が架かる・岩がどく・階段がせり上がる（地形だけで開く。
##   ルールで通せんぼはしない）
## - 草原の近くに小さな仕掛け: 高台（窪みのブロックにジャンプを貸す）・札の門・鐘の扉
## - クリアしたステージの生き物が住み、建物が建つ（見た目だけ）
## 座標: 1 マス = 1 m、北 = -Z、地面の上面 y = 0。

const ORIGIN := Vector2i(-60, -76)
## 東の端は寄り道 O2 の小島（x 61〜69）まで
const WIDTH := 132
const DEPTH := 104
## 出現地点（4 人分の真ん中）。1 人目は x = 0.5 で、導入のポータルの真正面。
const SPAWN_CENTER := Vector3(2.0, 0.0, 11.5)
## 高台の仕掛け: 高さ 2 の台と、その東の窪みのブロック（上面が地面と同じ）
const LEDGE_MIN := Vector2i(-18, 6)
const LEDGE_MAX := Vector2i(-14, 11)
const LEDGE_LIFT := Vector2i(-13, 8)
## 札の門の庭（南西）と鐘の扉の庭（北東）。壁は高さ 3、門と扉の上にまぐさ（高さ 2〜3）。
## 庭の中に寄り道のワールド（O3・O1）のポータルが 5 つずつ並ぶ（OptionalWorldPlan）。鐘の扉の庭の東の壁と
## 鐘の谷（W2）の間は幅 5 以上の谷のまま（先に W2 へ渡れないように）。
const BAN_YARD := Rect2i(-26, 14, 16, 12)
const BAN_GATE := Vector3i(-14, 0, 14)
const BELL_YARD := Rect2i(15, -22, 9, 13)
## 寄り道 O2 の小島（浮島の東の端から幅 5 の空の先）。5 つのポータルが立つ
const SKY_ISLET := Rect2i(61, -55, 9, 14)
const BELL_DOOR := Vector3i(15, 0, -13)
const BELL_AT := Vector3(12.5, 0.0, -14.5)
## W3 ふわふわ浮島の丸い島の中心と半径
const ISLES: Array[Vector2] = [
	Vector2(32, -38),
	Vector2(42, -41),
	Vector2(50, -36),
	Vector2(50, -49),
	Vector2(42, -56),
	Vector2(32, -52)
]
const ISLE_RADIUS := Vector2(5.0, 4.5)
## 建物と住む生き物の場所（ポータルからのずれ。ポータルが南を向くとき）
const BUILDING_OFFSET := Vector3(3.0, 0.0, -2.5)
const HOME_OFFSET := Vector3(-2.5, 0.0, 1.5)
const _MOVES: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD, RuleAction.Kind.LEFT, RuleAction.Kind.BACK, RuleAction.Kind.RIGHT
]
const _EQUIPMENT: Array[RuleAction.Kind] = [RuleAction.Kind.HIGH_JUMP, RuleAction.Kind.CLIMB]
## 持っているだけで効く性質（キーが無い）。ホットバーに置くと勝手に効く（重いと浮くは打ち消し合い、
## 重いと水に沈む）ので、広場では通常インベントリに渡し、使うときに自分でホットバーへ移す。
const _PASSIVES: Array[RuleAction.Kind] = [
	RuleAction.Kind.HEAVY, RuleAction.Kind.FLOAT, RuleAction.Kind.SWIM
]


static func build(state: OverworldState) -> StageDef:
	var def := StageDef.new()
	def.stage_id = StageCatalog.HUB_ID
	def.display_name = "広場"
	def.provisional = true
	var layout := OverworldLayout.new()
	def.overworld = layout
	var map := _map(state)
	_puzzles(def, map, layout)  # 窪み（pit）を掘るので、地形の箱を作る前に置く
	var field := HeightField.from_map(map)
	def.terrain_boxes = _terrain(field)
	def.terrain_boxes.append_array(_walls_and_gates(state))
	for dx: float in [-1.5, -0.5, 0.5, 1.5]:
		def.spawn_points.append(SPAWN_CENTER + Vector3(dx, 0.0, 0.0))
	_loadout(def, state)
	_portals(def, layout, state)
	PortalSpots.place(def, layout, field)  # ステージから戻ったときの立ち位置（docs/adr/0020）
	_settle(layout, state)
	OverworldScenery.scatter(layout, field, def)
	return def


## その地方（ワールド）の地形の高さ（ポータルの y）。
static func region_height(world_id: String) -> int:
	match world_id:
		"w6":
			return 4
		"w7":
			return 7
	return 0


# --- 地形 --------------------------------------------------------------------------


static func _map(state: OverworldState) -> IslandMap:
	var m := IslandMap.blank(ORIGIN, WIDTH, DEPTH)
	# W1 はじまりの草原（真ん中）と高台
	_blob(m, Vector2(2.0, 3.0), Vector2(21.0, 19.0), 0)
	m.fill(LEDGE_MIN.x, LEDGE_MIN.y, LEDGE_MAX.x, LEDGE_MAX.y, 2)
	m.fill(BAN_YARD.position.x, BAN_YARD.position.y, BAN_YARD.end.x - 1, BAN_YARD.end.y - 1, 0)
	m.fill(BELL_YARD.position.x, BELL_YARD.position.y, BELL_YARD.end.x - 1, BELL_YARD.end.y - 1, 0)
	m.fill(8, -16, BELL_YARD.position.x - 1, -9, 0)  # 鐘の扉の前（鐘の立つ地面）
	# 草原のなだらかな丘（見た目と寄り道。ポータル・出現地点の前は避ける）
	_blob(m, Vector2(14.5, 16.5), Vector2(4.0, 3.0), 1)
	_blob(m, Vector2(-12.0, -12.0), Vector2(4.0, 3.0), 1)
	_blob(m, Vector2(-13.0, -12.5), Vector2(1.8, 1.5), 2)
	# W2 鐘の谷（東）。真ん中に小さな丘
	_blob(m, Vector2(43.0, -4.0), Vector2(15.0, 18.0), 0)
	_blob(m, Vector2(43.0, -3.0), Vector2(3.5, 3.5), 1)
	# W3 ふわふわ浮島（北東）: 丸い島を細い道でつなぐ。東の端の先に寄り道の小島（幅 5 の空）
	var isles: Array[Vector2] = [
		Vector2(32, -38),
		Vector2(42, -41),
		Vector2(50, -36),
		Vector2(50, -49),
		Vector2(42, -56),
		Vector2(32, -52)
	]
	for i in isles.size():
		_blob(m, isles[i], Vector2(5.0, 4.5), 0)
		_path(m, isles[i], isles[(i + 1) % isles.size()], 0)
	m.fill(SKY_ISLET.position.x, SKY_ISLET.position.y, SKY_ISLET.end.x - 1, SKY_ISLET.end.y - 1, 0)
	# W4 けものの森（西）・W5 札の庭（北西）
	_blob(m, Vector2(-41.0, -6.0), Vector2(15.0, 18.0), 0)
	_blob(m, Vector2(-41.0, -48.0), Vector2(15.0, 15.0), 0)
	# W6 霧の峰（北。高さ 4 の台地）・W7 空の頂（さらに北。高さ 7）
	_blob(m, Vector2(0.0, -38.0), Vector2(20.0, 17.0), 4)
	_blob(m, Vector2(0.0, -68.0), Vector2(13.0, 7.0), 7)
	# 草原から西へ渡る土の道（いつもある。閉じている間は岩がふさぐ）
	m.fill(-27, -1, -17, 1, 0)
	_bridges(m, state)
	return m


## 地図から地形の箱を作る。上面は草、高い所の側面は石の崖にする（地図の箱は高さで種類が決まるので、
## 広場では塗り分け直す）。まわりより高い列だけ地面の下（y = -1）まで埋め、内側は上の 2 マスだけにする
## （見えない内側のセルを作らない。広場は広いので、組み立ての時間とセルの数を抑える）。
static func _terrain(field: HeightField) -> Array:
	var result: Array = []
	for row in field.depth:
		var z := field.origin.y + row
		var run: Array = []  # [x0, top, bottom]
		for col in field.width + 1:
			var x := field.origin.x + col
			var cell := _column(field, x, z) if col < field.width else Vector2i(-100, 0)
			if not run.is_empty() and cell == Vector2i(run[1], run[2]):
				continue
			if not run.is_empty() and int(run[1]) > -100:
				_emit_column(result, int(run[0]), x - 1, z, int(run[1]), int(run[2]))
			run = [x, cell.x, cell.y]
	return result


## マスの [上面の高さ, 埋める一番下の y]。何もなければ上面 -100。
static func _column(field: HeightField, x: int, z: int) -> Vector2i:
	var top := field.top(x, z)
	if top <= -100:
		return Vector2i(-100, 0)
	var bottom := mini(-1, top - 1)
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if field.top(x + d.x, z + d.y) < top:
			return Vector2i(top, bottom)
	return Vector2i(top, maxi(bottom, top - 2))


static func _emit_column(result: Array, x0: int, x1: int, z: int, top: int, bottom: int) -> void:
	if top - 1 > bottom:
		result.append([Vector3i(x0, bottom, z), Vector3i(x1, top - 2, z), "rock"])
	result.append([Vector3i(x0, top - 1, z), Vector3i(x1, top - 1, z), "grass"])


## 開いた地方へ渡る橋・階段（地形だけで開く）。
static func _bridges(m: IslandMap, state: OverworldState) -> void:
	if state.is_region_open("w2"):
		m.fill(22, -1, 30, 1, 0)
	if state.is_region_open("w3"):
		m.fill(49, -31, 51, -19, 0)
	if state.is_region_open("w5"):
		m.fill(-42, -34, -40, -23, 0)
	if state.is_region_open("w6"):
		for i in 4:
			m.fill(-1, -17 - i, 1, -17 - i, i + 1)
	if state.is_region_open("w7"):
		for i in 5:
			m.fill(-1, -56 - i, 1, -56 - i, mini(5 + i, 7))


## 庭の壁・門と扉のまぐさ・西の道をふさぐ岩（どれも地形の箱。岩は W4 が開くと消える）。
static func _walls_and_gates(state: OverworldState) -> Array:
	var boxes: Array = []
	for yard: Rect2i in [BAN_YARD, BELL_YARD]:
		var lo := yard.position
		var hi := yard.end - Vector2i.ONE
		boxes.append([Vector3i(lo.x, 0, lo.y), Vector3i(hi.x, 2, lo.y), "rock"])
		boxes.append([Vector3i(lo.x, 0, hi.y), Vector3i(hi.x, 2, hi.y), "rock"])
		boxes.append([Vector3i(lo.x, 0, lo.y + 1), Vector3i(lo.x, 2, hi.y - 1), "rock"])
		boxes.append([Vector3i(hi.x, 0, lo.y + 1), Vector3i(hi.x, 2, hi.y - 1), "rock"])
	# 門（北の壁）と扉（西の壁）は、壁の箱から抜いて作り直す
	var cut: Array[Vector3i] = [BAN_GATE, BAN_GATE + Vector3i(-1, 0, 0), BELL_DOOR]
	cut.append(BELL_DOOR + Vector3i(0, 0, -1))
	boxes = _carve(boxes, cut)
	# まぐさ（通り道の高さ 2 を残す）と、ブロックが逃げ込むくぼみの両わきの柱（くぼみは門・扉の側にだけ
	# 開く。人はブロックのある門を通れないので、くぼみから庭へは入れない。天井でふさぐと、ブロックが
	# 天井に触れて動けなかった）
	boxes.append([BAN_GATE + Vector3i(0, 2, 0), BAN_GATE + Vector3i(0, 2, 0), "rock"])
	boxes.append([BELL_DOOR + Vector3i(0, 2, 0), BELL_DOOR + Vector3i(0, 2, 0), "rock"])
	for pillar: Vector3i in [
		BAN_GATE + Vector3i(-1, 0, -1),
		BAN_GATE + Vector3i(-1, 0, 1),
		BELL_DOOR + Vector3i(-1, 0, -1),
		BELL_DOOR + Vector3i(1, 0, -1),
	]:
		boxes.append([pillar, pillar + Vector3i(0, 2, 0), "rock"])
	if not state.is_region_open("w4"):
		boxes.append([Vector3i(-24, 0, -2), Vector3i(-21, 2, 2), "rock"])
	return boxes


## 箱の並びから、cells の列（その x, z の y 0〜2）を抜く。壁は 1 列の箱なので、分けて作り直す。
static func _carve(boxes: Array, cells: Array[Vector3i]) -> Array:
	var result: Array = []
	for box: Array in boxes:
		var parts: Array = [box]
		for cell in cells:
			var next: Array = []
			for piece: Array in parts:
				next.append_array(_split(piece, cell))
			parts = next
		result.append_array(parts)
	return result


static func _split(box: Array, cell: Vector3i) -> Array:
	var lo := box[0] as Vector3i
	var hi := box[1] as Vector3i
	var inside := cell.x >= lo.x and cell.x <= hi.x and cell.z >= lo.z and cell.z <= hi.z
	if not inside:
		return [box]
	var pieces: Array = []
	if lo.x == hi.x:  # 南北に伸びる壁
		if cell.z > lo.z:
			pieces.append([lo, Vector3i(hi.x, hi.y, cell.z - 1), box[2]])
		if cell.z < hi.z:
			pieces.append([Vector3i(lo.x, lo.y, cell.z + 1), hi, box[2]])
	else:  # 東西に伸びる壁
		if cell.x > lo.x:
			pieces.append([lo, Vector3i(cell.x - 1, hi.y, hi.z), box[2]])
		if cell.x < hi.x:
			pieces.append([Vector3i(cell.x + 1, lo.y, lo.z), hi, box[2]])
	return pieces


## 楕円の島を高さ h で塗る。
static func _blob(m: IslandMap, center: Vector2, radius: Vector2, h: int) -> void:
	for z in range(floori(center.y - radius.y), ceili(center.y + radius.y) + 1):
		var dz := (z + 0.5 - center.y) / radius.y
		if dz * dz > 1.0:
			continue
		# マスの中心が楕円の中にある x の範囲を、行ごとに 1 回で塗る
		var half := radius.x * sqrt(1.0 - dz * dz)
		var x0 := ceili(center.x - half - 0.5)
		var x1 := floori(center.x + half - 0.5)
		if x0 <= x1:
			m.fill(x0, z, x1, z, h)


## a から b へ幅 3 の道を高さ h で塗る。
static func _path(m: IslandMap, a: Vector2, b: Vector2, h: int) -> void:
	var steps := ceili(a.distance_to(b))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(maxi(steps, 1)))
		m.fill(floori(p.x) - 1, floori(p.y) - 1, floori(p.x) + 1, floori(p.y) + 1, h)


# --- 能力とポータル ----------------------------------------------------------------


## 広場の能力: W/A/S/D・ジャンプと、クリアで開いた能力。装備（ブーツ・グローブ）は装備した状態で、
## 持っているだけで効く性質（重い・浮く・泳ぐ）は通常インベントリに渡す（docs/adr/0015 の追記）。
## 全部開いてもホットバーは 7 枠（W/A/S/D・ジャンプ・投げる・ダッシュ）で、2 枠は性質を移す空き。
static func _loadout(def: StageDef, state: OverworldState) -> void:
	var hotbar: Array[RuleAction.Kind] = _MOVES.duplicate()
	hotbar.append(RuleAction.Kind.JUMP)
	for action in state.unlocked_actions():
		if _EQUIPMENT.has(action):
			def.start_equipment.append(action)
		elif _PASSIVES.has(action):
			def.start_inventory.append(action)
		elif hotbar.size() < RuleLedger.HOTBAR_SIZE:
			hotbar.append(action)
	def.set_loadout_for_all(hotbar)


static func _portals(def: StageDef, layout: OverworldLayout, state: OverworldState) -> void:
	var first := true
	for w in CampaignPlan.worlds():
		for s in CampaignPlan.built_slots(w):
			var p := OverworldLayout.PortalSpec.new()
			p.stage_id = s.stage_id
			p.label = s.label()
			p.title = CampaignPlan.stage_name(s.stage_id)
			p.target_minutes = CampaignPlan.stage_minutes(s.stage_id)
			p.position = s.portal
			p.facing = s.facing
			p.open = state.is_stage_open(s.stage_id)
			p.cleared = state.has_cleared(s.stage_id)
			p.hard = s.hard
			# 次に行くとよいポータル（計画の順で、開いていてまだクリアしていない最初の 1 つ）。
			# クリアした後も「はじめはここから」が最初の門に残り、次の行き先が分からなかった（2026-11-22 の通し）
			p.first = first and p.open and not p.cleared
			if p.first:
				first = false
			layout.portals.append(p)
			def.entrances.append(_entrance(s.stage_id, s.portal))
	# 計画に無いステージ（試作など）も入れるよう、草原の南に並べる
	var extra := 0
	for stage_id in CampaignPlan.built_ids():
		if CampaignPlan.slot(stage_id) == null:
			var at := Vector3(-8.5 + 3.5 * extra, 0.0, 18.5)
			extra += 1
			def.entrances.append(_entrance(stage_id, at))
	for w in CampaignPlan.worlds():
		if w.optional and CampaignPlan.built_slots(w).is_empty():
			var t := OverworldLayout.TeaserSpec.new()
			t.title = w.display_name
			t.position = w.teaser
			layout.teasers.append(t)


static func _entrance(stage_id: String, at: Vector3) -> StageDef.EntranceSpec:
	var area := AABB(at - Vector3(1.0, 0.0, 1.0), Vector3(2.0, 2.5, 2.0))
	return StageDef.EntranceSpec.new(stage_id, at, area)


# --- 小さな仕掛け --------------------------------------------------------------------


static func _puzzles(def: StageDef, map: IslandMap, layout: OverworldLayout) -> void:
	# 高台: 窪みのブロックにジャンプを貸して乗る（導入と同じ考え方）。上に見晴らしの発見
	var lift := StageDef.BlockSpec.new("ow_lift", map.pit(LEDGE_LIFT.x, LEDGE_LIFT.y))
	lift.color = Color(0.7, 0.58, 0.86)
	def.blocks.append(lift)
	var ledge_area := AABB(
		Vector3(LEDGE_MIN.x, 1.9, LEDGE_MIN.y),
		Vector3(LEDGE_MAX.x - LEDGE_MIN.x + 1, 3.0, LEDGE_MAX.y - LEDGE_MIN.y + 1)
	)
	layout.secrets.append(OverworldLayout.SecretSpec.new("ledge", ledge_area, "ひみつの見晴らし台を見つけた！"))
	# 札の門: 門のブロックに W・S・A の禁止の札。札を回収して手放してから、A を渡すとくぼみへどく
	var gate := StageDef.BlockSpec.new("ow_ban_gate", BAN_GATE)
	gate.color = Color(0.86, 0.62, 0.55)
	for action: RuleAction.Kind in [
		RuleAction.Kind.FORWARD, RuleAction.Kind.BACK, RuleAction.Kind.LEFT
	]:
		gate.tokens.append(StageDef.TokenSpec.new(action, true))
	def.blocks.append(gate)
	# 鐘の扉: 扉のブロックに信号の W。鐘が鳴っている間、北のくぼみへすべって開く
	var door := StageDef.BlockSpec.new("ow_bell_door", BELL_DOOR)
	door.color = Color(0.55, 0.72, 0.86)
	door.tokens.append(
		StageDef.TokenSpec.new(RuleAction.Kind.FORWARD, false, TriggerMode.Kind.SIGNAL)
	)
	def.blocks.append(door)
	def.bells.append(StageDef.BellSpec.new("ow_bell", BELL_AT))
	_yard_secrets(layout)


static func _yard_secrets(layout: OverworldLayout) -> void:
	for w in CampaignPlan.worlds():
		if not w.optional:
			continue
		var area := AABB(w.teaser - Vector3(2.5, 0.1, 2.5), Vector3(5.0, 3.0, 5.0))
		layout.secrets.append(
			OverworldLayout.SecretSpec.new(w.id, area, "寄り道のワールド「%s」の入口を見つけた！" % w.display_name)
		)


# --- 住む生き物と建物 --------------------------------------------------------------


static func _settle(layout: OverworldLayout, state: OverworldState) -> void:
	for p in layout.portals:
		if not p.cleared:
			continue
		var s := CampaignPlan.slot(p.stage_id)
		var turn := Basis(Vector3.UP, s.facing - PI)
		var r := OverworldLayout.ResidentSpec.new()
		r.stage_id = p.stage_id
		r.species = s.species
		r.tint = s.tint
		r.home = p.position + turn * HOME_OFFSET
		layout.residents.append(r)
		var building := OverworldLayout.PropSpec.new(
			s.building, p.position + turn * BUILDING_OFFSET, s.facing + 0.35
		)
		building.building = true
		layout.props.append(building)
	_signs(layout, state)


## 地方の名前の立て札と、閉じた道の説明。
static func _signs(layout: OverworldLayout, state: OverworldState) -> void:
	var gates: Array = [
		["w2", Vector3(20.5, 0.0, 2.5)],
		["w3", Vector3(48.0, 0.0, -18.5)],
		["w4", Vector3(-17.5, 0.0, 3.0)],
		["w5", Vector3(-38.5, 0.0, -22.5)],
		["w6", Vector3(3.0, 0.0, -14.5)],
		["w7", Vector3(3.0, 4.0, -53.5)],
	]
	for entry: Array in gates:
		var w := CampaignPlan.world(String(entry[0]))
		var text := "%s →" % w.display_name
		if not state.is_region_open(w.id):
			var needed := CampaignPlan.stage_name(CampaignPlan.required_stage(w))
			var by := needed if needed != "" else "前のワールド"
			text = "%s\n（「%s」をクリアすると道が開く）" % [w.display_name, by]
		layout.signs.append(OverworldLayout.SignSpec.new(entry[1] as Vector3, text))
