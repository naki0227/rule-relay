class_name CreatureWishView
extends Node3D
## 生き物の頭の上の吹き出し（2026-11-21 本人「どうぶつがなにをもとめてるのかがわかりにくい」）。
## - 印は1つだけ出す: 足りない能力のアイコン（移動・ジャンプ）か、考えていること（↑ 向かう／？ 探す／… 待つ／
##   ↑× 上がれない）か、願いがかなったら ♪
## - 願いの一文（「高いところの巣へ行きたい」）は、プレイヤーが近くに来たか狙ったときだけ、印の下に出す
## 印の種類は文字列の鍵で持ち、通信では鍵だけを配る（参加者の画面も同じ印になる。WorldFrame）。

const KEY_WAIT := "wait"
const KEY_SEEK := "seek"
const KEY_SEARCH := "search"
const KEY_STUCK := "stuck"
const KEY_NEED_MOVE := "need_move"
const KEY_NEED_JUMP := "need_jump"
const KEY_HAPPY := "happy"
const TEXTS: Dictionary[String, String] = {
	KEY_WAIT: "…",
	KEY_SEEK: "↑",
	KEY_SEARCH: "？",
	KEY_STUCK: "↑×",
	KEY_NEED_MOVE: "？",
	KEY_NEED_JUMP: "？",
	KEY_HAPPY: "♪",
}
const STUCK_COLOR := Color("#d9483b")
const HAPPY_COLOR := Color("#5f9a3c")

var _key: String = ""
var _text: Label3D
var _icon: Sprite3D
var _wish: Label3D


func _ready() -> void:
	_text = _label(64)
	_icon = Sprite3D.new()
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.pixel_size = 0.0065
	_icon.no_depth_test = true
	_icon.render_priority = 1
	_icon.modulate = UiTheme.INK  # 移動の矢印の形は白いので、文字と同じこげ茶にする
	_icon.position = Vector3(-0.14, 0.0, 0.0)
	_icon.visible = false
	add_child(_icon)
	_wish = _label(40)
	_wish.position.y = 0.75  # 持っている能力のアイコン（頭の上 1.45）よりさらに上
	_wish.visible = false
	var first := _key if _key != "" else KEY_WAIT
	_key = ""
	show_key(first)


## 印を変える（同じ鍵なら何もしない）。
func show_key(key: String) -> void:
	if key == _key or not TEXTS.has(key):
		return
	_key = key
	if _text == null:
		return
	_text.text = TEXTS[key]
	_text.modulate = (
		STUCK_COLOR if key == KEY_STUCK else HAPPY_COLOR if key == KEY_HAPPY else UiTheme.INK
	)
	var need := RuleAction.Kind.FORWARD if key == KEY_NEED_MOVE else RuleAction.Kind.JUMP
	_icon.visible = key == KEY_NEED_MOVE or key == KEY_NEED_JUMP
	if _icon.visible:
		_icon.texture = ItemIcons.glyph(need)
	# 足りない能力のアイコンの右に小さく「？」を添える
	_text.position.x = 0.22 if _icon.visible else 0.0
	_text.font_size = 56 if _icon.visible else 64


func key() -> String:
	return _key


func set_wish_text(text: String) -> void:
	if _wish != null:
		_wish.text = text


func wish_text() -> String:
	return _wish.text if _wish != null else ""


## 願いの一文を出す・隠す（近くに来た・狙ったときだけ出す）。
func show_wish(on: bool) -> void:
	if _wish != null:
		_wish.visible = on and _wish.text != ""


func is_wish_shown() -> bool:
	return _wish != null and _wish.visible


func _label(font_size: int) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.005
	label.font = UiTheme.font(700, 2)
	label.font_size = font_size
	label.modulate = UiTheme.INK
	label.outline_modulate = Color(UiTheme.CREAM, 0.95)
	label.outline_size = 12
	add_child(label)
	return label
