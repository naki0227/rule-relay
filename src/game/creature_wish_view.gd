class_name CreatureWishView
extends Node3D
## 生き物の頭の上の吹き出し（2026-11-21 本人「足りひんやつとかをコメントで言うんじゃなくて、吹き出しの中に
## 欲しいこういうメダルのやつ、アイコンみたいな」。ADR 0019）。足りないものは文字や知らせで言わず、ここだけで見せる:
## - 足りない能力: ホットバー・器と同じメダルの絵を吹き出しの中に並べる（多くて 3 つ）
## - どの能力でも進めない（道が要る）: 吹き出しの中に小さな階段の絵
## - 願いがかなった: 緑の ♪ を出して、しばらくすると消える
## - 何も足りない物が無い（歩いている・待つだけ）: 吹き出しを出さない
## 吹き出しはカメラのほうを向き、ゆっくり上下する（Creature が高さを揺らす）。遠いと薄くなり、もっと遠いと消える。
## 願いの一文（「高いところの巣へ行きたい」）は、近くに来たか狙ったときだけ吹き出しの上に小さく出す。
## 印は文字列の鍵で持ち、通信では鍵だけを配る（参加者の画面も同じ吹き出しになる。WorldFrame）。

## 鍵: 空 = 出さない、"happy" = ♪、"path" = 階段、"need:<RuleAction.Kind>,..." = メダル。
const KEY_NONE := ""
const KEY_HAPPY := "happy"
const KEY_PATH := "path"
const NEED_PREFIX := "need:"
const KEY_NEED_MOVE := "need:0"
const KEY_NEED_JUMP := "need:4"
const MAX_MEDALS: int = 3
const HAPPY_COLOR := Color("#5f9a3c")
## メダル・階段の絵の大きさ（128 px の絵が約 0.24 m）。
const ICON_PIXEL: float = 0.0023
const MEDAL_STEP: float = 0.32
## ♪ を出しておく秒数と、消えるまでの秒数。
const HAPPY_HOLD: float = 2.5
const HAPPY_FADE: float = 1.0
## カメラからこの距離までははっきり、FAR で消える（遠くの吹き出しで画面をにぎやかにしない）。
const NEAR: float = 10.0
const FAR: float = 18.0

static var _backs: Dictionary[int, ImageTexture] = {}
static var _stairs_texture: ImageTexture

var _key: String = KEY_NONE
var _bubble: Node3D
var _back: Sprite3D
var _medals: Array[Sprite3D] = []
var _stairs: Sprite3D
var _note: Label3D
var _wish: Label3D
var _happy_time: float = 0.0
var _distance_alpha: float = 1.0


func _ready() -> void:
	_bubble = Node3D.new()
	_bubble.name = "Bubble"
	add_child(_bubble)
	_back = _sprite(null)
	_back.render_priority = 0
	_back.position.y = -0.0085
	for i in MAX_MEDALS:
		_medals.append(_sprite(null))
	_stairs = _sprite(stairs_texture())
	_note = Label3D.new()
	_note.text = "♪"
	_note.pixel_size = 0.005
	_note.font = UiTheme.font(700, 2)
	_note.font_size = 64
	_note.modulate = HAPPY_COLOR
	_note.outline_modulate = Color(UiTheme.CREAM, 0.95)
	_note.outline_size = 12
	_note.no_depth_test = true
	_bubble.add_child(_note)
	_wish = Label3D.new()
	_wish.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_wish.pixel_size = 0.004
	_wish.font = UiTheme.font(700, 2)
	_wish.font_size = 36
	_wish.modulate = UiTheme.INK
	_wish.outline_modulate = Color(UiTheme.CREAM, 0.95)
	_wish.outline_size = 10
	_wish.position.y = 0.75  # 持っている能力のアイコン（頭の上 1.45）よりさらに上
	_wish.visible = false
	add_child(_wish)
	var first := _key
	_key = "-"
	show_key(first)


func _process(delta: float) -> void:
	if _bubble == null:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		_bubble.global_basis = cam.global_basis
		var d := cam.global_position.distance_to(global_position)
		_distance_alpha = clampf((FAR - d) / (FAR - NEAR), 0.0, 1.0)
	if _key == KEY_HAPPY:
		_happy_time += delta
	_apply_alpha()


## 印を変える（同じ鍵なら何もしない。知らない鍵は出さない）。
func show_key(key: String) -> void:
	key = normalize(key)
	if key == _key:
		return
	_key = key
	_happy_time = 0.0
	if _bubble == null:
		return
	var kinds := needs()
	var path := key == KEY_PATH
	var happy := key == KEY_HAPPY
	var count := maxi(kinds.size(), 1)
	_back.visible = not kinds.is_empty() or path
	if _back.visible:
		_back.texture = bubble_texture(count)
	for i in MAX_MEDALS:
		var medal := _medals[i]
		medal.visible = i < kinds.size()
		if medal.visible:
			var token := RuleToken.new()
			token.action = kinds[i]
			medal.texture = ItemIcons.for_token(token)
			medal.position = Vector3(
				(float(i) - float(kinds.size() - 1) * 0.5) * MEDAL_STEP, 0.02, 0.0
			)
	_stairs.visible = path
	_stairs.position = Vector3(0.0, 0.02, 0.0)
	_note.visible = happy
	_apply_alpha()


