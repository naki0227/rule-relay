class_name ScreenBlur
extends ColorRect
## メニューの背景。後ろの景色を少しだけぼかし、生成りの色を薄く重ねる。
## 景色を主役にするため、暗くしすぎない・ぼかしすぎない（soft のとき）。

const SHADER := preload("res://assets/shaders/screen_blur.gdshader")

## true: 景色が見えるくらい軽く（持ち物・一時停止）。false: しっかり隠す。
var soft: bool = true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var blur := ShaderMaterial.new()
	blur.shader = SHADER
	if soft:
		blur.set_shader_parameter("blur_lod", 1.4)
		blur.set_shader_parameter("tint", Color(1.0, 0.97, 0.92, 0.32))
		blur.set_shader_parameter("vignette", 0.0)
	material = blur
