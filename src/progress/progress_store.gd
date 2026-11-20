class_name ProgressStore
extends RefCounted
## PlayerProgress を各自の PC に JSON で保存する（`user://progress/<profile>.json`）。
## Steam 版では同じファイルを Steam クラウドの同期対象にする予定（docs/adr/0006 の 4）。
##
## - 書き込みは一時ファイルに書いてから置き換える。途中で落ちても前の保存が残る
## - 先頭に schema_version を持つ。知らない新しい版は読まずに新規扱いにする
## - ファイルが無い・壊れている場合も止まらず、新しい進行と誤りを返す。壊れたファイルは
##   `<profile>.corrupt.json` へ退避し、次の保存で上書きして失わないようにする

const SCHEMA_VERSION: int = 1
const DEFAULT_DIR: String = "user://progress"

var base_dir: String = DEFAULT_DIR


## 読み込みの結果。progress は必ず入っている（失敗時は新しい進行）。
class LoadResult:
	var progress: PlayerProgress = PlayerProgress.new()
	## OK / ERR_FILE_NOT_FOUND（初回）/ ERR_FILE_CORRUPT / ERR_FILE_UNRECOGNIZED（新しすぎる版）など
	var error: Error = OK
	var message: String = ""

	func is_ok() -> bool:
		return error == OK


func _init(p_base_dir: String = DEFAULT_DIR) -> void:
	base_dir = p_base_dir


## プロファイル名に使える文字は英小文字・数字・`_`・`-` だけ（パスの外へ出させない）。
static func is_valid_profile(profile: String) -> bool:
	if profile.is_empty() or profile.length() > 64:
		return false
	for character: String in profile:
		if not "abcdefghijklmnopqrstuvwxyz0123456789_-".contains(character):
			return false
	return true


func path_for(profile: String) -> String:
	return base_dir.path_join("%s.json" % profile)


func corrupt_path_for(profile: String) -> String:
	return base_dir.path_join("%s.corrupt.json" % profile)


func exists(profile: String) -> bool:
	return is_valid_profile(profile) and FileAccess.file_exists(path_for(profile))


func save(profile: String, progress: PlayerProgress) -> Error:
	if not is_valid_profile(profile) or progress == null:
		return ERR_INVALID_PARAMETER
	var made := DirAccess.make_dir_recursive_absolute(base_dir)
	if made != OK:
		return made
	var text := JSON.stringify(
		{"schema_version": SCHEMA_VERSION, "progress": progress.to_dict()}, "\t"
	)
	var temp_path := path_for(profile) + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temp_path)
		return write_error
	return DirAccess.rename_absolute(temp_path, path_for(profile))


func load_progress(profile: String) -> LoadResult:
	var result := LoadResult.new()
	if not is_valid_profile(profile):
		return _failed(result, ERR_INVALID_PARAMETER, "invalid profile name")
	var path := path_for(profile)
	if not FileAccess.file_exists(path):
		return _failed(result, ERR_FILE_NOT_FOUND, "no saved progress (new profile)")
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var parsed := json.parse(text) if not text.is_empty() else ERR_PARSE_ERROR
	var root: Variant = json.data if parsed == OK else null
	var problem := _check_root(root)
	if problem != OK:
		_set_aside(profile)
		return _failed(result, problem, "saved progress is unreadable; moved to .corrupt.json")
	var progress := PlayerProgress.from_dict((root as Dictionary)["progress"] as Dictionary)
	if progress == null:
		_set_aside(profile)
		return _failed(result, ERR_FILE_CORRUPT, "saved progress has a wrong shape")
	result.progress = progress
	return result


func delete(profile: String) -> void:
	if not is_valid_profile(profile):
		return
	for path: String in [path_for(profile), path_for(profile) + ".tmp", corrupt_path_for(profile)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


static func _check_root(root: Variant) -> Error:
	if not root is Dictionary:
		return ERR_FILE_CORRUPT
	var data := root as Dictionary
	var version: Variant = data.get("schema_version")
	if not (version is int or version is float) or not data.get("progress") is Dictionary:
		return ERR_FILE_CORRUPT
	if int(version) > SCHEMA_VERSION or int(version) < 1:
		return ERR_FILE_UNRECOGNIZED
	return OK


func _set_aside(profile: String) -> void:
	var corrupt := corrupt_path_for(profile)
	if FileAccess.file_exists(corrupt):
		DirAccess.remove_absolute(corrupt)
	DirAccess.rename_absolute(path_for(profile), corrupt)


static func _failed(result: LoadResult, error: Error, message: String) -> LoadResult:
	result.progress = PlayerProgress.new()
	result.error = error
	result.message = message
	return result
