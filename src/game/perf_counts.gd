class_name PerfCounts
extends RefCounted
## 場面の重さの目安になる、毎回同じになる数（性能の測定 tools/perf_bench.gd と、予算のテスト
## tests/integration/test_perf_budget.gd が使う。docs/reports/2026-11-24-performance.md）。
## 描画の呼び出し回数は描画サーバーが無いヘッドレスでは 0 になるので、その代わりに「見えるメッシュの面
## （surface）の数」を数える（MultiMesh は 1 つで 1 回。カメラの外のものも数えるので、実際の回数の上限）。


## root より下を数える。
static func of(root: Node) -> Dictionary:
	var counts := {
		"nodes": 0,
		"mesh_instances": 0,
		"multimesh_instances": 0,
		"surfaces": 0,
		"labels_3d": 0,
		"lights": 0,
		"shadow_lights": 0,
		"collision_shapes": 0,
		"bodies": 0,
		"processing": 0,
		"physics_processing": 0,
	}
	if root != null:
		_walk(root, counts, true)
	return counts


static func _walk(node: Node, counts: Dictionary, visible: bool) -> void:
	counts["nodes"] += 1
	if node.is_processing():
		counts["processing"] += 1
	if node.is_physics_processing():
		counts["physics_processing"] += 1
	var shown := visible
	if node is Node3D:
		shown = visible and (node as Node3D).visible
	if node is CollisionShape3D and not (node as CollisionShape3D).disabled:
		counts["collision_shapes"] += 1
	elif node is CollisionObject3D:
		counts["bodies"] += 1
	if shown:
		_count_visual(node, counts)
	for child in node.get_children():
		_walk(child, counts, shown)


static func _count_visual(node: Node, counts: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null and mesh.get_surface_count() > 0:
			counts["mesh_instances"] += 1
			counts["surfaces"] += mesh.get_surface_count()
	elif node is MultiMeshInstance3D:
		var multimesh := (node as MultiMeshInstance3D).multimesh
		if multimesh != null and multimesh.mesh != null and multimesh.visible_instance_count != 0:
			counts["multimesh_instances"] += 1
			counts["surfaces"] += multimesh.mesh.get_surface_count()
	elif node is Label3D:
		counts["labels_3d"] += 1
		counts["surfaces"] += 1
	elif node is SpriteBase3D or node is CPUParticles3D:
		counts["surfaces"] += 1
	elif node is Light3D:
		counts["lights"] += 1
		if (node as Light3D).shadow_enabled:
			counts["shadow_lights"] += 1
