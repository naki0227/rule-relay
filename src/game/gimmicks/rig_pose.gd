class_name RigPose
extends RefCounted
## 骨格付きの仕掛けのモデル（art/scripts/build_switches.py）のアニメーションを、状態の度合い（0〜1）に
## 合わせた位置で止めて見せる係。板の沈み・扉の開き・レバーの倒れ具合は、ゲームの状態から決まるので、
## 時間で再生せず、再生位置を合わせる（参加者の画面でも、届いた状態から同じ姿になる）。


## model の中の AnimationPlayer（無ければ null。テスト用の空の木など）。
static func player_of(model: Node) -> AnimationPlayer:
	if model == null:
		return null
	var found := model.find_children("*", "AnimationPlayer", true, false)
	return null if found.is_empty() else found[0] as AnimationPlayer


## clip を fraction（0 = 始め、1 = 終わり）の姿で止める。
static func hold(player: AnimationPlayer, clip: StringName, fraction: float) -> void:
	if player == null or not player.has_animation(clip):
		return
	if player.assigned_animation != clip:
		player.play(clip)
		player.pause()
	player.seek(clampf(fraction, 0.0, 1.0) * player.get_animation(clip).length, true)


## clip を最初から 1 回再生する（ワープの石の光・砂時計の返し）。
static func play_once(player: AnimationPlayer, clip: StringName) -> void:
	if player == null or not player.has_animation(clip):
		return
	player.stop()
	player.play(clip)


## clip を繰り返し再生する（ワープの石の結晶のゆれ）。
static func loop(player: AnimationPlayer, clip: StringName) -> void:
	if player == null or not player.has_animation(clip):
		return
	player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	player.play(clip)


## 床に広がって消える輪（鐘の音波と同じ見た目。板・レバーが音波を出すとき）。
static func pulse(parent: Node3D, radius: float, color: Color) -> void:
	if not parent.is_inside_tree():
		return
	var ring_mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.96
	torus.outer_radius = 1.0
	torus.rings = 48
	ring_mesh.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color, 0.7)
	ring_mesh.material_override = mat
	ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_mesh.top_level = true
	parent.add_child(ring_mesh)
	ring_mesh.global_position = parent.global_position + Vector3(0.0, 0.1, 0.0)
	ring_mesh.scale = Vector3.ONE * 0.6
	var tween := ring_mesh.create_tween().set_parallel()
	tween.tween_property(ring_mesh, "scale", Vector3(radius, 1.0, radius), 1.2)
	tween.tween_property(mat, "albedo_color:a", 0.0, 1.2)
	tween.chain().tween_callback(ring_mesh.queue_free)
