class_name WorldJuice
extends Node3D
## 手応えの効果（docs/adr/0022-visual-direction-and-quality.md）。見た目だけで、ルールにも物理にも触れない。
## 合図は島の「音の合図」（GameWorld.sound_requested の場所つきの音）と、クリア（goal_reached）。
## 参加者の画面にもホストから同じ音の合図が届く（NetWorld）ので、みんなの画面に同じ効果が出る。
##
## | 合図 | 効果 |
## |---|---|
## | 能力を渡した（lend@n / lend_range@n） | 受け取った物が「むにっ」とつぶれて戻る＋はちみつ色の輪＋小さな光の粒 |
## | 取り戻した（recall） | 小さく弾む＋生成りの輪 |
## | ブロックの着地（block_land） | つぶれて戻る＋足もとの土ぼこり |
## | 自分・仲間の着地（player_land）／跳ぶ（player_jump）／ダッシュ（dash） | つぶれ・伸び＋足もとの土ぼこり |
## | クリア（goal_reached） | 紙吹雪（ルールの赤は使わない） |
##
## つぶれて戻る動きは画質の低でも出す（手応えの合図なので）。粒は低では出さない（bursts）。
## 当たり判定の形は変えない: ブロックは見た目の Model、プレイヤーは Visual の大きさだけを動かす。

## 同時に出ている粒の上限（たくさん着地しても重くならない）。
const MAX_BURSTS := 16
## 合図の場所から、つぶす相手を探す距離。
const PICK_RADIUS := 0.95
const HONEY := Color("#ffd772")
const CREAM := Color("#fff4dc")
const DUST := Color("#e9dcc4")
## 紙吹雪の色（生成り・夕日の淡い色・若葉・空色・藤。禁止の赤は使わない）。
const CONFETTI: Array[Color] = [
	Color("#fff3d6"), Color("#ffd18a"), Color("#a8d98a"), Color("#9cc9f0"), Color("#d2b8ef")
]

var world: GameWorld
## 粒を出すか（画質の中・高）。
var bursts: bool = true

var _active: int = 0
var _squash: Dictionary[Node3D, Tween] = {}


## 粒の動き方（寿命・速さ・向き・広がり（度）・重力）。
class Motion:
	var life: float
	var speed: float
	var direction: Vector3
	var spread: float
	var gravity: Vector3

	func _init(
		p_life: float, p_speed: float, p_direction: Vector3, p_spread: float, p_gravity: Vector3
	) -> void:
		life = p_life
		speed = p_speed
		direction = p_direction
		spread = p_spread
		gravity = p_gravity


func _ready() -> void:
	if world == null:
		return
	world.sound_requested.connect(_on_sound)
	world.goal_reached.connect(_on_goal)


## 効果の合図（テストや道具から直接呼んでもよい）。
func _on_sound(event: StringName, at: Vector3, positional: bool) -> void:
	if not positional:
		return
	var name := String(event).get_slice("@", 0)
	match name:
		"lend", "lend_range":
			var target := _nearest_body(at)
			_squash_node(target, Vector3(1.18, 0.78, 1.18), 0.34)
			ring(at - Vector3(0.0, 0.45, 0.0), HONEY, 1.0)
			sparkle(at + Vector3(0.0, 0.4, 0.0), HONEY, 18)
		"recall":
			_squash_node(_nearest_body(at), Vector3(0.9, 1.14, 0.9), 0.26)
			ring(at, CREAM, 0.6)
		"block_land":
			_squash_node(_nearest_block(at), Vector3(1.12, 0.84, 1.12), 0.28)
			dust(at - Vector3(0.0, RuleBlock.SIZE * 0.5, 0.0), 10, 0.9)
		"player_land":
			_squash_node(_nearest_avatar(at), Vector3(1.16, 0.8, 1.16), 0.26)
			dust(at, 8, 0.7)
		"player_jump":
			_squash_node(_nearest_avatar(at), Vector3(0.88, 1.16, 0.88), 0.22)
			dust(at, 5, 0.45)
		"dash":
			dust(at, 6, 0.6)


func _on_goal() -> void:
	var center := Vector3.ZERO
	if world.player != null:
		center = world.player.global_position
	confetti(center + Vector3(0.0, 2.6, 0.0))


## 小さな光の粒が上へ散る（渡したとき）。
func sparkle(at: Vector3, tint: Color, count: int) -> void:
	_burst(at, count, tint, 0.2, Motion.new(0.55, 2.4, Vector3.UP, 70.0, Vector3(0, -2.5, 0)))


## 足もとの土ぼこり: 横へ広がって薄れる。
func dust(at: Vector3, count: int, spread: float) -> void:
	var motion := Motion.new(0.45, spread * 1.6, Vector3(0.0, 0.25, 0.0), 180.0, Vector3(0, 0.6, 0))
	_burst(at + Vector3(0.0, 0.08, 0.0), count, DUST, 0.16, motion)


