class_name StageTransition
extends CanvasLayer
## ステージに入る・出る・最初からやり直すとき、新しい島を生成りの幕から丸く開いて見せる
## （docs/adr/0022-visual-direction-and-quality.md）。島がぱっと切りかわる瞬間と、組み立て中の一瞬を隠す。
## 見た目だけで、入力も遊びも止めない（幕はマウスを受けない。開くのは 0.6 秒）。

const NODE_NAME := "StageTransition"
const SHADER := preload("res://assets/shaders/iris.gdshader")
const OPEN_SECONDS: float = 0.6
## 開き始めるまで、幕を閉じたまま見せる時間（島の最初の数フレームのちらつきを隠す）。
const HOLD_SECONDS: float = 0.12

var _rect: ColorRect
var _material: ShaderMaterial


## parent の上で幕を開く。すでに開いている途中なら、閉じた所からやり直す。
static func play_on(parent: Node) -> StageTransition:
	var old := parent.get_node_or_null(NODE_NAME)
	if old != null:
		old.free()
	var transition := StageTransition.new()
	transition.name = NODE_NAME
	parent.add_child(transition)
	return transition


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"tint", UiTheme.CREAM)
	_material.set_shader_parameter(&"progress", 0.0)
	_rect.material = _material
	add_child(_rect)
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(HOLD_SECONDS)
	tween.tween_method(_set_progress, 0.0, 1.0, OPEN_SECONDS)
	tween.tween_callback(queue_free)


## 幕の開き具合（0 = 閉じている、1 = 全部見える）。
func progress() -> float:
	return float(_material.get_shader_parameter(&"progress"))


func _set_progress(value: float) -> void:
	_material.set_shader_parameter(&"progress", value)
