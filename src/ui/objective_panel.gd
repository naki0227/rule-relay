class_name ObjectivePanel
extends Control
## ステージの目的の一覧（docs/adr/0020）。画面の右上に、生成りの小さな札で短いチェックリストを出す。
## 行は「印・短い文・チェック」。チェックは条件がそろうと若葉色に塗られる（ホストが数えた進み具合）。
## - ステージに入ったとき: 画面の上の真ん中に大きく BIG_SECONDS 秒出してから、右上の隅へ小さく縮む
## - 目的を見るキー（Tab。パッドは既定で割り当て無し。Start のメニューでも見られる）: もう一度大きく出す
## - 一時停止のメニューを開いている間: メニューの右に大きく出す（メニューの札とは重ならない）
## - 広場・持ち物を開いている間は出さない
## 文は StageObjectives が作る（ここは表示だけ）。HUD（hud.gd）を変えずに、GameRoot が HUD に足す。

## 入ったとき・キーで出したときに大きく出しておく秒数。
const BIG_SECONDS: float = 3.0
## 大きい札の上端（画面の上からの距離。上の真ん中の札 PartyBanner の下）。
const BIG_TOP: float = 104.0
const ICON_BIG: float = 30.0
const ICON_SMALL: float = 22.0

var director: PartyDirector
## 持ち物を開いている間は隠す・一時停止のメニューの間は大きく出すのに使う（無くても動く）。
var hud: Hud

var _big: PanelContainer
var _big_rows: VBoxContainer
var _corner: PanelContainer
var _corner_rows: VBoxContainer
var _big_left: float = 0.0
var _signature: String = ""
var _met: Array[bool] = []
var _tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS  # 一時停止のメニューの間も出す
	theme = UiTheme.get_theme()
	_build()
	if _has_objectives():
		show_big()
	_refresh(true)


func _process(delta: float) -> void:
	if not _has_objectives():
		visible = false
		return
	var paused := hud != null and hud.pause_menu != null and hud.pause_menu.is_open()
	visible = not (hud != null and hud.is_inventory_open())
	if not get_tree().paused:
		_big_left = maxf(0.0, _big_left - delta)
	_place_big(paused)
	if paused and not _big.visible:
		_big.visible = true
		_big.modulate.a = 1.0
		_big.scale = Vector2.ONE
	if paused and _big.visible:
		_corner.modulate.a = 0.0  # 同じ一覧を 2 か所に出さない（閉じると縮んで隅へ戻る）
	elif not paused and _big_left <= 0.0 and _tween == null and _big.visible:
		_shrink()
	_refresh(false)


func _unhandled_input(event: InputEvent) -> void:
	if not InputMap.has_action(&"show_objectives") or not _has_objectives():
		return
	if event.is_action_pressed(&"show_objectives"):
		show_big()
		get_viewport().set_input_as_handled()


## 大きく出す（seconds 秒したら隅へ縮む）。
func show_big(seconds: float = BIG_SECONDS) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_big_left = seconds
	_big.visible = true
	_big.modulate.a = 1.0
	_big.scale = Vector2.ONE
	_corner.modulate.a = 0.0


## 大きく出しているか（テスト用）。
func is_big() -> bool:
	return _big.visible and _big.modulate.a > 0.5


## 隅の札が見えているか（テスト用）。
func is_corner_shown() -> bool:
	return visible and _corner.visible and _corner.modulate.a > 0.5


## いま隅の札に出している行の文（チェックの印つき。StageObjectives.Item.describe と同じ形。テスト用）。
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for row in _corner_rows.get_children():
		if row.is_queued_for_deletion() or row.get_child_count() < 3:
			continue
		var met := (row.get_child(2) as Check).met
		out.append("%s %s" % ["[x]" if met else "[ ]", (row.get_child(1) as Label).text])
	return out


func _has_objectives() -> bool:
	return director != null and director.in_stage() and not director.objectives.is_empty()


## 大きい札が隅へ移りながら小さくなって消え、隅の札が現れる。
func _shrink() -> void:
	var target := _corner.global_position + _corner.size * 0.5
	_big.pivot_offset = _big.size * 0.5
	var shift := target - (_big.global_position + _big.size * 0.5)
	_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_big, "position", _big.position + shift, 0.45)
	_tween.parallel().tween_property(_big, "scale", Vector2.ONE * 0.4, 0.45)
	_tween.parallel().tween_property(_big, "modulate:a", 0.0, 0.45)
	_tween.tween_property(_corner, "modulate:a", 1.0, UiTheme.NORMAL)
	_tween.tween_callback(
		func() -> void:
			_big.visible = false
			_tween = null
	)


