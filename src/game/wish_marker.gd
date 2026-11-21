class_name WishMarker
extends Node3D
## 願いの行き先（巣）の目印: 巣の床に薄い輪と、上へ伸びる薄い光の柱（2026-11-21 本人
## 「どうぶつがなにをもとめてるのかがわかりにくい」）。遠くからでも行き先が分かり、景色を邪魔しないよう薄くする。
## 願いがかなったら消える（参加者の画面でも、ホストから届いた頭の上の印で判断する）。
## 画面の外にあるときの向きの案内は HUD（WishPointer）が出す。

const BEAM_HEIGHT: float = 7.0
const COLOR := Color(1.0, 0.72, 0.35)

var creature: Creature
var box: AABB = AABB()


## 生き物の行き先（creature.wish_box）に目印を置く。
static func attach(parent: Node3D, who: Creature) -> WishMarker:
	var marker := WishMarker.new()
	marker.name = "WishMarker%d" % who.entity_id
	marker.creature = who
	marker.box = who.wish_box
	parent.add_child(marker)
	return marker


## 行き先の床の真ん中（世界の座標）。箱の上から光線を落として床を探す（見つからなければ箱の底）。
func floor_center() -> Vector3:
	var center := box.get_center()
	var top := Vector3(center.x, box.end.y, center.z)
	var query := PhysicsRayQueryParameters3D.create(
		top, Vector3(center.x, box.position.y - 1.0, center.z), Tuning.LAYER_TERRAIN
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return Vector3(center.x, box.position.y, center.z) if hit.is_empty() else hit["position"]


func _ready() -> void:
	global_position = floor_center()
	var radius := maxf(box.size.x, box.size.z) * 0.5
	var beam := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.06
	cylinder.bottom_radius = radius * 0.35
	cylinder.height = BEAM_HEIGHT
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	beam.mesh = cylinder
	beam.position.y = BEAM_HEIGHT * 0.5
	beam.material_override = _material(0.3)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.06
	torus.outer_radius = radius
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.3, 1.0)
	ring.position.y = 0.04
	ring.material_override = _material(0.7)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)


func _process(_delta: float) -> void:
	visible = is_instance_valid(creature) and creature.bubble_key() != CreatureWishView.KEY_HAPPY


func _material(alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(COLOR, alpha)
	return mat
