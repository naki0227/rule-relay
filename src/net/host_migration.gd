class_name HostMigration
extends Node
## ホスト移譲（引き継ぎ仕様 4.3。docs/adr/0006・0010）。
## - ホスト: 進行の状態（PartyDirector.export_state）・参加者の対応表（鍵のハッシュ）・参加者の IP アドレスを
##   1.5 秒ごとに全員へ配っておく
## - 参加者: ホストとの接続が切れたら、世界を止めて「ホスト選出中…」を出す。残った参加者のうち
##   プレイヤー ID がいちばん小さい人が新しいホストになり、ほかの人はその人へつなぎ直す
##   （全員が同じ情報から同じ人を選ぶので、話し合いは要らない）
## - 新しいホスト: 同じポートで部屋を開き直し、受け取っていた最後の状態から続ける（「あなたがホストになりました」）
## - だれにもつながらなければ、成功したふりをせず「ホストが見つかりません」と出す
## ENet の直接接続では、新しいホストの PC にも外からつながる必要がある（ポート開放など）。
## Steam 版（link に Steam 版の通信を入れたとき。docs/adr/0012）は、ID の小さい人を選ぶ代わりに
## 「Steam が決めた新しいロビーの持ち主 = 新しいホスト」にする。全員が同じロビーの持ち主を見るので、
## これも話し合いは要らない。P2P は Valve の中継を通るので、新しいホストのポート開放も要らない（未検証）。
## 子ノード名は固定（"Migration"）。RPC のパスを両側でそろえるため。

signal status_changed(text: String)

const PACKAGE_PERIOD: float = 1.5
## つなぎ直しを待つ時間（これを過ぎたらあきらめる）。
const REJOIN_TIMEOUT: float = 12.0
## 新しいホストが部屋を開き直すのを待ってからつなぐ。
const REJOIN_DELAY: float = 1.0
## Steam 版: ロビーの持ち主が移るのを待つ時間（落ちた人を Steam が抜けたと判断するまで少しかかる）。
const OWNER_TIMEOUT: float = 30.0

var director: PartyDirector
var net: NetWorld
var port: int = 0
var session_key: String = ""
## Steam 版の通信（src/steam/steam_transport.gd）。null なら ENet の直接接続（今までどおり）。
var link: Node = null
## 移譲の途中か。
var migrating: bool = false
## 最後に受け取ったホストの状態。
var package: Dictionary = {}

var _timer: float = 0.0
var _rejoin_left: float = -1.0
var _rejoin_address: String = ""
var _owner_left: float = -1.0


func _ready() -> void:
	name = "Migration"
	process_mode = Node.PROCESS_MODE_ALWAYS


## 参加者として入ったあとに呼ぶ（ホストとの接続が切れたら移譲を始める）。
func watch() -> void:
	if not multiplayer.server_disconnected.is_connected(_on_host_lost):
		multiplayer.server_disconnected.connect(_on_host_lost)


func _physics_process(delta: float) -> void:
	if net == null or director == null or director.world == null:
		return
	if net.is_host() and not migrating and net.is_online():
		_timer += delta
		if _timer >= PACKAGE_PERIOD:
			_timer = 0.0
			_receive.rpc(_make_package())
	elif _rejoin_left >= 0.0:
		_wait_for_rejoin(delta)
	elif _owner_left >= 0.0:
		_wait_for_owner(delta)


func _make_package() -> Dictionary:
	var made := {
		"director": director.export_state(),
		"roster": net.session.public_roster(),
		"addresses": net.session.peer_addresses(),
		"generation": net.session.generation,
	}
	if link != null:
		made["steam_ids"] = link.call(&"steam_ids_by_player", net.session, director.local_id())
	return made


@rpc("authority", "call_remote", "reliable")
func _receive(new_package: Dictionary) -> void:
	package = new_package


## 次のホストになる人（前のホスト以外で、IP アドレスが分かっている人のうち ID がいちばん小さい人）。
static func elect(addresses: Dictionary, old_host: int) -> int:
	var best := -1
	for player_id: int in addresses:
		if player_id != old_host and (best == -1 or player_id < best):
			best = player_id
	return best


## Steam 版: 新しいロビーの持ち主がどのプレイヤーか（前のホストのまま・知らない人なら -1 で、まだ待つ）。
static func elect_by_owner(steam_ids: Dictionary, owner_steam_id: int, old_host: int) -> int:
	if owner_steam_id == 0:
		return -1
	for player_id: int in steam_ids:
		if player_id != old_host and int(steam_ids[player_id]) == owner_steam_id:
			return player_id
	return -1