## 大きい札の場所: ふだんは上の真ん中、一時停止のメニューの間はメニューの札の右。
func _place_big(paused: bool) -> void:
	if _tween != null:
		return
	var view := get_viewport_rect().size
	var width := _big.size.x
	var left := (view.x - width) * 0.5
	var top := BIG_TOP
	if paused:
		left = maxf(left, minf(760.0, view.x - width - UiTheme.SAFE_MARGIN))
		top = 150.0
	_big.position = Vector2(left, top)


func _refresh(force: bool) -> void:
	if director == null:
		return
	var items := director.objectives
	var signature := ""
	for item in items:
		signature += "%s|%s;" % [item.label(), item.is_met()]
	signature += str(KeyBindings.revision) + str(InputMode.using_pad)
	if signature == _signature and not force:
		return
	_signature = signature
	var newly_met: Array[int] = []
	for i in items.size():
		var was := i < _met.size() and _met[i]
		if items[i].is_met() and not was and _met.size() == items.size():
			newly_met.append(i)
	_met.clear()
	for item in items:
		_met.append(item.is_met())
	_fill(_big_rows, items, true)
	_fill(_corner_rows, items, false)
	for i in newly_met:
		_pop(_corner_rows.get_child(i) as Control)
		_pop(_big_rows.get_child(i) as Control)


func _fill(rows: VBoxContainer, items: Array[StageObjectives.Item], big: bool) -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for item in items:
		rows.add_child(_row(item, big))
	if big:
		var note := Label.new()
		note.theme_type_variation = &"Note"
		note.add_theme_font_size_override("font_size", UiTheme.SIZE_SMALL)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.text = "順番は自由・%s でもう一度" % InputMode.key(&"show_objectives")
		rows.add_child(note)


