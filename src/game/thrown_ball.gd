class_name ThrownBall
extends Node3D
## 投げられた玉（発射台・生き物が「投げる」で投げる）。放物線で飛び、鐘に当たると鳴らす。
## ほかの物に当たる・一定時間たつと消える。当たり判定は光線（細かい物理はしない）。

signal hit(collider: Object)

const LIFETIME: float = 3.0
const GRAVITY: float = 6.0

var velocity: Vector3 = Vector3.ZERO

var _age: float = 0.0
var _exclude: Array[RID] = []


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#c97b4a")
	mesh.material_override = mat
	add_child(mesh)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(
		from, to, Tuning.LAYER_TERRAIN | Tuning.LAYER_BLOCKS | Tuning.LAYER_CREATURES
	)
	query.exclude = _exclude
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		global_position = to
		return
	var collider: Object = result["collider"]
	if collider is Bell:
		(collider as Bell).ring()
	hit.emit(collider)
	queue_free()


## 投げた本人には当たらないようにする。
func ignore(body: CollisionObject3D) -> void:
	if body != null:
		_exclude.append(body.get_rid())
