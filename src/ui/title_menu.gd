class_name TitleMenu
extends Control
## 起動したときの入口: ひとりで遊ぶ／部屋を作る／部屋に入る（docs/adr/0006）。
## 提出版は Steam なしの直接接続（IP アドレスとポート）。Steam 版では、部屋に入るはロビーと招待に変わる。

signal solo_chosen(profile: String)
signal host_chosen(profile: String, port: int)
signal join_chosen(profile: String, address: String, port: int)

const DEFAULT_PORT: int = 24565

var _profile: LineEdit
var _address: LineEdit
var _port: LineEdit
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	var backdrop := ColorRect.new()
	backdrop.color = UiTheme.CREAM_DEEP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.panel_box())
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(460, 0)
	card.add_child(box)
	_add_label(box, "Rule Relay", UiTheme.SIZE_TITLE, UiTheme.INK)
	_add_label(box, "ルールは厳格に。解法は自由に。", UiTheme.SIZE_SMALL, UiTheme.INK_SOFT)
	_profile = _add_field(box, "記録の名前（同じ PC で2つ起動するときは別の名前に）", "player")
	var first := _add_button(box, "ひとりで遊ぶ", func() -> void: solo_chosen.emit(profile_name()))
	# ゲームパッドでも選べるよう、最初のボタンに焦点を置く（十字キーで移動、A で決定）
	first.call_deferred(&"grab_focus")
	_add_button(box, "部屋を作る（友だちを待つ）", _host)
	_address = _add_field(box, "部屋に入る: ホストの IP アドレス", "127.0.0.1")
	_port = _add_field(box, "ポート", str(DEFAULT_PORT))
	_add_button(box, "部屋に入る", _join)
	_status = _add_label(box, "", UiTheme.SIZE_SMALL, UiTheme.BAN)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func profile_name() -> String:
	var cleaned := _profile.text.strip_edges().to_lower()
	return cleaned if ProgressStore.is_valid_profile(cleaned) else "player"


func show_error(text: String) -> void:
	_status.text = text


func _host() -> void:
	host_chosen.emit(profile_name(), _port_number())


func _join() -> void:
	var address := _address.text.strip_edges()
	if address.is_empty():
		show_error("ホストの IP アドレスを入れてください")
		return
	join_chosen.emit(profile_name(), address, _port_number())


func _port_number() -> int:
	var value := int(_port.text) if _port.text.is_valid_int() else DEFAULT_PORT
	return value if value > 1024 and value < 65536 else DEFAULT_PORT


func _add_label(parent: Control, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UiTheme.font(700))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _add_field(parent: Control, caption: String, value: String) -> LineEdit:
	_add_label(parent, caption, UiTheme.SIZE_SMALL, UiTheme.INK_SOFT)
	var edit := LineEdit.new()
	edit.text = value
	parent.add_child(edit)
	return edit


func _add_button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button
