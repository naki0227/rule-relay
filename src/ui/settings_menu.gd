class_name SettingsMenu
extends Control
## 設定の画面（Esc のメニューの「せってい」から開く）。生成りの札を1枚、画面の中央に出す。
##   文字の大きさ（4段階）／画質（低・中・高、ミニチュア風のぼかし）／視点の速さ（マウス・パッド）／
##   音の大きさ（BGM・効果音）／
##   キー割り当て（キーボード・マウスとパッド）
## ゲームパッドだけでも使える: 十字キーで項目を移り、A で決定、つまみは左右で動かす。B か Start でもどる。
## 割り当ては、ボタンを選んでから割り当てたい入力を押す（5秒押さなければ取り消し）。
## 変えたらすぐ反映し、`user://settings.cfg` へ保存する（GameSettings）。

signal closed

## 入力を待つ秒数。
const CAPTURE_SECONDS: float = 5.0
## ここより小さいスティック・トリガーの傾きは、割り当ての入力として受け取らない。
const AXIS_THRESHOLD: float = 0.6
const SLOTS: Array[KeyBindings.Slot] = [KeyBindings.Slot.KEYBOARD, KeyBindings.Slot.PAD]
const DEFAULT_NOTE := "変えるとすぐに反映して、保存します。"

var settings: GameSettings
## 効果音を鳴らす関数（Hud.play_ui）。無ければ鳴らさない。
var play_sound: Callable

var _card: PanelContainer
var _scroll: ScrollContainer
var _scale_buttons: Array[Button] = []
var _quality_buttons: Array[Button] = []
var _quality_note: Label
var _dof_button: Button
var _mouse_slider: HSlider
var _pad_slider: HSlider
var _mouse_value: Label
var _pad_value: Label
var _music_slider: HSlider
var _sfx_slider: HSlider
var _music_value: Label
var _sfx_value: Label
var _bind_buttons: Dictionary[String, Button] = {}
var _status: Label
var _reset: Button
var _reset_armed: bool = false
var _capture_action: StringName = &""
var _capture_slot: KeyBindings.Slot = KeyBindings.Slot.KEYBOARD
var _capture_left: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func is_open() -> bool:
	return visible


func is_capturing() -> bool:
	return _capture_action != &""


func open() -> void:
	if settings == null:
		settings = GameSettings.get_current()
	_reset_armed = false
	visible = true
	_fit()
	refresh()
	_set_status(DEFAULT_NOTE)
	_sound(&"ui_open")
	_scale_buttons[settings.scale_step].grab_focus()
	# 焦点に合わせたスクロールで見出しが隠れないよう、開いたときは先頭から見せる
	_scroll.set_deferred(&"scroll_vertical", 0)


func close() -> void:
	if not visible:
		return
	_cancel_capture()
	if settings != null:
		settings.save_file()
	visible = false
	_sound(&"ui_close")
	closed.emit()


func refresh() -> void:
	if settings == null:
		return
	for i in _scale_buttons.size():
		_scale_buttons[i].set_pressed_no_signal(i == settings.scale_step)
	for i in _quality_buttons.size():
		_quality_buttons[i].set_pressed_no_signal(i == settings.visual_quality)
	_quality_note.text = VisualQuality.NOTES[settings.visual_quality]
	_dof_button.set_pressed_no_signal(settings.miniature_dof)
	_dof_button.text = "ミニチュア風のぼかし: %s" % ("あり" if settings.miniature_dof else "なし")
	_mouse_slider.set_value_no_signal(settings.mouse_sensitivity)
	_pad_slider.set_value_no_signal(settings.pad_sensitivity)
	_mouse_value.text = "×%.1f" % settings.mouse_sensitivity
	_pad_value.text = "×%.1f" % settings.pad_sensitivity
	_music_slider.set_value_no_signal(settings.music_volume)
	_sfx_slider.set_value_no_signal(settings.sfx_volume)
	_music_value.text = "%d%%" % settings.music_volume
	_sfx_value.text = "%d%%" % settings.sfx_volume
	for action: StringName in KeyBindings.ACTIONS:
		for slot: KeyBindings.Slot in SLOTS:
			var descriptor := settings.bindings.get_descriptor(action, slot)
			var event := InputNames.decode(descriptor)
			_bind_button(action, slot).text = "—" if event == null else InputNames.text(event)
	_reset.text = "もう一度えらぶと、はじめの設定に" if _reset_armed else "はじめの設定にもどす"


