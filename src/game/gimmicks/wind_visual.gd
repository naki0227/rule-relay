class_name WindVisual
extends Node3D
## 風の見た目: 風上の端に立つかざぐるま（Blender の骨格付きモデル wind_fan。羽根は「spin」で回る）と、
## 範囲を流れていく木の葉（CPUParticles3D。葉の形は wind_leaf）。当たり判定は持たない。
## 脈打つ風は、吹いていない間は葉を止め、かざぐるまをゆっくりにする（時計は NatureField.clock）。

const SPIN := &"spin"
## 吹いていない間のかざぐるまの回る速さ（倍率）。止めきらず、風がまた来ることを見せる。
const CALM_SPIN: float = 0.12

var spec: NatureLayout.WindSpec
var field: NatureField
var leaves: CPUParticles3D
var fan: Node3D
var _rig: RigAnimator
var _spin: float = 1.0


func setup(p_spec: NatureLayout.WindSpec, p_field: NatureField) -> void:
	spec = p_spec
	field = p_field
	name = "Wind"


func _ready() -> void:
	var area := spec.area()
	var dir := Vector3(spec.direction)
	leaves = CPUParticles3D.new()
	leaves.name = "Leaves"
	leaves.mesh = ModelLibrary.mesh("wind_leaf")
	leaves.position = area.get_center()
	leaves.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	leaves.emission_box_extents = area.size * 0.5
	leaves.direction = dir
	leaves.spread = 12.0
	leaves.gravity = Vector3(0.0, -0.25, 0.0)
	leaves.initial_velocity_min = spec.strength * 0.9
	leaves.initial_velocity_max = spec.strength * 1.3
	leaves.angular_velocity_min = -220.0
	leaves.angular_velocity_max = 220.0
	leaves.scale_amount_min = 0.7
	leaves.scale_amount_max = 1.3
	var length := absf(area.size.dot(dir.abs()))
	leaves.lifetime = maxf(length / spec.strength, 0.6)
	leaves.amount = clampi(int(area.size.x * area.size.z * 0.5), 6, 64)
	leaves.local_coords = false
	add_child(leaves)
	fan = ModelLibrary.instantiate("wind_fan")
	fan.name = "Fan"
	# 風上の端の真ん中に、風下（モデルの正面 -Z）を向けて立てる
	var upwind := area.get_center() - dir * (absf(area.size.dot(dir.abs())) * 0.5 - 0.5)
	fan.position = Vector3(upwind.x, area.position.y, upwind.z)
	fan.rotation.y = atan2(-dir.x, -dir.z)
	add_child(fan)
	_rig = RigAnimator.new(fan)
	if _rig.has(SPIN):
		_rig.player.get_animation(SPIN).loop_mode = Animation.LOOP_LINEAR
		_rig.play(SPIN)
	_update(0.0)


func _process(delta: float) -> void:
	_update(delta)


func is_blowing() -> bool:
	return spec.is_blowing(field.clock)


func _update(delta: float) -> void:
	var blowing := is_blowing()
	leaves.emitting = blowing
	_spin = move_toward(_spin, 1.0 if blowing else CALM_SPIN, delta * 2.0)
	if _rig.has(SPIN):
		_rig.play(SPIN, _spin * spec.strength / NatureTuning.WIND_STRENGTH)
