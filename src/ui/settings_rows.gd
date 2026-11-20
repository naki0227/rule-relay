class_name SettingsRows
extends RefCounted
## 設定の画面の部品（見出し・つまみの行・ボタン）。見た目は UiTheme に合わせる。


## 若葉色の印の付いた見出し（持ち物の画面の見出しと同じ形）。
static func section(title: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var dot := ColorRect.new()
	dot.color = UiTheme.LEAF
	dot.custom_minimum_size = Vector2(6, 18)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var label := Label.new()
	label.text = title
	label.theme_type_variation = &"Strong"
	row.add_child(label)
	return row


## 視点の速さのつまみ（倍率）。パッドでは左右で 0.1 ずつ動く。
static func slider(on_changed: Callable) -> HSlider:
	var bar := HSlider.new()
	bar.min_value = GameSettings.SENSITIVITY_MIN
	bar.max_value = GameSettings.SENSITIVITY_MAX
	bar.step = 0.1
	bar.value = 1.0
	bar.custom_minimum_size = Vector2(440, 40)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.focus_mode = Control.FOCUS_ALL
	bar.value_changed.connect(on_changed)
	return bar


## 「名前　つまみ　値」の行。
static func labeled(caption: String, control: Control, value: Label) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(300, 0)
	row.add_child(label)
	row.add_child(control)
	value.theme_type_variation = &"Strong"
	value.custom_minimum_size = Vector2(80, 0)
	row.add_child(value)
	return row


static func rule() -> Control:
	var line := ColorRect.new()
	line.color = UiTheme.EDGE
	line.custom_minimum_size = Vector2(0, UiTheme.LINE)
	return line


## メニューの項目と同じ丸い札のボタン（文字は本文の大きさ）。マウスで指すと焦点も移す。
static func small_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 46)
	button.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	# メニューの項目と違い、選んでいないときも押せる札だと分かるよう、淡い地と枠線を付ける
	var base := UiTheme.get_theme().get_stylebox("normal", "Button") as StyleBoxFlat
	var normal := base.duplicate() as StyleBoxFlat
	normal.bg_color = UiTheme.CREAM_DEEP
	normal.border_color = UiTheme.EDGE
	button.add_theme_stylebox_override("normal", normal)
	button.mouse_entered.connect(button.grab_focus)
	return button
