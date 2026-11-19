class_name KeyPrompt
extends HBoxContainer
## 「[キー] 動作」の案内（例: [F] 回収）。画面下の操作の帯や、照準の下の文脈の案内に使う。


static func make(key: String, action: String, dim: bool = false) -> KeyPrompt:
	var prompt := KeyPrompt.new()
	prompt.add_theme_constant_override("separation", 8)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap := PanelContainer.new()
	cap.theme_type_variation = &"KeyCap"
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var key_label := Label.new()
	key_label.text = key
	key_label.theme_type_variation = &"KeyLabel"
	cap.add_child(key_label)
	prompt.add_child(cap)
	var label := Label.new()
	label.text = action
	label.theme_type_variation = &"Caption" if dim else &"Strong"
	label.add_theme_font_size_override("font_size", 15)
	prompt.add_child(label)
	return prompt
