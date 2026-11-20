class_name HintMemory
extends RefCounted
## 操作の案内を「慣れるまで」だけ出すための記録。同じ操作を LEARN_AFTER 回したら、その案内は出さない。
## （常に操作説明を並べない。対象に近づいたときと、初めのうちだけ出す）
## 記録の名前（プロファイル）ごとに `user://hints/<profile>.json` へ保存し、次に遊ぶときも覚えている。
## 保存の作法は ProgressStore と同じ（一時ファイルから置きかえ・版を持つ・壊れていたら初めから）。

const LEARN_AFTER: int = 3
const SCHEMA_VERSION: int = 1
const DEFAULT_DIR: String = "user://hints"

## 保存先（空なら保存しない。テストや、記録の名前がないとき）。
var save_path: String = ""

var _counts: Dictionary[String, int] = {}


## 記録の名前ごとの記録を読む。名前が使えなければ保存しない記録を返す。
static func for_profile(profile: String, base_dir: String = DEFAULT_DIR) -> HintMemory:
	var memory := HintMemory.new()
	if ProgressStore.is_valid_profile(profile):
		memory.save_path = base_dir.path_join("%s.json" % profile)
		memory.load_saved()
	return memory


func used(key: String) -> void:
	var before: int = _counts.get(key, 0)
	_counts[key] = before + 1
	# 慣れるまでの回数だけ書く（慣れた後は何度使っても書かない）
	if before < LEARN_AFTER:
		save()


func should_show(key: String) -> bool:
	return _counts.get(key, 0) < LEARN_AFTER


func reset() -> void:
	_counts.clear()
	save()


func save() -> Error:
	if save_path.is_empty():
		return OK
	var made := DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	if made != OK:
		return made
	var counts := {}
	for key: String in _counts:
		counts[key] = mini(_counts[key], LEARN_AFTER)
	var temp := save_path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"schema_version": SCHEMA_VERSION, "counts": counts}))
	file.close()
	return DirAccess.rename_absolute(temp, save_path)


## 保存した記録を読む。無い・壊れている・新しすぎる版なら、初めからにする。
func load_saved() -> void:
	_counts.clear()
	if save_path.is_empty() or not FileAccess.file_exists(save_path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(save_path)) != OK or not json.data is Dictionary:
		return
	var root := json.data as Dictionary
	var version: Variant = root.get("schema_version")
	if not (version is int or version is float) or int(version) != SCHEMA_VERSION:
		return
	var counts: Variant = root.get("counts")
	if not counts is Dictionary:
		return
	for key: Variant in counts as Dictionary:
		var value: Variant = (counts as Dictionary)[key]
		if key is String and (value is int or value is float):
			_counts[String(key)] = clampi(int(value), 0, LEARN_AFTER)
