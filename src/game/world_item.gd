class_name WorldItem
extends Node3D
## 世界に落ちている器の見た目（F で拾うと、ホットバーに空きがあればそこ、無ければかばんへ入る）。台帳の状態を映すだけで、
## 拾う処理は GameWorld が台帳に対して行う。当たり判定はない。

## 装備・ダッシュの道具を、手に持つ大きさより少し大きく見せる倍率。
const TOOL_SCALE: float = 1.3

var vessel_id: int = -1

## 浮かんで回る見た目（メダル・装備）。
var _visual: Node3D
var _time: float = 0.0


func setup(v: RuleVessel, t: RuleToken, ability_only: bool = false) -> void:
	vessel_id = v.id
	name = "WorldItem%d" % v.id
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.position.y = 0.7
	_visual.add_child(medal_model(t) if ability_only else _make_model(t))
	add_child(_visual)
	var shadow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.28
	disc.bottom_radius = 0.28
	disc.height = 0.01
	shadow.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(UiTheme.INK, 0.18)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = mat
	shadow.position.y = 0.02
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
	var label := KeyLabel3D.new()
	var item_label := v.item_name if v.item_name != "" else t.describe()
	label.template = "%s（%s で拾う）" % [item_label, InputMode.token(&"interact")]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 1.25
	label.pixel_size = 0.004
	label.font = UiTheme.font(700, 2)
	label.font_size = 36
	label.modulate = UiTheme.INK
	label.outline_modulate = Color(UiTheme.CREAM, 0.95)
	label.outline_size = 12
	add_child(label)


func _process(delta: float) -> void:
	_time += delta
	if _visual != null:
		_visual.position.y = 0.7 + sin(_time * 2.2) * 0.07
		_visual.rotation.y = _time * 1.4


## 見た目のモデルの名前（art/scripts/build_markers.py・build_nature.py）。装備・ダッシュ・重い（おもり）・
## 浮く（風船）・泳ぐ（足ひれ）は道具の形、
## ほかの能力ははちみつ色のメダル、禁止は灰の地に赤い輪と斜線のメダル。
static func model_for(t: RuleToken) -> String:
	if t.is_prohibition:
		return "ban_medal"
	match t.action:
		RuleAction.Kind.HIGH_JUMP:
			return "jump_boots"
		RuleAction.Kind.CLIMB:
			return "climbing_gloves"
		RuleAction.Kind.DASH:
			return "dash_feather"
		RuleAction.Kind.HEAVY:
			return "heavy_weight"
		RuleAction.Kind.FLOAT:
			return "float_balloon"
		RuleAction.Kind.SWIM:
			return "swim_fins"
	return "vessel_medal"


static func _make_model(t: RuleToken) -> Node3D:
	var model_name := model_for(t)
	if model_name.ends_with("_medal"):
		return medal_model(t)
	var model := ModelLibrary.instantiate(model_name)
	model.name = "Model"
	# 道具は足もとが原点なので、メダルと同じ高さに中心をそろえ、遠くから形が分かるよう少し大きく
	model.position.y = -0.3
	model.scale = Vector3.ONE * TOOL_SCALE
	return model


## 器のメダル（能力ははちみつ色、禁止は灰の地に赤い輪）に行動の記号を重ねたもの。道具の能力でもメダルにする
## （投げたメダルの見た目 MedalVisual にも使う）。
static func medal_model(t: RuleToken) -> Node3D:
	var model := ModelLibrary.instantiate("ban_medal" if t.is_prohibition else "vessel_medal")
	model.name = "Model"
	# メダルの両面に、行動の記号を重ねる（矢印・山形など。禁止は赤い斜線の下に見える）
	for side: float in [1.0, -1.0]:
		var glyph := Sprite3D.new()
		glyph.name = "GlyphFront" if side > 0.0 else "GlyphBack"
		glyph.texture = ItemIcons.glyph(t.action)
		glyph.pixel_size = 0.0036
		glyph.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		glyph.shaded = false
		glyph.modulate = ArtPalette.GLYPH_BAN if t.is_prohibition else ArtPalette.GLYPH_ABILITY
		glyph.position.z = 0.03 * side
		glyph.rotation.y = 0.0 if side > 0.0 else PI
		model.add_child(glyph)
	return model


## 台帳に合わせて、世界に落ちている器と能力（単発成功時に付与者が退出していた）の見た目をそろえる。
## nodes はキー → ノード（器は vessel_id、落ちている能力は -token_id）。
static func sync_all(parent: Node, ledger: RuleLedger, nodes: Dictionary[int, WorldItem]) -> void:
	var present := {}
	for v in ledger.world_vessels():
		present[v.id] = true
		_place(parent, nodes, v.id, v, ledger.token(v.token_id))
	for t in PartyQuery.dropped_tokens(ledger):
		# 器を離れて落ちている能力は、中身だけ（メダル）で見せる。装備の能力でも入れ物の姿にしない
		var stand_in := RuleVessel.new()
		stand_in.world_position = t.drop_position
		present[-t.id] = true
		_place(parent, nodes, -t.id, stand_in, t, true)
	for key: int in nodes.keys():
		if not present.has(key):
			nodes[key].queue_free()
			nodes.erase(key)


static func _place(
	parent: Node,
	nodes: Dictionary[int, WorldItem],
	key: int,
	v: RuleVessel,
	t: RuleToken,
	ability_only: bool = false
) -> void:
	if not nodes.has(key):
		var node := WorldItem.new()
		node.setup(v, t, ability_only)
		parent.add_child(node)
		nodes[key] = node
	nodes[key].position = v.world_position


## 拾ったときの知らせ。slot は入ったホットバーの枠（0 始まり。かばんに入ったら -1）。
## 「かばんへ」は本当にかばんに入ったときだけ言う（2026-11-23 本人の判断「ホットバーに入れる」）。
## 装備品は、つけるまで効かないことと、つけ方を添える（docs/adr/0018）。
static func pickup_text(v: RuleVessel, t: RuleToken, slot: int = -1) -> String:
	var item_label := v.item_name if v.item_name != "" else t.describe()
	var bag := InputMode.token(&"inventory")
	if v.is_equipment():
		var where := "ホットバー %d へ。" % (slot + 1) if slot >= 0 else ""
		return "%sを拾いました（%sつけるまで効きません。%s で開いて「そうびする」）" % [item_label, where, bag]
	if slot >= 0:
		return "%sを拾いました（ホットバー %d へ）" % [item_label, slot + 1]
	# 持ち物の画面の言い方（かばん）にそろえる。前は「通常インベントリ」だった
	return "%sを拾いました（かばんへ。%s で開いてホットバーへ）" % [item_label, bag]


## 拾える距離にある、いちばん近い器（無ければ null）。
static func nearest(ledger: RuleLedger, from: Vector3) -> RuleVessel:
	var best: RuleVessel = null
	var best_distance := Tuning.PICKUP_REACH
	for v in ledger.world_vessels():
		var d := from.distance_to(v.world_position)
		if d <= best_distance:
			best = v
			best_distance = d
	return best
