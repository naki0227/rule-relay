class_name KeyPrompt
extends HBoxContainer
## 「[キー] 動作」の案内（例: [F] 回収）。


static func make(key: String, action: String, _dim: bool = false) -> KeyPrompt:
	var prompt := KeyPrompt.new()
	prompt.add_theme_constant_override("separation", 8)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := PanelContainer.new()
	cap.theme_type_variation = &"KeyCap"
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var key_label := Label.new()
	key_label.text = InputMode.label(key)
	key_label.theme_type_variation = &"KeyLabel"
	cap.add_child(key_label)
	prompt.add_child(cap)
	var label := Label.new()
	label.text = action
	label.theme_type_variation = &"Strong"
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL + 1)
	prompt.add_child(label)
	return prompt
