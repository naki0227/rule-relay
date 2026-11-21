class_name WaterVisual
extends Node3D
## 水の見た目: 水面（透ける空色・つやのある板。ゆっくり上下する）と、底へ向かって濃くなる水の柱、
## 流れがあれば水面を流れる泡（CPUParticles3D）。当たり判定は持たない（水は物理の床ではない）。

## 水の柱の深さ（m）。底なしなので、下の方は暗くして見えなくする。
const DEPTH: float = 3.0
## 色（art/scripts/palette.py の SKY・SKY_DEEP・CREAM と同じ系統）。
const WATER := Color("#8cc4e8")
const WATER_DEEP := Color("#4f8fc0")
const FOAM := Color("#fff3df")

var spec: NatureLayout.WaterSpec
var surface: MeshInstance3D
var foam: CPUParticles3D
var _time: float = 0.0


func setup(p_spec: NatureLayout.WaterSpec) -> void:
	spec = p_spec
	name = "Water"


func _ready() -> void:
	var lo := Vector3(spec.min_cell)
	var size := Vector3(spec.max_cell - spec.min_cell + Vector3i.ONE)
	var top := spec.surface_y()
	surface = MeshInstance3D.new()
	surface.name = "Surface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(size.x, size.z)
	surface.mesh = plane
	surface.material_override = _material(Color(WATER, 0.62), 0.08)
	surface.position = Vector3(lo.x + size.x * 0.5, top, lo.z + size.z * 0.5)
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(size.x - 0.02, DEPTH, size.z - 0.02)
	body.mesh = box
	body.material_override = _material(Color(WATER_DEEP, 0.7), 0.4)
	body.position = surface.position - Vector3(0.0, DEPTH * 0.5 + 0.02, 0.0)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	if spec.current != Vector3i.ZERO:
		_add_foam(size)


func _process(delta: float) -> void:
	_time += delta
	surface.position.y = spec.surface_y() + sin(_time * 1.3) * 0.015


func _add_foam(size: Vector3) -> void:
	foam = CPUParticles3D.new()
	foam.name = "Foam"
	var bit := SphereMesh.new()
	bit.radius = 0.06
	bit.height = 0.03
	bit.material = _material(Color(FOAM, 0.9), 0.6)
	foam.mesh = bit
	foam.position = surface.position + Vector3(0.0, 0.02, 0.0)
	foam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	foam.emission_box_extents = Vector3(size.x * 0.5, 0.0, size.z * 0.5)
	foam.direction = Vector3(spec.current)
	foam.spread = 4.0
	foam.gravity = Vector3.ZERO
	foam.initial_velocity_min = spec.current_speed * 0.9
	foam.initial_velocity_max = spec.current_speed * 1.1
	foam.lifetime = maxf(absf(size.dot(Vector3(spec.current).abs())) / spec.current_speed, 0.5)
	foam.amount = clampi(int(size.x * size.z), 8, 80)
	foam.scale_amount_min = 0.6
	foam.scale_amount_max = 1.4
	foam.local_coords = false
	add_child(foam)


static func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = roughness
	mat.metallic_specular = 0.7
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.rim_enabled = true
	mat.rim = 0.4
	return mat
