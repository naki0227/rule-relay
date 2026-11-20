class_name KeyPrompt
extends HBoxContainer
## 「[キー] 動作」の案内（例: [F] 回収）。


## key はキーボードの初期の表記（"F" など）。いまの割り当てと入力の種類に置きかえて出す。
static func make(key: String, action: String, _dim: bool = false) -> KeyPrompt:
	return make_literal(InputMode.label(key), action)


## キーの表記をそのまま出す（呼ぶ側で InputMode.key などから作った表記。置きかえない）。
static func make_literal(key_text: String, action: String) -> KeyPrompt:
	var prompt := KeyPrompt.new()
	prompt.add_theme_constant_override("separation", 8)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := PanelContainer.new()
	cap.theme_type_variation = &"KeyCap"
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var key_label := Label.new()
	key_label.text = key_text
	key_label.theme_type_variation = &"KeyLabel"
	cap.add_child(key_label)
	prompt.add_child(cap)
	var label := Label.new()
	label.text = action
	label.theme_type_variation = &"Strong"
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL + 1)
	prompt.add_child(label)
	return prompt
