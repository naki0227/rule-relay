class_name ScreenBlur
extends ColorRect
## 全画面のぼかし＋暗幕。メニュー（持ち物・一時停止）の背景に敷く。

const SHADER := preload("res://assets/shaders/screen_blur.gdshader")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var blur := ShaderMaterial.new()
	blur.shader = SHADER
	material = blur
