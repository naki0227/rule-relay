class_name NetWorld
extends Node
## GameWorld をオンライン協力につなぐ（ホスト権威。docs/adr/0006）。
## - ホスト: 世界（ブロック・生き物・鐘・玉・全員のアバターの位置）を 1 秒に 20 回、全員へ配る。
##   参加者の操作（渡す・F・単発のキー）は、その人のアバターで代わりに実行する（WorldParty.act_as）。
##   台帳が変わったら、そのフレームの終わりに1回だけ全員へ配る（NetSession.publish）。
## - 参加者: 自分のアバターだけを自分の画面で動かし、その位置をホストへ送る。ブロックなどは
##   受け取った位置へ動かすだけ。操作はホストへの依頼になる（GameWorld.replica）。
## 子に NetSession を持つ。RPC のパスを両側でそろえるため、ノード名は固定（"Net"／"Session"）。

## ホスト: 参加者が入ったとき（はじめの持ち物を配る・ステージの準備に使う）。
signal player_joined(player_id: int)

const SEND_PERIOD: float = 1.0 / 20.0
## 仲間が現れる位置のずらし幅（出現地点からの横のずれ）。
const SPAWN_SPACING: float = 1.2

var world: GameWorld
var session: NetSession
## ホスト: 新しい参加者に配るはじめの持ち物 func(player_id)。空なら配らない。
var give_starting_items: Callable = Callable()
## 落ちた自分のアバターを出現地点へ戻すか（PartyDirector がいるときは死亡として扱うので false）。
var manage_falls: bool = true

var _send_timer: float = 0.0
var _ledger_dirty: bool = false
var _ball_ghosts: Array[MeshInstance3D] = []
## 投げたメダルの見た目（番号 → MedalVisual。MedalThrow.apply_frame）。
var _medal_ghosts: Dictionary = {}


func _ready() -> void:
	name = "Net"
	session = NetSession.new()
	session.name = "Session"
	add_child(session)


func is_host() -> bool:
	return session.is_host()


## 通信がつながっているか（切れた・閉じた直後は false。送ると誤りになるので送らない）。
func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return (
		peer != null
		and not peer is OfflineMultiplayerPeer
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	)


## 部屋を作る。peer は ENet なら create_server 済みのもの。
func start_host(peer: MultiplayerPeer, session_key: String) -> void:
	session.host(peer, world.ledger, session_key)
	_listen_as_host()
	bind(world)


## ホスト移譲: 参加者だった自分がホストになる（世界は PartyDirector が作り直してから bind する）。
func become_host(
	peer: MultiplayerPeer, session_key: String, player_id: int, hashes: Dictionary, generation: int
) -> void:
	session.host(peer, world.ledger, session_key, player_id, hashes, generation + 1000)
	_listen_as_host()


func _listen_as_host() -> void:
	if not session.player_joined.is_connected(_on_player_joined):
		session.player_joined.connect(_on_player_joined)


## 部屋に入る。peer は ENet なら create_client 済みのもの。
func start_client(peer: MultiplayerPeer, session_key: String) -> void:
	session.joined.connect(_on_joined)
	session.state_changed.connect(func(_g: int) -> void: sync_avatars())
	bind(world)
	session.join(peer, session_key, world.ledger)


## 世界（島・ステージ）を差し替えたときに、通信をその世界へつなぎ直す。
func bind(new_world: GameWorld) -> void:
	world = new_world
	world.networked = true
	session.ledger = world.ledger
	if is_host():
		world.ledger.changed.connect(func() -> void: _ledger_dirty = true)
		world.sound_requested.connect(_relay_sound)
		_ledger_dirty = true
	else:
		world.replica = true
		for block: RuleBlock in world.blocks.values():
			block.remote = true
		for creature: Creature in world.creatures.values():
			creature.remote = true
		world.action_requested.connect(_send_action)
		if session.player_id != -1:
			_adopt_local_id(session.player_id)
	_ball_ghosts.clear()
	_medal_ghosts.clear()
	sync_avatars()


func close() -> void:
	session.close()


# --- 毎フレーム -------------------------------------------------------------


func _physics_process(delta: float) -> void:
	if world == null or not is_online():
		return
	if (
		manage_falls
		and world.player != null
		and world.player.global_position.y < Tuning.FALL_LIMIT_Y
	):
		_respawn_local()
	if is_host() and _ledger_dirty:
		_ledger_dirty = false
		sync_avatars()
		session.publish()
	_send_timer += delta
	if _send_timer < SEND_PERIOD:
		return
	_send_timer = 0.0
	if is_host():
		_frame.rpc(WorldFrame.capture(world))
	elif session.player_id != -1 and world.player != null and multiplayer.get_unique_id() != 1:
		_avatar_state.rpc_id(1, world.player.remote_state())


