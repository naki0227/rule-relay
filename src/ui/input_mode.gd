class_name InputMode
extends RefCounted
## いま使っているのがゲームパッドか（キーボード・マウスか）。画面の操作案内の表記を切り替える。
## ボタン配置は Xbox 風（Steam Deck・多くの PC 用パッドと同じ並び。Steam Input もこの並びで渡す）。

## キーボードの表記 → ゲームパッドの表記（project.godot の割り当てと合わせる）。
const PAD_LABELS := {
	"F": "X",
	"左クリック": "RT",
	"右クリック": "LT",
	"C": "Y",
	"E": "View",
	"Q": "十字↑",
	"V": "十字↓",
	"Esc": "Start",
	"Space": "A",
	"Shift": "B",
	"1〜9": "LB / RB",
}

static var using_pad: bool = false


## 入力が来るたびに呼ぶ。ゲームパッドのボタン・スティックならパッド、キー・マウスならキーボード。
static func observe(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		using_pad = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		using_pad = false


## 操作案内に出すキーの表記（ゲームパッドならパッドのボタン名にする）。
static func label(keyboard: String) -> String:
	return String(PAD_LABELS.get(keyboard, keyboard)) if using_pad else keyboard
