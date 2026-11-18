class_name CharacterPreview
extends SubViewportContainer
## 持ち物の画面の左に出す、プレイヤーのモデル（ゆっくり回る）。景色とキャラクターを主役にする。

var _model: Node3D
var _time: float = 0.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	_model = ModelLibrary.instantiate("traveler")
	_model.rotation.y = PI - 0.5  # 顔をこちらへ、少し斜めに
	stage.add_child(_model)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.95, 3.6)
	camera.rotation.x = deg_to_rad(-4.0)
	camera.fov = 30.0
	camera.current = true
	stage.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35.0), deg_to_rad(25.0), 0.0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.96, 0.88)
	stage.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.95, 0.88)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	stage.add_child(world_env)
	# 足元の丸い影の台
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.55
	mesh.bottom_radius = 0.55
	mesh.height = 0.04
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ead9bd")
	mesh.material = material
	disc.mesh = mesh
	disc.position.y = -0.02
	stage.add_child(disc)


func _process(delta: float) -> void:
	if _model != null and is_visible_in_tree():
		# 正面のまわりで、ゆっくり左右に向きを変える（背中を見せ続けない）
		_time += delta
		_model.rotation.y = PI + sin(_time * 0.6) * 0.6