## 文字の大きさを選ぶ（0〜3）。テストからも呼ぶ。
func choose_scale(step: int) -> void:
	settings.set_scale_step(step)
	settings.apply(get_tree())
	_saved("文字の大きさ: %s" % GameSettings.SCALE_NAMES[settings.scale_step])
	_fit()


## 画質を選ぶ（0 = 低、1 = 中、2 = 高）。いまの島の効果へすぐ反映し、保存する。テストからも呼ぶ。
func choose_quality(level: int) -> void:
	settings.set_visual_quality(level)
	VisualQuality.apply_all(get_tree())
	_saved("画質: %s" % VisualQuality.NAMES[settings.visual_quality])


## 遠くを少しぼかす（ミニチュア風）。テストからも呼ぶ。
func choose_miniature_dof(on: bool) -> void:
	settings.miniature_dof = on
	VisualQuality.apply_all(get_tree())
	_saved("ミニチュア風のぼかし: %s" % ("あり" if on else "なし"))


## BGM の音量（0〜100%）。すぐにバスへ反映し、保存は閉じるときにまとめて行う。テストからも呼ぶ。
func choose_music_volume(percent: int) -> void:
	settings.set_music_volume(percent)
	settings.apply_volumes()
	_saved("BGM の音量: %d%%" % settings.music_volume, false)


## 効果音の音量（0〜100%）。大きさが分かるよう、動かすたびに選んだ音を鳴らす。テストからも呼ぶ。
func choose_sfx_volume(percent: int) -> void:
	settings.set_sfx_volume(percent)
	settings.apply_volumes()
	_saved("効果音の音量: %d%%" % settings.sfx_volume, false)
	_sound(&"ui_select")


## 割り当てたい入力を待つ。テストからも呼ぶ。
func begin_capture(action: StringName, slot: KeyBindings.Slot) -> void:
	_capture_action = action
	_capture_slot = slot
	_capture_left = CAPTURE_SECONDS
	_bind_button(action, slot).text = "押してください…"
	var what := "キーかマウスのボタン" if slot == KeyBindings.Slot.KEYBOARD else "パッドのボタン"
	_set_status(
		(
			"「%s」に割り当てる%sを押してください（%d 秒で取り消し）。"
			% [KeyBindings.action_name(action), what, int(CAPTURE_SECONDS)]
		)
	)
	_sound(&"ui_select")


## 入力を待っている間に来た入力を割り当てる。受け取ったら true（テストからも呼ぶ）。
func capture(event: InputEvent) -> bool:
	if not is_capturing() or not event.is_pressed() or event.is_echo():
		return false
	var descriptor := InputNames.encode(event)
	if descriptor == "" or _too_small(event):
		return false
	var action := _capture_action
	if InputNames.is_pad_descriptor(descriptor) != (_capture_slot == KeyBindings.Slot.PAD):
		var wrong := "パッドのボタン" if _capture_slot == KeyBindings.Slot.PAD else "キー"
		_set_status("ここには%sを割り当てます。" % wrong)
		return true
	var result := settings.bindings.assign(action, _capture_slot, descriptor)
	_capture_action = &""
	if not result.ok:
		_sound(&"ui_error")
		_set_status(
			(
				"%s は「%s」に使っているので、割り当てられません。"
				% [InputNames.text(event), KeyBindings.action_name(result.blocked_by)]
			)
		)
		refresh()
		return true
	settings.bindings.apply()
	var note := "「%s」を %s にしました。" % [KeyBindings.action_name(action), InputNames.text(event)]
	if result.swapped_with != &"":
		var moved := InputNames.decode(
			settings.bindings.get_descriptor(result.swapped_with, _capture_slot)
		)
		note += (
			"「%s」は %s と入れかえました。"
			% [KeyBindings.action_name(result.swapped_with), InputNames.text(moved)]
		)
	_saved(note)
	return true


