class_name RangePreview
extends Node3D
## 範囲付与の円（企画書 5.3）。円の線1本と、選ばれる層の上面に敷く薄い円板だけで示す。
## - プレビュー（右クリックを押している間）: 夕日色の線と、薄い円板（ここが選ばれる、の印）
## - 付与中の範囲（lent）: 赤い線と、円の中心に能力のアイコンを1つだけ
## ブロックやセルごとの枠・角の印・文字は出さない（2026-11-21 本人: 「UI がごちゃごちゃしてるのがいらん」）。
## 円板は層の上面（layer + 1）に置くので、地面に範囲で渡すときは、選ばれるセルの面がそのまま薄く色づく。

const LIFT: float = 0.03
const RING_WIDTH: float = 0.05

var lent: bool = false
var _ring: MeshInstance3D
var _disc: MeshInstance3D
var _icon: Sprite3D
var _radius: float = -1.0


func _ready() -> void:
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color(0.72, 0.27, 0.23) if lent else UiTheme.SUN
	_ring = _mesh_child(ring_material)
	if lent:
		_icon = Sprite3D.new()
		_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_icon.pixel_size = 0.004
		_icon.position.y = 1.4
		add_child(_icon)
	else:
		var disc_material := StandardMaterial3D.new()
		disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disc_material.albedo_color = Color(UiTheme.SUN, 0.22)
		_disc = _mesh_child(disc_material)
	visible = false


## 中心・半径・層（その層の上面に円を置く）。
func show_at(center: Vector3, radius: float, layer: int) -> void:
	if not is_equal_approx(radius, _radius):
		_rebuild(radius)
	global_position = Vector3(center.x, float(layer) + 1.0 + LIFT, center.z)
	visible = true


func set_icon(texture: Texture2D) -> void:
	if _icon != null:
		_icon.texture = texture


func icon_texture() -> Texture2D:
	return _icon.texture if _icon != null else null


func _rebuild(radius: float) -> void:
	_radius = radius
	var torus := TorusMesh.new()
	torus.inner_radius = radius - RING_WIDTH
	torus.outer_radius = radius + RING_WIDTH
	torus.rings = 96
	torus.ring_segments = 6
	_ring.mesh = torus
	_ring.scale = Vector3(1.0, 0.3, 1.0)  # 平たい線にする（立った筒や二重の線にしない）
	if _disc != null:
		var disc := CylinderMesh.new()
		disc.top_radius = radius
		disc.bottom_radius = radius
		disc.height = 0.01
		disc.radial_segments = 96
		disc.rings = 1
		_disc.mesh = disc


func _mesh_child(material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.material_override = material
	add_child(mesh)
	return mesh


## 付与中の範囲の円を台帳に合わせる（トークン ID → 円）。範囲ごとに円と中心のアイコンを1つずつ。
static func sync_lent(parent: Node3D, ledger: RuleLedger, marks: Dictionary) -> void:
	var live := {}
	for t: RuleToken in ledger.all_tokens():
		if t.is_range and t.is_lent():
			live[t.id] = t
	for id: int in marks.keys():
		if not live.has(id):
			(marks[id] as Node).queue_free()
			marks.erase(id)
	for id: int in live:
		var t := live[id] as RuleToken
		if not marks.has(id):
			var mark := RangePreview.new()
			mark.lent = true
			mark.name = "RangeMark%d" % id
			parent.add_child(mark)
			marks[id] = mark
		var shown := marks[id] as RangePreview
		shown.show_at(t.range_center, t.range_radius, t.range_layer)
		shown.set_icon(ItemIcons.for_token(t))
