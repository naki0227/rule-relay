extends TestCase
## 地形のモデル（assets/models/island_terrain.glb）は art/source/island_terrain.json から Blender で作る。
## 島の地形（当たり判定）を変えたのに JSON とモデルを作り直し忘れると、見た目と当たり判定がずれる。
## 直し方: godot --headless --script res://tools/export_terrain.gd → blender ... build_terrain.py


func test_terrain_model_source_matches_the_island() -> void:
	var text := FileAccess.get_file_as_string("res://art/source/island_terrain.json")
	assert_ne(text, "", "art/source/island_terrain.json exists")
	var boxes := (JSON.parse_string(text) as Dictionary)["boxes"] as Array
	var expected := PrototypeIsland.terrain_boxes()
	assert_eq(boxes.size(), expected.size(), "re-export the terrain")
	for i in mini(boxes.size(), expected.size()):
		var box := boxes[i] as Dictionary
		var lo := box["min"] as Array
		var hi := box["max"] as Array
		var e := expected[i] as Array
		assert_eq(Vector3i(int(lo[0]), int(lo[1]), int(lo[2])), e[0], "box %d min" % i)
		assert_eq(Vector3i(int(hi[0]), int(hi[1]), int(hi[2])), e[1], "box %d max" % i)
		assert_eq(String(box["kind"]), String(e[2]), "box %d kind" % i)
	assert_true(ResourceLoader.exists("res://assets/models/island_terrain.glb"))
