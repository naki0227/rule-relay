class_name KeyLabel3D
extends Label3D
## 操作のキーを含む3Dの看板（鐘・チェックポイント・入口・落ちている器）。
## 文は `{key:interact}` の目印を含む型（template）で持ち、割り当てを変えたとき・
## キーボードとパッドを切り替えたときに描き直す（島を作り直さなくても新しいキーが出る）。

## カメラが近いときに画面での大きさを止め、すぐそばでは薄くして消す（OverworldPortal の文字と同じ決まり）。
## チェックポイントの「チェックポイント」が、台座のそばで画面の端からはみ出すほど大きくなり、照準の下の案内に
## 重なっていた（2026-11-22 の通し）。門の文字は OverworldPortal が自分で決めるので切る。
var fit_to_camera: bool = true

var template: String = "":
	set(value):
		template = value
		render()


func _process(_delta: float) -> void:
	if not fit_to_camera or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		fit(cam.global_position.distance_to(global_position))


## カメラとのきょりに合わせて、大きさと濃さを決める（テストからも呼ぶ）。
func fit(distance: float) -> void:
	scale = Vector3.ONE * clampf(distance / OverworldPortal.LABEL_FULL_AT, 0.05, 1.0)
	var span := OverworldPortal.LABEL_FADE_FROM - OverworldPortal.LABEL_GONE_AT
	var alpha := clampf((distance - OverworldPortal.LABEL_GONE_AT) / span, 0.0, 1.0)
	modulate.a = alpha
	outline_modulate.a = 0.95 * alpha
	visible = alpha > 0.0


func _enter_tree() -> void:
	if not InputMode.notifier.changed.is_connected(render):
		InputMode.notifier.changed.connect(render)
	render()


func _exit_tree() -> void:
	if InputMode.notifier.changed.is_connected(render):
		InputMode.notifier.changed.disconnect(render)


func render() -> void:
	text = InputMode.resolve(template)
