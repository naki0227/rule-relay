class_name MedalPuff
extends MeshInstance3D
## 投げたメダルが当たったところの小さな輪（docs/adr/0017）。0.35 秒で広がって薄れ、消える。1 つだけで粒は出さない。

const LIFETIME: float = 0.35
const START_RADIUS: float = 0.12
const END_RADIUS: float = 0.55

var tint: Color = Color.WHITE

var _age: float = 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.82
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 6
	mesh = ring
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_material.albedo_color = Color(tint, 0.8)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scale = Vector3.ONE * START_RADIUS


func _process(delta: float) -> void:
	_age += delta
	var k := clampf(_age / LIFETIME, 0.0, 1.0)
	scale = Vector3.ONE * lerpf(START_RADIUS, END_RADIUS, 1.0 - (1.0 - k) * (1.0 - k))
	_material.albedo_color = Color(tint, 0.8 * (1.0 - k))
	if k >= 1.0:
		queue_free()
