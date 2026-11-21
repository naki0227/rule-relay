extends TestCase
## 島の地面には厚さがある（2026-11-21 本人の試遊「なんで床抜けるもん。浮島の地面一段しかないからめっちゃすぐ
## 抜けるしな」。docs/adr/0003 決定 8・src/game/terrain_grid.gd）。
## 再現（前の作り）: 高さ 0 の地面は y = -1 の1段だけで、セルに能力を渡して跳ばす・動かすと、跡から島の下の空が
## 見えた（見えない岩盤で落ちはしない）。地面に範囲で D を繰り返しで渡すと、島の縁に面したセルから列ごとに
## 島の外へ落ちていった（最大 19 マスが元の場所から離れた）。
## 今: 島の地面の下に見える土台（能力は渡せない）が 3 段あり、抜けた跡は土の床が見える深さ 1 の窪みになる。

const W := RuleAction.Kind.FORWARD
const A := RuleAction.Kind.LEFT
const S := RuleAction.Kind.BACK
const D := RuleAction.Kind.RIGHT
const JUMP := RuleAction.Kind.JUMP

var island: PrototypeIsland


func before_each() -> void:
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	await wait_physics_frames(10)


func after_each() -> void:
	if is_instance_valid(island):
		island.queue_free()
	await tree.process_frame


## (x, z) の列を上から下へ光線で調べ、当たった高さ（地形・ブロック）。何も無ければ -INF（島の下の空）。
func floor_height(x: int, z: int) -> float:
	var at := Vector3(x + 0.5, 6.0, z + 0.5)
	var q := PhysicsRayQueryParameters3D.create(at, at + Vector3(0.0, -40.0, 0.0))
	q.collision_mask = Tuning.LAYER_TERRAIN | Tuning.LAYER_BLOCKS
	var hit := island.get_world_3d().direct_space_state.intersect_ray(q)
	return -INF if hit.is_empty() else (hit["position"] as Vector3).y


## 地面のセル cell（上面 y = 0）が抜けても、その真下に見える土の床があり、深さは 1 まで。
func assert_solid_under(cell: Vector3i, why: String) -> void:
	assert_true(
		island.terrain.foundation.has(cell + Vector3i.DOWN), "%s: visible ground below" % why
	)
	assert_gt(floor_height(cell.x, cell.z), float(cell.y) - 0.05, "%s: at most a 1-deep dent" % why)


func lend_single(action_slot: int, cell: Vector3i, mode: TriggerMode.Kind) -> RuleBlock:
	island.player.global_position = Vector3(cell.x + 0.5, 0.05, cell.z + 2.5)
	await wait_physics_frames(6)
	island.select_slot(action_slot)
	island.set_lend_mode(mode)
	assert_eq(island.lend_to(island.terrain_target(cell), false), RuleLedger.LendResult.OK)
	island.player.global_position = Vector3(cell.x + 0.5, 0.05, cell.z + 4.5)
	return island.blocks[island.promoted[cell]]


func test_every_ground_column_has_a_visible_foundation() -> void:
	for x in range(PrototypeIsland.GROUND_MIN.x, PrototypeIsland.GROUND_MAX.x + 1):
		for z in range(PrototypeIsland.GROUND_MIN.z, PrototypeIsland.GROUND_MAX.z + 1):
			var low := -1
			while island.terrain.has_cell(Vector3i(x, low - 1, z)):
				low -= 1
			if not island.terrain.has_cell(Vector3i(x, low, z)):
				continue
			for d in TerrainGrid.FOUNDATION_DEPTH:
				var below := Vector3i(x, low - 1 - d, z)
				if not island.terrain.foundation.has(below):
					fail("no foundation at %s" % below)
					return
				assert_false(
					island.terrain.has_cell(below), "the foundation is not a lendable cell"
				)


