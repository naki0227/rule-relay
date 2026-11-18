class_name HintMemory
extends RefCounted
## 操作の案内を「慣れるまで」だけ出すための記録。同じ操作を LEARN_AFTER 回したら、その案内は出さない。
## （常に操作説明を並べない。対象に近づいたときと、初めのうちだけ出す）

const LEARN_AFTER: int = 3

var _counts: Dictionary[String, int] = {}


func used(key: String) -> void:
	_counts[key] = _counts.get(key, 0) + 1


func should_show(key: String) -> bool:
	return _counts.get(key, 0) < LEARN_AFTER


func reset() -> void:
	_counts.clear()
