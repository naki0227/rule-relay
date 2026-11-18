class_name RangePreview
extends Node3D
## 範囲付与のプレビュー: 水平の円と、縦1層ぶんの厚みを半透明の筒で示す（企画書 5.3）。
## 色だけに頼らず、上下の縁の線で「1層だけ」が分かるようにする。

var _band: MeshInstance3D
var _rims: Array[MeshInstance3D] = []
var _radius: float = -1.0


func _ready() -> void:
	var band_material := StandardMaterial3D.new()
	band_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	band_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	band_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	band_material.albedo_color = Color(0.9, 0.15, 0.15, 0.18)
	_band = MeshInstance3D.new()
	_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_band.material_override = band_material
	add_child(_band)
	var rim_material := StandardMaterial3D.new()
	rim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_material.albedo_color = Color(0.75, 0.05, 0.05)
	for y: float in [0.02, 0.98]:
		var rim := MeshInstance3D.new()
		rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rim.material_override = rim_material
		rim.position.y = y
		add_child(rim)
		_rims.append(rim)
	visible = false


func show_at(center: Vector3, radius: float, layer: int) -> void:
	if not is_equal_approx(radius, _radius):
		_rebuild(radius)
	global_position = Vector3(center.x, float(layer), center.z)
	visible = true


func _rebuild(radius: float) -> void:
	_radius = radius
	var band := CylinderMesh.new()
	band.top_radius = radius
	band.bottom_radius = radius
	band.height = 1.0
	band.cap_top = false
	band.cap_bottom = false
	band.radial_segments = 64
	_band.mesh = band
	_band.position.y = 0.5
	for rim in _rims:
		var torus := TorusMesh.new()
		torus.inner_radius = radius - 0.04
		torus.outer_radius = radius + 0.04
		torus.rings = 64
		rim.mesh = torus
