class_name CheckpointHistory
extends RefCounted
## チェックポイントの履歴。最後の保存だけでなく、直前の保存（最大 CAPACITY 件）と、
## 島に入った時点の状態を残す（企画書 9 の「別の安全な直前スナップショットの保持」）。
## スナップショットの中身（Dictionary）には立ち入らない。

## 残す保存の数（仮値）。古いものから捨てる。
const CAPACITY: int = 3

var _initial: Dictionary = {}
var _saves: Array[Dictionary] = []


func set_initial(snapshot: Dictionary) -> void:
	_initial = snapshot
	_saves.clear()


func push(snapshot: Dictionary) -> void:
	_saves.append(snapshot)
	while _saves.size() > CAPACITY:
		_saves.remove_at(0)


func save_count() -> int:
	return _saves.size()


## 戻る先。保存が無ければ島に入った時点。
func latest() -> Dictionary:
	return _saves[-1] if not _saves.is_empty() else _initial


## 「ひとつ前へ戻る」ができるか（最後の保存を取り消せるか）。
func can_discard_latest() -> bool:
	return not _saves.is_empty()


## 最後の保存を取り消し、新しく戻る先になったスナップショットを返す。
## 詰んだ状態で保存してしまったときの逃げ道。取り消した保存には戻れない。
func discard_latest() -> Dictionary:
	if not _saves.is_empty():
		_saves.remove_at(_saves.size() - 1)
	return latest()


## 島の最初からやり直す。保存はすべて消える。
func reset_to_initial() -> Dictionary:
	_saves.clear()
	return _initial


func initial() -> Dictionary:
	return _initial
