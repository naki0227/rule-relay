class_name RuleBlock
extends AnimatableBody3D
## 能力を受け取って自分で動くブロック。隣のブロックと一体化せず、物理も禁止も個別に解決する。
## 動きは自前の運動学（重力・1ブロック移動）で計算し、AnimatableBody3D の同期移動で反映する。
## そのため上に乗ったプレイヤーは床の速度を引き継いで運ばれる。
## プレイヤーとは衝突判定しない（collision_mask にプレイヤーを含めない）ので、乗っている人に
## 押し戻されて止まることはない。

## 効果音のための合図（音そのものは SoundBank が鳴らす）。
signal jumped
signal landed(impact_speed: float)
signal stepped

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
var _in_range: bool = false
var _previewed: bool = false
var _marker_material: StandardMaterial3D
var _signal_label: Label3D
## 登る（クライミンググローブの能力）を持っているとき、底面をこの高さまで上げてつかまる。NAN なら登らない。
var _climb_bottom: float = NAN


func _ready() -> void:
	sync_to_physics = true
	collision_layer = Tuning.LAYER_BLOCKS
	collision_mask = Tuning.LAYER_TERRAIN | Tuning.LAYER_BLOCKS
	if get_child_count() == 0:
		_build_visuals()


func setup(id: int, cell: Vector3i, color: Color, model_name: String = "ability_block") -> void:
	entity_id = id
	name = "Block%d" % id
	position = cell_center(cell)
	set_meta("color", color)
	set_meta("model", model_name)


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
## high_jump: 高跳び（ジャンプブーツの能力）を持っていれば、跳ぶ高さが固定で上がる。
func perform(action: RuleAction.Kind, high_jump: bool = false) -> void:
	if action == RuleAction.Kind.JUMP:
		var height := Tuning.BLOCK_HIGH_JUMP_HEIGHT if high_jump else Tuning.BLOCK_JUMP_HEIGHT
		velocity_y = Tuning.jump_velocity(height)
		jumped.emit()
		return
	stepped.emit()
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


## チェックポイント用。1ブロック移動の途中で保存しても、復元後に同じ動きの続きをして
## マス目に収まるよう、移動の始点・終点・経過時間も残す。
func capture_state() -> Dictionary:
	return {
		"position": global_position,
		"velocity_y": velocity_y,
		"step_from": _step_from,
		"step_to": _step_to,
		"step_time": _step_time,
	}


func restore_state(state: Dictionary) -> void:
	teleport(state["position"] as Vector3, float(state["velocity_y"]))
	_step_from = state.get("step_from", global_position) as Vector3
	_step_to = state.get("step_to", global_position) as Vector3
	_step_time = float(state.get("step_time", -1.0))


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
	_in_range = in_range
	_update_markers()
	_update_outline()
	# 持っている能力・禁止を、ブロックの上に器のアイコンで並べる（文字より重なりにくい）。
	# 禁止は赤い輪と斜線の形で、能力の下には発動方式を小さく書く
	for child in _label.get_children():
		child.queue_free()
	var count := tokens.size()
	for i in count:
		var t := tokens[i]
		var icon := Sprite3D.new()
		icon.texture = ItemIcons.for_token(t)
		icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		icon.pixel_size = 0.0032
		icon.no_depth_test = true
		icon.render_priority = 1
		icon.position = Vector3((float(i) - float(count - 1) * 0.5) * 0.46, 0.0, 0.0)
		_label.add_child(icon)
		if not t.is_prohibition:
			var note := Label3D.new()
			note.text = ("範囲・" if t.is_range else "") + TriggerMode.label(t.mode)
			note.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			note.pixel_size = 0.0035
			note.font = UiTheme.font(600)
			note.font_size = 36
			note.modulate = UiTheme.INK
			note.outline_modulate = Color(UiTheme.CREAM, 0.95)
			note.outline_size = 12
			note.no_depth_test = true
			note.render_priority = 2
			note.position = Vector3(0.0, -0.27, 0.0)
			icon.add_child(note)


func _physics_process(delta: float) -> void:
	_integrate_vertical(delta)
	_integrate_horizontal(delta)


## 登る: 隣のマス（東西南北）でいちばん高い上面まで、自分の上面がそろう高さへ登ってつかまる
## （2026-11-19 本人の判断。例: 高さ 1・3・[1]・2 の [1] に渡すと、左の 3 の高さまで登る。両側の高さにはならない）。
## target_bottom は底面の高さ。NAN を渡すと登るのをやめ、重力で落ちる。
func set_climb_target(target_bottom: float) -> void:
	_climb_bottom = target_bottom


func is_climbing() -> bool:
	return not is_nan(_climb_bottom) and global_position.y - SIZE * 0.5 < _climb_bottom + 0.01


func _integrate_vertical(delta: float) -> void:
	if _integrate_climb(delta):
		return
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
	if velocity_y < -3.0:
		landed.emit(-velocity_y)
	velocity_y = 0.0