func key() -> String:
	return _key


## 吹き出しに出している、足りない能力。
func needs() -> Array[RuleAction.Kind]:
	return parse_needs(_key)


## 吹き出しに階段（道が要る）を出しているか。
func shows_path() -> bool:
	return _key == KEY_PATH


## 吹き出しが見えているか（♪ が消えた後・何も無いときは false）。
func is_bubble_shown() -> bool:
	if _key == KEY_NONE:
		return false
	return _key != KEY_HAPPY or _happy_time < HAPPY_HOLD + HAPPY_FADE


## 足りない能力と「道が要る」から鍵を作る。
static func key_for(kinds: Array, path: bool) -> String:
	if not kinds.is_empty():
		var parts: PackedStringArray = []
		for kind: int in kinds.slice(0, MAX_MEDALS):
			parts.append(str(kind))
		return NEED_PREFIX + ",".join(parts)
	return KEY_PATH if path else KEY_NONE


## 鍵から足りない能力を読む（通信から来た値なので、知らない数は捨てる）。
static func parse_needs(key: String) -> Array[RuleAction.Kind]:
	var kinds: Array[RuleAction.Kind] = []
	if not key.begins_with(NEED_PREFIX):
		return kinds
	for part in key.substr(NEED_PREFIX.length()).split(",", false):
		if not part.is_valid_int():
			continue
		var value := part.to_int()
		if value >= 0 and value < RuleAction.Kind.size() and kinds.size() < MAX_MEDALS:
			kinds.append(value as RuleAction.Kind)
	return kinds


## 知らない鍵は「出さない」にする。
static func normalize(key: String) -> String:
	if key == KEY_HAPPY or key == KEY_PATH:
		return key
	var kinds := parse_needs(key)
	return key_for(kinds, false) if not kinds.is_empty() else KEY_NONE


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


func _apply_alpha() -> void:
	var alpha := _distance_alpha
	if _key == KEY_HAPPY:
		alpha *= clampf(1.0 - (_happy_time - HAPPY_HOLD) / HAPPY_FADE, 0.0, 1.0)
	_bubble.visible = alpha > 0.01 and _key != KEY_NONE
	for sprite: Sprite3D in [_back, _stairs] + _medals:
		sprite.modulate.a = alpha
	_note.modulate.a = alpha
	_note.outline_modulate.a = 0.95 * alpha


func _sprite(texture: Texture2D) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = texture
	sprite.pixel_size = ICON_PIXEL
	sprite.no_depth_test = true
	sprite.render_priority = 1
	sprite.visible = false
	_bubble.add_child(sprite)
	return sprite


## 吹き出しの絵（メダル count 個ぶんの幅。下の真ん中にしっぽ）。クリーム色の地にこげ茶のふち。
static func bubble_texture(count: int) -> ImageTexture:
	count = clampi(count, 1, MAX_MEDALS)
	if _backs.has(count):
		return _backs[count]
	var step := int(MEDAL_STEP / ICON_PIXEL)
	var width := 72 + count * step
	var body := 160
	var height := body + 30
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var fill := Color(UiTheme.CREAM, 0.96)
	var ink := UiTheme.INK
	var line := 6.0
	var radius := 44.0
	var half := Vector2(width * 0.5 - 3.0, body * 0.5 - 3.0)
	var center := Vector2(width * 0.5, body * 0.5)
	var tail_top := float(body) - line - 2.0
	for y in height:
		for x in width:
			var p := Vector2(x + 0.5, y + 0.5)
			var q := (p - center).abs() - half + Vector2(radius, radius)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
			d -= radius
			var color := Color(0, 0, 0, 0)
			if d <= 0.0:
				color = fill if d < -line else ink
			# しっぽ（下向きの三角）。ふちの内側は地の色で、本体の下のふちとつなげる
			var dy := p.y - tail_top
			var reach := 26.0 * (1.0 - dy / (height - 2.0 - tail_top))
			if dy >= 0.0 and absf(p.x - center.x) <= reach:
				var inner := reach - line * 1.4
				color = fill if absf(p.x - center.x) <= inner and p.y < height - line else ink
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_backs[count] = texture
	return texture


## 「道が要る」の絵: 3 段の小さな階段（どの能力でも進めない＝段や足場を作ってほしい）。
static func stairs_texture() -> ImageTexture:
	if _stairs_texture != null:
		return _stairs_texture
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var ink := UiTheme.INK
	var stone := Color("#b9a68c")
	for i in 3:
		var rect := Rect2i(18 + i * 31, 104 - (i + 1) * 28, 31, (i + 1) * 28)
		image.fill_rect(rect, ink)
		image.fill_rect(rect.grow(-5), stone)
	_stairs_texture = ImageTexture.create_from_image(image)
	return _stairs_texture
