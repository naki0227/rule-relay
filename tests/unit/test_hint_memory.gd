extends TestCase
## 操作の案内の「慣れた」記録を、記録の名前ごとに user:// へ保存して次回も覚えていること。

const DIR := "user://zz_test_hints"


func before_each() -> void:
	_clean()


func after_each() -> void:
	_clean()


func _clean() -> void:
	for profile: String in ["alice", "bob"]:
		for suffix: String in [".json", ".json.tmp"]:
			var path := DIR.path_join(profile + suffix)
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)


func test_learned_hints_survive_a_restart() -> void:
	var first := HintMemory.for_profile("alice", DIR)
	for i in HintMemory.LEARN_AFTER:
		first.used("lend")
	first.used("range")
	assert_false(first.should_show("lend"))
	var again := HintMemory.for_profile("alice", DIR)
	assert_false(again.should_show("lend"), "learned hint stays hidden after reloading")
	assert_true(again.should_show("range"), "used once is not learned yet")
	again.used("range")
	again.used("range")
	assert_false(HintMemory.for_profile("alice", DIR).should_show("range"))


func test_each_profile_has_its_own_record() -> void:
	var alice := HintMemory.for_profile("alice", DIR)
	for i in HintMemory.LEARN_AFTER:
		alice.used("save")
	assert_true(HintMemory.for_profile("bob", DIR).should_show("save"))
	assert_false(HintMemory.for_profile("alice", DIR).should_show("save"))


func test_broken_or_future_file_starts_over() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := FileAccess.open(DIR.path_join("alice.json"), FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	assert_true(HintMemory.for_profile("alice", DIR).should_show("lend"))
	file = FileAccess.open(DIR.path_join("alice.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": 99, "counts": {"lend": 3}}))
	file.close()
	assert_true(HintMemory.for_profile("alice", DIR).should_show("lend"), "unknown version")


func test_invalid_profile_is_not_saved() -> void:
	var memory := HintMemory.for_profile("../evil", DIR)
	assert_eq(memory.save_path, "")
	for i in HintMemory.LEARN_AFTER:
		memory.used("lend")
	assert_false(memory.should_show("lend"), "still works for the session")
	assert_false(FileAccess.file_exists(DIR.path_join("../evil.json")))


func test_reset_forgets_and_saves() -> void:
	var memory := HintMemory.for_profile("alice", DIR)
	for i in HintMemory.LEARN_AFTER:
		memory.used("lend")
	memory.reset()
	assert_true(HintMemory.for_profile("alice", DIR).should_show("lend"))
