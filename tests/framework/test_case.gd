class_name TestCase
extends RefCounted
## テストの基底クラス。`test_` で始まるメソッドを run_tests.gd が順に呼ぶ。
## 外部アドオンに依存しない最小実装（理由は docs/adr/0002-testing-and-ci.md）。

## 結合テスト用。シーンを木に追加したり物理フレームを待ったりするときに使う。
var tree: SceneTree

var _failures: PackedStringArray = PackedStringArray()


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func get_failures() -> PackedStringArray:
	return _failures


func clear_failures() -> void:
	_failures = PackedStringArray()


func fail(message: String) -> void:
	_failures.append(message)


func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		fail("expected true. %s" % message)


func assert_false(condition: bool, message: String = "") -> void:
	if condition:
		fail("expected false. %s" % message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if not _same(actual, expected):
		fail("expected <%s> but was <%s>. %s" % [str(expected), str(actual), message])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if _same(actual, unexpected):
		fail("did not expect <%s>. %s" % [str(unexpected), message])


func assert_almost(actual: float, expected: float, tolerance: float, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		fail("expected %f±%f but was %f. %s" % [expected, tolerance, actual, message])


func assert_gt(actual: float, threshold: float, message: String = "") -> void:
	if not actual > threshold:
		fail("expected > %f but was %f. %s" % [threshold, actual, message])


func assert_lt(actual: float, threshold: float, message: String = "") -> void:
	if not actual < threshold:
		fail("expected < %f but was %f. %s" % [threshold, actual, message])


## 物理フレームを n 回進める（結合テスト用）。
func wait_physics_frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		# int と float の比較だけは値で比べる
		var numeric := [TYPE_INT, TYPE_FLOAT]
		if typeof(a) in numeric and typeof(b) in numeric:
			return float(a) == float(b)
		return false
	return a == b
