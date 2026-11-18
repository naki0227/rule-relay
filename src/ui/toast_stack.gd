class_name ToastStack
extends VBoxContainer
## 知らせ: 画面左の決まった場所に、左に金の線を付けた1行で出す。新しいものが下に入り、
## 左から滑り込んで、しばらくしたら消える。多すぎるときは古いものから消す（God of War の
## 「1か所の列で順に出す」考え方）。

const MAX_TOASTS: int = 3
const LIFETIME: float = 3.6


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)


func push(text: String) -> void:
	while get_child_count() >= MAX_TOASTS:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	var bar := ColorRect.new()
	bar.color = UiTheme.ACCENT
	bar.custom_minimum_size = Vector2(2, 0)
	row.add_child(bar)
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Strong"
	label.add_theme_font_size_override("font_size", 18)
	UiTheme.add_text_shadow(label)
	row.add_child(label)
	row.modulate.a = 0.0
	add_child(row)
	label.position.x = -24.0
	var tween := row.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(row, "modulate:a", 1.0, UiTheme.NORMAL)
	tween.tween_interval(LIFETIME)
	tween.tween_property(row, "modulate:a", 0.0, 0.6)
	tween.tween_callback(row.queue_free)


func messages() -> PackedStringArray:
	var out := PackedStringArray()
	for child in get_children():
		if child.is_queued_for_deletion():
			continue
		var label := child.get_child(1) as Label
		if label != null:
			out.append(label.text)
	return out
