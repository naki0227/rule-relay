class_name KeyBindings
extends RefCounted
## 主な操作のキー割り当て（設定画面で変える）。各操作に「キーボード・マウス」と「ゲームパッド」の
## 枠を1つずつ持つ。初期値は project.godot の Input Map。
## - 同じ入力を別の操作に割り当てると、割り当て直せる操作どうしなら入れかえる（どちらも空にならない）
## - 割り当て直せない操作（Q・C・1〜9 など）が使っている入力は断る
## - 全員リセットの投票（vote_reset）は長押しのまま。押しているかを見るだけなので、どの入力でも同じに動く

enum Slot { KEYBOARD, PAD }

## 割り当て直せる操作（設定画面の並び順）。
const ACTIONS: Array[StringName] = [
	&"move_forward",
	&"move_back",
	&"move_left",
	&"move_right",
	&"jump",
	&"dash",
	&"interact",
	&"lend_single",
	&"vote_reset",
	&"inventory",
	&"restore_checkpoint",
]

## 操作の名前（衝突の知らせにも使うので、割り当て直せない操作の名前も持つ）。
const NAMES: Dictionary[StringName, String] = {
	&"move_forward": "前へ",
	&"move_back": "後ろへ",
	&"move_left": "左へ",
	&"move_right": "右へ",
	&"jump": "ジャンプ",
	&"dash": "突進",
	&"interact": "回収・保存・拾う",
	&"lend_single": "渡す",
	&"vote_reset": "全員リセットの投票（長押し）",
	&"inventory": "持ち物",
	&"restore_checkpoint": "メニュー",
	&"toggle_reach": "触る／投げる",
	&"lend_range": "まとめて渡す",
	&"cycle_mode": "方式の切り替え",
	&"radial_menu": "円形メニュー",
	&"store_item": "かばんへ",
	&"hotbar_prev": "ホットバーの前の枠",
	&"hotbar_next": "ホットバーの次の枠",
	&"release_mouse": "マウスを離す",
}


## 割り当ての結果。
class Result:
	var ok: bool = false
	## 入れかえた相手の操作（入れかえなかったら空）。
	var swapped_with: StringName = &""
	## 断った理由になった操作（断らなかったら空）。
	var blocked_by: StringName = &""


## Input Map へ反映した回数（案内の表示を作り直すかの判定に使う）。
static var revision: int = 0

## 操作 → [キーボードの記述子, パッドの記述子]（空文字は未割り当て）。
var _events: Dictionary[StringName, PackedStringArray] = {}


func _init() -> void:
	reset_to_defaults()


static func action_name(action: StringName) -> String:
	if NAMES.has(action):
		return NAMES[action]
	var text := String(action)
	if text.begins_with("slot_"):
		return "ホットバー%s" % text.trim_prefix("slot_")
	return text


## project.godot に書いた初期の割り当て（記述子）。
static func default_for(action: StringName, slot: Slot) -> String:
	var setting: Variant = ProjectSettings.get_setting("input/%s" % action)
	if not setting is Dictionary:
		return ""
	for event: Variant in (setting as Dictionary).get("events", []):
		var descriptor := InputNames.encode(event as InputEvent) if event is InputEvent else ""
		if descriptor != "" and _slot_of(descriptor) == slot:
			return descriptor
	return ""


static func _slot_of(descriptor: String) -> Slot:
	return Slot.PAD if InputNames.is_pad_descriptor(descriptor) else Slot.KEYBOARD


func reset_to_defaults() -> void:
	_events.clear()
	for action: StringName in ACTIONS:
		_events[action] = PackedStringArray(
			[default_for(action, Slot.KEYBOARD), default_for(action, Slot.PAD)]
		)


func get_descriptor(action: StringName, slot: Slot) -> String:
	return _events[action][slot] if _events.has(action) else ""


func is_default() -> bool:
	for action: StringName in ACTIONS:
		for slot: Slot in [Slot.KEYBOARD, Slot.PAD]:
			if get_descriptor(action, slot) != default_for(action, slot):
				return false
	return true


## action の slot に descriptor を割り当てる。衝突は入れかえるか断る（Result を見る）。
func assign(action: StringName, slot: Slot, descriptor: String) -> Result:
	var result := Result.new()
	if not _events.has(action) or InputNames.decode(descriptor) == null:
		return result
	if _slot_of(descriptor) != slot:
		return result
	var old := get_descriptor(action, slot)
	if old == descriptor:
		result.ok = true
		return result
	var owner := _rebindable_owner(descriptor, slot, action)
	if owner == &"":
		result.blocked_by = _fixed_owner(descriptor)
		if result.blocked_by != &"":
			return result
	else:
		_events[owner][slot] = old
		result.swapped_with = owner
	_events[action][slot] = descriptor
	result.ok = true
	return result


## Input Map へ反映する（割り当て直せる操作の入力を置きかえる）。
func apply() -> void:
	revision += 1
	for action: StringName in ACTIONS:
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		for descriptor: String in _events[action]:
			var event := InputNames.decode(descriptor)
			if event != null:
				InputMap.action_add_event(action, event)
	InputMode.notify_changed()


func save_to(config: ConfigFile, section: String) -> void:
	for action: StringName in ACTIONS:
		config.set_value(section, String(action), Array(_events[action]))


## 保存した割り当てを読む。壊れた値・種類の合わない値・重複は無視して初期値のままにする。
func load_from(config: ConfigFile, section: String) -> void:
	reset_to_defaults()
	if not config.has_section(section):
		return
	for action: StringName in ACTIONS:
		var saved: Variant = config.get_value(section, String(action), [])
		if not saved is Array:
			continue
		var values := saved as Array
		for slot: Slot in [Slot.KEYBOARD, Slot.PAD]:
			if slot < values.size() and values[slot] is String:
				assign(action, slot, String(values[slot]))


## 同じ枠でこの入力を使っている、割り当て直せる別の操作。
func _rebindable_owner(descriptor: String, slot: Slot, except: StringName) -> StringName:
	for other: StringName in ACTIONS:
		if other != except and get_descriptor(other, slot) == descriptor:
			return other
	return &""


## この入力を使っている、割り当て直せない操作（ui_* の画面操作は数えない）。
static func _fixed_owner(descriptor: String) -> StringName:
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_") or action in ACTIONS:
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			if InputNames.encode(event) == descriptor:
				return action
	return &""
