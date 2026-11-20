class_name HubDressing
extends RefCounted
## 広場（ハブ）の飾り付け: 街灯・柵・鉢植え・ベンチ・木と草花。人が手入れしている場所に見せる。
## すべて見た目だけで当たり判定はない（遊び方を変えない）。歩く道（出現地点と入口の並び）には置かない。
## モデルは art/scripts/build_hub_props.py と build_assets.py。配置は固定シードで毎回同じ。

## 出現地点から入口の並びまでの、何も置かない帯（x は広場いっぱい）。
const WALK_Z_MIN: float = -8.2
const WALK_Z_MAX: float = 5.2


static func build(parent: Node3D, def: StageDef) -> void:
	if def.terrain_boxes.is_empty():
		return
	var lo := Vector3(def.terrain_boxes[0][0] as Vector3i)
	var hi := Vector3(def.terrain_boxes[0][1] as Vector3i) + Vector3.ONE
	var dressing := Node3D.new()
	dressing.name = "HubDressing"
	parent.add_child(dressing)
	_lamps(dressing, def)
	_fences(dressing, lo, hi)
	_corner_garden(dressing, lo, hi)
	_scatter(dressing, lo, hi)


## 入口と入口のあいだ（1つおき）と、出現地点の両わきに街灯。
static func _lamps(parent: Node3D, def: StageDef) -> void:
	for i in range(0, def.entrances.size() - 1, 2):
		var a := def.entrances[i].position
		var b := def.entrances[i + 1].position
		_put(parent, "hub_lamp", Vector3((a.x + b.x) * 0.5, 0.0, a.z + 0.4), 0.0)
	var spawn := def.spawn_point(0)
	_put(parent, "hub_lamp", Vector3(spawn.x - 2.0, 0.0, spawn.z + 1.6), 0.0)
	_put(parent, "hub_lamp", Vector3(spawn.x + 5.0, 0.0, spawn.z + 1.6), 0.0)
	_put(parent, "hub_planter", Vector3(spawn.x - 2.0, 0.0, spawn.z + 2.5), 0.4)
	_put(parent, "hub_planter", Vector3(spawn.x + 5.0, 0.0, spawn.z + 2.5), 1.9)
	_put(parent, "hub_bench", Vector3(spawn.x + 1.5, 0.0, spawn.z + 4.4), 0.0)


## 南の縁と西の縁に柵（2m の区画を並べ、ところどころ隙間を空ける）。
static func _fences(parent: Node3D, lo: Vector3, hi: Vector3) -> void:
	var x := lo.x + 1.5
	var k := 0
	while x + 1.0 <= hi.x - 0.5:
		if k % 4 != 3:
			_put(parent, "hub_fence", Vector3(x, 0.0, hi.z - 0.3), PI)
		x += 2.0
		k += 1
	var z := lo.z + 1.5
	k = 0
	while z + 1.0 <= hi.z - 1.0:
		if k % 3 != 2:
			_put(parent, "hub_fence", Vector3(lo.x + 0.3, 0.0, z), PI * 0.5)
		z += 2.0
		k += 1


## 四隅に木と鉢植えを寄せて、小さな庭にする。
static func _corner_garden(parent: Node3D, lo: Vector3, hi: Vector3) -> void:
	var corners: Array[Vector3] = [
		Vector3(lo.x + 1.4, 0.0, lo.z + 1.2),
		Vector3(hi.x - 1.4, 0.0, lo.z + 1.2),
		Vector3(lo.x + 1.6, 0.0, hi.z - 1.6),
		Vector3(hi.x - 1.6, 0.0, hi.z - 1.6),
	]
	for i in corners.size():
		var at := corners[i]
		_put(parent, "tree_round" if i % 2 == 0 else "tree_tall", at, float(i) * 1.3)
		var side := 1.0 if at.x < 0.0 else -1.0
		_put(parent, "hub_planter", at + Vector3(side * 1.3, 0.0, 0.4), float(i))


## 草・花・小石を、歩く帯の外に散らす。
static func _scatter(parent: Node3D, lo: Vector3, hi: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261120
	var kinds: Array[String] = ["grass_tuft", "grass_tuft", "flower", "flower", "pebbles"]
	for i in 90:
		var at := Vector3(
			rng.randf_range(lo.x + 0.6, hi.x - 0.6), 0.0, rng.randf_range(lo.z + 0.6, hi.z - 0.6)
		)
		var kind := kinds[rng.randi() % kinds.size()]
		var scale := rng.randf_range(0.8, 1.3)
		var yaw := rng.randf() * TAU
		var near_side := at.x < lo.x + 1.8 or at.x > hi.x - 1.8
		if at.z > WALK_Z_MIN and at.z < WALK_Z_MAX and not near_side:
			continue
		var prop := _put(parent, kind, at, yaw)
		prop.scale = Vector3.ONE * scale


static func _put(parent: Node3D, model_name: String, at: Vector3, yaw: float) -> Node3D:
	var model := ModelLibrary.instantiate(model_name)
	model.position = at
	model.rotation.y = yaw
	parent.add_child(model)
	return model
