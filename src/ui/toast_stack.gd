class_name ToastStack
extends VBoxContainer
## 知らせ: 画面左上に、生成りの小さな吹き出しで出す。ふわっと現れて、しばらくしたら消える。
## 多すぎるときは古いものから消す（1か所の列で順に出す）。

const MAX_TOASTS: int = 3
const LIFETIME: float = 3.2


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)


func push(text: String) -> void:
	while get_child_count() >= MAX_TOASTS:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var bubble := PanelContainer.new()
	bubble.theme_type_variation = &"Bubble"
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var dot := ColorRect.new()
	dot.color = UiTheme.LEAF
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Body"
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL + 1)
	row.add_child(label)
	bubble.add_child(row)
	bubble.modulate.a = 0.0
	add_child(bubble)
	var tween := bubble.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(bubble, "modulate:a", 1.0, UiTheme.NORMAL)
	tween.tween_interval(LIFETIME)
	tween.tween_property(bubble, "modulate:a", 0.0, 0.5)
	tween.tween_callback(bubble.queue_free)


func messages() -> PackedStringArray:
	var out := PackedStringArray()
	for child in get_children():
		if child.is_queued_for_deletion():
			continue
		var label := child.get_child(0).get_child(1) as Label
		if label != null:
			out.append(label.text)
	return out
