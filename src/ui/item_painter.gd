class_name ItemPainter
extends RefCounted
## アイテム（器）の枠を描く唯一の場所。HUD のホットバー・持ち物のホットバー・かばんのグリッドで
## 同じ見た目・同じ状態表示を使う（線の太さ・角丸・色を統一する）。
##
## 状態の示し方（色と形の両方）:
## - 選択中: 夕日色の太い縁＋淡い地
## - 貸出中: アイコンを薄くし、下に、はちみつ色の帯「貸出中」と外向きの矢印
## - 禁止: 右上に赤い輪と斜線の印（器のアイコン自体も禁止の形）
## - 自分に効いている能力（ホットバーにあるとき）: 右上に若葉色の点（show_active のときだけ）


class Style:
	extends RefCounted
	var selected: bool = false
	var hovered: bool = false
	var dimmed: bool = false  # 検索に合わない
	var drop_target: bool = false
	var number: int = -1  # 枠の番号（ホットバー）。-1 なら出さない
	var show_active: bool = false
	var compact: bool = false  # HUD 用（帯の文字を省く）


static func draw_slot(ci: CanvasItem, rect: Rect2, token: RuleToken, style: Style) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.CREAM_DEEP
	box.border_color = UiTheme.EDGE
	box.set_border_width_all(UiTheme.LINE)
	box.set_corner_radius_all(UiTheme.RADIUS_SLOT)
	box.anti_aliasing = true
	if style.hovered or style.drop_target:
		box.bg_color = UiTheme.CREAM
		box.border_color = UiTheme.EDGE_DEEP
	if style.selected:
		box.bg_color = UiTheme.SUN_SOFT
		box.border_color = UiTheme.SUN
		box.set_border_width_all(3)
	if style.drop_target:
		box.border_color = UiTheme.LEAF
		box.set_border_width_all(3)
	ci.draw_style_box(box, rect)
	# 内側の上辺にだけ淡い光を入れて、札の厚みを出す
	ci.draw_line(
		rect.position + Vector2(UiTheme.RADIUS_SLOT, 3.5),
		rect.position + Vector2(rect.size.x - UiTheme.RADIUS_SLOT, 3.5),
		Color(1, 1, 1, 0.7),
		2.0,
		true
	)
	if style.number >= 0:
		ci.draw_string(
			UiTheme.bold(),
			rect.position + Vector2(9, 21),
			str(style.number),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			UiTheme.SUN if style.selected else UiTheme.INK_SOFT
		)
	if token == null:
		return
	var alpha := 1.0
	if not token.is_in_vessel():
		alpha = 0.42
	if style.dimmed:
		alpha *= 0.3
	var icon_size := minf(rect.size.x, rect.size.y) * (0.6 if style.compact else 0.62)
	var icon_rect := Rect2(
		rect.position + Vector2((rect.size.x - icon_size) * 0.5, (rect.size.y - icon_size) * 0.42),
		Vector2(icon_size, icon_size)
	)
	ci.draw_texture_rect(ItemIcons.for_token(token), icon_rect, false, Color(1, 1, 1, alpha))
	var corner := rect.position + Vector2(rect.size.x - 13, 13)
	if not token.is_in_vessel():
		_draw_lent_band(ci, rect, style.compact)
	elif token.is_prohibition:
		UiGlyphs.draw_ban(ci, corner, 18.0)
	elif style.show_active:
		ci.draw_circle(corner, 6.0, Color.WHITE)
		ci.draw_circle(corner, 4.5, UiTheme.LEAF)


static func _draw_lent_band(ci: CanvasItem, rect: Rect2, compact: bool) -> void:
	var band := Rect2(rect.position + Vector2(5, rect.size.y - 25), Vector2(rect.size.x - 10, 20))
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.HONEY_SOFT
	box.border_color = UiTheme.HONEY
	box.set_border_width_all(UiTheme.LINE)
	box.set_corner_radius_all(999)
	box.anti_aliasing = true
	ci.draw_style_box(box, band)
	if compact:
		UiGlyphs.draw_lent(ci, band.get_center(), 14.0, UiTheme.HONEY.darkened(0.25))
		return
	UiGlyphs.draw_lent(ci, band.position + Vector2(13, 10), 12.0, UiTheme.HONEY.darkened(0.25))
	ci.draw_string(
		UiTheme.bold(),
		band.position + Vector2(18, 15),
		"貸出中",
		HORIZONTAL_ALIGNMENT_CENTER,
		band.size.x - 22,
		14,
		UiTheme.HONEY.darkened(0.35)
	)
