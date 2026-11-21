class_name WishMarker
extends Node3D
## 願いの行き先（巣）の目印（2026-11-21 本人「どうぶつがなにをもとめてるのかがわかりにくい」
## 「巣がどこかもわかりにくい」。ADR 0016・0019）:
## - 巣の床に、小枝を編んだ巣のモデル（creature_nest。UI が無くても「動物のおうち」と読める）
## - 巣の床の薄い輪と、島の向こうからでも見える高い光の柱。色は生き物ごと（tint。同じ島に何匹いても、
##   どの巣が誰のか分かる。吹き出しの巣の絵・画面の縁の案内も同じ色）
## - 光の柱は、カメラが巣に近づくと薄くなり、近くでは消える（間近の謎を隠さない）
## - 願いがかなったら輪と柱を消し、巣の上で小さく喜びの輪を広げる。巣のモデルは残る（生き物の家）
## 参加者の画面でも、ホストから届いた頭の上の吹き出し（♪）で同じに判断する。同じ箱を行き先にする生き物が
## 何匹いても、目印は 1 つ（全員の願いがかなうまで柱を出す）。
## 画面の外にあるときの向きの案内は HUD（WishPointer）が出す。

const BEAM_HEIGHT: float = 24.0
## 生き物ごとの色（パレットの夕日・空・若葉・藤・桃）。置いた順に割り当てる。
const TINTS: Array[Color] = [
	Color("#f09a45"), Color("#5f9fcf"), Color("#5d9147"), Color("#9172b8"), Color("#e0644f")
]
## カメラから巣までの水平の距離が FADE_NEAR 以下で柱は消え、FADE_FAR 以上ではっきり見える。
const FADE_NEAR: float = 4.0
const FADE_FAR: float = 13.0
## 巣のモデルの直径（箱の小さいほうの辺に対する割合と、上限 m）。
const NEST_FILL: float = 0.8
const NEST_MAX: float = 1.8
const NEST_MODEL := "creature_nest"
## 喜びの輪が広がって消えるまでの秒数。
const CHEER_TIME: float = 1.4

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.7, 0.35, 0.5);
uniform float fade_near = 4.0;
uniform float fade_far = 13.0;
uniform float height = 24.0;
varying float rise;
varying float near_fade;
void vertex() {
	rise = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 origin = MODEL_MATRIX[3].xyz;
	near_fade = smoothstep(fade_near, fade_far, length(cam.xz - origin.xz));
}
void fragment() {
	float edge = mix(0.3, 1.0, abs(dot(NORMAL, VIEW)));
	float top = 1.0 - smoothstep(0.6, 1.0, rise);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * edge * top * near_fade;
}
"""

static var _beam_shader: Shader

var creatures: Array[Creature] = []
var box: AABB = AABB()
var tint: Color = TINTS[0]
var _beam: MeshInstance3D
var _ring: MeshInstance3D
var _nest: Node3D
var _cheer: MeshInstance3D
var _cheer_left: float = 0.0
var _met: bool = false


## 生き物の行き先（creature.wish_box）に目印を置く。同じ箱の目印がもうあれば、それに生き物を足す。
## 生き物の巣の色（creature.nest_tint）も、ここで決める。
static func attach(parent: Node3D, who: Creature) -> WishMarker:
	var markers: Array[WishMarker] = []
	for child in parent.get_children():
		if child is WishMarker:
			markers.append(child as WishMarker)
	for marker in markers:
		if marker.box.is_equal_approx(who.wish_box):
			marker.creatures.append(who)
			who.set_nest_tint(marker.tint)
			return marker
	var made := WishMarker.new()
	made.name = "WishMarker%d" % who.entity_id
	made.creatures.append(who)
	made.box = who.wish_box
	made.tint = TINTS[markers.size() % TINTS.size()]
	who.set_nest_tint(made.tint)
	parent.add_child(made)
	return made


## 行き先の床の真ん中（世界の座標）。箱の上から光線を落として床を探す（見つからなければ箱の底）。
func floor_center() -> Vector3:
	var center := box.get_center()
	var top := Vector3(center.x, box.end.y, center.z)
	var query := PhysicsRayQueryParameters3D.create(
		top, Vector3(center.x, box.position.y - 1.0, center.z), Tuning.LAYER_TERRAIN
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return Vector3(center.x, box.position.y, center.z) if hit.is_empty() else hit["position"]


## カメラから巣までの水平の距離に対する柱の濃さ（0〜1。シェーダーと同じ式）。
static func beam_fade(distance: float) -> float:
	return smoothstep(FADE_NEAR, FADE_FAR, distance)


## 巣のモデルの直径（m）。
func nest_diameter() -> float:
	return minf(minf(box.size.x, box.size.z) * NEST_FILL, NEST_MAX)


func nest_model() -> Node3D:
	return _nest


## 光の柱と輪を出しているか（願いがかなうと消える）。
func is_beam_shown() -> bool:
	return _beam != null and _beam.visible


func is_cheering() -> bool:
	return _cheer_left > 0.0


func _ready() -> void:
	global_position = floor_center()
	var radius := maxf(box.size.x, box.size.z) * 0.5
	_nest = ModelLibrary.instantiate(NEST_MODEL)
	_nest.name = "Nest"
	_nest.scale = Vector3.ONE * nest_diameter()
	add_child(_nest)
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.25
	cylinder.bottom_radius = clampf(radius * 0.45, 0.35, 0.9)
	cylinder.height = BEAM_HEIGHT
	cylinder.cap_top = false
	cylinder.cap_bottom = false
	cylinder.radial_segments = 24
	_beam.mesh = cylinder
	_beam.position.y = BEAM_HEIGHT * 0.5
	var beam_mat := ShaderMaterial.new()
	beam_mat.shader = beam_shader()
	beam_mat.set_shader_parameter("tint", Color(tint, 0.7))
	beam_mat.set_shader_parameter("fade_near", FADE_NEAR)
	beam_mat.set_shader_parameter("fade_far", FADE_FAR)
	beam_mat.set_shader_parameter("height", BEAM_HEIGHT)
	_beam.material_override = beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_ring = _torus("Ring", radius, 0.7)
	_cheer = _torus("Cheer", radius * 0.5, 0.9)
	_cheer.visible = false


func _process(delta: float) -> void:
	var met := _all_met()
	if met and not _met:
		_cheer_left = CHEER_TIME
	_met = met
	_beam.visible = not met
	_ring.visible = not met
	if _cheer_left > 0.0:
		_cheer_left -= delta
		var t := 1.0 - clampf(_cheer_left / CHEER_TIME, 0.0, 1.0)
		_cheer.visible = _cheer_left > 0.0
		_cheer.scale = Vector3(1.0 + t * 1.6, 0.3, 1.0 + t * 1.6)
		_cheer.position.y = 0.3 + t * 0.6
		(_cheer.material_override as StandardMaterial3D).albedo_color.a = 0.9 * (1.0 - t)
		var squash := sin(t * PI) * 0.12
		_nest.scale = Vector3(1.0 + squash, 1.0 - squash, 1.0 + squash) * nest_diameter()


## 全員の願いがかなったか（参加者の画面でも同じになるよう、頭の上の吹き出しの鍵で見る）。
func _all_met() -> bool:
	for c in creatures:
		if is_instance_valid(c) and c.bubble_key() != CreatureWishView.KEY_HAPPY:
			return false
	return true


func _torus(node_name: String, radius: float, alpha: float) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = node_name
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.06
	torus.outer_radius = radius
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.3, 1.0)
	ring.position.y = 0.04
	ring.material_override = _material(alpha)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	return ring


func _material(alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(tint, alpha)
	return mat


static func beam_shader() -> Shader:
	if _beam_shader == null:
		_beam_shader = Shader.new()
		_beam_shader.code = BEAM_SHADER
	return _beam_shader
