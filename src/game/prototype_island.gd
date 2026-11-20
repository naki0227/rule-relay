class_name PrototypeIsland
extends GameWorld
## P0 の検証用の小さな島（企画書 10、仮案）。見た目・配置は仮で、世界観は未定。
##
## 座標: 1ブロック = 1m、北 = -Z。地面の上面が y = 0。
## 高台（目標）: x 2..7, z -11..-6, 高さ 3。東に高さ 2 の岩棚（x 8..9）。
## 地面から高台・岩棚へは自力のジャンプ（1.3）では届かない。少なくとも次の解法がある（仮）:
##   1. 跳ねるブロック（紫）から F で全部回収（ジャンプとジャンプ禁止）→ 自分のジャンプを繰り返しで渡し直す
##      → 跳ね始めたブロックに乗って高台へ（自分はジャンプ禁止になるが、外から持ち上げられるのは妨げない）
##   2. 高台の南の3つ並び（中央だけジャンプ禁止）にジャンプを渡し、乗って跳ぶ（単体でも範囲でも）
##   3. 南の青緑ブロックに W を渡して北へ動かし、岩棚の前まで運ぶ → 階段にして登る
## 南西の小さな谷（深さ1、幅2）には、W と S を交互に繰り返す往復の足場がある（企画書 4-5・10）。
## 谷の向こうは小島。ジャンプを渡して跳べないときも、往復の足場に乗れば渡れる。
## 装備（企画書 7・10。解法を増やす道具で、唯一の通行証にはしない）:
##   - 小島にジャンプブーツ（高跳び、約2ブロック）→ 岩棚（高さ2）へ跳び、そこから高台へ
##   - 岩棚の東にクライミンググローブ（登る）→ 高台の壁を直接登る
## 鐘と信号（企画書 5.2・5.4）: 高台の西に鐘（F で鳴らすと5秒間、音波が届く距離 6）。3つ並びの西の2つは
## 音波の中、東の1つと青緑のブロックは外にある。信号方式で渡した能力は、鐘が鳴っている間だけ動く。
## 鐘の西 5マスに東向きの発射台。「投げる」を渡すと玉を撃ち、玉が鐘に当たって鳴る（離れていても鳴らせる）。
## 生き物は木の実を1つ持っていて、「投げる」を渡すと立ち止まったときに投げる。
## 生き物（企画書 6・10）: 「高いところへ行きたい」1匹が開始地点の東にいる。W/A/S/D は持っているが
## ジャンプが無いので、低い段しか上がれない。ジャンプを渡すと、自分で段を跳んで高い所へ向かう。

const SPAWN := Vector3(0.5, 0.0, 4.5)
const GROUND_MIN := Vector3i(-10, -1, -13)
const GROUND_MAX := Vector3i(13, -1, 8)
## 木（当たり判定あり）は解法に関わらない島の外周だけに置く。
const TREES: Array[Vector3] = [
	Vector3(-8.5, 0, -11.0),
	Vector3(-6.0, 0, 6.5),
	Vector3(11.5, 0, 5.5),
	Vector3(12.5, 0, -11.5),
	Vector3(-9.0, 0, -2.5),
	Vector3(-3.5, 0, -12.0),
	Vector3(12.0, 0, 0.5),
	Vector3(5.0, 0, 7.0),
]
## 草や花を置かない範囲（パズルの通り道と、開始地点）。見た目だけで当たり判定はない。
const CLEAR_AREA := AABB(Vector3(-1.0, -1.0, -12.0), Vector3(12.0, 4.0, 11.0))
## 谷（床の上面 y = -1）と、その向こうの小島（上面 y = 0）。西寄りの x -7..-4。
const VALLEY_MIN := Vector3i(-7, -2, 9)
const VALLEY_MAX := Vector3i(-4, -2, 10)
const ISLET_MIN := Vector3i(-7, -1, 11)
const ISLET_MAX := Vector3i(-4, -1, 13)
const BOOTS_AT := Vector3(-5.5, 0.0, 12.5)
const GLOVES_AT := Vector3(11.5, 0.0, -8.5)

var bouncer: RuleBlock
var row: Array[RuleBlock] = []
var mover: RuleBlock
var shuttle: RuleBlock
var creature: Creature
var bell: Bell
var launcher: RuleBlock
var _goal_crystal: Node3D
var _time: float = 0.0


func _ready() -> void:
	super._ready()
	_build_environment()
	# 地形はどのセルにも能力を渡せる（渡したセルは動くブロックになる）。見た目はつないで角を丸めたメッシュ
	build_terrain(terrain_boxes())
	_build_scenery()
	_build_blocks()
	_build_creature()
	_give_starting_items()
	spawn_player(SPAWN)
	checkpoint_center = SPAWN
	goal_box = AABB(Vector3(2.0, 2.9, -11.0), Vector3(6.0, 3.0, 6.0))
	_add_model("checkpoint_pad", checkpoint_center)
	_add_label(checkpoint_center + Vector3(0.0, 1.9, 0.0), "チェックポイント（F で保存）")
	_goal_crystal = _add_model("goal_beacon", Vector3(6.6, 3.0, -10.4)).find_child("Crystal")
	_add_label(Vector3(5.0, 4.9, -8.5), "目標: 高台")
	set_initial_checkpoint()


## 動かない地形: [最小のセル, 最大のセル（両端を含む）, 種類]。種類は grass / rock / sand。
static func terrain_boxes() -> Array:
	return [
		[GROUND_MIN, GROUND_MAX, "grass"],
		[Vector3i(2, 0, -11), Vector3i(7, 2, -6), "rock"],
		[Vector3i(8, 0, -11), Vector3i(9, 1, -6), "sand"],
		[VALLEY_MIN, VALLEY_MAX, "rock"],
		[ISLET_MIN, ISLET_MAX, "grass"],
	]


