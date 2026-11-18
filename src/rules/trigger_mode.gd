class_name TriggerMode
extends RefCounted
## ブロックへ能力を渡すときの発動方式（企画書 5.2）。生き物・禁止には使わない（NONE）。

enum Kind { NONE, SINGLE_SHOT, REPEAT, SIGNAL }


static func label(kind: Kind) -> String:
	match kind:
		Kind.SINGLE_SHOT:
			return "単発"
		Kind.REPEAT:
			return "繰り返し"
		Kind.SIGNAL:
			return "信号"
	return "-"


## P0 で使える方式。信号は音波と一緒に P1 で実装する。
static func is_supported(kind: Kind) -> bool:
	return kind == Kind.SINGLE_SHOT or kind == Kind.REPEAT
