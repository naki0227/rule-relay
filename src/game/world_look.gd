class_name WorldLook
extends Node3D
## 島の空気: 空・日の光・霧・色の整え方・遠い雲・舞う花びら・手応えの効果（WorldJuice）をまとめて置く
## （docs/adr/0022-visual-direction-and-quality.md、調べた根拠は docs/quality/research.md）。
## 見た目だけで、当たり判定・台帳・ルールを持たない。どの画面も同じ定義・同じ固定のシードから同じ物を作るので、
## 通信では送らない。画質（VisualQuality）で効果ごとに入り切りし、設定を変えたらすぐ読み直す。
##
## 方針（調べた作品から取り出した一般的な考え方。特定の作品の見た目は写さない）:
## - 空は上の青から地平線の淡い水色へのグラデーション。島の下も白く飛ばさず淡い青にして「浮かぶ島」に見せる
## - 遠くほど空の色へ溶ける（空気遠近）。島より下は高さの霧でかすませ、雲の海の上にいるように見せる
## - 影と環境光は暖かく（黒く濁らせない）、明るい所はふんわりにじませる
## - ルールの色（禁止の赤・貸出のはちみつ・選択の夕日）は効果に使わない。読みやすさを先にする

const NODE_NAME := "WorldLook"

const SKY_TOP := Color("#4a90e2")
const SKY_HORIZON := Color("#cde4f3")
const SKY_BELOW := Color("#c4def0")
const SKY_DEEP := Color("#8fbde3")
const FOG_COLOR := Color("#cfe3f0")
const SUN_COLOR := Color(1.0, 0.92, 0.79)
## 環境光に少し混ぜる暖かい色（影を青黒くしない）。
const AMBIENT_WARM := Color("#fff0da")
## 島の霧の濃さ（遠くほど空の色へ）。広場は広いので overworld_dressing.gd が薄くする。
const FOG_DENSITY := 0.0045
## この高さより下は霧でかすむ（島の底と、下の雲）。
const FOG_HEIGHT := -3.0
const FOG_HEIGHT_DENSITY := 0.09

## 遠い雲（球を組んだかたまり）の数と、1つのかたまりの球の数。
const CLOUDS := 12
const PUFFS_PER_CLOUD := 6
## 雲の輪がゆっくり回る速さ（ラジアン/秒）。
const CLOUD_DRIFT := 0.006
## 雲の固定のシード（どの画面でも同じ並び）。
const CLOUD_SEED := 20261124

static var _dot_texture: GradientTexture2D

var sun: DirectionalLight3D
var world_environment: WorldEnvironment
var environment: Environment
var sky_material: ProceduralSkyMaterial
var juice: WorldJuice

var _clouds: MultiMeshInstance3D
var _cloud_center: Vector3 = Vector3.ZERO
var _motes: GPUParticles3D
var _camera_attributes: CameraAttributesPractical


## parent（島）に空・光・霧と効果を置く。日の光と WorldEnvironment は島の直下に置く
## （広場の作り直しやスクリーンショットの道具が、島の直下から探すため）。
static func attach(parent: Node) -> WorldLook:
	var look := WorldLook.new()
	look.name = NODE_NAME
	look._build_light_and_sky(parent)
	parent.add_child(look)
	return look


## parent の WorldLook（無ければ null）。
static func of(parent: Node) -> WorldLook:
	return parent.get_node_or_null(NODE_NAME) as WorldLook if parent != null else null


func _ready() -> void:
	add_to_group(VisualQuality.GROUP)
	var world := get_parent() as GameWorld
	if world != null:
		juice = WorldJuice.new()
		juice.name = "Juice"
		juice.world = world
		add_child(juice)
	_build_motes()
	# 雲の位置は地形の広さで決める（地形は WorldLook の後に作られる）
	_build_clouds.call_deferred()
	apply_quality()


func _process(delta: float) -> void:
	if _clouds != null and _clouds.visible:
		_clouds.rotate_y(CLOUD_DRIFT * delta)
	if _motes != null and _motes.emitting:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			# 舞う粒はカメラの前のまわりにだけ出す（世界の座標で残るので、動いても粒は流れない）
			_motes.global_position = (
				camera.global_position - camera.global_basis.z * 7.0 + Vector3(0.0, 1.5, 0.0)
			)


