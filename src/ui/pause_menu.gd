class_name PauseMenu
extends Control
## Esc のメニュー（企画書 8・9）。景色を軽くぼかし、左寄りに生成りの札を1枚出す。開いている間はゲームを止める。
## 能力が何も無くても使える復帰操作をここに集める: 最後のチェックポイント、ひとつ前の
## チェックポイント（最後の保存を取り消す）、島の最初から。
## 項目の説明は、選んでいる項目の下に短く出す（画面の端に長文を常時出さない）。

signal closed

const ITEMS: Array[Array] = [
	["resume", "つづける", "ゲームにもどります。"],
	["latest", "チェックポイントへもどる", "最後に保存したときの世界に、まるごともどります。"],
	["previous", "ひとつ前の保存へもどる", "最後の保存を取り消します。詰んだまま保存してしまったときに。"],
	["restart", "島のはじめから", "保存をすべて消して、島に来たときにもどります。"],
	["settings", "せってい", "キー割り当て・文字の大きさ・視点の速さ・音の大きさを変えます。"],
	[
		"quit",
		"ゲームをやめる",
		"ゲームを終了します。協力中は部屋を出たことになり、まだクリアしていない回の報酬は受け取れません。",
	],
]

var world: GameWorld
## 設定の画面（「せってい」で開く。この札の上に重ねる）。
var settings_menu: SettingsMenu
## 効果音を鳴らす関数（Hud.play_ui）。無ければ鳴らさない。
var play_sound: Callable
## 「ゲームをやめる」で呼ぶ関数（GameRoot.quit_game: 協力中の参加者は退出を伝えてから終わる。PartyExit）。
## 無ければその場で終わる。
var quit_request: Callable

var _card: PanelContainer
var _buttons: Dictionary[String, Button] = {}
var _description: Label
var _saves: Label
var _restart_armed: bool = false
var _quitting: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	_restart_armed = false
	visible = true
	modulate.a = 0.0
	var rest := _card.position
	_card.position = rest - Vector2(30, 0)
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "modulate:a", 1.0, UiTheme.FAST)
	tween.parallel().tween_property(_card, "position", rest, UiTheme.NORMAL)
	get_tree().paused = true
	_sound(&"ui_open")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	_buttons["resume"].grab_focus()


func close() -> void:
	if settings_menu.is_open():
		settings_menu.close()
	if visible:
		_sound(&"ui_close")
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func refresh() -> void:
	if world == null or _buttons.is_empty():
		return
	_buttons["previous"].disabled = not world.can_restore_previous_checkpoint()
	_buttons["restart"].text = "もう一度えらぶと、はじめから" if _restart_armed else "島のはじめから"
	_saves.text = "保存 %d / %d" % [world.checkpoint_save_count(), CheckpointHistory.CAPACITY]


## 項目を選んだときの処理。テストからも呼ぶ。
func choose(item: String) -> void:
	if _quitting:
		return  # 部屋を出ている途中（ホストの受け付けを待っている）
	if item != "restart":
		_restart_armed = false
	if item == "previous" and not world.can_restore_previous_checkpoint():
		_sound(&"ui_error")
		return
	_sound(&"ui_select" if item == "restart" and not _restart_armed else &"ui_confirm")
	match item:
		"resume":
			close()
		"latest":
			world.restore_checkpoint()
			close()
		"previous":
			if world.restore_previous_checkpoint():
				close()
		"restart":
			if _restart_armed:
				world.restart_island()
				close()
			else:
				_restart_armed = true
				refresh()
				_describe("もう一度えらぶと、保存をすべて消して島のはじめにもどります。")
		"settings":
			_card.visible = false
			settings_menu.open()
		"quit":
			get_tree().paused = false
			if quit_request.is_valid():
				_quitting = true
				_describe("部屋を出ています…")
				quit_request.call()
			else:
				get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"restore_checkpoint"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var blur := ScreenBlur.new()
	blur.soft = true
	add_child(blur)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.CREAM, 28, 36.0))
	_card.position = Vector2(150, 150)
	_card.custom_minimum_size = Vector2(560, 0)
	add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_card.add_child(column)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "ひとやすみ"
	title.theme_type_variation = &"Title"
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_saves = Label.new()
	_saves.theme_type_variation = &"Note"
	_saves.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_saves)
	column.add_child(head)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	column.add_child(gap)
	for item: Array in ITEMS:
		var key := String(item[0])
		var button := Button.new()
		button.text = String(item[1])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 56)
		button.pressed.connect(choose.bind(key))
		button.focus_entered.connect(_describe.bind(String(item[2])))
		button.mouse_entered.connect(button.grab_focus)
		column.add_child(button)
		_buttons[key] = button
	var rule := ColorRect.new()
	rule.color = UiTheme.EDGE
	rule.custom_minimum_size = Vector2(0, UiTheme.LINE)
	column.add_child(rule)
	_description = Label.new()
	_description.theme_type_variation = &"Note"
	UiTheme.wrap_text(_description)
	_description.custom_minimum_size = Vector2(480, 56)
	column.add_child(_description)
	# 設定の画面は最後の子にして、Esc・B を札より先に受け取る（設定を閉じて札にもどる）
	settings_menu = SettingsMenu.new()
	settings_menu.play_sound = func(event: StringName) -> void: _sound(event)
	settings_menu.closed.connect(_on_settings_closed)
	add_child(settings_menu)


func _on_settings_closed() -> void:
	_card.visible = true
	if visible:
		_buttons["settings"].grab_focus()


func _describe(text: String) -> void:
	if visible and _description.text != text:
		_sound(&"ui_hover")
	_description.text = text


func _sound(event: StringName) -> void:
	if play_sound.is_valid():
		play_sound.call(event)
