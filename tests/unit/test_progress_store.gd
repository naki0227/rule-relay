extends TestCase
## 進行の保存（user://progress/<profile>.json）。テスト専用のプロファイル名を使い、終わったら消す。

const PROFILE := "zz_test_progress_store"
const STAGE := "prototype_island"

var store: ProgressStore


func before_each() -> void:
	store = ProgressStore.new()
	store.delete(PROFILE)


func after_each() -> void:
	store.delete(PROFILE)


func _cleared_progress() -> PlayerProgress:
	var progress := PlayerProgress.new()
	var rewards := StageRunRewards.new(STAGE, "run-1")
	rewards.settle(
		{"me": StageRunRewards.Status.ACTIVE}, RunMetrics.create(42.5, 3, 1), 1_790_000_000
	)
	progress.apply_reward_event(rewards.event_for("me"), RewardTable.provisional())
	return progress


func _write_raw(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(store.base_dir)
	var file := FileAccess.open(store.path_for(PROFILE), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_save_and_load_round_trip() -> void:
	var progress := _cleared_progress()
	assert_eq(store.save(PROFILE, progress), OK)
	assert_true(store.exists(PROFILE))
	assert_false(FileAccess.file_exists(store.path_for(PROFILE) + ".tmp"), "temp file renamed")
	var loaded := store.load_progress(PROFILE)
	assert_true(loaded.is_ok(), loaded.message)
	assert_eq(loaded.progress.to_dict(), progress.to_dict())
	assert_eq(loaded.progress.first_clear_time(STAGE), 1_790_000_000)


func test_saved_file_has_schema_version() -> void:
	store.save(PROFILE, _cleared_progress())
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(store.path_for(PROFILE)))
	assert_true(parsed is Dictionary)
	assert_eq(int((parsed as Dictionary)["schema_version"]), ProgressStore.SCHEMA_VERSION)


func test_save_overwrites_previous_save() -> void:
	store.save(PROFILE, PlayerProgress.new())
	store.save(PROFILE, _cleared_progress())
	assert_true(store.load_progress(PROFILE).progress.has_cleared(STAGE))


func test_missing_file_returns_fresh_progress() -> void:
	var loaded := store.load_progress(PROFILE)
	assert_eq(loaded.error, ERR_FILE_NOT_FOUND)
	assert_true(loaded.progress != null)
	assert_true(loaded.progress.cleared_stages().is_empty())


func test_corrupt_file_returns_fresh_progress_and_is_set_aside() -> void:
	_write_raw("{ this is not json")
	var loaded := store.load_progress(PROFILE)
	assert_eq(loaded.error, ERR_FILE_CORRUPT)
	assert_false(loaded.message.is_empty())
	assert_true(loaded.progress.cleared_stages().is_empty())
	assert_false(FileAccess.file_exists(store.path_for(PROFILE)))
	assert_eq(FileAccess.get_file_as_string(store.corrupt_path_for(PROFILE)), "{ this is not json")
	# 次の保存は新しい進行で書け、退避したファイルは残る
	assert_eq(store.save(PROFILE, _cleared_progress()), OK)
	assert_true(store.load_progress(PROFILE).is_ok())
	assert_true(FileAccess.file_exists(store.corrupt_path_for(PROFILE)))


func test_wrong_shapes_are_reported_as_corrupt() -> void:
	for text: String in ["", "[1, 2]", '{"progress": {}}', '{"schema_version": 1}']:
		_write_raw(text)
		var loaded := store.load_progress(PROFILE)
		assert_eq(loaded.error, ERR_FILE_CORRUPT, "text: %s" % text)
	_write_raw('{"schema_version": 1, "progress": {"stages": []}}')
	assert_eq(store.load_progress(PROFILE).error, ERR_FILE_CORRUPT, "progress with wrong types")


func test_newer_schema_version_is_not_read() -> void:
	_write_raw('{"schema_version": 99, "progress": {}}')
	var loaded := store.load_progress(PROFILE)
	assert_eq(loaded.error, ERR_FILE_UNRECOGNIZED)
	assert_true(loaded.progress.cleared_stages().is_empty())
	assert_true(FileAccess.file_exists(store.corrupt_path_for(PROFILE)), "kept, not overwritten")


func test_invalid_profile_names_are_rejected() -> void:
	for name: String in ["", "../escape", "a/b", "Upper", "with space"]:
		assert_false(ProgressStore.is_valid_profile(name), name)
		assert_eq(store.save(name, PlayerProgress.new()), ERR_INVALID_PARAMETER)
		assert_eq(store.load_progress(name).error, ERR_INVALID_PARAMETER)
	assert_true(ProgressStore.is_valid_profile("player_1-a"))
