extends SceneTree
## ヘッドレスでテストを実行する。
##   godot --headless --fixed-fps 60 --script res://tests/run_tests.gd [-- --filter=<部分一致>]
## 失敗が1件でもあれば終了コード1で終わる。

const TEST_DIRS: PackedStringArray = ["res://tests/unit", "res://tests/integration"]


func _initialize() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	var filter := _read_filter()
	var passed := 0
	var failed := 0
	var started := Time.get_ticks_msec()
	for path in _discover():
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			printerr("LOAD FAIL %s" % path)
			failed += 1
			continue
		for method_name in _test_methods(script):
			var label := "%s::%s" % [path.get_file().get_basename(), method_name]
			if filter != "" and not label.contains(filter):
				continue
			var ok: bool = await _run_one(script, method_name, label)
			if ok:
				passed += 1
			else:
				failed += 1
	var elapsed := Time.get_ticks_msec() - started
	print("\n%d passed, %d failed (%d ms)" % [passed, failed, elapsed])
	await _release_everything()
	quit(1 if failed > 0 or passed == 0 else 0)


## 終了前に、テストが残したノードと鳴っている音を片付ける。queue_free の直後に quit すると、
## 速いマシンでは削除待ちのノードや再生中の音が残り、「resources still in use at exit」が出る。
func _release_everything() -> void:
	for child in root.get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).stop()
		child.queue_free()
	for i in 3:
		await process_frame


func _run_one(script: GDScript, method_name: String, label: String) -> bool:
	var instance := script.new() as TestCase
	if instance == null:
		printerr("FAIL %s: script does not extend TestCase" % label)
		return false
	instance.tree = self
	await instance.before_each()
	await Callable(instance, method_name).call()
	await instance.after_each()
	var failures := instance.get_failures()
	if failures.is_empty():
		print("ok   %s" % label)
		return true
	printerr("FAIL %s" % label)
	for message in failures:
		printerr("     - %s" % message)
	return false


func _discover() -> PackedStringArray:
	var found := PackedStringArray()
	for dir_path in TEST_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file_name in dir.get_files():
			if file_name.begins_with("test_") and file_name.ends_with(".gd"):
				found.append(dir_path.path_join(file_name))
	found.sort()
	return found


func _test_methods(script: GDScript) -> PackedStringArray:
	var names := PackedStringArray()
	for info: Dictionary in script.get_script_method_list():
		var method_name := String(info["name"])
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	return names


func _read_filter() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			return arg.trim_prefix("--filter=")
	return ""
