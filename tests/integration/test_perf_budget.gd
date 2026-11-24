extends TestCase
## 性能の予算（docs/reports/2026-11-24-performance.md）。フレーム時間は PC ごとに違うので測らず、毎回同じに
## なる数（ノード・見えるメッシュの面の数＝描画の呼び出しの上限・光・地形の作り直しの範囲）だけを確かめる。
## 予算は 2026-11-24 の直したあとの値に 15% ほどの余裕を足したもの。超えたら、増えた理由を確かめてから
## 予算を上げるか、まとめて描く（OverworldDressing の MultiMesh・TerrainGrid の区画）ようにする。

## 広場（全部クリアして、生き物と建物が全部そろった状態）。直す前は面 2,651・ノード 3,407。
const HUB_SURFACES := 2350
const HUB_NODES := 3350
const HUB_MESH_INSTANCES := 800
## 重いステージ（地形のセルが多い・生き物が多い）。直す前の面は 140〜300。
const STAGES: Array[String] = [
	"long_expedition", "w7_summit_6", "w6_peak_bells", "w4_herd_path", "o2_5"
]
const STAGE_SURFACES := 400
const STAGE_NODES := 1000
## 1 つのセルを動くブロックにしたときに作り直す地形の区画の数（そのセルのまわり 1 マスにかかる区画）。
const PROMOTE_CHUNKS := 4
## ホストが 1 秒に 20 回配る世界の様子（WorldFrame）の大きさ（バイト）。範囲で 80 マスを動くブロックにした
## あと、全部を送る回と、何も動いていない回。直す前は毎回 約 4,000（UDP の 1 パケットに収まらなかった）。
const FRAME_FULL_BYTES := 3500
const FRAME_QUIET_BYTES := 900

var _nodes: Array[Node] = []


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await tree.process_frame


func _world(def: StageDef) -> StageWorld:
	var world := StageWorld.new()
	world.setup(def)
	_nodes.append(world)
	tree.root.add_child(world)
	return world


func test_hub_stays_within_its_budget() -> void:
	var world := _world(Overworld.build(OverworldState.everything(true)))
	await tree.process_frame
	var counts := PerfCounts.of(world)
	assert_lt(counts["surfaces"], HUB_SURFACES, "visible surfaces (draw calls) %s" % counts)
	assert_lt(counts["nodes"], HUB_NODES, "nodes %s" % counts)
	assert_lt(counts["mesh_instances"], HUB_MESH_INSTANCES, "mesh instances %s" % counts)
	assert_eq(counts["lights"], 1, "only the sun")
	assert_eq(counts["shadow_lights"], 1, "only the sun casts shadows")


func test_heavy_stages_stay_within_their_budget() -> void:
	for stage_id in STAGES:
		var world := _world(StageCatalog.by_id(stage_id))
		await tree.process_frame
		var counts := PerfCounts.of(world)
		assert_lt(counts["surfaces"], STAGE_SURFACES, "%s surfaces %s" % [stage_id, counts])
		assert_lt(counts["nodes"], STAGE_NODES, "%s nodes %s" % [stage_id, counts])
		assert_eq(counts["shadow_lights"], 1, "%s: only the sun casts shadows" % stage_id)
		world.free()
		_nodes.clear()


## 広場の置物は MultiMesh にまとめて描く（1 つずつのノードにしない）。数は減らさない。
func test_hub_props_are_batched_without_losing_any() -> void:
	var world := _world(Overworld.build(OverworldState.everything(true)))
	await tree.process_frame
	var props := world.get_node("OverworldDressing/Props")
	var batches := props.find_children("Batch_*", "MultiMeshInstance3D", false, false)
	assert_gt(batches.size(), 0, "props are drawn as MultiMesh batches")
	assert_eq(
		OverworldDressing.prop_count(world.get_node("OverworldDressing")),
		world.def.overworld.props.size(),
		"every prop is still placed"
	)
	assert_lt(
		props.find_children("*", "MeshInstance3D", true, false).size(),
		20,
		"only animated buildings stay as mesh nodes"
	)


## セルを動くブロックにしても、作り直すのはまわりの区画だけで、全部を作り直したときと同じ形になる。
func test_promoting_a_cell_rebuilds_only_nearby_terrain_chunks() -> void:
	var world := _world(Overworld.build(OverworldState.everything(true)))
	await tree.process_frame
	var terrain := world.terrain
	# 区画の角にあるセル（となりが別の区画）と、区画の真ん中のセル
	for cell: Vector3i in [Vector3i(0, -1, 16), Vector3i(8, -1, 8)]:
		assert_true(terrain.has_cell(cell), "%s is terrain" % cell)
		TerrainPromotion.promote(world, cell)
		terrain.flush()
		assert_lt(terrain.rebuilt_chunks, PROMOTE_CHUNKS + 1, "chunks rebuilt for %s" % cell)
		assert_gt(terrain.rebuilt_chunks, 0)
	var partial := _mesh_digest(terrain)
	terrain.rebuild()
	assert_eq(_mesh_digest(terrain), partial, "partial rebuild = full rebuild (shape and shading)")
	TerrainPromotion.demote(world, Vector3i(0, -1, 16))
	terrain.flush()
	assert_true(terrain.has_cell(Vector3i(0, -1, 16)), "the cell is terrain again")


