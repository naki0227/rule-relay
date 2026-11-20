class_name GoalMarker
extends Node3D
## ゴール（全員で集まる場所）の目印。夕日色の旗（布に「集まる」印）を真ん中に立て、範囲の四隅に
## 小さな灯りの杭、床にうすい夕日色の板を敷く。モデルは art/scripts/build_markers.py。
## 見た目だけで、当たり判定は持たない（光線も遮らない）。

## 床の板の色（夕日を半透明に）。
const FLOOR_COLOR := Color(1.0, 0.79, 0.54, 0.4)
const FLAG_SCALE: float = 1.2

var _flag_cloth: Node3D
var _time: float = 0.0


## area はゴールの範囲（下の面が床）。size が 0 なら旗だけを立てる。
func setup(area: AABB) -> void:
	name = "GoalMarker"
	var floor_y := area.position.y + 0.1 if area.has_volume() else area.position.y
	var center := Vector3(area.get_center().x, floor_y, area.get_center().z)
	position = center
	var flag := ModelLibrary.instantiate("goal_flag")
	flag.name = "FlagModel"
	flag.scale = Vector3.ONE * FLAG_SCALE
	add_child(flag)
	_flag_cloth = flag.find_child("Flag", true, false) as Node3D
	if not area.has_volume():
		return
	var half := Vector3(area.size.x * 0.5 - 0.15, 0.0, area.size.z * 0.5 - 0.15)
	var corners: Array[Vector3] = [
		Vector3(-half.x, 0.0, -half.z),
		Vector3(half.x, 0.0, -half.z),
		Vector3(-half.x, 0.0, half.z),
		Vector3(half.x, 0.0, half.z),
	]
	for i in corners.size():
		var post := ModelLibrary.instantiate("goal_corner")
		post.name = "Corner%d" % i
		post.position = corners[i]
		add_child(post)
	var plate := MeshInstance3D.new()
	plate.name = "Floor"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(area.size.x - 0.3, 0.02, area.size.z - 0.3)
	var material := StandardMaterial3D.new()
	material.albedo_color = FLOOR_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	plate.mesh = mesh
	plate.position.y = 0.02
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plate)


func _process(delta: float) -> void:
	_time = fmod(_time + delta, TAU * 10.0)
	if _flag_cloth != null:
		# 布がそよ風でゆれる（竿を軸に少し振る）
		_flag_cloth.rotation.y = sin(_time * 1.7) * 0.12 + sin(_time * 3.1) * 0.04
