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

## 知らせの文に埋める「操作のキー」の目印。`{key:interact}` のように書き、表示する側で
## その人の割り当てと入力の種類に置きかえる（ホストが作った知らせに、ホストのキー名が出ないように）。
const TOKEN_PREFIX: String = "{key:"
const TOKEN_SUFFIX: String = "}"

## 割り当て・入力の種類が変わったことを知らせる。静的な signal は持てないので、この1つの物に持たせる。
static var notifier: Notifier = Notifier.new()

static var using_pad: bool = false:
	set(value):
		if using_pad == value:
			return
		using_pad = value
		notify_changed()


## 案内の表示を作り直す合図（KeyLabel3D・知らせの吹き出しが受け取る）。
class Notifier:
	extends RefCounted
	signal changed


## 割り当てを Input Map へ反映したとき（KeyBindings.apply）と、入力の種類が変わったときに呼ぶ。
static func notify_changed() -> void:
	notifier.changed.emit()


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


## 知らせの文に埋める目印（表示するときに resolve でキー名へ置きかえる）。
static func token(action: StringName) -> String:
	return TOKEN_PREFIX + String(action) + TOKEN_SUFFIX


## 文の中の目印 `{key:操作}` を、いまの割り当てと入力の種類のキー名に置きかえる。
## 知らない操作・閉じていない目印はそのまま残す（文を壊さない）。
static func resolve(text: String) -> String:
	var at := text.find(TOKEN_PREFIX)
	if at == -1:
		return text
	var out := ""
	var from := 0
	while at != -1:
		var end := text.find(TOKEN_SUFFIX, at + TOKEN_PREFIX.length())
		if end == -1:
			break
		var name_at := at + TOKEN_PREFIX.length()
		var action := StringName(text.substr(name_at, end - name_at))
		out += text.substr(from, at - from)
		out += key(action) if InputMap.has_action(action) else text.substr(at, end - at + 1)
		from = end + 1
		at = text.find(TOKEN_PREFIX, from)
	return out + text.substr(from)
