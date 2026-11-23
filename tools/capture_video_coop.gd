extends RefCounted
## capture_video.gd の協力の場面で使う 2P（参加者）。同じプロセスの中に、専用の SceneMultiplayer と
## own_world_3d の SubViewport（物理の世界）を持つ参加者を作り、ENet（127.0.0.1）でホストの部屋へ入る
## （tests/integration/net_party.gd と同じつなぎ方）。2P の画面は、1P の画面の左上に小さく重ねる。
## 2P の操作は、移動の入力と向き（move_intent / view_yaw）と渡す操作だけ（瞬間移動しない）。

const JUMP := RuleAction.Kind.JUMP
const FPS := 30.0
const INSET_SCALE := 0.3
const INSET_MARGIN := 16

var tree: SceneTree
var port: int
## 1 フレーム進める関数（capture_video.gd の _frame。1P の視点と、この 2P の step を進める）。
var frame: Callable
var director: PartyDirector
var net: NetWorld
var side: Node
var view: SubViewport
var target: Vector3 = Vector3.INF
var host_view_yaw: float = 0.0

var _frame_rect: ColorRect
var _stuck: int = 0


func _init(p_tree: SceneTree, p_port: int, p_frame: Callable) -> void:
	frame = p_frame
	tree = p_tree
	port = p_port
	side = Node.new()
	side.name = "Side2P"
	tree.root.add_child(side)
	tree.set_multiplayer(SceneMultiplayer.new(), side.get_path())
	var size := tree.root.get_visible_rect().size
	# RPC はマルチプレイの根からの相対パスで届くので、ホスト（/root/GameRoot/Director・Net・Migration）と
	# 同じ並びにする。物理の世界を分けるため、"GameRoot" は own_world_3d の SubViewport にする
	view = SubViewport.new()
	view.name = "GameRoot"
	view.own_world_3d = true
	view.size = Vector2i(size * INSET_SCALE)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	side.add_child(view)
	director = PartyDirector.new()
	director.profile = "zz_capture_video_2p"
	ProgressStore.new().delete(director.profile)
	view.add_child(director)
	net = NetWorld.new()
	view.add_child(net)
	# ホスト移譲の係（ホストが配る状態を受け取るだけ。ホストが落ちても引き継がないよう watch() は呼ばない）
	var migration := HostMigration.new()
	migration.director = director
	migration.net = net
	migration.port = port
	migration.session_key = GameRoot.session_key(director.profile)
	view.add_child(migration)
	# 左上に 2P の画面（白い縁つき）
	var layer := CanvasLayer.new()
	layer.layer = 50
	side.add_child(layer)
	_frame_rect = ColorRect.new()
	_frame_rect.color = Color(1.0, 0.97, 0.92)
	_frame_rect.position = Vector2(INSET_MARGIN - 4, INSET_MARGIN - 4)
	_frame_rect.size = Vector2(view.size) + Vector2(8, 8)
	layer.add_child(_frame_rect)
	var picture := TextureRect.new()
	picture.texture = view.get_texture()
	picture.position = Vector2(INSET_MARGIN, INSET_MARGIN)
	picture.size = Vector2(view.size)
	layer.add_child(picture)
	var label := Label.new()
	label.text = "2P"
	label.position = Vector2(INSET_MARGIN + 8, INSET_MARGIN + 4)
	label.add_theme_font_size_override(&"font_size", 22)
	label.add_theme_color_override(&"font_color", Color(1, 1, 1))
	label.add_theme_color_override(&"font_outline_color", Color(0.3, 0.23, 0.17))
	label.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(label)


func world() -> StageWorld:
	return director.world


## 部屋に入り、2P のプレイヤー ID（2）がもらえて、ホストと同じ場所にいるまで待つ。
func join() -> void:
	director.prepare_client()
	net.world = director.world
	director.attach_net(net)
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", port)
	net.start_client(peer, GameRoot.session_key(director.profile))
	for i in 600:
		if director.world != null and director.world.player.player_id == 2:
			break
		await tree.physics_frame
	for i in 120:
		await tree.physics_frame


func wait_in_stage(stage_id: String) -> void:
	for i in 900:
		if director.stage_id == stage_id and director.world.player.global_position.y > -1.0:
			break
		await tree.physics_frame
	for i in 30:
		await tree.physics_frame


