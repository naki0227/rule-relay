class_name UiTheme
extends RefCounted
## 画面の色・書体・形・動きを1か所で決める（設計は docs/ui-design.md）。
## 世界観: やわらかく温かい3Dブロックの箱庭。景色とキャラクターを主役にし、UI は
## 「生成りの紙と木の札」のような素材感で、静かに寄り添う。かわいいが子ども向けに寄りすぎない。
## ルール（能力・禁止・貸出）だけは、色と形の両方ではっきり示す。
## 世界観が決まったら、このファイルの値を差し替える（仮のトークン）。

# --- 色 ---
const CREAM := Color("#fff8ec")  # 札・パネルの地
const CREAM_DEEP := Color("#f4e7d1")  # 枠（スロット）の地
const EDGE := Color("#e2cdac")  # 枠線（やわらかい茶）
const EDGE_DEEP := Color("#cdb38b")
const INK := Color("#4d3a2c")  # 文字（こげ茶。真っ黒にしない）
const INK_SOFT := Color("#8a7462")  # 補助の文字
const INK_FAINT := Color("#b7a28e")
const SUN := Color("#f09a45")  # 選択・決定（夕日のだいだい）
const SUN_SOFT := Color("#fde3c6")
const LEAF := Color("#76a85f")  # 有効・自分に効いている（若葉）
const LEAF_SOFT := Color("#e3f0d6")
const HONEY := Color("#e2a72e")  # 貸出中（はちみつ色）
const HONEY_SOFT := Color("#fbecc4")
const BAN := Color("#e0644f")  # 禁止（小さな印・輪だけに使う）
const BAN_SOFT := Color("#fadcd4")
const SKY := Color("#8cc4e8")  # 信号（音）・情報
const SHADOW := Color(0.29, 0.2, 0.12, 0.18)  # 影は茶色寄りにして、黒く濁らせない

# --- 動き ---
const FAST: float = 0.14
const NORMAL: float = 0.22

# --- 寸法（1920x1080 基準。canvas_items で拡大縮小） ---
const SAFE_MARGIN: float = 48.0
const RADIUS_PANEL: int = 22
const RADIUS_SLOT: int = 14
const LINE: int = 2  # 線の太さはすべて 2px にそろえる（選択中だけ 3px）

# --- 文字の大きさ（1080p。720p では 2/3 になるので、最小 18 を守る） ---
const SIZE_SMALL: int = 18
const SIZE_BODY: int = 21
const SIZE_LARGE: int = 26
const SIZE_TITLE: int = 34

const FONT_MEDIUM := "res://assets/fonts/ZenMaruGothic-Medium.ttf"
const FONT_BOLD := "res://assets/fonts/ZenMaruGothic-Bold.ttf"

static var _theme: Theme
static var _fonts: Dictionary[String, Font] = {}


## weight が 600 以上なら太字、それ未満なら中太。spacing は字間（px）。
static func font(weight: int = 500, spacing: int = 0) -> Font:
	var path := FONT_BOLD if weight >= 600 else FONT_MEDIUM
	var key := "%s_%d" % [path, spacing]
	if not _fonts.has(key):
		var variation := FontVariation.new()
		variation.base_font = load(path) as FontFile
		variation.spacing_glyph = spacing
		var system := SystemFont.new()
		system.font_names = PackedStringArray(
			[
				"Yu Gothic UI",
				"Meiryo",
				"Hiragino Maru Gothic ProN",
				"Noto Sans CJK JP",
				"sans-serif"
			]
		)
		variation.fallbacks = [system]
		_fonts[key] = variation
	return _fonts[key]


static func regular() -> Font:
	return font(500)


static func medium() -> Font:
	return font(500)


static func bold() -> Font:
	return font(700)


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


## 生成りの札（パネル）。
static func panel_box(
	fill: Color = CREAM, radius: int = RADIUS_PANEL, margin: float = 24.0
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = EDGE
	box.set_border_width_all(LINE)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	box.shadow_color = SHADOW
	box.shadow_size = 14
	box.shadow_offset = Vector2(0, 6)
	box.anti_aliasing = true
	return box


## 小さな丸い札（チップ・吹き出し）。
static func pill_box(fill: Color = CREAM, border: Color = EDGE) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(LINE)
	box.set_corner_radius_all(999)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 6
	box.content_margin_bottom = 7
	box.shadow_color = Color(SHADOW, 0.12)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0, 3)
	box.anti_aliasing = true
	return box


