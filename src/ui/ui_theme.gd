class_name UiTheme
extends RefCounted
## 画面の色・書体・形・動きを1か所で決める。方針は docs/ui-research.md（AAA タイトルの調査）。
## - 世界の上に重ねる UI は、暗い半透明の面・細い線・小さな角丸。文字は温かい白に弱い影
## - 書体は Noto Sans JP の1書体。見出し・本文・小さなラベルは、太さと字間で区別する
## - 色は中立（白・黒の透明度の段階）＋強調色の金1つ。赤は「禁止」の小さな印だけ
## - 動きは ease-out 0.15〜0.25 秒にそろえる
## 世界観が決まったら、このファイルの値を差し替える（仮のトークン）。

# --- 色 ---
const TEXT := Color("#f3efe6")  # 温かい白（真っ白にしない）
const TEXT_DIM := Color(0.953, 0.937, 0.902, 0.64)
const TEXT_FAINT := Color(0.953, 0.937, 0.902, 0.38)
const LINE := Color(1, 1, 1, 0.16)
const LINE_STRONG := Color(1, 1, 1, 0.34)
const SURFACE := Color(0.055, 0.063, 0.086, 0.62)  # 世界の上に重ねる面
const SURFACE_SOLID := Color(0.055, 0.063, 0.086, 0.88)
const SCRIM := Color(0.03, 0.035, 0.05, 0.58)  # メニューの背景を暗くする
const ACCENT := Color("#e2c07a")  # 金（器のアイコンと同じ系統）
const ACCENT_DIM := Color(0.886, 0.753, 0.478, 0.22)
const ALERT := Color("#e4574e")  # 禁止の印だけ
const TEXT_SHADOW := Color(0, 0, 0, 0.45)

# --- 動き ---
const FAST: float = 0.15
const NORMAL: float = 0.22

# --- 寸法（1920x1080 基準。canvas_items で拡大縮小） ---
const SAFE_MARGIN: float = 56.0  # 画面端からの余白（タイトルセーフに近い）
const RADIUS: int = 4

const FONT_PATH := "res://assets/fonts/NotoSansJP-VF.ttf"

static var _theme: Theme
static var _fonts: Dictionary[String, Font] = {}


## weight は 100〜900。spacing は字間（px）。
static func font(weight: int = 400, spacing: int = 0) -> Font:
	var key := "%d_%d" % [weight, spacing]
	if not _fonts.has(key):
		var variation := FontVariation.new()
		variation.base_font = load(FONT_PATH) as FontFile
		# 軸のキーは文字列 "wght" では効かない（Godot 4.6.3 で確認）。OpenType のタグ値で渡す
		variation.variation_opentype = {
			TextServerManager.get_primary_interface().name_to_tag("wght"): weight
		}
		variation.spacing_glyph = spacing
		var system := SystemFont.new()
		system.font_names = PackedStringArray(
			["Yu Gothic UI", "Meiryo", "Hiragino Sans", "Noto Sans CJK JP", "sans-serif"]
		)
		variation.fallbacks = [system]
		_fonts[key] = variation
	return _fonts[key]


static func regular() -> Font:
	return font(400)


static func medium() -> Font:
	return font(500)


static func bold() -> Font:
	return font(700)


## 小さな見出し（例: 「付与方式」「持ち物」上の小ラベル）。字間を開ける。
static func label_font() -> Font:
	return font(600, 2)


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func surface_box(
	fill: Color = SURFACE, border: Color = LINE, radius: int = RADIUS, margin: float = 16.0
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1 if border.a > 0.0 else 0)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	box.anti_aliasing = true
	return box


## 文字に弱い影を付ける（明るい空の上でも読めるように）。
static func add_text_shadow(label: Control) -> void:
	label.add_theme_color_override("font_shadow_color", TEXT_SHADOW)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("shadow_outline_size", 0)


static func _build() -> Theme:
	var theme := Theme.new()
	theme.default_font = regular()
	theme.default_font_size = 18

	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", TEXT_SHADOW)
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 2)
	theme.set_constant("shadow_outline_size", "Label", 0)
	theme.set_stylebox("panel", "PanelContainer", surface_box())
	theme.set_stylebox("panel", "Panel", surface_box())

	_variation(theme, "Display", "Label", font(700, 2), 46, TEXT)
	_variation(theme, "HeaderLarge", "Label", font(700, 1), 34, TEXT)
	_variation(theme, "Header", "Label", bold(), 24, TEXT)
	_variation(theme, "Strong", "Label", medium(), 18, TEXT)
	_variation(theme, "Caption", "Label", regular(), 15, TEXT_DIM)
	_variation(theme, "Kicker", "Label", label_font(), 13, ACCENT)
	_variation(theme, "KeyLabel", "Label", font(600), 13, TEXT)

	theme.set_type_variation("KeyCap", "PanelContainer")
	var key := surface_box(Color(1, 1, 1, 0.1), LINE_STRONG, 3, 0.0)
	key.content_margin_left = 7
	key.content_margin_right = 7
	key.content_margin_top = 1
	key.content_margin_bottom = 2
	theme.set_stylebox("panel", "KeyCap", key)

	_menu_buttons(theme)
	_inputs(theme)
	return theme