## 落ちたら出現地点へ戻す（仮。死亡観戦・共通チェックポイントは次の段で入れる）。
func _respawn_local() -> void:
	world.player.global_position = spawn_point(world.player.player_id)
	world.player.velocity = Vector3.ZERO


## プレイヤーごとの出現地点（ずらして重ならないようにする）。
func spawn_point(player_id: int) -> Vector3:
	if world.has_method(&"spawn_for"):
		return world.call(&"spawn_for", player_id)
	var offset := float(player_id - RuleLedger.PLAYER_ID) * SPAWN_SPACING
	return world._spawn_point + Vector3(offset, 0.5, 0.0)


# --- ホスト -------------------------------------------------------------------


func _on_player_joined(player_id: int) -> void:
	if (
		give_starting_items.is_valid()
		and world.ledger.all_vessels().all(
			func(v: RuleVessel) -> bool: return v.owner_id != player_id
		)
	):
		give_starting_items.call(player_id)
	sync_avatars()
	if world.avatars.has(player_id):
		world.avatars[player_id].global_position = spawn_point(player_id)
	player_joined.emit(player_id)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _avatar_state(state: Array) -> void:
	if not is_host() or state.size() < 4:
		return
	var player_id := session.player_of_peer(multiplayer.get_remote_sender_id())
	var avatar := world.avatars.get(player_id) as PlayerAvatar
	if avatar == null or typeof(state[0]) != TYPE_VECTOR3:
		return
	avatar.apply_remote(state[0] as Vector3, float(state[1]), bool(state[2]), bool(state[3]))


## 参加者の操作。誰の操作かは通信の送り主から決める（依頼の中身は信用しない）。
@rpc("any_peer", "call_remote", "reliable")
func _action(op: Dictionary, choice: Dictionary) -> void:
	if not is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	var player_id := session.player_of_peer(peer)
	if player_id == -1 or not world.ledger.players().has(player_id):
		return
	var sink := func(text: String, sound: StringName) -> void: _notice.rpc_id(peer, text, sound)
	var target := WorldQueries.resolve_target(world, op.get("target", {}) as Dictionary)
	match String(op.get("op", "")):
		"lend":
			var use_range := bool(op.get("range", false))
			WorldParty.act_as(
				world, player_id, choice, sink, func() -> void: world.lend_to(target, use_range)
			)
		"interact":
			WorldParty.act_as(
				world, player_id, choice, sink, func() -> void: world.interact(target)
			)
		"press":
			var action := int(op.get("action", -1))
			if action >= 0 and action < RuleAction.Kind.size():
				var kind := action as RuleAction.Kind
				WorldParty.act_as(
					world, player_id, choice, sink, func() -> void: world.press_action(kind)
				)


## 位置のある効果音は全員へ。
func _relay_sound(event: StringName, at: Vector3, positional: bool) -> void:
	if positional and world.post_sink.is_null() and is_online():
		_sound.rpc(event, at)


# --- 参加者 -------------------------------------------------------------------


func _on_joined(player_id: int) -> void:
	var first_time := world.player.player_id != player_id
	_adopt_local_id(player_id)
	if first_time:
		world.player.global_position = spawn_point(player_id)
	world.player.velocity = Vector3.ZERO
	sync_avatars()
	world.state_changed.emit()


func _adopt_local_id(player_id: int) -> void:
	world.player.player_id = player_id
	world.ledger_actions.player_id = player_id
	world.ledger_actions.remote = func(command: Dictionary) -> void: session.send(command)


func _send_action(op: Dictionary) -> void:
	_action.rpc_id(1, op, WorldParty.current_choice(world))


@rpc("authority", "call_remote", "unreliable_ordered")
func _frame(data: Dictionary) -> void:
	WorldFrame.apply(world, data, _ball_ghosts, _medal_ghosts)


@rpc("authority", "call_remote", "reliable")
func _notice(text: String, sound: StringName) -> void:
	if text != "":
		world.message_posted.emit(text)
	if sound != &"":
		world.sound_requested.emit(sound, Vector3.ZERO, false)


@rpc("authority", "call_remote", "unreliable_ordered")
func _sound(event: StringName, at: Vector3) -> void:
	world.sound_requested.emit(event, at, true)


# --- 共通 -------------------------------------------------------------------


## 台帳の参加中のプレイヤーに合わせて、仲間のアバターを出し入れする。
func sync_avatars() -> void:
	var me := world.player.player_id if world.player != null else -1
	var present := world.ledger.players()
	for player_id in present:
		if player_id != me and not world.avatars.has(player_id):
			WorldParty.add_avatar(world, player_id, spawn_point(player_id))
	for player_id: int in world.avatars.keys():
		if not present.has(player_id):
			WorldParty.remove_avatar(world, player_id)
