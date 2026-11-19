class_name RuleBlock
extends AnimatableBody3D
## 能力を受け取って自分で動くブロック。隣のブロックと一体化せず、物理も禁止も個別に解決する。
## 動きは自前の運動学（重力・1ブロック移動）で計算し、AnimatableBody3D の同期移動で反映する。
## そのため上に乗ったプレイヤーは床の速度を引き継いで運ばれる。
## プレイヤーとは衝突判定しない（collision_mask にプレイヤーを含めない）ので、乗っている人に
## 押し戻されて止まることはない。

const SIZE: float = 1.0

var entity_id: int = -1
var velocity_y: float = 0.0

var _step_from: Vector3 = Vector3.ZERO
var _step_to: Vector3 = Vector3.ZERO
var _step_time: float = -1.0
var _outline: MeshInstance3D
var _outline_material: StandardMaterial3D
var _corner_markers: Node3D
var _label: Label3D
var _aimed: bool = false
var _assigned: bool = false


func _ready() -> void:
	sync_to_physics = true
	collision_layer = Tuning.LAYER_BLOCKS
	collision_mask = Tuning.LAYER_TERRAIN | Tuning.LAYER_BLOCKS
	if get_child_count() == 0:
		_build_visuals()


func setup(id: int, cell: Vector3i, color: Color) -> void:
	entity_id = id
	name = "Block%d" % id
	position = cell_center(cell)
	set_meta("color", color)


static func cell_center(cell: Vector3i) -> Vector3:
	return Vector3(cell) + Vector3.ONE * (SIZE * 0.5)


func cell() -> Vector3i:
	var p := global_position - Vector3.ONE * (SIZE * 0.5)
	return Vector3i(roundi(p.x), roundi(p.y), roundi(p.z))


func is_moving_horizontally() -> bool:
	return _step_time >= 0.0


func is_grounded() -> bool:
	return velocity_y <= 0.0 and test_move(global_transform, Vector3.DOWN * 0.05)


## 物理的にその行動を始められるか（能力・禁止の判定は BlockRules が先に行う）。
func is_ready_for(action: RuleAction.Kind) -> bool:
	if not is_grounded() or is_moving_horizontally():
		return false
	if action == RuleAction.Kind.JUMP:
		return true
	var dir := Vector3(RuleAction.world_direction(action)) * SIZE
	return not test_move(global_transform, dir * 0.98)


## 行動を実行する。呼ぶ前に is_ready_for と BlockRules.attempt で成功を確かめること。
func perform(action: RuleAction.Kind) -> void:
	if action == RuleAction.Kind.JUMP:
		velocity_y = Tuning.jump_velocity(Tuning.BLOCK_JUMP_HEIGHT)
		return
	_step_from = global_position
	_step_to = global_position + Vector3(RuleAction.world_direction(action)) * SIZE
	_step_time = 0.0


## 下から押し上げられたとき（外力）。禁止はこれを妨げない。
func receive_lift(upward_velocity: float) -> void:
	velocity_y = maxf(velocity_y, upward_velocity)


## チェックポイント復元用。運動学の同期を切って瞬間移動する。
func teleport(target: Vector3, new_velocity_y: float) -> void:
	sync_to_physics = false
	global_position = target
	sync_to_physics = true
	velocity_y = new_velocity_y
	_step_time = -1.0


func capture_state() -> Dictionary:
	return {"position": global_position, "velocity_y": velocity_y}


## 照準が当たっているとき（黄）。付与先の赤い輪郭とは色と太さで区別する。
func set_highlight(on: bool) -> void:
	_aimed = on
	_update_outline()


func show_tokens(tokens: Array[RuleToken]) -> void:
	if _label == null:
		return
	_assigned = false
	var in_range := false
	for t in tokens:
		_assigned = _assigned or (t.vessel_id != -1 and not t.is_prohibition)
		in_range = in_range or t.is_range
	_corner_markers.visible = in_range
	_update_outline()
	var lines := PackedStringArray()
	for t in tokens:
		if t.is_prohibition:
			lines.append("⛔ %s禁止" % RuleAction.label(t.action))
		else:
			var range_mark := "◎範囲 " if t.is_range else ""
			lines.append(
				"%s%s（%s）" % [range_mark, RuleAction.label(t.action), TriggerMode.label(t.mode)]
			)
	_label.text = "\n".join(lines)


func _physics_process(delta: float) -> void:
	_integrate_vertical(delta)
	_integrate_horizontal(delta)


func _integrate_vertical(delta: float) -> void:
	velocity_y -= Tuning.GRAVITY * delta
	var motion := Vector3(0.0, velocity_y * delta, 0.0)
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, motion, hit):
		global_position += motion
		return
	var travel := hit.get_travel()
	if velocity_y > 0.0:
		var above := hit.get_collider() as RuleBlock
		if above != null:
			# 上のブロックを押し上げ、次のフレームから一緒に上がる
			above.receive_lift(velocity_y)
	global_position += travel
	velocity_y = 0.0


func _integrate_horizontal(delta: float) -> void:
	if _step_time < 0.0:
		return
	_step_time = minf(_step_time + delta, Tuning.BLOCK_STEP_DURATION)
	var t := _step_time / Tuning.BLOCK_STEP_DURATION
	var target := _step_from.lerp(_step_to, t)
	var motion := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var hit := KinematicCollision3D.new()
	if test_move(global_transform, motion, hit):
		# 途中で塞がれたら止まる（P0 ではブロックが横に押し合わない）
		global_position += hit.get_travel()
		_step_time = -1.0
		return
	global_position += motion
	if _step_time >= Tuning.BLOCK_STEP_DURATION:
		_step_time = -1.0


func _update_outline() -> void:
	if _outline == null:
		return
	_outline.visible = _aimed or _assigned
	_outline_material.albedo_color = Color(0.9, 0.1, 0.1) if _assigned else Color(1.0, 0.9, 0.3)
	_outline.scale = Vector3.ONE * (1.0 if _assigned else 0.97)


func _build_visuals() -> void:
	var color: Color = get_meta("color", Color(0.85, 0.65, 0.35))
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * (SIZE * 0.98)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	mesh.mesh = box
	add_child(mesh)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3.ONE * SIZE
	shape.shape = box_shape
	add_child(shape)

	# 付与先の表示: 少し大きい箱の裏面だけを赤で描く（反転ハル）。色だけに頼らず文字ラベルも併用する
	_outline = MeshInstance3D.new()
	var outline_box := BoxMesh.new()
	outline_box.size = Vector3.ONE * (SIZE * 1.08)
	_outline_material = StandardMaterial3D.new()
	_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
	outline_box.material = _outline_material
	_outline.mesh = outline_box
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outline.visible = false
	add_child(_outline)

	# 範囲付与の対象: 上面の四隅に濃い赤の角マーカー（企画書 8）
	_corner_markers = Node3D.new()
	var marker_mesh := BoxMesh.new()
	marker_mesh.size = Vector3(0.12, 0.3, 0.12)
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = Color(0.5, 0.0, 0.05)
	marker_mesh.material = marker_material
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var post := MeshInstance3D.new()
		post.mesh = marker_mesh
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		post.position = Vector3(corner.x * 0.47, SIZE * 0.6, corner.y * 0.47)
		_corner_markers.add_child(post)
	_corner_markers.visible = false
	add_child(_corner_markers)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, SIZE * 0.95, 0.0)
	_label.pixel_size = 0.006
	_label.font_size = 40
	_label.outline_size = 10
	_label.no_depth_test = true
	add_child(_label)
