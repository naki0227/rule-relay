class_name PauseMenu
extends Control
## Esc のメニュー（企画書 8・9）。開いている間はゲームを止める。
## 能力が何も無くても使える復帰操作をここに集める: 最後のチェックポイント、ひとつ前の
## チェックポイント（最後の保存を取り消す）、島の最初から。

signal closed

var world: GameWorld

var _panel: PanelContainer
var _buttons: Dictionary[String, Button] = {}
var _note: Label
var _restart_armed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	_restart_armed = false
	visible = true
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
	if world == null:
		return
	var saves := world.checkpoint_save_count()
	_buttons["previous"].disabled = not world.can_restore_previous_checkpoint()
	_buttons["restart"].text = ("本当に最初からやり直す（もう一度押す）" if _restart_armed else "島の最初からやり直す")
	_note.text = (
		"保存: %d 件（最大 %d 件まで残ります）。保存できない状態では F を押しても保存されません。" % [saves, CheckpointHistory.CAPACITY]
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
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.12, 0.16, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "一時停止"
	title.theme_type_variation = &"HeaderLarge"
	box.add_child(title)
	for item: Array in [
		["resume", "つづける"],
		["latest", "最後のチェックポイントへ戻る"],
		["previous", "ひとつ前のチェックポイントへ戻る（最後の保存を取り消す）"],
		["restart", "島の最初からやり直す"],
		["quit", "ゲームを終了する"],
	]:
		var button := Button.new()
		button.text = String(item[1])
		button.custom_minimum_size = Vector2(0, 44)
		button.pressed.connect(choose.bind(String(item[0])))
		box.add_child(button)
		_buttons[String(item[0])] = button
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(400, 0)
	_note.theme_type_variation = &"Caption"
	box.add_child(_note)