## 範囲付与でまとめて動くブロックにしても、当たり判定は 1 マスずつ抜いたときと同じ（抜いたマスは下の土台の
## 上面まで空き、となりのマスは地形のまま）。
func test_promoting_many_cells_at_once_keeps_collision_right() -> void:
	var world := _world(Overworld.build(OverworldState.everything(true)))
	await tree.process_frame
	var center := Vector3(2.5, -0.5, 15.5)
	var cells := world.terrain.cells_in_disc(center, BlockRules.DEFAULT_RANGE_RADIUS, -1)
	assert_gt(cells.size(), 60)
	TerrainPromotion.promote_many(world, cells)
	for cell in cells:
		world.blocks[world.promoted[cell]].collision_layer = 0  # 地形だけを見る
	await tree.physics_frame
	await tree.physics_frame
	var space := world.get_world_3d().direct_space_state
	for cell: Vector3i in [cells[0], cells[cells.size() / 2], cells[cells.size() - 1]]:
		var top := _ground_top(space, cell)
		assert_almost(top, -1.0, 0.01, "%s: open down to the foundation" % cell)
	var outside := Vector3i(floori(center.x) + 7, -1, floori(center.z))
	if world.terrain.has_cell(outside):
		assert_almost(_ground_top(space, outside), 0.0, 0.01, "a cell outside the range stays")


static func _ground_top(space: PhysicsDirectSpaceState3D, cell: Vector3i) -> float:
	var from := Vector3(cell.x + 0.5, 6.0, cell.z + 0.5)
	var query := PhysicsRayQueryParameters3D.create(
		from, from + Vector3.DOWN * 20.0, Tuning.LAYER_TERRAIN
	)
	var hit := space.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else -INF


## 範囲付与で選ぶセルは、円を囲む四角だけを調べても、全部のセルを調べたときと同じ。
func test_range_cells_match_a_full_scan() -> void:
	var world := _world(Overworld.build(OverworldState.everything(true)))
	await tree.process_frame
	var radius := BlockRules.DEFAULT_RANGE_RADIUS
	for center: Vector3 in [
		Vector3(2.5, -0.5, 15.5), Vector3(-14.2, 1.5, 8.7), Vector3(40, -0.5, -40)
	]:
		var layer := floori(center.y - 0.5 + 0.001)
		var expected: Array[Vector3i] = []
		for cell: Vector3i in world.terrain.cells:
			var flat := Vector2(cell.x + 0.5 - center.x, cell.z + 0.5 - center.z)
			if cell.y == layer and flat.length() <= radius + 0.0001:
				expected.append(cell)
		var found := world.terrain.cells_in_disc(center, radius, layer)
		expected.sort()
		found.sort()
		assert_eq(found, expected, "cells around %s" % center)


## 世界の様子は、動いたブロックだけを送り、全部の回でも 1 パケットに近い大きさに収まる。受け取った側には
## 同じセルとブロックの位置が届く。
func test_world_frames_stay_small_after_a_big_range_lend() -> void:
	var host := _world(StageCatalog.by_id("w7_summit_6"))
	var guest := _world(StageCatalog.by_id("w7_summit_6"))
	guest.replica = true
	await tree.process_frame
	var center := host.player.global_position + Vector3(0.0, -1.0, -3.0)
	var cells := host.terrain.cells_in_disc(center, BlockRules.DEFAULT_RANGE_RADIUS, -1)
	assert_gt(cells.size(), 60, "a big range")
	for cell in cells:
		TerrainPromotion.promote(host, cell)
	var sender := WorldFrame.Sender.new()
	var full := WorldFrame.capture(host, sender)
	assert_lt(var_to_bytes(full).size(), FRAME_FULL_BYTES, "full frame")
	var ghosts: Array[MeshInstance3D] = []
	WorldFrame.apply(guest, full, ghosts)
	assert_eq(guest.promoted.size(), host.promoted.size(), "the guest promotes the same cells")
	# 落ち着くまで物理を進める（ステージに最初からある動くブロックは動き続けてよい）
	for i in 30:
		await tree.physics_frame
	var quiet := {}
	for i in WorldFrame.REPEAT_AFTER_CHANGE + 2:
		await tree.physics_frame
		quiet = WorldFrame.capture(host, sender)
	assert_eq(_terrain_ids(quiet).size(), 0, "resting promoted cells are not resent")
	assert_lt(var_to_bytes(quiet).size(), FRAME_QUIET_BYTES, "quiet frame")
	assert_false(quiet.has("promoted"), "the cell list is not resent while it does not change")
	# 1 つだけ動かすと、そのセルのブロックだけが入り、受け取った側の目標の位置も変わる
	var id := host.promoted[cells[0]]
	host.blocks[id].teleport(host.blocks[id].global_position + Vector3(0.0, 2.0, 0.0), 0.0)
	var delta := WorldFrame.capture(host, sender)
	assert_eq(_terrain_ids(delta), PackedInt32Array([id]), "only the moved cell's block")
	WorldFrame.apply(guest, delta, ghosts)
	assert_true(guest.blocks[id].remote, "the guest follows the host")
	for node in ghosts:
		node.queue_free()


## 世界の様子に入っている、地形から動くブロックにしたセルのブロックの ID。
static func _terrain_ids(frame: Dictionary) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for id in frame["block_ids"] as PackedInt32Array:
		if id >= GameWorld.FIRST_TERRAIN_ID:
			ids.append(id)
	return ids


## 区画のメッシュの頂点の数と、頂点の色（陰を含む）の合計。
static func _mesh_digest(terrain: TerrainGrid) -> String:
	var count := 0
	var shade := 0.0
	for node in terrain.find_children("Chunk_*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh as ArrayMesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		count += mesh.surface_get_array_len(0)
		for color: Color in mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray:
			shade += color.r + color.g + color.b
	return "%d vertices, shade %.2f" % [count, shade]