## 画質の設定を読み直す（VisualQuality.apply_all から呼ばれる）。
func apply_quality() -> void:
	var flags := VisualQuality.flags()
	if environment != null:
		environment.glow_enabled = bool(flags["glow"])
		environment.ssao_enabled = bool(flags["ssao"])
	if sun != null:
		# 影の縁をぼかす（プロジェクト設定の柔らかい影の質に掛かる）
		sun.shadow_blur = 1.6 if bool(flags["soft_shadow"]) else 0.6
		VisualQuality.apply_sun(sun, flags)  # 影の分割と距離（描画の重さ。docs/adr/0023）
	if world_environment != null:
		world_environment.camera_attributes = (_camera_attributes if bool(flags["dof"]) else null)
	if _clouds != null:
		_clouds.visible = bool(flags["clouds"])
	if _motes != null:
		var amount := int(flags["motes"])
		_motes.emitting = amount > 0
		_motes.visible = amount > 0
		if amount > 0 and _motes.amount != amount:
			_motes.amount = amount
	if juice != null:
		juice.bursts = bool(flags["burst"])
	Foliage.set_enabled(bool(flags["sway"]))


func _build_light_and_sky(parent: Node) -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-35.0), 0.0)
	sun.light_color = SUN_COLOR
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	parent.add_child(sun)

	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = SKY_TOP
	sky_material.sky_horizon_color = SKY_HORIZON
	sky_material.sky_curve = 0.12
	sky_material.ground_horizon_color = SKY_HORIZON
	sky_material.ground_bottom_color = SKY_BELOW
	sky_material.ground_curve = 0.25
	sky_material.sun_angle_max = 12.0
	var sky := Sky.new()
	sky.sky_material = sky_material

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = AMBIENT_WARM
	environment.ambient_light_sky_contribution = 0.8
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 6.0
	# 明るい所のにじみ（画質の中から）。にじみを全体に薄く足して、模型の写真のような柔らかさにする
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.glow_intensity = 0.7
	environment.glow_strength = 0.95
	environment.glow_bloom = 0.02
	environment.glow_hdr_threshold = 1.0
	# すき間・角の陰（画質の高だけ）。光の当たる所にはほとんど掛けない
	environment.ssao_radius = 0.9
	environment.ssao_intensity = 1.6
	environment.ssao_power = 1.4
	environment.ssao_light_affect = 0.1
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.05
	environment.adjustment_saturation = 1.12
	environment.fog_enabled = true
	environment.fog_light_color = FOG_COLOR
	environment.fog_density = FOG_DENSITY
	environment.fog_sky_affect = 0.0  # 空のグラデーションは霧で消さない
	environment.fog_height = FOG_HEIGHT
	environment.fog_height_density = FOG_HEIGHT_DENSITY
	world_environment = WorldEnvironment.new()
	world_environment.environment = environment
	parent.add_child(world_environment)

	# ミニチュア風のぼかし: 遠くだけをやわらかくぼかす（近くの遊び場はくっきり）
	_camera_attributes = CameraAttributesPractical.new()
	_camera_attributes.dof_blur_far_enabled = true
	_camera_attributes.dof_blur_far_distance = 24.0
	_camera_attributes.dof_blur_far_transition = 18.0
	_camera_attributes.dof_blur_amount = 0.06