static func _build() -> Theme:
	var theme := Theme.new()
	theme.default_font = medium()
	theme.default_font_size = SIZE_BODY

	theme.set_color("font_color", "Label", INK)
	theme.set_stylebox("panel", "PanelContainer", panel_box())
	theme.set_stylebox("panel", "Panel", panel_box())

	_variation(theme, "Title", "Label", bold(), SIZE_TITLE, INK)
	_variation(theme, "Heading", "Label", bold(), SIZE_LARGE, INK)
	_variation(theme, "Strong", "Label", bold(), SIZE_BODY, INK)
	_variation(theme, "Body", "Label", medium(), SIZE_BODY, INK)
	_variation(theme, "Note", "Label", medium(), SIZE_SMALL, INK_SOFT)
	_variation(theme, "SectionLabel", "Label", bold(), SIZE_SMALL, INK_SOFT)
	_variation(theme, "KeyLabel", "Label", bold(), 16, INK)

	theme.set_type_variation("Bubble", "PanelContainer")
	theme.set_stylebox("panel", "Bubble", pill_box())
	theme.set_type_variation("KeyCap", "PanelContainer")
	var key := StyleBoxFlat.new()
	key.bg_color = Color.WHITE
	key.border_color = EDGE_DEEP
	key.set_border_width_all(LINE)
	key.border_width_bottom = 4  # 下辺を厚くして押せるキーに見せる
	key.set_corner_radius_all(8)
	key.content_margin_left = 9
	key.content_margin_right = 9
	key.content_margin_top = 1
	key.content_margin_bottom = 2
	theme.set_stylebox("panel", "KeyCap", key)

	_buttons(theme)
	_inputs(theme)
	return theme


static func _variation(
	theme: Theme, name: String, base: String, typeface: Font, size: int, color: Color
) -> void:
	theme.set_type_variation(name, base)
	theme.set_font("font", name, typeface)
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, color)


## メニューの項目: 丸い札。選ぶと夕日色の縁と淡い地になる。
static func _buttons(theme: Theme) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(CREAM_DEEP, 0.0)
	normal.border_color = Color(EDGE, 0.0)
	normal.set_border_width_all(LINE)
	normal.set_corner_radius_all(16)
	normal.content_margin_left = 22
	normal.content_margin_right = 18
	normal.content_margin_top = 10
	normal.content_margin_bottom = 11
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = SUN_SOFT
	focus.border_color = SUN
	focus.set_border_width_all(3)
	var pressed := focus.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(SUN, 0.35)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("disabled", "Button", normal)
	theme.set_stylebox("hover", "Button", focus)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("hover_pressed", "Button", pressed)
	for state: String in ["font_color", "font_hover_color", "font_focus_color"]:
		theme.set_color(state, "Button", INK)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_hover_pressed_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", INK_FAINT)
	theme.set_font("font", "Button", bold())
	theme.set_font_size("font_size", "Button", SIZE_LARGE)

	# 絞り込みのチップ: 小さな丸い札。選んでいるものは若葉色
	theme.set_type_variation("Chip", "Button")
	var chip := pill_box(CREAM, EDGE)
	chip.shadow_size = 0
	chip.content_margin_top = 3
	chip.content_margin_bottom = 4
	chip.content_margin_left = 14
	chip.content_margin_right = 14
	var chip_on := chip.duplicate() as StyleBoxFlat
	chip_on.bg_color = LEAF_SOFT
	chip_on.border_color = LEAF
	theme.set_stylebox("normal", "Chip", chip)
	theme.set_stylebox("hover", "Chip", chip_on)
	theme.set_stylebox("focus", "Chip", StyleBoxEmpty.new())
	theme.set_stylebox("pressed", "Chip", chip_on)
	theme.set_stylebox("hover_pressed", "Chip", chip_on)
	theme.set_font("font", "Chip", bold())
	theme.set_font_size("font_size", "Chip", SIZE_SMALL)
	theme.set_color("font_color", "Chip", INK_SOFT)
	theme.set_color("font_hover_color", "Chip", INK)
	theme.set_color("font_pressed_color", "Chip", INK)
	theme.set_color("font_hover_pressed_color", "Chip", INK)


static func _inputs(theme: Theme) -> void:
	var field := pill_box(Color.WHITE, EDGE)
	field.shadow_size = 0
	field.content_margin_left = 20
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = SUN
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", INK_FAINT)
	theme.set_color("caret_color", "LineEdit", SUN)
	theme.set_color("selection_color", "LineEdit", Color(SUN, 0.3))
	theme.set_color("clear_button_color", "LineEdit", INK_SOFT)
	theme.set_font_size("font_size", "LineEdit", SIZE_SMALL)

	# スクロールバー: 細い丸い棒
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = EDGE_DEEP
	grabber.set_corner_radius_all(999)
	grabber.content_margin_left = 4
	grabber.content_margin_right = 4
	var track := StyleBoxFlat.new()
	track.bg_color = Color(EDGE, 0.35)
	track.set_corner_radius_all(999)
	track.content_margin_left = 4
	track.content_margin_right = 4
	for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		theme.set_stylebox(state, "VScrollBar", grabber)
	theme.set_stylebox("scroll", "VScrollBar", track)
	theme.set_stylebox("scroll_focus", "VScrollBar", track)
