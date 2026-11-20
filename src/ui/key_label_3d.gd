class_name KeyLabel3D
extends Label3D
## 操作のキーを含む3Dの看板（鐘・チェックポイント・入口・落ちている器）。
## 文は `{key:interact}` の目印を含む型（template）で持ち、割り当てを変えたとき・
## キーボードとパッドを切り替えたときに描き直す（島を作り直さなくても新しいキーが出る）。

var template: String = "":
	set(value):
		template = value
		render()


func _enter_tree() -> void:
	if not InputMode.notifier.changed.is_connected(render):
		InputMode.notifier.changed.connect(render)
	render()


func _exit_tree() -> void:
	if InputMode.notifier.changed.is_connected(render):
		InputMode.notifier.changed.disconnect(render)


func render() -> void:
	text = InputMode.resolve(template)