func _row(item: StageObjectives.Item, big: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12 if big else 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := Glyph.new()
	icon.icon = item.icon
	icon.custom_minimum_size = Vector2.ONE * (ICON_BIG if big else ICON_SMALL)
	row.add_child(icon)
	var text := Label.new()
	text.text = item.label()
	text.theme_type_variation = &"Strong"
	text.add_theme_font_size_override(
		"font_size", UiTheme.SIZE_LARGE if big else UiTheme.SIZE_SMALL
	)
	if item.is_met():
		text.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var check := Check.new()
	check.met = item.is_met()
	check.custom_minimum_size = Vector2.ONE * (ICON_BIG if big else ICON_SMALL)
	row.add_child(check)
	return row


## 条件がそろった行を小さく弾ませる（色だけでなく動きでも分かるように）。
func _pop(row: Control) -> void:
	if row == null:
		return
	row.pivot_offset = Vector2(0.0, row.size.y * 0.5)
	row.scale = Vector2.ONE * 1.12
	var tween := row.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(row, "scale", Vector2.ONE, 0.35)


func _build() -> void:
	_corner = _card(18, 14.0)
	_corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_corner.offset_top = UiTheme.SAFE_MARGIN
	_corner.offset_right = -UiTheme.SAFE_MARGIN
	_corner.modulate.a = 0.0
	_corner_rows = VBoxContainer.new()
	_corner_rows.add_theme_constant_override("separation", 6)
	_corner_rows.custom_minimum_size = Vector2(200, 0)
	_corner.add_child(_corner_rows)
	add_child(_corner)

	_big = _card(26, 24.0)
	_big.custom_minimum_size = Vector2(420, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_big.add_child(column)
	var title := Label.new()
	title.text = "このステージの目的"
	title.theme_type_variation = &"Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_big_rows = VBoxContainer.new()
	_big_rows.add_theme_constant_override("separation", 10)
	column.add_child(_big_rows)
	_big.visible = false
	add_child(_big)


func _card(radius: int, padding: float) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override(
		"panel", UiTheme.panel_box(Color(UiTheme.CREAM, 0.94), radius, padding)
	)
	return card


## 行の印（このゲームの言葉から描く: どうぶつ・運ぶ箱・鐘・時の鐘・上向きの矢印・ゴールの旗）。
class Glyph:
	extends Control

	var icon: StageObjectives.Icon = StageObjectives.Icon.OTHER

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var w := maxf(2.0, s * 0.08)
		match icon:
			StageObjectives.Icon.ANIMAL:
				_animal(c, s, w)
			StageObjectives.Icon.CARRY:
				var box := Rect2(c - Vector2.ONE * s * 0.32, Vector2.ONE * s * 0.64)
				draw_rect(box, UiTheme.HONEY_SOFT)
				draw_rect(box, UiTheme.HONEY, false, w)
				draw_line(box.position, box.end, UiTheme.HONEY, w * 0.7, true)
			StageObjectives.Icon.BELL:
				_bell(c, s, w, UiTheme.HONEY)
			StageObjectives.Icon.TIMED_BELL:
				_bell(c + Vector2(-s * 0.08, 0.0), s * 0.9, w, UiTheme.SKY)
				draw_arc(c + Vector2(s * 0.3, s * 0.28), s * 0.16, 0, TAU, 16, UiTheme.SKY, w, true)
			StageObjectives.Icon.HEIGHT:
				var top := c + Vector2(0, -s * 0.36)
				draw_line(c + Vector2(0, s * 0.36), top, UiTheme.LEAF, w * 1.3, true)
				draw_line(top, top + Vector2(-s * 0.22, s * 0.22), UiTheme.LEAF, w * 1.3, true)
				draw_line(top, top + Vector2(s * 0.22, s * 0.22), UiTheme.LEAF, w * 1.3, true)
			StageObjectives.Icon.GOAL:
				var foot := c + Vector2(-s * 0.2, s * 0.38)
				var head := c + Vector2(-s * 0.2, -s * 0.38)
				draw_line(foot, head, UiTheme.INK_SOFT, w, true)
				draw_colored_polygon(
					PackedVector2Array(
						[head, head + Vector2(s * 0.5, s * 0.15), head + Vector2(0, s * 0.32)]
					),
					UiTheme.SUN
				)
			_:
				draw_arc(c, s * 0.3, 0, TAU, 24, UiTheme.INK_SOFT, w, true)
				draw_circle(c, s * 0.1, UiTheme.INK_SOFT)

	func _animal(c: Vector2, s: float, w: float) -> void:
		for side: float in [-1.0, 1.0]:
			draw_circle(c + Vector2(side * s * 0.22, -s * 0.24), s * 0.12, UiTheme.HONEY)
		draw_circle(c + Vector2(0, s * 0.06), s * 0.32, UiTheme.HONEY_SOFT)
		draw_arc(c + Vector2(0, s * 0.06), s * 0.32, 0, TAU, 24, UiTheme.HONEY, w, true)
		for side: float in [-1.0, 1.0]:
			draw_circle(c + Vector2(side * s * 0.11, s * 0.02), s * 0.04, UiTheme.INK)

	func _bell(c: Vector2, s: float, w: float, color: Color) -> void:
		var dome := PackedVector2Array()
		for i in 13:
			var a := PI + PI * float(i) / 12.0
			dome.append(c + Vector2(cos(a) * s * 0.26, sin(a) * s * 0.3 - s * 0.02))
		dome.append(c + Vector2(s * 0.34, s * 0.24))
		dome.append(c + Vector2(-s * 0.34, s * 0.24))
		draw_colored_polygon(dome, color)
		draw_circle(c + Vector2(0, s * 0.34), s * 0.08, color.darkened(0.25))
		draw_line(c + Vector2(0, -s * 0.32), c + Vector2(0, -s * 0.42), color, w, true)


## 行の右のチェック: まだなら細い輪、そろったら若葉色の丸に白いチェック。
class Check:
	extends Control

	var met: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var r := s * 0.4
		if not met:
			draw_arc(c, r, 0, TAU, 28, UiTheme.EDGE_DEEP, UiTheme.LINE, true)
			return
		draw_circle(c, r, UiTheme.LEAF)
		var w := maxf(2.0, s * 0.1)
		var a := c + Vector2(-r * 0.45, 0.0)
		var b := c + Vector2(-r * 0.1, r * 0.38)
		var d := c + Vector2(r * 0.5, -r * 0.35)
		draw_polyline(PackedVector2Array([a, b, d]), UiTheme.CREAM, w, true)
