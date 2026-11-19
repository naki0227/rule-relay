extends TestCase
## テスト基盤そのものの自己検査。CIがテストを本当に実行しているかを確かめる。


func test_assertions_record_failures() -> void:
	var probe := TestCase.new()
	probe.assert_eq(1, 2)
	probe.assert_true(false)
	assert_eq(probe.get_failures().size(), 2)


func test_int_and_float_compare_by_value() -> void:
	var probe := TestCase.new()
	probe.assert_eq(3, 3.0)
	assert_true(probe.get_failures().is_empty())


func test_async_physics_wait_runs() -> void:
	var before := Engine.get_physics_frames()
	await wait_physics_frames(3)
	assert_true(Engine.get_physics_frames() >= before + 3)