## 登っている・つかまっているなら重力の代わりに上へ動かし、true を返す。
func _integrate_climb(delta: float) -> bool:
	if is_nan(_climb_bottom) or velocity_y > 0.0:
		return false  # 跳んでいる最中は登らない
	var bottom := global_position.y - SIZE * 0.5
	if bottom > _climb_bottom + 0.01:
		return false  # つかまる高さより上にいる（重力で降りてくる）
	velocity_y = 0.0
	var rise := minf(Tuning.CLIMB_SPEED * delta, _climb_bottom - bottom)
	if rise <= 0.0:
		return true  # つかまっている
	var motion := Vector3(0.0, rise, 0.0)
	var hit := KinematicCollision3D.new()
	if test_move(global_transform, motion, hit):
		global_position += hit.get_travel()  # 頭上が塞がれたらそこで止まる
	else:
		global_position += motion
	return true


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


## 範囲プレビューの対象になっているか（右クリックを押している間）。
func set_preview(on: bool) -> void:
	_previewed = on
	_update_markers()


func is_previewed() -> bool:
	return _previewed


## 角マーカー: 付与済みの範囲は濃い赤、プレビュー中は明るい赤で、背を高くして区別する。
func _update_markers() -> void:
	if _corner_markers == null:
		return
	_corner_markers.visible = _in_range or _previewed
	_marker_material.albedo_color = (
		Color(0.94, 0.54, 0.47) if _previewed else Color(0.66, 0.22, 0.18)
	)
	_corner_markers.scale = Vector3(1.0, 1.6 if _previewed else 1.0, 1.0)


func _update_outline() -> void:
	if _outline == null:
		return
	_outline.visible = _aimed or _assigned
	_outline_material.albedo_color = Color("#d9483b") if _assigned else UiTheme.SUN
	_outline.scale = Vector3.ONE * (1.0 if _assigned else 0.97)


func _build_visuals() -> void:
	var color: Color = get_meta("color", Color(0.85, 0.65, 0.35))
	# 見た目は Blender のモデル（art/source/*.blend）。能力のブロックは各面のパネルをブロックの色にする。
	# 地形から動くブロックにしたセルは、その種類のセルの形（grass_cell など）
	var model_name := String(get_meta("model", "ability_block"))
	var model := ModelLibrary.instantiate(model_name)
	model.name = "Model"
	if model_name == "ability_block":
		ModelLibrary.tint_material(model, "Panel", color)
	add_child(model)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	# 横は少しだけ細くする。となりの地形と面がぴったり接していると、物理エンジン（Jolt）の
	# 動きの判定が、最初から重なっているとみなして床を見落とした（地形のセルを動くブロックにしたとき）
	box_shape.size = Vector3(SIZE * 0.98, SIZE, SIZE * 0.98)
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
	_marker_material = StandardMaterial3D.new()
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mesh.material = _marker_material
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
	_label.position = Vector3(0.0, SIZE * 0.95 + 0.12, 0.0)
	_label.pixel_size = 0.005
	_label.font = UiTheme.medium()
	_label.font_size = 40
	_label.modulate = UiTheme.INK
	_label.outline_modulate = Color(UiTheme.CREAM, 0.95)
	_label.outline_size = 14
	_label.no_depth_test = true
	add_child(_label)


# --- 音波（企画書 5.2 信号・5.4 音源） ---------------------------------------


## 発射台にする（「投げる」を渡すと direction へ玉を撃つ）。撃つ向きに矢印の札を付ける。
func make_launcher(direction: Vector3i) -> void:
	var note := Label3D.new()
	note.text = "発射台 → %s" % _direction_name(direction)
	note.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	note.position = Vector3(0.0, SIZE * 0.5 + 0.35, 0.0)
	note.pixel_size = 0.004
	note.font = UiTheme.font(700, 2)
	note.font_size = 36
	note.modulate = UiTheme.INK
	note.outline_modulate = Color(UiTheme.CREAM, 0.95)
	note.outline_size = 12
	add_child(note)


static func _direction_name(direction: Vector3i) -> String:
	match direction:
		Vector3i(0, 0, -1):
			return "北"
		Vector3i(0, 0, 1):
			return "南"
		Vector3i(1, 0, 0):
			return "東"
	return "西"


## 信号方式の能力を持つときの表示: 受信中（音波が届いて動く）／休止中（届かず止まっている）。
func set_signal_state(has_signal: bool, receiving: bool) -> void:
	if not has_signal:
		if _signal_label != null:
			_signal_label.visible = false
		return
	if _signal_label == null:
		_signal_label = Label3D.new()
		_signal_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_signal_label.position = Vector3(0.0, SIZE * 0.95 + 0.55, 0.0)
		_signal_label.pixel_size = 0.0035
		_signal_label.font = UiTheme.font(700, 2)
		_signal_label.font_size = 36
		_signal_label.outline_modulate = Color(UiTheme.CREAM, 0.95)
		_signal_label.outline_size = 12
		_signal_label.no_depth_test = true
		_signal_label.render_priority = 2
		add_child(_signal_label)
	_signal_label.visible = true
	_signal_label.text = "♪ 受信中" if receiving else "休止中（音が届かない）"
	_signal_label.modulate = UiTheme.LEAF.darkened(0.25) if receiving else UiTheme.INK_FAINT
