extends TestCase
## StageDef.nature と地形の氷から、ステージ（StageWorld）が自然の仕掛けを組み立てる（docs/adr/0015）。
## ここの demo_stage() が、風・氷・水と流れ・新しい能力の拾える物を 1 つずつ置いた小さな試しの島
## （ステージの作り手がまねする見本。StageCatalog には載せない）。

const SWIM := RuleAction.Kind.SWIM

var world: StageWorld


## 試しの島: 南の草地（出現地点）→ 北へ吹く風の道 → 氷の広場 → 東へ流れる川 → 北の岸のゴール。
##   草地 x -4〜4, z 2〜6／風の道 x -1〜1, z -2〜1（北向き、4 秒ごとに 2 秒）／
##   氷 x -4〜4, z -6〜-3／川 x -4〜4, z -9〜-7（東向きの流れ。底なし）／北の岸 x -4〜4, z -13〜-10。
static func demo_stage() -> StageDef:
	var def := StageDef.new()
	def.stage_id = "zz_nature_demo"
	def.display_name = "自然の仕掛けの見本"
	def.terrain_boxes = [
		[Vector3i(-4, -1, -2), Vector3i(4, -1, 6), "grass"],
		[Vector3i(-4, -1, -6), Vector3i(4, -1, -3), "ice"],
		[Vector3i(-4, -1, -13), Vector3i(4, -1, -10), "grass"],
	]
	def.nature.add_pulsing_wind(
		Vector3i(-1, 0, -2), Vector3i(1, 2, 1), Vector3i(0, 0, -1), 4.0, 2.0
	)
	def.nature.add_current(Vector3i(-4, -2, -9), Vector3i(4, -1, -7), Vector3i(1, 0, 0))
	def.spawn_points = [
		Vector3(-1.5, 0.0, 4.5),
		Vector3(-0.5, 0.0, 4.5),
		Vector3(0.5, 0.0, 4.5),
		Vector3(1.5, 0.0, 4.5)
	]
	var moves: Array[RuleAction.Kind] = [
		RuleAction.Kind.FORWARD,
		RuleAction.Kind.LEFT,
		RuleAction.Kind.BACK,
		RuleAction.Kind.RIGHT,
		RuleAction.Kind.JUMP,
	]
	def.set_loadout_for_all(moves)
	def.world_items = [
		StageDef.PlacementSpec.in_world(RuleAction.Kind.HEAVY, Vector3(-3.5, 0.0, 3.5)),
		StageDef.PlacementSpec.in_world(RuleAction.Kind.FLOAT, Vector3(3.5, 0.0, 3.5)),
		StageDef.PlacementSpec.in_world(SWIM, Vector3(0.5, 0.0, -2.5 - 3.0)),
	]
	var raft := StageDef.BlockSpec.new("raft", Vector3i(-4, -1, -8))
	raft.tokens = [StageDef.TokenSpec.new(RuleAction.Kind.FLOAT)]
	def.blocks = [raft]
	def.clear_condition = ClearCondition.all_at_goal(
		AABB(Vector3(-4.0, -0.1, -13.0), Vector3(9.0, 3.0, 3.0))
	)
	return def


func before_each() -> void:
	world = StageWorld.new()
	world.setup(demo_stage())
	tree.root.add_child(world)
	var loadout := StageLoadout.new(world.def, world.entity_ids)
	loadout.apply(world.ledger, PackedInt32Array([RuleLedger.PLAYER_ID]))
	await wait_physics_frames(5)


func after_each() -> void:
	world.queue_free()
	await tree.process_frame


func test_the_demo_stage_is_valid() -> void:
	assert_true(demo_stage().problems().is_empty(), "%s" % demo_stage().problems())


func test_the_stage_builds_its_nature() -> void:
	assert_eq(world.nature.layout.winds.size(), 1)
	assert_true(world.find_child("Wind", false, false) is WindVisual)
	assert_true(world.find_child("Water", false, false) is WaterVisual)
	assert_true(world.find_child("IceFrost", false, false) is IceFrost)
	assert_true(world.nature.is_ice(Vector3i(0, -1, -4)))
	assert_true(world.player.nature == world.nature, "the player feels it")


func test_new_ability_pickups_use_their_models() -> void:
	var models := PackedStringArray()
	for item: Node in world.find_children("WorldItem*", "WorldItem", false, false):
		models.append(String(item.get_node("Visual/Model").scene_file_path).get_file())
	for model: String in ["heavy_weight.glb", "float_balloon.glb", "swim_fins.glb"]:
		assert_true(models.has(model), "%s in %s" % [model, models])


func test_the_raft_floats_in_the_river_and_drifts_east() -> void:
	var raft := world.blocks[int(world.entity_ids["raft"])]
	await wait_physics_frames(90)
	assert_true(raft.afloat)
	assert_gt(float(raft.cell().x), -4.0, "the current carries it")


func test_the_wind_gusts_on_the_path() -> void:
	world.player.global_position = Vector3(0.5, 0.0, 0.5)
	world.nature.clock = 0.0
	await wait_physics_frames(30)
	assert_lt(world.player.global_position.z, 0.0, "blown north during the gust")