## 紙吹雪（クリア）。
func confetti(at: Vector3) -> void:
	if not bursts or not is_inside_tree():
		return
	for i in CONFETTI.size():
		var motion := Motion.new(2.4, 5.5, Vector3.UP, 55.0, Vector3(0, -2.6, 0))
		_burst(at, 14, CONFETTI[i], 0.14, motion, true)


## 床に広がって消える輪（MedalPuff と同じ形）。
func ring(at: Vector3, tint: Color, size: float) -> void:
	if not bursts or not is_inside_tree():
		return
	# MedalPuff は 0.55 m まで広がるので、入れ物の大きさで広がりを変える
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * size * 1.8
	add_child(holder)
	holder.global_position = at
	var puff := MedalPuff.new()
	puff.tint = tint
	puff.tree_exited.connect(holder.queue_free)
	holder.add_child(puff)


func _burst(
	at: Vector3, count: int, tint: Color, size: float, motion: Motion, paper: bool = false
) -> void:
	var life := motion.life
	var speed := motion.speed
	var direction := motion.direction
	var spread := motion.spread
	var gravity := motion.gravity
	if not bursts or not is_inside_tree() or _active >= MAX_BURSTS:
		return
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.amount = count
	particles.lifetime = life
	particles.local_coords = true  # 置いた場所から動かないので、粒はこの位置を基準にする
	particles.direction = direction
	particles.spread = spread
	particles.initial_velocity_min = speed * 0.45
	particles.initial_velocity_max = speed
	particles.gravity = gravity
	particles.damping_min = 1.5
	particles.damping_max = 3.0
	particles.angle_min = 0.0
	particles.angle_max = 360.0
	particles.angular_velocity_min = -240.0
	particles.angular_velocity_max = 240.0
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.0
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(0.7, 0.8))
	shrink.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = shrink
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size * 0.55) if paper else Vector2(size, size)
	if paper:
		# 紙吹雪は四角い紙。くるくる回って、裏も見える
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.albedo_color = tint
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		quad.material = material
	else:
		quad.material = WorldLook.soft_dot_material(tint, false)
	particles.mesh = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	particles.global_position = at
	particles.emitting = true
	_active += 1
	particles.finished.connect(
		func() -> void:
			_active -= 1
			particles.queue_free()
	)


## 見た目だけをつぶして、弾むように戻す（下の面を床に付けたまま）。
func _squash_node(node: Node3D, squash: Vector3, seconds: float) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	if _squash.has(node) and _squash[node] != null and _squash[node].is_valid():
		_squash[node].kill()
	# ブロックの見た目は中心が原点なので、下の面を床に付けたままにするには位置もずらす。
	# プレイヤー・生き物の見た目は足もとが原点なので、大きさだけでよい
	var anchor := -RuleBlock.SIZE * 0.5 if node.get_parent() is RuleBlock else 0.0
	if not node.has_meta(&"juice_base_y"):
		node.set_meta(&"juice_base_y", node.position.y)
	var base_y := float(node.get_meta(&"juice_base_y"))
	node.scale = squash
	node.position.y = base_y + anchor * squash.y - anchor
	var tween := node.create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector3.ONE, seconds * 2.2)
	tween.parallel().tween_property(node, "position:y", base_y, seconds * 2.2)
	_squash[node] = tween
	tween.finished.connect(func() -> void: _squash.erase(node))


## at にいちばん近い物（ブロック・生き物・プレイヤー）の見た目。渡す・取り戻すの相手（仲間にも渡せる）。
## 足もとの合図でも、立っているブロックではなくその人を選ぶ（いちばん近い物を選ぶので）。
func _nearest_body(at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := PICK_RADIUS * 1.6
	var candidates: Array = []
	for id in world.blocks:
		candidates.append([world.blocks[id], "Model"])
	for id in world.creatures:
		candidates.append([world.creatures[id], "Body/Model"])
	for avatar: Node3D in _avatars():
		candidates.append([avatar, "Visual"])
	for pair: Array in candidates:
		var body := pair[0] as Node3D
		if body == null or not is_instance_valid(body):
			continue
		var d := body.global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = body.get_node_or_null(String(pair[1])) as Node3D
	return best


## at にいちばん近いブロックの見た目（Model）。
func _nearest_block(at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := PICK_RADIUS
	for id in world.blocks:
		var block: RuleBlock = world.blocks[id]
		var d := block.global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = block.get_node_or_null("Model") as Node3D
	return best


## at にいちばん近いプレイヤー（自分・仲間）の見た目（Visual）。
func _nearest_avatar(at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := PICK_RADIUS
	for avatar: Node3D in _avatars():
		if avatar == null or not is_instance_valid(avatar):
			continue
		var d := avatar.global_position.distance_to(at)
		if d < best_d:
			best_d = d
			best = avatar.get_node_or_null("Visual") as Node3D
	return best


func _avatars() -> Array[Node3D]:
	var list: Array[Node3D] = []
	for id in world.avatars:
		list.append(world.avatars[id])
	if world.player != null and not list.has(world.player):
		list.append(world.player)
	return list
