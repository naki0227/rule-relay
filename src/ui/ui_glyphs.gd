class_name UiGlyphs
extends RefCounted
## 文字の代わりに使う小さな記号（線の太さは UiTheme.LINE にそろえる）。
## 既存作品の記号は使わず、このゲームの言葉（貸す・触る・投げる・1回・反復・音）から描く。


## 発動方式: 単発 = 点と「1」の短い棒、繰り返し = 回る矢印、信号 = 音の波。
static func draw_mode(
	ci: CanvasItem, center: Vector2, size: float, mode: TriggerMode.Kind, color: Color
) -> void:
	var r := size * 0.5
	var w := maxf(2.0, size * 0.09)
	match mode:
		TriggerMode.Kind.SINGLE_SHOT:
			ci.draw_arc(center, r * 0.82, 0, TAU, 32, color, w, true)
			ci.draw_line(
				center + Vector2(0, -r * 0.42), center + Vector2(0, r * 0.42), color, w, true
			)
			ci.draw_line(
				center + Vector2(0, -r * 0.42),
				center + Vector2(-r * 0.22, -r * 0.2),
				color,
				w,
				true
			)
		TriggerMode.Kind.REPEAT:
			# 2本の弧が追いかけ合う輪（くり返し）
			for half in 2:
				var start := -PI * 0.15 + PI * half
				ci.draw_arc(center, r * 0.68, start, start + PI * 0.7, 16, color, w, true)
				var tip := center + Vector2.from_angle(start + PI * 0.7) * r * 0.68
				var tangent := Vector2.from_angle(start + PI * 0.7 + PI * 0.5)
				var normal := tangent.orthogonal()
				(
					ci
					. draw_colored_polygon(
						PackedVector2Array(
							[
								tip + tangent * r * 0.32,
								tip + normal * r * 0.24,
								tip - normal * r * 0.24,
							]
						),
						color
					)
				)
		TriggerMode.Kind.SIGNAL:
			ci.draw_circle(center + Vector2(-r * 0.55, 0), r * 0.16, color)
			for k in 3:
				var rr := r * (0.38 + 0.3 * k)
				ci.draw_arc(
					center + Vector2(-r * 0.55, 0), rr, -PI * 0.3, PI * 0.3, 16, color, w, true
				)


## 届き方: 触る = 指先（丸い札に点）、投げる = 放物線と矢印。
static func draw_reach(
	ci: CanvasItem, center: Vector2, size: float, throw: bool, color: Color
) -> void:
	var r := size * 0.5
	var w := maxf(2.0, size * 0.09)
	if not throw:
		# 触る: 手のひらで押す（丸い掌と4本の短い指）
		ci.draw_circle(center + Vector2(0, r * 0.28), r * 0.42, color)
		for k in 4:
			var x := lerpf(-r * 0.42, r * 0.42, float(k) / 3.0)
			var top := center + Vector2(x, -r * (0.55 if k in [1, 2] else 0.38))
			ci.draw_line(top, center + Vector2(x, r * 0.1), color, w * 1.6, true)
			ci.draw_circle(top, w * 0.8, color)
	else:
		var points := PackedVector2Array()
		for k in 9:
			var t := float(k) / 8.0
			points.append(
				center + Vector2(lerpf(-r * 0.8, r * 0.7, t), r * 0.5 - sin(t * PI) * r * 0.9)
			)
		ci.draw_polyline(points, color, w, true)
		var tip := points[-1]
		ci.draw_colored_polygon(
			PackedVector2Array(
				[
					tip + Vector2(r * 0.18, r * 0.12),
					tip + Vector2(-r * 0.24, r * 0.06),
					tip + Vector2(r * 0.0, -r * 0.3)
				]
			),
			color
		)


## 貸出中: 器から外へ出ていく小さな矢印。
static func draw_lent(ci: CanvasItem, center: Vector2, size: float, color: Color) -> void:
	var r := size * 0.5
	var w := maxf(2.0, size * 0.12)
	ci.draw_line(
		center + Vector2(-r * 0.45, r * 0.45), center + Vector2(r * 0.4, -r * 0.4), color, w, true
	)
	ci.draw_line(
		center + Vector2(r * 0.4, -r * 0.4), center + Vector2(-r * 0.05, -r * 0.42), color, w, true
	)
	ci.draw_line(
		center + Vector2(r * 0.4, -r * 0.4), center + Vector2(r * 0.42, r * 0.05), color, w, true
	)


## 禁止の印: 赤い輪と斜線。
static func draw_ban(ci: CanvasItem, center: Vector2, size: float) -> void:
	var r := size * 0.5
	ci.draw_circle(center, r, Color.WHITE)
	ci.draw_arc(center, r * 0.78, 0, TAU, 32, UiTheme.BAN, maxf(2.0, size * 0.14), true)
	var d := Vector2.from_angle(-PI * 0.25) * r * 0.62
	ci.draw_line(center - d, center + d, UiTheme.BAN, maxf(2.0, size * 0.14), true)
