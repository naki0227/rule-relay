extends SceneTree
## 島の地形（PrototypeIsland.terrain_boxes）を art/source/island_terrain.json に書き出す。
## Blender の art/scripts/build_terrain.py がこれを読んで、角を丸めた地形のモデルを作る。
##   godot --headless --script res://tools/export_terrain.gd


func _initialize() -> void:
	_export.call_deferred()


func _export() -> void:
	var boxes: Array = []
	for box: Array in PrototypeIsland.terrain_boxes():
		var lo := box[0] as Vector3i
		var hi := box[1] as Vector3i
		boxes.append({"min": [lo.x, lo.y, lo.z], "max": [hi.x, hi.y, hi.z], "kind": box[2]})
	var file := FileAccess.open("res://art/source/island_terrain.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"boxes": boxes}, "  ") + "\n")
	file.close()
	print("wrote %d boxes" % boxes.size())
	quit()