## はじめの設定にもどす（もう一度えらぶと確定）。テストからも呼ぶ。
func choose_reset() -> void:
	if not _reset_armed:
		_reset_armed = true
		refresh()
		_set_status("もう一度えらぶと、文字の大きさ・画質・視点の速さ・音の大きさ・キー割り当てをはじめにもどします。")
		_sound(&"ui_select")
		return
	_reset_armed = false
	settings.reset_to_defaults()
	settings.apply(get_tree())
	_saved("はじめの設定にもどしました。")
	_fit()


func _input(event: InputEvent) -> void:
	if not visible or not is_capturing():
		return
	InputMode.observe(event)
	if capture(event):
		get_viewport().set_input_as_handled()
	elif not event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	InputMode.observe(event)
	if event.is_action_pressed(&"restore_checkpoint") or event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_capturing():
		return
	_capture_left -= delta
	if _capture_left <= 0.0:
		_cancel_capture()
		_set_status("割り当てを取り消しました。")
		_sound(&"ui_cancel")


## 割り当てに使わない入力: 小さな傾きのスティック・トリガーと、ホイールの回転（押しっぱなしにできない）。
static func _too_small(event: InputEvent) -> bool:
	var motion := event as InputEventJoypadMotion
	if motion != null:
		return absf(motion.axis_value) < AXIS_THRESHOLD
	var mouse := event as InputEventMouseButton
	return (
		mouse != null
		and mouse.button_index >= MOUSE_BUTTON_WHEEL_UP
		and mouse.button_index <= MOUSE_BUTTON_WHEEL_RIGHT
	)


func _cancel_capture() -> void:
	if is_capturing():
		_capture_action = &""
		refresh()


## 変えた設定を保存して知らせる。つまみは動かすたびに書かず、閉じるときにまとめて保存する。
func _saved(note: String, write: bool = true) -> void:
	if write:
		settings.save_file()
		_sound(&"ui_confirm")
	refresh()
	_set_status(note)


func _set_status(text: String) -> void:
	_status.text = text


func _bind_button(action: StringName, slot: KeyBindings.Slot) -> Button:
	return _bind_buttons["%s:%d" % [action, slot]]


## 画面が小さいとき（文字を大きくしたときなど）も札が収まるよう、スクロールする部分の高さを決める。
func _fit() -> void:
	var height := get_viewport_rect().size.y
	_scroll.custom_minimum_size.y = clampf(height - 330.0, 240.0, 600.0)


func _sound(event: StringName) -> void:
	if play_sound.is_valid():
		play_sound.call(event)


