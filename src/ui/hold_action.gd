class_name HoldAction
extends RefCounted
## 押し続けたら1回だけ発火する操作（誤操作を防ぐ長押し）。離すまで再発火しない。
## 例: V 長押しで全員リセットの投票（2026-11-20 本人の指示「V 長押しにせんと誤操作起きそう」）。

## 発火までの秒数（仮値。体感で調整する）。
var hold_seconds: float
var _held: float = 0.0
var _fired: bool = false


func _init(p_hold_seconds: float = 0.8) -> void:
	hold_seconds = p_hold_seconds


## 毎フレーム呼ぶ。押し続けて hold_seconds に届いたフレームだけ true。
func update(pressed: bool, delta: float) -> bool:
	if not pressed:
		_held = 0.0
		_fired = false
		return false
	if _fired:
		return false
	_held += delta
	if _held >= hold_seconds:
		_fired = true
		return true
	return false


## 0〜1 の進み具合（表示用）。
func progress() -> float:
	if _fired:
		return 1.0
	return clampf(_held / hold_seconds, 0.0, 1.0)