func test_single_lends_of_every_kind_leave_a_shallow_dent() -> void:
	# 地面の中のセル（四方が地形）は W/A/S/D では動かないので、谷の縁のセルで動かす
	var edge := Vector3i(-5, -1, 8)  # 南西の谷（上面 y = -1）の北の縁
	var block := await lend_single(2, edge, TriggerMode.Kind.SINGLE_SHOT)  # S（南 = 谷へ）
	island.press_action(S)
	await wait_physics_frames(90)
	assert_ne(block.cell(), edge, "the cell was pushed into the valley")
	assert_solid_under(edge, "S into the valley")
	for pair: Array in [[0, W, Vector3i(-8, -1, -13)], [1, A, Vector3i(-10, -1, -4)]]:
		var cell := pair[2] as Vector3i  # 島の北・西の縁: 押すと島の外へ落ちる
		var b := await lend_single(int(pair[0]), cell, TriggerMode.Kind.SINGLE_SHOT)
		island.press_action(pair[1] as RuleAction.Kind)
		await wait_physics_frames(50)
		assert_lt(b.global_position.y, -1.0, "a cell pushed off the island still falls")
		assert_solid_under(cell, "%s off the edge" % RuleAction.label(pair[1] as RuleAction.Kind))
	var east := Vector3i(13, -1, -4)
	var b2 := await lend_single(3, east, TriggerMode.Kind.SINGLE_SHOT)
	island.press_action(D)
	await wait_physics_frames(50)
	assert_lt(b2.global_position.y, -1.0)
	assert_solid_under(east, "D off the edge")
	var jumper := Vector3i(-3, -1, 1)
	await lend_single(4, jumper, TriggerMode.Kind.SINGLE_SHOT)
	island.press_action(JUMP)
	await wait_physics_frames(12)
	assert_solid_under(jumper, "while the cell is in the air")


func test_a_range_jump_on_the_ground_leaves_no_hole_to_the_sky() -> void:
	var center := Vector3i(-3, -1, 2)
	island.player.global_position = Vector3(-2.5, 0.05, 4.5)
	await wait_physics_frames(6)
	island.select_slot(4)
	island.set_lend_mode(TriggerMode.Kind.SINGLE_SHOT)
	assert_eq(island.lend_to(island.terrain_target(center), true), RuleLedger.LendResult.OK)
	island.player.global_position = Vector3(5.5, 0.05, 6.5)  # 円の外
	await wait_physics_frames(4)
	island.press_action(JUMP)
	await wait_physics_frames(14)
	var lifted := 0
	for cell: Vector3i in island.promoted:
		if island.blocks[island.promoted[cell]].global_position.y > 0.0:
			lifted += 1
		assert_solid_under(cell, "range jump %s" % cell)
	assert_gt(float(lifted), 30.0, "the circle of ground is in the air")


func test_range_moves_on_the_ground_do_not_shed_the_floor_off_the_edge() -> void:
	island.player.global_position = Vector3(11.5, 0.05, 2.5)
	await wait_physics_frames(10)
	island.select_slot(3)  # D（東 = 島の縁の外へ）
	island.set_lend_mode(TriggerMode.Kind.REPEAT)
	assert_eq(
		island.lend_to(island.terrain_target(Vector3i(11, -1, 0)), true), RuleLedger.LendResult.OK
	)
	island.player.global_position = Vector3(12.5, 0.05, 0.5)  # 円の中、縁のすぐ手前に立つ
	var low := 0.0
	for i in int(60 * Tuning.REPEAT_PERIOD * 4.0):
		await tree.physics_frame
		low = minf(low, island.player.global_position.y)
	for cell: Vector3i in island.promoted:
		assert_eq(island.blocks[island.promoted[cell]].cell(), cell, "the circle stays put")
	assert_gt(low, -0.2, "the player was not carried off the island")


func test_the_foundation_cannot_be_aimed_or_lent() -> void:
	var cell := Vector3i(-3, -1, 1)
	await lend_single(4, cell, TriggerMode.Kind.SINGLE_SHOT)
	var below := cell + Vector3i.DOWN
	assert_true(island.terrain.foundation.has(below))
	assert_false(island.terrain.has_cell(below), "not a terrain cell: the aim never picks it")


func test_stage_terrain_keeps_every_lendable_cell_and_gains_only_a_foundation() -> void:
	var defs := StageCatalog.all_stages()
	defs.append(StageCatalog.hub())
	defs.append(StageCatalog.intro_jump_lend())
	for def in defs:
		var grid := TerrainGrid.new()
		tree.root.add_child(grid)
		grid.build(def.terrain_boxes)
		var expected := {}
		for box: Array in def.terrain_boxes:
			var lo := box[0] as Vector3i
			var hi := box[1] as Vector3i
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					for z in range(lo.z, hi.z + 1):
						expected[Vector3i(x, y, z)] = true
		assert_eq(grid.cells.size(), expected.size(), "%s: same lendable cells" % def.stage_id)
		var overlaps := 0
		for cell: Vector3i in grid.foundation:
			if expected.has(cell):
				overlaps += 1
		assert_eq(overlaps, 0, "%s: the foundation is only below the old ground" % def.stage_id)
		for b in def.blocks:
			assert_false(
				grid.foundation.has(b.cell), "%s: block %s is clear" % [def.stage_id, b.key]
			)
		var shapes := grid.get_node("TerrainBody").get_child_count()
		assert_lt(float(shapes), 6000.0, "%s: merged collision boxes (%d)" % [def.stage_id, shapes])
		grid.free()
