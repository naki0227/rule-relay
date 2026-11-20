class_name WorldItem
extends Node3D
## 世界に落ちている器の見た目（F で拾うと通常インベントリへ入る）。台帳の状態を映すだけで、
## 拾う処理は GameWorld が台帳に対して行う。当たり判定はない。

var vessel_id: int = -1

var _medal: Sprite3D
var _time: float = 0.0


func setup(v: RuleVessel, t: RuleToken) -> void:
	vessel_id = v.id
	name = "WorldItem%d" % v.id
	_medal = Sprite3D.new()
	_medal.texture = ItemIcons.for_token(t)
	_medal.pixel_size = 0.0045
	_medal.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_medal.shaded = false
	_medal.position.y = 0.7
	add_child(_medal)
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
	var label := Label3D.new()
	label.text = "%s（F で拾う）" % (v.item_name if v.item_name != "" else t.describe())
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
	if _medal != null:
		_medal.position.y = 0.7 + sin(_time * 2.2) * 0.07
		_medal.rotation.y = _time * 1.4


## 台帳の「世界に落ちている器」と、見た目のノード（vessel_id → WorldItem）を合わせる。
static func sync(parent: GameWorld, nodes: Dictionary[int, WorldItem]) -> void:
	var present := {}
	for v in parent.ledger.world_vessels():
		present[v.id] = true
		if not nodes.has(v.id):
			var node := WorldItem.new()
			node.setup(v, parent.ledger.token(v.token_id))
			parent.add_child(node)
			nodes[v.id] = node
		nodes[v.id].position = v.world_position
	for id: int in nodes.keys():
		if not present.has(id):
			nodes[id].queue_free()
			nodes.erase(id)


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