func _build_blocks() -> void:
	bouncer = add_block(Vector3i(1, 0, -8), Color(0.7, 0.58, 0.86))
	ledger.place_on_entity(RuleAction.Kind.JUMP, false, bouncer.entity_id, TriggerMode.Kind.REPEAT)
	ledger.place_on_entity(RuleAction.Kind.JUMP, true, bouncer.entity_id)
	for x: int in [3, 4, 5]:
		row.append(add_block(Vector3i(x, 0, -5)))
	ledger.place_on_entity(RuleAction.Kind.JUMP, true, row[1].entity_id)
	mover = add_block(Vector3i(8, 0, -2), Color(0.45, 0.76, 0.72))
	bell = add_bell(Vector3(-0.5, 0.0, -5.5))
	launcher = add_launcher(Vector3i(-6, 0, -6), Vector3i(1, 0, 0))
	# 谷底を北と南に1マスずつ往復する足場（上面が地面と同じ高さ）
	shuttle = add_block(Vector3i(-6, -1, 9), Color(0.96, 0.78, 0.5))
	ledger.place_on_entity(RuleAction.Kind.BACK, false, shuttle.entity_id, TriggerMode.Kind.REPEAT)
	ledger.place_on_entity(
		RuleAction.Kind.FORWARD, false, shuttle.entity_id, TriggerMode.Kind.REPEAT
	)


func _build_creature() -> void:
	creature = add_creature(Vector3(5.5, 0.0, 0.5))
	creature.held_item = "木の実"
	for action: RuleAction.Kind in CheckpointPolicy.MOVE_ACTIONS:
		ledger.place_on_entity(action, false, creature.entity_id)


func _give_starting_items() -> void:
	ledger.give_player_item(RuleAction.Kind.FORWARD, false, 0)
	ledger.give_player_item(RuleAction.Kind.LEFT, false, 1)
	ledger.give_player_item(RuleAction.Kind.BACK, false, 2)
	ledger.give_player_item(RuleAction.Kind.RIGHT, false, 3)
	ledger.give_player_item(RuleAction.Kind.JUMP, false, 4)
	ledger.give_player_item(RuleAction.Kind.THROW, false, 5)
	select_slot(4)
	ledger.place_in_world(
		RuleAction.Kind.HIGH_JUMP, false, BOOTS_AT, RuleVessel.Part.FEET, "ジャンプブーツ"
	)
	ledger.place_in_world(
		RuleAction.Kind.CLIMB, false, GLOVES_AT, RuleVessel.Part.HANDS, "クライミンググローブ"
	)


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-35.0), 0.0)
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.4, 0.64, 0.9)
	sky_material.sky_horizon_color = Color(0.86, 0.92, 0.93)
	sky_material.ground_horizon_color = Color(0.86, 0.92, 0.93)
	sky_material.ground_bottom_color = Color(0.78, 0.84, 0.88)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.9, 0.92, 0.9)
	env.fog_density = 0.004
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


## 島の見た目: 浮かぶ岩の底、外周の木、草・花・小石（固定シードで毎回同じ配置）。
func _build_scenery() -> void:
	var size := Vector3(GROUND_MAX - GROUND_MIN + Vector3i.ONE)
	var base := _add_model(
		"island_base", Vector3(GROUND_MIN) + Vector3(size.x * 0.5, 0.0, size.z * 0.5)
	)
	base.position.y = -0.98
	base.scale = Vector3(size.x * 1.02, 9.0, size.z * 1.02)
	for i in TREES.size():
		var at := TREES[i]
		var tree := _add_model("tree_round" if i % 2 == 0 else "tree_tall", at)
		tree.rotation.y = float(i) * 1.7
		_add_trunk_collision(at)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261118
	var kinds: Array[String] = ["grass_tuft", "grass_tuft", "grass_tuft", "flower", "pebbles"]
	for i in 70:
		var at := Vector3(
			rng.randf_range(GROUND_MIN.x + 0.5, GROUND_MAX.x + 0.5),
			0.0,
			rng.randf_range(GROUND_MIN.z + 0.5, GROUND_MAX.z + 0.5)
		)
		if CLEAR_AREA.has_point(at + Vector3(0.0, 0.5, 0.0)):
			continue
		var prop := _add_model(kinds[rng.randi() % kinds.size()], at)
		prop.rotation.y = rng.randf() * TAU
		prop.scale = Vector3.ONE * rng.randf_range(0.8, 1.3)


func _add_model(model_name: String, at: Vector3) -> Node3D:
	var model := ModelLibrary.instantiate(model_name)
	model.position = at
	add_child(model)
	return model


func _add_trunk_collision(at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Tuning.LAYER_TERRAIN
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.25
	cylinder.height = 2.0
	shape.shape = cylinder
	shape.position = Vector3(0.0, 1.0, 0.0)
	body.add_child(shape)
	body.position = at
	add_child(body)


func _process(delta: float) -> void:
	_time += delta
	if _goal_crystal != null:
		_goal_crystal.rotation.y = _time * 1.2
		_goal_crystal.position.y = 1.55 + sin(_time * 2.0) * 0.08


func _add_label(at: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	label.pixel_size = 0.005
	label.font = UiTheme.font(700, 2)
	label.font_size = 40
	label.modulate = UiTheme.INK
	label.outline_modulate = Color(UiTheme.CREAM, 0.95)
	label.outline_size = 14
	add_child(label)
