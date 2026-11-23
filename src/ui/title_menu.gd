class_name TitleMenu
extends Control
## 起動したときの入口: ひとりで遊ぶ／部屋を作る／部屋に入る（docs/adr/0006）。
## 提出版は Steam なしの直接接続（IP アドレスとポート）。
## Steam 版だけ、Steam 版の通信（src/steam/）が add_entry / add_note で項目を足す（docs/adr/0012）。
## 足されなければ、この画面は Steam のことを何も知らない（提出版はいつもこちら）。
## 「せってい」は Esc のメニューと同じ設定の画面（SettingsMenu）を開く。遊ぶ前にキーや文字の大きさを変えられる。
## 部屋の項目（作る・IP アドレス・ポート・入る・部屋のオプション）は「友だちと遊ぶ」を選んだときだけ出す。
## 初めての人の最初の画面に、IP アドレスやポートや「いたずら向け」の選択が並んでいた（2026-11-22 の通し）。

signal solo_chosen(profile: String)
signal host_chosen(profile: String, port: int)
signal join_chosen(profile: String, address: String, port: int)
signal prohibition_option_toggled(on: bool)

const DEFAULT_PORT: int = 24565
const FRIENDS_CLOSED := "友だちと遊ぶ"
const FRIENDS_OPEN := "友だちと遊ぶ（とじる）"

## 設定の画面（Esc のメニューと同じもの）。
var settings_menu: SettingsMenu

var _profile: LineEdit
var _address: LineEdit
var _port: LineEdit
var _status: Label
var _box: VBoxContainer
var _center: CenterContainer
var _settings_button: Button
var _friends_button: Button
## 部屋の項目（「友だちと遊ぶ」で開く）。
var _room: VBoxContainer


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
	_center = center
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.panel_box())
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(460, 0)
	card.add_child(box)
	_box = box
	_add_label(box, "Rule Relay", UiTheme.SIZE_TITLE, UiTheme.INK)
	_add_label(box, "ルールは厳格に。解法は自由に。", UiTheme.SIZE_SMALL, UiTheme.INK_SOFT)
	_profile = _add_field(box, "記録の名前", "player")
	var first := _add_button(box, "ひとりで遊ぶ", func() -> void: solo_chosen.emit(profile_name()))
	# ゲームパッドでも選べるよう、最初のボタンに焦点を置く（十字キーで移動、A で決定）
	first.call_deferred(&"grab_focus")
	_friends_button = _add_button(box, FRIENDS_CLOSED, toggle_room)
	_room = VBoxContainer.new()
	_room.add_theme_constant_override("separation", 12)
	_room.visible = false
	box.add_child(_room)
	_add_button(_room, "部屋を作る（友だちを待つ）", _host)
	var option := CheckBox.new()
	option.text = "部屋のオプション: 禁止を仲間へ直接渡せる（いたずら向け）"
	option.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
	option.toggled.connect(func(on: bool) -> void: prohibition_option_toggled.emit(on))
	_room.add_child(option)
	_address = _add_field(_room, "部屋に入る: ホストの IP アドレス", "127.0.0.1")
	_port = _add_field(_room, "ポート", str(DEFAULT_PORT))
	_add_button(_room, "部屋に入る", _join)
	_add_label(_room, "同じ PC で 2 つ起動するときは、記録の名前を別にする", UiTheme.SIZE_SMALL, UiTheme.INK_SOFT)
	_settings_button = _add_button(box, "せってい", open_settings)
	_status = _add_label(box, "", UiTheme.SIZE_SMALL, UiTheme.BAN)
	# 設定の画面は最後の子にして、札より手前に出す
	settings_menu = SettingsMenu.new()
	settings_menu.closed.connect(_on_settings_closed)
	add_child(settings_menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## 設定の画面を開く。札は隠す（パッドの十字キーで後ろのボタンへ焦点が抜けないように）。
func open_settings() -> void:
	_center.visible = false
	settings_menu.open()


## 「友だちと遊ぶ」: 部屋の項目を出す・しまう。
func toggle_room() -> void:
	_room.visible = not _room.visible
	_friends_button.text = FRIENDS_OPEN if _room.visible else FRIENDS_CLOSED


func is_room_open() -> bool:
	return _room.visible


func is_settings_open() -> bool:
	return settings_menu.is_open()


func profile_name() -> String:
	var cleaned := _profile.text.strip_edges().to_lower()
	return cleaned if ProgressStore.is_valid_profile(cleaned) else "player"


func show_error(text: String) -> void:
	_status.text = text


## 項目を足す（「部屋に入る」の下、「せってい」の上）。_ready の後に呼ぶ。
func add_entry(text: String, action: Callable) -> Button:
	var button := _add_button(_box, text, action)
	_box.move_child(button, _settings_button.get_index())
	return button


## 小さな説明を足す（add_entry と同じ位置）。
func add_note(text: String) -> Label:
	var label := _add_label(_box, text, UiTheme.SIZE_SMALL, UiTheme.INK_SOFT)
	_box.move_child(label, _settings_button.get_index())
	return label


## 札の項目の並び（設定の画面は含まない。テスト用）。
func menu_box() -> VBoxContainer:
	return _box


func _on_settings_closed() -> void:
	_center.visible = true
	_settings_button.grab_focus()


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