static func _variation(
	theme: Theme, name: String, base: String, typeface: Font, size: int, color: Color
) -> void:
	theme.set_type_variation(name, base)
	theme.set_font("font", name, typeface)
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, color)


## メニューの項目: 文字だけの行。選ぶと左に金の線と薄い面が出る（AAA のメニューの定番）。
static func _menu_buttons(theme: Theme) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.content_margin_left = 20
	normal.content_margin_right = 16
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(1, 1, 1, 0.08)
	focus.border_color = ACCENT
	focus.border_width_left = 3
	var pressed := focus.duplicate() as StyleBoxFlat
	pressed.bg_color = ACCENT_DIM
	for state: String in ["normal", "disabled"]:
		theme.set_stylebox(state, "Button", normal)
	theme.set_stylebox("hover", "Button", focus)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("hover_pressed", "Button", pressed)
	theme.set_color("font_color", "Button", TEXT_DIM)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_focus_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", TEXT)
	theme.set_color("font_hover_pressed_color", "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", TEXT_FAINT)
	theme.set_font("font", "Button", medium())
	theme.set_font_size("font_size", "Button", 22)

	# 種類のタブ: 文字だけ。選んでいるタブは白い文字と金の下線
	theme.set_type_variation("Tab", "Button")
	var tab := StyleBoxFlat.new()
	tab.bg_color = Color(0, 0, 0, 0)
	tab.content_margin_left = 4
	tab.content_margin_right = 4
	tab.content_margin_top = 6
	tab.content_margin_bottom = 8
	var tab_on := tab.duplicate() as StyleBoxFlat
	tab_on.border_color = ACCENT
	tab_on.border_width_bottom = 2
	theme.set_stylebox("normal", "Tab", tab)
	theme.set_stylebox("hover", "Tab", tab)
	theme.set_stylebox("focus", "Tab", StyleBoxEmpty.new())
	theme.set_stylebox("pressed", "Tab", tab_on)
	theme.set_stylebox("hover_pressed", "Tab", tab_on)
	theme.set_font("font", "Tab", font(600, 1))
	theme.set_font_size("font_size", "Tab", 18)
	theme.set_color("font_color", "Tab", TEXT_FAINT)
	theme.set_color("font_hover_color", "Tab", TEXT_DIM)
	theme.set_color("font_pressed_color", "Tab", TEXT)
	theme.set_color("font_hover_pressed_color", "Tab", TEXT)


static func _inputs(theme: Theme) -> void:
	# 検索欄: 面を持たず、下線だけ（入力中は金）
	var field := StyleBoxFlat.new()
	field.bg_color = Color(1, 1, 1, 0.05)
	field.border_color = LINE_STRONG
	field.border_width_bottom = 1
	field.content_margin_left = 12
	field.content_margin_right = 12
	field.content_margin_top = 10
	field.content_margin_bottom = 10
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = ACCENT
	field_focus.border_width_bottom = 2
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_FAINT)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", ACCENT_DIM)
	theme.set_color("clear_button_color", "LineEdit", TEXT_DIM)
	theme.set_font_size("font_size", "LineEdit", 18)

	var list := StyleBoxEmpty.new()
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color(1, 1, 1, 0.08)
	selected.border_color = ACCENT
	selected.border_width_left = 3
	var hovered := StyleBoxFlat.new()
	hovered.bg_color = Color(1, 1, 1, 0.04)
	theme.set_stylebox("panel", "ItemList", list)
	theme.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("selected", "ItemList", selected)
	theme.set_stylebox("selected_focus", "ItemList", selected)
	theme.set_stylebox("hovered", "ItemList", hovered)
	theme.set_stylebox("hovered_selected", "ItemList", selected)
	theme.set_stylebox("hovered_selected_focus", "ItemList", selected)
	theme.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	theme.set_color("font_color", "ItemList", TEXT_DIM)
	theme.set_color("font_selected_color", "ItemList", TEXT)
	theme.set_color("font_hovered_color", "ItemList", TEXT)
	theme.set_color("font_hovered_selected_color", "ItemList", TEXT)
	theme.set_color("guide_color", "ItemList", LINE)
	theme.set_constant("v_separation", "ItemList", 14)
	theme.set_constant("h_separation", "ItemList", 14)
	theme.set_constant("icon_margin", "ItemList", 10)
	theme.set_font_size("font_size", "ItemList", 18)