## 粒の形: 中心が明るく、縁へ向かって透ける丸（四角い粒に見せない）。tint は色、use_vertex は粒ごとの色。
static func soft_dot_material(tint: Color, use_vertex: bool) -> StandardMaterial3D:
	if _dot_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.45, Color(1, 1, 1, 0.9))
		_dot_texture = GradientTexture2D.new()
		_dot_texture.gradient = gradient
		_dot_texture.fill = GradientTexture2D.FILL_RADIAL
		_dot_texture.fill_from = Vector2(0.5, 0.5)
		_dot_texture.fill_to = Vector2(0.5, 0.0)
		_dot_texture.width = 32
		_dot_texture.height = 32
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_texture = _dot_texture
	material.albedo_color = tint
	material.vertex_color_use_as_albedo = use_vertex
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## 遠い雲: 島のまわりの輪に、平たい球を組んだかたまりを置く。全部で1つの MultiMesh（描く回数は1回）。
func _build_clouds() -> void:
	if not is_inside_tree():
		return
	var bounds := _terrain_bounds()
	_cloud_center = bounds.get_center()
	var radius := maxf(bounds.size.x, bounds.size.z) * 0.5
	var sphere := SphereMesh.new()
	sphere.radial_segments = 14
	sphere.rings = 7
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#fbfdff")
	material.roughness = 1.0
	material.emission_enabled = true
	material.emission = Color("#dceaf6")
	material.emission_energy_multiplier = 0.35  # 影の側も灰色に濁らせない
	material.rim_enabled = true
	material.rim = 0.5
	material.rim_tint = 0.2
	sphere.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = sphere
	multimesh.instance_count = CLOUDS * PUFFS_PER_CLOUD
	var rng := RandomNumberGenerator.new()
	rng.seed = CLOUD_SEED
	var index := 0
	for c in CLOUDS:
		var angle := TAU * (float(c) + rng.randf_range(-0.3, 0.3)) / CLOUDS
		var distance := radius + rng.randf_range(16.0, 38.0)
		var height := rng.randf_range(-18.0, 5.0)
		var size := rng.randf_range(2.6, 5.2)
		var center := Vector3(cos(angle) * distance, height, sin(angle) * distance)
		for p in PUFFS_PER_CLOUD:
			var offset := Vector3(
				rng.randf_range(-1.6, 1.6), rng.randf_range(-0.2, 0.5), rng.randf_range(-0.9, 0.9)
			)
			var puff := size * rng.randf_range(0.55, 1.0)
			var basis := Basis.from_scale(Vector3(puff * 1.4, puff * 0.8, puff * 1.1))
			basis = Basis(Vector3.UP, angle) * basis
			var at := center + (Basis(Vector3.UP, angle) * offset) * size
			multimesh.set_instance_transform(index, Transform3D(basis, at))
			index += 1
	_clouds = MultiMeshInstance3D.new()
	_clouds.name = "Clouds"
	_clouds.multimesh = multimesh
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_clouds.position = _cloud_center
	add_child(_clouds)
	apply_quality()


func _terrain_bounds() -> AABB:
	var world := get_parent() as GameWorld
	if world == null or world.terrain == null or world.terrain.cells.is_empty():
		return AABB(Vector3(-15.0, 0.0, -15.0), Vector3(30.0, 1.0, 30.0))
	var low := Vector3(INF, INF, INF)
	var high := -low
	for cell: Vector3i in world.terrain.cells:
		low = low.min(Vector3(cell))
		high = high.max(Vector3(cell))
	return AABB(low, high - low + Vector3.ONE)


## 舞う花びらと光の粒。カメラの前のまわりに少しだけ、ゆっくり落ちて揺れる。
func _build_motes() -> void:
	_motes = GPUParticles3D.new()
	_motes.name = "Motes"
	_motes.amount = 36
	_motes.lifetime = 9.0
	_motes.preprocess = 9.0
	_motes.local_coords = false
	_motes.visibility_aabb = AABB(Vector3(-30.0, -20.0, -30.0), Vector3(60.0, 40.0, 60.0))
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(13.0, 5.0, 11.0)
	process.direction = Vector3(0.4, -1.0, 0.15)
	process.spread = 50.0
	process.initial_velocity_min = 0.12
	process.initial_velocity_max = 0.35
	process.gravity = Vector3(0.05, -0.04, 0.0)
	process.angular_velocity_min = -90.0
	process.angular_velocity_max = 90.0
	process.angle_min = 0.0
	process.angle_max = 360.0
	process.scale_min = 0.6
	process.scale_max = 1.25
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.15, Color(1, 1, 1, 0.85))
	fade.add_point(0.85, Color(1, 1, 1, 0.85))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	# 生成り・淡い花・淡い若葉。禁止の赤・はちみつ・夕日は使わない（ルールの色と混ぜない）
	var tints := Gradient.new()
	tints.set_color(0, Color("#fffaf0"))
	tints.set_color(1, Color("#d9efc4"))
	tints.add_point(0.5, Color("#fde7ee"))
	var tint_texture := GradientTexture1D.new()
	tint_texture.gradient = tints
	process.color_initial_ramp = tint_texture
	_motes.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	quad.material = soft_dot_material(Color.WHITE, true)
	_motes.draw_pass_1 = quad
	add_child(_motes)
