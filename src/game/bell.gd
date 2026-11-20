class_name Bell
extends StaticBody3D
## 鐘（企画書 5.4 の音源。2026-11-19 本人の判断: 音源は基本、鐘）。
## 近くで F を押すと鳴り、しばらく音波を出す。そのあいだ、届く範囲の信号ブロックが動く。
## 投げた玉が当たっても鳴る。動かない置物で、能力の付与先にはならない（entity_id は -1）。
## 吹いて鳴らすアイテム（トランペットなど）は、後で別の音源として足す。

signal rang

const HEIGHT: float = 1.6

## 付与先ではないことを示す（照準・HUD が entity_id を読むため）。
var entity_id: int = -1
## 鳴り終わるまでの残り秒数。0 なら鳴っていない。
var remaining: float = 0.0
var radius: float = Tuning.SIGNAL_RADIUS

var _pulse_timer: float = 0.0
var _swing: float = 0.0
var _cup: Node3D


func _ready() -> void:
	collision_layer = Tuning.LAYER_TERRAIN
	collision_mask = 0
	if get_child_count() == 0:
		_build()


func is_ringing() -> bool:
	return remaining > 0.0


## 鳴らす（鳴っている途中なら、鳴る時間を最初から数え直す）。
func ring() -> void:
	var was_ringing := is_ringing()
	remaining = Tuning.BELL_RING_TIME
	_swing = 1.0
	if not was_ringing:
		_pulse_timer = Tuning.SIGNAL_PULSE_PERIOD
	rang.emit()


## position に音波が届いているか。
func reaches(at: Vector3) -> bool:
	return is_ringing() and global_position.distance_to(at) <= radius


func _physics_process(delta: float) -> void:
	if _cup != null:
		_swing = maxf(0.0, _swing - delta * 0.35)
		_cup.rotation.x = sin(Time.get_ticks_msec() * 0.012) * 0.35 * _swing  # 梁（東西）を軸に揺れる
	if not is_ringing():
		return
	remaining = maxf(0.0, remaining - delta)
	_pulse_timer += delta
	if _pulse_timer >= Tuning.SIGNAL_PULSE_PERIOD:
		_pulse_timer = 0.0
		_emit_pulse()


func capture_state() -> Dictionary:
	return {"remaining": remaining}


func restore_state(state: Dictionary) -> void:
	remaining = float(state.get("remaining", 0.0))


## 音波の輪を1つ出す（届く距離まで広がって消える）。
func _emit_pulse() -> void:
	if not is_inside_tree():
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
	mat.albedo_color = Color(UiTheme.HONEY, 0.7)
	ring_mesh.material_override = mat
	ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring_mesh.top_level = true
	add_child(ring_mesh)
	ring_mesh.global_position = global_position + Vector3(0.0, 0.1, 0.0)
	ring_mesh.scale = Vector3.ONE * 0.6
	var tween := ring_mesh.create_tween().set_parallel()
	tween.tween_property(ring_mesh, "scale", Vector3(radius, 1.0, radius), 1.2)
	tween.tween_property(mat, "albedo_color:a", 0.0, 1.2)
	tween.chain().tween_callback(ring_mesh.queue_free)


func _build() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, HEIGHT, 0.9)
	shape.shape = box
	shape.position.y = HEIGHT * 0.5
	add_child(shape)
	# 見た目は Blender のモデル（art/scripts/build_contraptions.py）。鐘の本体 BellCup は吊り下げ点が原点
	var model := ModelLibrary.instantiate("bell")
	model.name = "Model"
	add_child(model)
	_cup = model.find_child("BellCup", true, false) as Node3D
	var label := Label3D.new()
	label.text = "鐘（%s で鳴らす）" % InputMode.key(&"interact")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = HEIGHT + 0.35
	label.pixel_size = 0.004
	label.font = UiTheme.font(700, 2)
	label.font_size = 36
	label.modulate = UiTheme.INK
	label.outline_modulate = Color(UiTheme.CREAM, 0.95)
	label.outline_size = 12
	add_child(label)
