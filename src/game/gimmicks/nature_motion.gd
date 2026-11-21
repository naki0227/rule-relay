class_name NatureMotion
extends RefCounted
## 自分のアバターが受ける風・氷・水と、重い・浮く・泳ぐの効き方（docs/adr/0015）。
## PlayerAvatar._physics_process が、歩く速さと重力を決めた後・跳ぶ前に呼ぶ。自分の画面で動かし、
## 位置はいつもどおりホストへ送る（ホスト権威の位置同期のまま）。
##
## - 風: 範囲の中で、風の速さを足す（空中でも）。重い人は流されない。
## - 氷: 床が氷なら、いまの勢いを望む速さへ少しずつしか寄せない（止まれない・曲がれない）。
##   氷から跳んだ・落ちたときも勢いは残り、氷でない床に着くと消える。
## - 水（底なし）: 浮く人・泳げる人は水面に浮かぶ。泳げる人だけが自分で進め、流れには誰でも運ばれる。
##   泳げない人・重い人は沈む。沈むと島から落ちたのと同じ（死亡→観戦の流れをそのまま使う）。
## - 浮く: 空中で、落ちる速さに上限（×n で n 倍ゆっくり）。


static func apply(p: PlayerAvatar, delta: float) -> void:
	var field := p.nature
	var feet := p.global_position
	var weight := BodyTraits.weight(p.ledger, p.player_id)
	var water := field.water_at(feet)
	p.afloat = false
	if water != null:
		p.slide = Vector2.ZERO
		_in_water(p, water, weight, field.wind_at(feet))
		return
	_on_ice(p, field, delta)
	if weight <= 0:
		var wind := field.wind_at(feet)
		p.velocity.x += wind.x
		p.velocity.z += wind.z
	if not p.is_on_floor():
		p.velocity.y = maxf(p.velocity.y, -NatureTuning.fall_limit(-weight))


## 氷の上: 望む速さ（いまの velocity）へ、勢いを少しずつ寄せる。壁で止まった分は勢いからも消す。
static func _on_ice(p: PlayerAvatar, field: NatureField, delta: float) -> void:
	var wanted := Vector2(p.velocity.x, p.velocity.z)
	if p.is_on_floor() and field.is_ice_under(p.global_position):
		var real := p.get_real_velocity()
		if p.slide == Vector2.ZERO:
			p.slide = Vector2(real.x, real.z)
		if absf(real.x) < absf(p.slide.x) - 0.05:
			p.slide.x = real.x
		if absf(real.z) < absf(p.slide.y) - 0.05:
			p.slide.y = real.z
		p.slide = p.slide.move_toward(wanted, NatureTuning.ICE_GRIP * delta)
	elif p.is_on_floor():
		p.slide = Vector2.ZERO
		return
	elif p.slide == Vector2.ZERO:
		return
	p.velocity.x = p.slide.x
	p.velocity.z = p.slide.y


## 水の中: 浮くか沈むかを決め、泳ぐ・流れ・風を足す。
static func _in_water(
	p: PlayerAvatar, water: NatureLayout.WaterSpec, weight: int, wind: Vector3
) -> void:
	var swim := BodyTraits.swim_level(p.ledger, p.player_id)
	var flow := water.flow()
	var buoyant := weight < 0 or (weight == 0 and swim > 0)
	if not buoyant:
		# 沈む: 自分では進めず、流れにだけ運ばれる
		p.velocity = Vector3(flow.x, -NatureTuning.SINK_SPEED, flow.z)
		return
	p.afloat = true
	var hold := water.surface_y() - NatureTuning.AFLOAT_DEPTH
	var feet_y := p.global_position.y
	p.velocity.y = maxf(p.velocity.y, -NatureTuning.WATER_DRAG_FALL)
	if feet_y < hold:
		var rise := minf((hold - feet_y) * 8.0, NatureTuning.SURFACE_PUSH)
		p.velocity.y = maxf(p.velocity.y, rise)
	var own := Vector3.ZERO
	if swim > 0:
		var wanted := Vector3(p.velocity.x, 0.0, p.velocity.z) / Tuning.PLAYER_SPEED
		own = wanted.limit_length(1.0) * NatureTuning.SWIM_SPEED * Tuning.stack_factor(swim)
	p.velocity.x = own.x + flow.x + wind.x
	p.velocity.z = own.z + flow.z + wind.z
