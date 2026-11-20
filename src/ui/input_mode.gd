class_name InputMode
extends RefCounted
## いま使っているのがゲームパッドか（キーボード・マウスか）。画面の操作案内の表記を切り替える。
## ボタン配置は Xbox 風（Steam Deck・多くの PC 用パッドと同じ並び。Steam Input もこの並びで渡す）。
## 表記は Input Map から作るので、設定画面で割り当て直したキーがそのまま案内に出る。

## 案内の文に書いてきたキーボードの表記 → その操作（Input Map から今の割り当てを引く）。
const LEGACY_ACTIONS: Dictionary[String, StringName] = {
	"F": &"interact",
	"左クリック": &"lend_single",
	"右クリック": &"lend_range",
	"C": &"toggle_reach",
	"E": &"inventory",
	"Q": &"cycle_mode",
	"V": &"vote_reset",
	"X": &"store_item",
	"Esc": &"restore_checkpoint",
	"Space": &"jump",
	"Shift": &"dash",
}
## 操作ひとつに当たらない表記（ゲームパッドでの言いかえ）。
const PAD_LABELS := {
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


## 操作案内に出すキーの表記。キーボードの初期の表記（"F" など）で指定し、いまの割り当てと
## 入力の種類（パッドならパッドのボタン名）に置きかえる。
static func label(keyboard: String) -> String:
	if LEGACY_ACTIONS.has(keyboard):
		return key(LEGACY_ACTIONS[keyboard])
	return String(PAD_LABELS.get(keyboard, keyboard)) if using_pad else keyboard


## 操作のいまの割り当ての表記（パッドを使っていればパッドの入力、なければキーボード・マウス）。
static func key(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	var fallback := ""
	for event: InputEvent in InputMap.action_get_events(action):
		var pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
		var text := InputNames.text(event)
		if pad == using_pad and text != "":
			return text
		if fallback == "":
			fallback = text
	return fallback
