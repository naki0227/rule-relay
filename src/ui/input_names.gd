class_name InputNames
extends RefCounted
## 入力（キー・マウス・ゲームパッド）の表示名と、保存用の短い文字列（記述子）。
## 記述子: "key:<物理キーコード>" / "mouse:<ボタン>" / "joy:<ボタン>" / "axis:<軸>:+" / "axis:<軸>:-"。
## パッドの表記は Xbox 風の並び（InputMode と同じ）。

const PAD_BUTTONS: PackedStringArray = [
	"A",
	"B",
	"X",
	"Y",
	"View",
	"Guide",
	"Start",
	"左スティック押し",
	"右スティック押し",
	"LB",
	"RB",
	"十字↑",
	"十字↓",
	"十字←",
	"十字→",
]
const MOUSE_BUTTONS: PackedStringArray = [
	"",
	"左クリック",
	"右クリック",
	"ホイール押し",
	"ホイール↑",
	"ホイール↓",
	"ホイール←",
	"ホイール→",
	"マウス戻る",
	"マウス進む",
]
## 軸の名前。軸 n の負の向きが 2n、正の向きが 2n+1。
const AXES: PackedStringArray = [
	"左スティック←",
	"左スティック→",
	"左スティック↑",
	"左スティック↓",
	"右スティック←",
	"右スティック→",
	"右スティック↑",
	"右スティック↓",
	"LT",
	"LT",
	"RT",
	"RT",
]
## OS の名前が長い・英語のままだと分かりにくいキー。
const KEY_NAMES: Dictionary[int, String] = {
	KEY_ESCAPE: "Esc",
	KEY_SPACE: "Space",
	KEY_SHIFT: "Shift",
	KEY_CTRL: "Ctrl",
	KEY_ALT: "Alt",
	KEY_TAB: "Tab",
	KEY_ENTER: "Enter",
	KEY_BACKSPACE: "BS",
	KEY_UP: "↑",
	KEY_DOWN: "↓",
	KEY_LEFT: "←",
	KEY_RIGHT: "→",
}


## 入力の表示名。対応しない入力は空文字。
static func text(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null:
		return key_text(key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode)
	var mouse := event as InputEventMouseButton
	if mouse != null:
		var index := int(mouse.button_index)
		return MOUSE_BUTTONS[index] if index < MOUSE_BUTTONS.size() else "マウス%d" % index
	var button := event as InputEventJoypadButton
	if button != null:
		var b := int(button.button_index)
		return PAD_BUTTONS[b] if b >= 0 and b < PAD_BUTTONS.size() else "ボタン%d" % b
	var motion := event as InputEventJoypadMotion
	if motion != null:
		var axis := int(motion.axis)
		var at := axis * 2 + (1 if motion.axis_value > 0.0 else 0)
		return AXES[at] if axis >= 0 and at < AXES.size() else "軸%d" % axis
	return ""


## 物理キーコードの表示名（いまのキー配列で、そのキーに書かれている文字）。
static func key_text(physical: int) -> String:
	if KEY_NAMES.has(physical):
		return KEY_NAMES[physical]
	var shown := physical
	# ヘッドレス（テスト・CI）ではキー配列を引けないので、物理キーの名前のまま（US 配列の表記）
	if DisplayServer.get_name() != "headless":
		shown = int(DisplayServer.keyboard_get_keycode_from_physical(physical as Key))
		if shown == KEY_NONE:
			shown = physical
	return KEY_NAMES.get(shown, OS.get_keycode_string(shown as Key))


## 入力 → 記述子。保存できない入力（ホイールの回転以外のマウス移動など）は空文字。
static func encode(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null:
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return "" if code == KEY_NONE else "key:%d" % code
	var mouse := event as InputEventMouseButton
	if mouse != null:
		return "mouse:%d" % mouse.button_index
	var button := event as InputEventJoypadButton
	if button != null:
		return "joy:%d" % button.button_index
	var motion := event as InputEventJoypadMotion
	if motion != null and absf(motion.axis_value) > 0.0:
		return "axis:%d:%s" % [motion.axis, "+" if motion.axis_value > 0.0 else "-"]
	return ""


## 記述子 → 入力。壊れた記述子は null。
static func decode(descriptor: String) -> InputEvent:
	var parts := descriptor.split(":")
	if parts.size() < 2 or not parts[1].is_valid_int() or parts[1].to_int() < 0:
		return null
	var number := parts[1].to_int()
	var event: InputEvent = null
	match parts[0]:
		"key":
			if number > 0:
				var key := InputEventKey.new()
				key.physical_keycode = number as Key
				event = key
		"mouse":
			if number > 0:
				var mouse := InputEventMouseButton.new()
				mouse.button_index = number as MouseButton
				event = mouse
		"joy":
			var button := InputEventJoypadButton.new()
			button.button_index = number as JoyButton
			event = button
		"axis":
			if parts.size() == 3 and parts[2] in ["+", "-"]:
				var motion := InputEventJoypadMotion.new()
				motion.axis = number as JoyAxis
				motion.axis_value = 1.0 if parts[2] == "+" else -1.0
				event = motion
	return event


## キーボード・マウスの入力か（false ならゲームパッド）。
static func is_pad_descriptor(descriptor: String) -> bool:
	return descriptor.begins_with("joy:") or descriptor.begins_with("axis:")
