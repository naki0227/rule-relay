class_name WishPointer
extends Control
## 願いの行き先（巣）が画面の外にあるとき、画面の縁に向きの矢印を出す（2026-11-21 本人
## 「どうぶつがなにをもとめてるのかがわかりにくい」）。生き物の近くにいるか狙っているときだけ出す
## （いつも出すと画面がにぎやかになる）。行き先が画面の中に見えていれば出さない（光の柱が見える）。
## 2026-11-21 本人「巣がどこかもわかりにくい」: 矢印だけでなく、丸い札に巣の絵（その生き物の巣の柱と同じ色）を
## 出し、札の外側に向きの矢じりを付ける。

const MARGIN: float = 64.0
## 札の半径（px）。
const SIZE: float = 26.0
const FILL := Color(1.0, 0.86, 0.55)

## 矢印の向き（画面の右が 0、時計回り）。
var angle: float = 0.0
## 巣の色（巣の光の柱と同じ）。
var tint: Color = FILL
var _icon: Texture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## target（世界の座標）を cam から見て、画面の外なら縁に矢印を出す。target が無ければ隠す。
## nest_tint は巣の色（巣の絵と矢じりの色）。
func point_to(cam: Camera3D, target: Variant, nest_tint: Color = FILL) -> void:
	if nest_tint.a > 0.0 and (_icon == null or not nest_tint.is_equal_approx(tint)):
		tint = nest_tint
		_icon = CreatureWishView.nest_texture(tint)
	if cam == null or typeof(target) != TYPE_VECTOR3:
		visible = false
		return
	var at := target as Vector3
	var rect := get_viewport_rect()
	var center := rect.size * 0.5
	var behind := cam.is_position_behind(at)
	var screen := cam.unproject_position(at)
	if not behind and rect.grow(-MARGIN).has_point(screen):
		visible = false
		return
	var dir := screen - center
	if behind:
		dir = -dir  # 後ろにあるときは、映った位置の反対側
	if dir.length() < 1.0:
		dir = Vector2.DOWN
	angle = dir.angle()
	# 縁（MARGIN の内側）の、中心からその向きへの交点に置く
	var half := center - Vector2(MARGIN, MARGIN)
	var reach := SIZE * 1.6
	var scale_to_edge := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	position = center + dir * scale_to_edge - Vector2(reach, reach)
	size = Vector2(reach, reach) * 2.0
	visible = true
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var fwd := Vector2.from_angle(angle)
	var side := fwd.orthogonal()
	# 向きの矢じり（札の外側）
	var tip := PackedVector2Array(
		[
			c + fwd * SIZE * 1.55,
			c + fwd * SIZE * 0.9 + side * SIZE * 0.45,
			c + fwd * SIZE * 0.9 - side * SIZE * 0.45
		]
	)
	draw_colored_polygon(tip, tint)
	draw_polyline(tip + PackedVector2Array([tip[0]]), UiTheme.INK, 2.0, true)
	# 丸い札に巣の絵
	draw_circle(c, SIZE, Color(UiTheme.CREAM, 0.95))
	draw_arc(c, SIZE, 0.0, TAU, 40, tint, 3.0, true)
	if _icon != null:
		var icon := SIZE * 1.5
		draw_texture_rect(_icon, Rect2(c - Vector2(icon, icon) * 0.5, Vector2(icon, icon)), false)
