class_name RepeatCursor
extends RefCounted
## 繰り返し方式の順番。周期ごとに1つの行動を選び、複数あれば交互（付与順に巡回）にする。
## 選んだ行動が禁止されていても順番は進む（その回をスキップする: 企画書 4-5）。

var _index: int = 0


## 次に試みる行動。行動がなければ -1。
func next_action(actions: Array[RuleAction.Kind]) -> int:
	if actions.is_empty():
		_index = 0
		return -1
	var action := actions[_index % actions.size()]
	_index = (_index + 1) % actions.size()
	return action


func reset() -> void:
	_index = 0


func get_index() -> int:
	return _index


func set_index(value: int) -> void:
	_index = value