## 1 フレームごとに呼ぶ: 目的地があれば歩き、2P の視点を向きに寄せる。
func step() -> void:
	var w := world()
	if w == null:
		return
	var me := w.player
	if target != Vector3.INF:
		var flat := Vector3(target.x - me.global_position.x, 0.0, target.z - me.global_position.z)
		if flat.length() <= 0.35 and absf(me.global_position.y - target.y) < 0.7:
			me.move_intent = Vector2.ZERO
			target = Vector3.INF
		else:
			me.view_yaw = lerp_angle(me.view_yaw, atan2(-flat.x, -flat.z), 0.3)
			me.move_intent = Vector2(0.0, 1.0)
			# 段差で止まったら跳ぶ（1P の歩き方と同じ）
			var moving := Vector2(me.velocity.x, me.velocity.z).length() > 0.5
			_stuck = 0 if moving else _stuck + 1
			if _stuck > 4 and me.is_on_floor():
				w.press_action(JUMP)
				_stuck = 0
	w.camera_rig.yaw = lerp_angle(w.camera_rig.yaw, me.view_yaw, 0.15)
	w.camera_rig.pitch = lerpf(w.camera_rig.pitch, deg_to_rad(-16.0), 0.15)


func walk_to(at: Vector3) -> void:
	target = at


func until_arrived() -> void:
	for i in int(10.0 * FPS):
		if target == Vector3.INF:
			break
		await frame.call()


func _face(at: Vector3) -> void:
	var me := world().player
	var flat := at - me.global_position
	me.view_yaw = atan2(-flat.x, -flat.z)


## 自分の位置がホストの画面に届くまで待つ（届くかはホストの画面の位置で決まる）。
func _settle(host_world: StageWorld) -> void:
	for i in 300:
		var here := world().player.global_position
		var there := host_world.avatar_of(2)
		if there != null and there.global_position.distance_to(here) < 0.1:
			return
		await frame.call()


## 2P のジャンプを 1P へ渡す（1P の手元はジャンプ ×2 になる）。
func give_jumps_to_host() -> void:
	var w := world()
	var host_world := _host_world()
	_face(w.avatars[1].global_position)
	for i in int(0.8 * FPS):
		await frame.call()
	await _settle(host_world)
	w.select_slot(_slot_of(JUMP))
	var before := host_world.ledger.ability_count(JUMP, 1)
	print(
		(
			"DBG 2P at %s, host sees 2P at %s, 1P at %s, slot %d"
			% [
				w.player.global_position,
				host_world.avatar_of(2).global_position,
				w.avatars[1].global_position,
				_slot_of(JUMP)
			]
		)
	)
	var result := w.lend_to(w.avatars[1], false)
	if result != RuleLedger.LendResult.OK:
		push_warning("capture_video: 2P could not lend (%s)" % result)
	for i in int(3.0 * FPS):
		if host_world.ledger.ability_count(JUMP, 1) > before:
			break
		await frame.call()


## もらったジャンプ ×2 で岩棚へ跳び上がり、ゴールの窪みへ歩いて入る。
func jump_up_and_into_goal() -> void:
	var w := world()
	_face(Vector3(-1.5, 2.0, -8.0))
	for i in int(0.6 * FPS):
		await frame.call()
	w.press_action(JUMP)
	var onto := Vector3(-1.5, 2.0, -6.4)
	for i in int(3.0 * FPS):
		var me := w.player
		if me.global_position.y > onto.y - 0.2 and me.global_position.z < onto.z + 0.3:
			break
		me.move_intent = Vector2(0.0, 1.0) if me.global_position.y > onto.y - 0.1 else Vector2.ZERO
		await frame.call()
	w.player.move_intent = Vector2.ZERO
	walk_to(Vector3(-0.5, 1.1, -8.6))
	await until_arrived()


func _slot_of(action: RuleAction.Kind) -> int:
	var w := world()
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, w.acting_id())
		if v != null and w.ledger.token(v.token_id).action == action:
			return slot
	return 0


func _host_world() -> StageWorld:
	for child in tree.root.get_children():
		var game := child as GameRoot
		if game != null:
			return game.director.world
	return null


func close() -> void:
	net.close()
	tree.set_multiplayer(null, side.get_path())
	ProgressStore.new().delete(director.profile)
	var key := "user://session/%s.key" % director.profile
	if FileAccess.file_exists(key):
		DirAccess.remove_absolute(key)
	side.queue_free()
