extends SceneTree
## ヘッドレスでテストを実行する。
##   godot --headless --fixed-fps 60 --script res://tests/run_tests.gd [-- <オプション>]
## オプション:
##   --filter=<部分一致>     「ファイル名::メソッド名」に含まれるテストだけ流す
##   --shard=<i>/<n>         テストファイルを n 個に分けた i 番目（1 始まり）だけ流す。分け方は
##                           res://tests/test_timings.json の実測（ファイルごとの ms）で、重い順に
##                           いちばん空いている組へ入れる（どのプロセスでも同じ分け方になる）
##   --alone                 RUN_ALONE_FILES だけ流す（--shard の組からは外れる。並列の組が終わってから流す）
##   --timing                最後に、遅いファイルとテストの上位 20 件を出す
##   --timing-out=<パス>     テストごと・ファイルごとの時間と結果を JSON で書き出す（tools/test_shards.py が読む）
## 失敗が1件でもあれば終了コード1で終わる。並列の流し方は tools/check.sh と docs/how-to-test.md。

const TEST_DIRS: PackedStringArray = ["res://tests/unit", "res://tests/integration"]
const TIMINGS_PATH := "res://tests/test_timings.json"
const TOP_COUNT := 20
## 実測の無い（新しい）ファイルの重さ。同じフォルダの実測の平均が取れないときに使う。
const UNKNOWN_FILE_MS := 1000.0
## 並列のとき、各組の user:// が分けてあることを確かめる（tools/check.sh が渡す）。
const DATA_HOME_ENV := "RULE_RELAY_TEST_DATA_HOME"
## 実時間（ms）の上限を確かめるテストのファイル。ほかの組と同時に流すと CPU の取り合いで遅くなり、
## 意味が変わる（上限を緩めることになる）ので、--shard の組から外し、並列の組が終わってから --alone で流す。
const RUN_ALONE_FILES: PackedStringArray = [
	"res://tests/integration/test_inventory_panel.gd",
]

var _test_ms: Dictionary[String, int] = {}
var _file_ms: Dictionary[String, int] = {}
var _failed_labels: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	var filter := _read_arg("--filter=")
	var files := _discover()
	var shard := TestCase.shard_spec()
	if not _user_dir_is_isolated():
		quit(1)
		return
	if _read_flag("--alone"):
		files = _only(files, RUN_ALONE_FILES, true)
		print("alone: %d files" % files.size())
	elif shard.y > 1:
		files = shard_files(_only(files, RUN_ALONE_FILES, false), _read_timings(), shard.x, shard.y)
		print("shard %d/%d: %d files" % [shard.x + 1, shard.y, files.size()])
	var passed := 0
	var failed := 0
	var started := Time.get_ticks_msec()
	for path in files:
		var file_started := Time.get_ticks_msec()
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			printerr("LOAD FAIL %s" % path)
			_failed_labels.append("LOAD FAIL %s" % path)
			failed += 1
			continue
		for method_name in _test_methods(script):
			var label := "%s::%s" % [path.get_file().get_basename(), method_name]
			if filter != "" and not label.contains(filter):
				continue
			var test_started := Time.get_ticks_msec()
			var ok: bool = await _run_one(script, method_name, label)
			_test_ms[label] = Time.get_ticks_msec() - test_started
			if ok:
				passed += 1
			else:
				failed += 1
				_failed_labels.append(label)
		_file_ms[_rel(path)] = Time.get_ticks_msec() - file_started
	var elapsed := Time.get_ticks_msec() - started
	if _read_flag("--timing"):
		_print_slowest()
	var timing_out := _read_arg("--timing-out=")
	if timing_out != "":
		_write_timing(timing_out, passed, failed, elapsed)
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


## files のうち、listed に入っている（keep = true）か入っていない（keep = false）もの。
static func _only(
	files: PackedStringArray, listed: PackedStringArray, keep: bool
) -> PackedStringArray:
	var picked := PackedStringArray()
	for path in files:
		if listed.has(path) == keep:
			picked.append(path)
	return picked