func _on_host_lost() -> void:
	if migrating or net == null or net.is_host():
		return
	migrating = true
	_freeze(true)
	_say("ホスト選出中…")
	if package.is_empty():
		_fail("ホストの状態を受け取る前に切れました。部屋を作り直してください")
		return
	if link != null:
		_owner_left = OWNER_TIMEOUT
		return
	var old_host := _old_host()
	var addresses := package["addresses"] as Dictionary
	var next := elect(addresses, old_host)
	if next == -1:
		_fail("ホストが見つかりません（ほかに参加者がいません）")
	elif next == director.local_id():
		_become_host()
	else:
		_rejoin_address = String(addresses[next])
		_rejoin_left = REJOIN_TIMEOUT + REJOIN_DELAY
		_say("ホスト選出中…（プレイヤー%d が新しいホストになります）" % next)


func _old_host() -> int:
	return int((package["director"] as Dictionary).get("host_id", RuleLedger.PLAYER_ID))


func _become_host() -> void:
	var server := ENetMultiplayerPeer.new()
	if server.create_server(port, PartyRoster.MAX_PLAYERS) != OK:
		_fail("新しいホストとして部屋を開けませんでした（ポート %d）" % port)
		return
	_open_as_host(server)


## Steam 版: ロビーの持ち主が前のホストから移るまで待ち、持ち主がホストになる・ほかの人は持ち主へつなぐ。
func _wait_for_owner(delta: float) -> void:
	_owner_left -= delta
	var owner := int(link.call(&"lobby_owner"))
	var next := elect_by_owner(package.get("steam_ids", {}) as Dictionary, owner, _old_host())
	if next == -1:
		if _owner_left < 0.0:
			_fail("新しいホストが決まりませんでした（Steam のロビー）")
		return
	_owner_left = -1.0
	if next == director.local_id():
		var server := link.call(&"make_host_peer") as MultiplayerPeer
		if server == null:
			_fail("新しいホストとして Steam の P2P で待ち受けられませんでした")
			return
		_open_as_host(server)
		return
	_say("ホスト選出中…（プレイヤー%d が新しいホストになります）" % next)
	var peer := link.call(&"make_client_peer", owner) as MultiplayerPeer
	if peer == null:
		_fail("新しいホストへ Steam の P2P でつなげませんでした")
		return
	_rejoin_with(peer)


func _open_as_host(server: MultiplayerPeer) -> void:
	net.become_host(
		server,
		session_key,
		director.local_id(),
		package["roster"] as Dictionary,
		int(package["generation"])
	)
	director.adopt_state(package["director"] as Dictionary)
	director.attach_net(net)
	_finish("あなたがホストになりました")


func _wait_for_rejoin(delta: float) -> void:
	var before := _rejoin_left
	_rejoin_left -= delta
	if before > REJOIN_TIMEOUT and _rejoin_left <= REJOIN_TIMEOUT:
		var peer := ENetMultiplayerPeer.new()
		if peer.create_client(_rejoin_address, port) != OK:
			_fail("新しいホストへつなげませんでした")
			return
		_rejoin_with(peer)
	elif _rejoin_left < 0.0:
		_fail("新しいホストへつなげませんでした（時間切れ）")


func _rejoin_with(peer: MultiplayerPeer) -> void:
	if _rejoin_left < 0.0:
		_rejoin_left = REJOIN_TIMEOUT  # Steam 版はここから時間切れを数える
	net.session.joined.connect(_on_rejoined, CONNECT_ONE_SHOT)
	net.session.join(peer, session_key, director.world.ledger)


func _on_rejoined(_player_id: int) -> void:
	_rejoin_left = -1.0
	_finish("新しいホストにつながりました")


func _finish(text: String) -> void:
	migrating = false
	_freeze(false)
	_say(text)
	watch()


func _fail(text: String) -> void:
	migrating = false
	_rejoin_left = -1.0
	_owner_left = -1.0
	_say(text)


## 移譲の間は世界を止める（全員の進行を一時停止。引き継ぎ仕様 4.3）。
func _freeze(on: bool) -> void:
	if director.world != null:
		director.world.process_mode = (
			Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
		)


func _say(text: String) -> void:
	status_changed.emit(text)
	if director.world != null:
		director.world.message_posted.emit(text)
