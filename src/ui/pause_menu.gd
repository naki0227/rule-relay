class_name PauseMenu
extends Control
## Esc のメニュー（企画書 8・9）。景色を軽くぼかし、左寄りに生成りの札を1枚出す。開いている間はゲームを止める。
## ステージの中では、能力が何も無くても使える復帰操作をここに集める（docs/adr/0020）:
## チェックポイントからやり直す・このステージを最初から（もう一度えらんで確定）・このステージから出る
## （もう一度えらんで確定。広場の、このステージのポータルの前へ）。
## 広場では「つづける」「せってい」「ゲームをやめる」だけ。保存を消すような言い方はしない（進行は消えない）。
## 項目の説明は、選んでいる項目の下に短く出す（画面の端に長文を常時出さない）。

signal closed

const ITEMS: Array[Array] = [
	["resume", "つづける", "ゲームにもどります。"],
	[
		"latest",
		"チェックポイントからやり直す",
		"最後のチェックポイントの世界に、まるごともどります。協力中は全員の投票になります。",
	],
	["restart", RESTART_LABEL, "このステージに入ったときの状態から、やり直します。"],
	[
		"leave",
		LEAVE_LABEL,
		"広場の、このステージのポータルの前にもどります。協力中の参加者がえらぶと、全員の投票になります。",
	],
	["settings", "せってい", "キー割り当て・文字の大きさ・視点の速さ・音の大きさを変えます。"],
	[
		"quit",
		"ゲームをやめる",
		"ゲームを終了します。協力中は部屋を出たことになり、まだクリアしていない回の報酬は受け取れません。",
	],
]

## ステージの中だけの項目（広場では出さない）。
const STAGE_ITEMS: PackedStringArray = ["latest", "restart", "leave"]
const RESTART_LABEL := "このステージを最初から"
const RESTART_ARMED := "もう一度えらぶと、このステージを最初から"
const LEAVE_LABEL := "このステージから出る"
const LEAVE_ARMED := "もう一度えらぶと、このステージから出る"

var world: GameWorld
## 設定の画面（「せってい」で開く。この札の上に重ねる）。
var settings_menu: SettingsMenu
## 効果音を鳴らす関数（Hud.play_ui）。無ければ鳴らさない。
var play_sound: Callable
## 「ゲームをやめる」で呼ぶ関数（GameRoot.quit_game: 協力中の参加者は退出を伝えてから終わる。PartyExit）。
## 無ければその場で終わる。
var quit_request: Callable
## 「このステージから出る」で呼ぶ関数（PartyDirector.request_leave_stage。ステージにいるときだけ GameRoot が渡す）。
## 無ければ項目を出さない（広場・1人用の試作の島）。
var leave_request: Callable

var _card: PanelContainer
var _buttons: Dictionary[String, Button] = {}
var _description: Label
## もう一度えらぶと確定する項目（"restart" / "leave"。空なら無し）。
var _armed: String = ""
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
	_armed = ""
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


## ステージの中か（広場ではステージの項目を出さない）。広場でない島（試作の島）もステージとして扱う。
func in_stage() -> bool:
	var stage := world as StageWorld
	return world != null and (stage == null or stage.def == null or not stage.def.is_hub())


## いま見えている項目のキー（上から順。テスト用）。
func visible_items() -> PackedStringArray:
	var keys := PackedStringArray()
	for item: Array in ITEMS:
		var key := String(item[0])
		if _buttons.has(key) and _buttons[key].visible:
			keys.append(key)
	return keys


## 項目の名前（テスト用）。
func item_text(key: String) -> String:
	return _buttons[key].text if _buttons.has(key) else ""


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
	var stage := in_stage()
	for key in STAGE_ITEMS:
		_buttons[key].visible = stage
	_buttons["leave"].visible = stage and leave_request.is_valid()
	_buttons["restart"].text = RESTART_ARMED if _armed == "restart" else RESTART_LABEL
	_buttons["leave"].text = LEAVE_ARMED if _armed == "leave" else LEAVE_LABEL


## 項目を選んだときの処理。テストからも呼ぶ。
func choose(item: String) -> void:
	if _quitting:
		return  # 部屋を出ている途中（ホストの受け付けを待っている）
	if STAGE_ITEMS.has(item) and not in_stage():
		return  # 広場にはステージの項目が無い
	var confirming := item in ["restart", "leave"]
	var arming := confirming and _armed != item
	_armed = item if arming else ""
	_sound(&"ui_select" if arming else &"ui_confirm")
	if arming:
		refresh()
		_describe(
			(
				"もう一度えらぶと、このステージに入ったときの状態からやり直します。"
				if item == "restart"
				else "もう一度えらぶと、このステージを出て、広場のポータルの前にもどります。"
			)
		)
		return
	refresh()
	match item:
		"resume":
			close()
		"latest":
			world.restore_checkpoint()
			close()
		"restart":
			world.restart_island()
			close()
		"leave":
			close()
			if leave_request.is_valid():
				leave_request.call()
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
	var title := Label.new()
	title.text = "ひとやすみ"
	title.theme_type_variation = &"Title"
	column.add_child(title)
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
