class_name PauseMenu
extends Control
## Esc のメニュー（企画書 8・9）。全画面で後ろのゲームをぼかし、左に項目の列、右に選んでいる
## 項目の説明、下に操作の案内を出す。開いている間はゲームを止める。
## 能力が何も無くても使える復帰操作をここに集める: 最後のチェックポイント、ひとつ前の
## チェックポイント（最後の保存を取り消す）、島の最初から。

signal closed

const ITEMS: Array[Array] = [
	["resume", "つづける", "ゲームに戻ります。"],
	[
		"latest",
		"最後のチェックポイントへ戻る",
		"最後に保存した時点へ、世界を丸ごと戻します。能力・ブロック・位置がすべて保存時の状態になります。",
	],
	[
		"previous",
		"ひとつ前のチェックポイントへ",
		"最後の保存を取り消して、その前の保存へ戻ります。詰んだ状態で保存してしまったときに使います。取り消した保存には戻れません。",
	],
	[
		"restart",
		"島の最初からやり直す",
		"保存をすべて消して、島に入った時点へ戻ります。確認のため、もう一度選ぶと実行します。",
	],
	["quit", "ゲームを終了する", "ゲームを終了します。"],
]

var world: GameWorld

var _buttons: Dictionary[String, Button] = {}
var _description: Label
var _status: Label
var _restart_armed: bool = false


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
	create_tween().tween_property(self, "modulate:a", 1.0, UiTheme.FAST)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	_buttons["resume"].grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func refresh() -> void:
	if world == null or _buttons.is_empty():
		return
	_buttons["previous"].disabled = not world.can_restore_previous_checkpoint()
	_buttons["restart"].text = "もう一度選ぶとやり直します" if _restart_armed else "島の最初からやり直す"
	_status.text = (
		"保存 %d / %d　·　足が地面についていない、W/A/S/D がどれも使えない、などの状態では保存できません"
		% [world.checkpoint_save_count(), CheckpointHistory.CAPACITY]
	)


## 項目を選んだときの処理。テストからも呼ぶ。
func choose(item: String) -> void:
	if item != "restart":
		_restart_armed = false
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
		"quit":
			get_tree().paused = false
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"restore_checkpoint"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	add_child(ScreenBlur.new())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 140)
	margin.add_theme_constant_override("margin_right", 140)
	margin.add_theme_constant_override("margin_top", 120)
	margin.add_theme_constant_override("margin_bottom", 56)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 0)
	margin.add_child(page)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 96)
	page.add_child(body)

	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(560, 0)
	column.add_theme_constant_override("separation", 6)
	body.add_child(column)
	var kicker := Label.new()
	kicker.text = "PAUSED"
	kicker.theme_type_variation = &"Kicker"
	column.add_child(kicker)
	var title := Label.new()
	title.text = "一時停止"
	title.theme_type_variation = &"Display"
	column.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 28)
	column.add_child(gap)
	for item: Array in ITEMS:
		var key := String(item[0])
		var button := Button.new()
		button.text = String(item[1])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 52)
		button.pressed.connect(choose.bind(key))
		button.focus_entered.connect(_describe.bind(String(item[2])))
		button.mouse_entered.connect(button.grab_focus)
		column.add_child(button)
		_buttons[key] = button

	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(side)
	var side_gap := Control.new()
	side_gap.custom_minimum_size = Vector2(0, 150)  # 項目の列の先頭とそろえる
	side.add_child(side_gap)
	var side_kicker := Label.new()
	side_kicker.text = "DETAIL"
	side_kicker.theme_type_variation = &"Kicker"
	side.add_child(side_kicker)
	_description = Label.new()
	_description.theme_type_variation = &"Caption"
	_description.add_theme_font_size_override("font_size", 19)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(460, 0)
	side.add_child(_description)

	var rule := ColorRect.new()
	rule.color = UiTheme.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	page.add_child(rule)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 28)
	var spacer_top := Control.new()
	spacer_top.custom_minimum_size = Vector2(0, 14)
	page.add_child(spacer_top)
	footer.add_child(KeyPrompt.make("Enter", "決定", true))
	footer.add_child(KeyPrompt.make("Esc", "戻る", true))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(fill)
	_status = Label.new()
	_status.theme_type_variation = &"Caption"
	_status.add_theme_font_size_override("font_size", 14)
	footer.add_child(_status)
	page.add_child(footer)


func _describe(text: String) -> void:
	_description.text = text