## files を count 組に分けた index 番目（0 始まり）。重い順に、いちばん軽い組（同じなら番号の小さい組）へ
## 入れる（LPT）。実測（timings のファイルごとの ms）が無いファイルは、同じフォルダの平均で見積もる。
## 同じ入力ならどのプロセスでも同じ結果になり、全部の組を合わせると files がちょうど1回ずつ出る。
static func shard_files(
	files: PackedStringArray, timings: Dictionary, index: int, count: int
) -> PackedStringArray:
	var weighted: Array[Array] = []
	for path in files:
		weighted.append([_estimate_ms(path, timings), path])
	weighted.sort_custom(
		func(a: Array, b: Array) -> bool:
			if float(a[0]) != float(b[0]):
				return float(a[0]) > float(b[0])
			return String(a[1]) < String(b[1])
	)
	var loads: Array[float] = []
	loads.resize(count)
	loads.fill(0.0)
	var mine := PackedStringArray()
	for entry in weighted:
		var best := 0
		for i in count:
			if loads[i] < loads[best]:
				best = i
		loads[best] += float(entry[0])
		if best == index:
			mine.append(String(entry[1]))
	mine.sort()
	return mine


static func _estimate_ms(path: String, timings: Dictionary) -> float:
	var key := _rel(path)
	if timings.has(key):
		return float(timings[key])
	var total := 0.0
	var known := 0
	var dir := key.get_base_dir()
	for other: String in timings:
		if other.get_base_dir() == dir:
			total += float(timings[other])
			known += 1
	return total / known if known > 0 else UNKNOWN_FILE_MS


## res://tests/unit/test_x.gd → tests/unit/test_x.gd（timings のキー）
static func _rel(path: String) -> String:
	return path.trim_prefix("res://")


func _read_timings() -> Dictionary:
	if not FileAccess.file_exists(TIMINGS_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TIMINGS_PATH))
	if not parsed is Dictionary:
		printerr("test timings are not a JSON object: %s" % TIMINGS_PATH)
		return {}
	var files: Variant = (parsed as Dictionary).get("files", {})
	return files if files is Dictionary else {}


## 並列で流すとき、user://（進行・設定・案内の記録）が組ごとに別のフォルダか確かめる。
## 同じフォルダだと、同じプロファイル名を使うテストが別の組で同時に書き消しする。
func _user_dir_is_isolated() -> bool:
	var expected := OS.get_environment(DATA_HOME_ENV)
	if expected == "":
		return true
	var actual := OS.get_user_data_dir()
	if actual.begins_with(expected):
		return true
	printerr("USER DIR NOT ISOLATED: user:// is %s, expected under %s" % [actual, expected])
	return false


func _print_slowest() -> void:
	print("\nslowest files:")
	for entry in _top(_file_ms):
		print("  %7d ms  %s" % [int(entry[0]), String(entry[1])])
	print("slowest tests:")
	for entry in _top(_test_ms):
		print("  %7d ms  %s" % [int(entry[0]), String(entry[1])])


func _top(durations: Dictionary[String, int]) -> Array[Array]:
	var entries: Array[Array] = []
	for key in durations:
		entries.append([durations[key], key])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	return entries.slice(0, TOP_COUNT)


func _write_timing(path: String, passed: int, failed: int, elapsed: int) -> void:
	var data := {
		"passed": passed,
		"failed": failed,
		"elapsed_ms": elapsed,
		"failed_tests": _failed_labels,
		"files": _file_ms,
		"tests": _test_ms,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("cannot write test timings to %s" % path)
		return
	file.store_string(JSON.stringify(data, "\t", true))
	file.close()


func _read_arg(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return ""


func _read_flag(flag: String) -> bool:
	return flag in OS.get_cmdline_user_args()
