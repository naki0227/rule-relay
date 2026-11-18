extends SceneTree
## 全GDScriptを読み込み、構文エラーと「エラー扱いの警告」（未型付け宣言など）を検出する。
##   godot --headless --script res://tools/check_scripts.gd

const ROOTS: PackedStringArray = ["res://src", "res://tests", "res://tools"]


func _initialize() -> void:
	var broken := PackedStringArray()
	var count := 0
	for root in ROOTS:
		for path in _collect(root):
			count += 1
			var script := load(path) as GDScript
			if script == null or not script.can_instantiate():
				broken.append(path)
	if broken.is_empty():
		print("static check: %d scripts OK" % count)
		quit(0)
	else:
		for path in broken:
			printerr("static check FAILED: %s" % path)
		quit(1)


func _collect(dir_path: String) -> PackedStringArray:
	var result := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			result.append(dir_path.path_join(file_name))
	for sub in dir.get_directories():
		result.append_array(_collect(dir_path.path_join(sub)))
	return result
