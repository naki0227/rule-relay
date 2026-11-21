class_name WishPointer
extends Control
## 願いの行き先（巣）が画面の外にあるとき、画面の縁に向きの矢印を出す（2026-11-21 本人
## 「どうぶつがなにをもとめてるのかがわかりにくい」）。生き物の近くにいるか狙っているときだけ出す
## （いつも出すと画面がにぎやかになる）。行き先が画面の中に見えていれば出さない（光の柱が見える）。

const MARGIN: float = 56.0
const SIZE: float = 18.0
const FILL := Color(1.0, 0.86, 0.55)

## 矢印の向き（画面の右が 0、時計回り）。
var angle: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## target（世界の座標）を cam から見て、画面の外なら縁に矢印を出す。target が無ければ隠す。
func point_to(cam: Camera3D, target: Variant) -> void:
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
	var scale_to_edge := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	position = center + dir * scale_to_edge - Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE) * 2.0
	visible = true
	queue_redraw()


func _draw() -> void:
	var c := Vector2(SIZE, SIZE)
	var fwd := Vector2.from_angle(angle)
	var side := fwd.orthogonal()
	var points := PackedVector2Array(
		[
			c + fwd * SIZE,
			c - fwd * SIZE * 0.6 + side * SIZE * 0.7,
			c - fwd * SIZE * 0.6 - side * SIZE * 0.7
		]
	)
	draw_colored_polygon(points, FILL)
	draw_polyline(points + PackedVector2Array([points[0]]), UiTheme.INK, 2.0, true)
