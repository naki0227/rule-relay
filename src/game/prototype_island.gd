class_name PrototypeIsland
extends GameWorld
## P0 の検証用の小さな島（企画書 10、仮案）。見た目・配置は仮で、世界観は未定。
##
## 座標: 1ブロック = 1m、北 = -Z。地面の上面が y = 0。
## 高台（目標）: x 2..7, z -11..-6, 高さ 3。東に高さ 2 の岩棚（x 8..9）。
## 地面から高台・岩棚へは自力のジャンプ（1.3）では届かない。少なくとも次の解法がある（仮）:
##   1. 跳ねるブロック（紫）の「ジャンプ禁止」を F で拾う → 跳ね始めたブロックに乗って高台へ
##      （自分はジャンプ禁止になるが、外から持ち上げられるのは妨げない）
##   2. 高台の南の3つ並び（中央だけジャンプ禁止）にジャンプを渡し、乗って跳ぶ（単体でも範囲でも）
##   3. 南の青緑ブロックに W を渡して北へ動かし、岩棚の前まで運ぶ → 階段にして登る

const SPAWN := Vector3(0.5, 0.0, 4.5)
const GRASS := Color(0.45, 0.68, 0.38)
const ROCK := Color(0.55, 0.52, 0.48)
const LEDGE := Color(0.62, 0.58, 0.5)

var bouncer: RuleBlock
var row: Array[RuleBlock] = []
var mover: RuleBlock


func _ready() -> void:
	super._ready()
	_build_environment()
	TerrainBuilder.add_box(self, Vector3i(-10, -1, -13), Vector3i(13, -1, 8), GRASS)
	TerrainBuilder.add_box(self, Vector3i(2, 0, -11), Vector3i(7, 2, -6), ROCK)
	TerrainBuilder.add_box(self, Vector3i(8, 0, -11), Vector3i(9, 1, -6), LEDGE)
	_build_blocks()
	_give_starting_items()
	spawn_player(SPAWN)
	checkpoint_center = SPAWN
	goal_box = AABB(Vector3(2.0, 2.9, -11.0), Vector3(6.0, 3.0, 6.0))
	_add_marker(checkpoint_center, Color(0.3, 0.6, 1.0), "チェックポイント（F で保存）")
	_add_marker(Vector3(5.0, 3.0, -8.5), Color(1.0, 0.85, 0.2), "目標: 高台")
	save_checkpoint()


func _build_blocks() -> void:
	bouncer = add_block(Vector3i(1, 0, -8), Color(0.62, 0.42, 0.8))
	ledger.place_on_entity(RuleAction.Kind.JUMP, false, bouncer.entity_id, TriggerMode.Kind.REPEAT)
	ledger.place_on_entity(RuleAction.Kind.JUMP, true, bouncer.entity_id)
	for x: int in [3, 4, 5]:
		row.append(add_block(Vector3i(x, 0, -5)))
	ledger.place_on_entity(RuleAction.Kind.JUMP, true, row[1].entity_id)
	mover = add_block(Vector3i(8, 0, -2), Color(0.3, 0.7, 0.7))


func _give_starting_items() -> void:
	ledger.give_player_item(RuleAction.Kind.FORWARD, false, 0)
	ledger.give_player_item(RuleAction.Kind.LEFT, false, 1)
	ledger.give_player_item(RuleAction.Kind.BACK, false, 2)
	ledger.give_player_item(RuleAction.Kind.RIGHT, false, 3)
	ledger.give_player_item(RuleAction.Kind.JUMP, false, 4)
	select_slot(4)


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-30.0), 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _add_marker(at: Vector3, color: Color, text: String) -> void:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.9
	mesh.bottom_radius = 0.9
	mesh.height = 0.04
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	disc.mesh = mesh
	disc.position = at + Vector3(0.0, 0.03, 0.0)
	add_child(disc)
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at + Vector3(0.0, 1.9, 0.0)
	label.pixel_size = 0.006
	label.font_size = 36
	label.outline_size = 8
	add_child(label)