func _build() -> void:
	var blur := ScreenBlur.new()
	blur.soft = true
	add_child(blur)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.CREAM, 28, 32.0))
	_card.custom_minimum_size = Vector2(980, 0)
	center.add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_card.add_child(column)
	var title := Label.new()
	title.text = "せってい"
	title.theme_type_variation = &"Title"
	column.add_child(title)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	column.add_child(_scroll)
	# スクロールバーがボタンに重ならないよう、右に余白を置く
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 24)
	_scroll.add_child(gutter)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	gutter.add_child(body)
	body.add_child(SettingsRows.section("文字の大きさ"))
	body.add_child(_build_scale_row())
	body.add_child(SettingsRows.section("画質"))
	body.add_child(_build_quality_row())
	body.add_child(SettingsRows.section("視点の速さ"))
	_mouse_slider = SettingsRows.slider(_on_mouse_changed)
	_mouse_value = Label.new()
	body.add_child(SettingsRows.labeled("マウス", _mouse_slider, _mouse_value))
	_pad_slider = SettingsRows.slider(_on_pad_changed)
	_pad_value = Label.new()
	body.add_child(SettingsRows.labeled("パッド（右スティック）", _pad_slider, _pad_value))
	body.add_child(SettingsRows.section("音の大きさ"))
	_music_slider = SettingsRows.volume_slider(
		func(v: float) -> void: choose_music_volume(roundi(v))
	)
	_music_value = Label.new()
	body.add_child(SettingsRows.labeled("BGM の音量", _music_slider, _music_value))
	_sfx_slider = SettingsRows.volume_slider(func(v: float) -> void: choose_sfx_volume(roundi(v)))
	_sfx_value = Label.new()
	body.add_child(SettingsRows.labeled("効果音の音量", _sfx_slider, _sfx_value))
	body.add_child(SettingsRows.section("キー割り当て"))
	body.add_child(_build_bindings())
	column.add_child(SettingsRows.rule())
	_status = Label.new()
	_status.theme_type_variation = &"Note"
	UiTheme.wrap_text(_status)
	_status.custom_minimum_size = Vector2(900, 52)
	column.add_child(_status)
	column.add_child(_build_footer())


func _build_scale_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	for i in GameSettings.SCALES.size():
		var button := SettingsRows.small_button(GameSettings.SCALE_NAMES[i])
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(choose_scale.bind(i))
		row.add_child(button)
		_scale_buttons.append(button)
	return row


## 画質（低・中・高）と、その中身の短い説明、ミニチュア風のぼかしの入り切り。
func _build_quality_row() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	for i in VisualQuality.NAMES.size():
		var button := SettingsRows.small_button(VisualQuality.NAMES[i])
		button.custom_minimum_size.x = 120
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(choose_quality.bind(i))
		row.add_child(button)
		_quality_buttons.append(button)
	_dof_button = SettingsRows.small_button("")
	_dof_button.toggle_mode = true
	_dof_button.toggled.connect(choose_miniature_dof)
	row.add_child(_dof_button)
	column.add_child(row)
	_quality_note = Label.new()
	_quality_note.theme_type_variation = &"Note"
	UiTheme.wrap_text(_quality_note)
	column.add_child(_quality_note)
	return column


func _build_bindings() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	for caption: String in ["", "キーボード・マウス", "ゲームパッド"]:
		var head := Label.new()
		head.text = caption
		head.theme_type_variation = &"SectionLabel"
		grid.add_child(head)
	for action: StringName in KeyBindings.ACTIONS:
		var name_label := Label.new()
		name_label.text = KeyBindings.action_name(action)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		for slot: KeyBindings.Slot in SLOTS:
			var button := SettingsRows.small_button("")
			button.custom_minimum_size = Vector2(230, 46)
			button.pressed.connect(begin_capture.bind(action, slot))
			grid.add_child(button)
			_bind_buttons["%s:%d" % [action, slot]] = button
	return grid


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_reset = SettingsRows.small_button("はじめの設定にもどす")
	_reset.pressed.connect(choose_reset)
	row.add_child(_reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var back := SettingsRows.small_button("もどる")
	back.custom_minimum_size = Vector2(160, 48)
	back.pressed.connect(close)
	row.add_child(back)
	return row


func _on_mouse_changed(value: float) -> void:
	settings.set_mouse_sensitivity(value)
	_saved("視点の速さ（マウス）: ×%.1f" % settings.mouse_sensitivity, false)


func _on_pad_changed(value: float) -> void:
	settings.set_pad_sensitivity(value)
	_saved("視点の速さ（パッド）: ×%.1f" % settings.pad_sensitivity, false)
