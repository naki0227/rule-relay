extends Node
## Steam 版の通信（docs/adr/0006・0012）。ロビー（作る・入る・招待）と Steam の P2P（SteamMultiplayerPeer）。
## **未検証**: GodotSteam（GDExtension 4.24）の API に合わせて書いたが、Steam クライアントと App ID が無い
## この環境・CI では、ロビーと P2P を一度も動かしていない。
##
## 分け方（docs/adr/0012）:
## - このフォルダ（src/steam/）は「Windows (Steam)」のプリセットだけに入る。提出版のプリセットは
##   exclude_filter で外すので、提出版の pck にはこのファイルが無い
## - このファイルを load するのは SteamGate だけ。class_name を付けない（付けると提出版のクラス一覧に名前が残る）
## - GodotSteam の関数は名前で呼ぶ（Steam のシングルトンが無い Godot でも、このスクリプトを読み込めるように）
##
## 確かめたこと（2026-11-20、Linux・Steam クライアントなし・GodotSteam GDExtension 4.24）:
## - steamInitEx は status 1（steamclient.so が無い）を返す
## - 初期化に失敗したまま SteamMultiplayerPeer.create_host を呼ぶと、Godot ごと落ちる（signal 11）。
##   なので peer を作る関数は、start() が成功した後だけ動く
##
## 流れ:
##   ホスト: host_lobby() → lobby_created → create_host → peer_ready(peer, true)
##   参加者: 招待を受ける（join_requested、または起動引数 +connect_lobby）→ joinLobby → lobby_joined
##           → ロビーの持ち主へ create_client → peer_ready(peer, false)
## ホスト移譲: HostMigration の link として使う。Steam はロビーの持ち主が抜けると別の人へ持ち主を移すので、
## 「新しいロビーの持ち主 = 新しいホスト」にする（lobby_owner / make_host_peer / make_client_peer）。

signal peer_ready(peer: MultiplayerPeer, as_host: bool)
signal failed(text: String)

const PEER_CLASS: StringName = &"SteamMultiplayerPeer"
const VIRTUAL_PORT: int = 0
## PartyRoster.MAX_PLAYERS と同じ（1〜4人）。
const MAX_MEMBERS: int = 4
## Steam.LOBBY_TYPE_FRIENDS_ONLY（フレンドだけが見つけて入れる。招待でも入れる）。
const LOBBY_FRIENDS_ONLY: int = 1
## lobby_created の connect が成功（Steam の k_EResultOK）。
const RESULT_OK: int = 1
## lobby_joined の response が成功（Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS）。
const ENTER_SUCCESS: int = 1
## 招待から起動されたときの引数（Steam が付ける）。
const CONNECT_LOBBY_ARG: String = "+connect_lobby"

## 入っているロビー（0 なら入っていない）。
var lobby_id: int = 0

var _steam: Object = null
var _started: bool = false


static func is_available() -> bool:
	return Engine.has_singleton(&"Steam") and ClassDB.class_exists(PEER_CLASS)


func _ready() -> void:
	# 一時停止中も Steam のコールバックを受け取る（止まると招待やロビーの知らせが届かない）
	process_mode = Node.PROCESS_MODE_ALWAYS


## Steam を初期化する。app_id が 0 なら、Steam クライアント（起動元）かプロジェクト設定に任せる。
## 開発中だけ app_id=480（Valve の見本 Spacewar）を使ってよい。書き出しには入れない（docs/steam-build.md）。
func start(app_id: int = 0) -> bool:
	if _started:
		return true
	if not is_available():
		return false
	_steam = Engine.get_singleton(&"Steam")
	var result: Variant = _steam.call(&"steamInitEx", app_id, false)
	_started = result is Dictionary and int((result as Dictionary).get("status", 1)) == 0
	if not _started:
		push_warning("Steam を初期化できませんでした: %s" % str(result))
		return false
	_steam.connect(&"lobby_created", _on_lobby_created)
	_steam.connect(&"lobby_joined", _on_lobby_joined)
	_steam.connect(&"join_requested", _on_join_requested)
	var invited := lobby_from_args(OS.get_cmdline_args())
	if invited != 0:
		join_lobby.call_deferred(invited)
	return true


func is_started() -> bool:
	return _started


func _process(_delta: float) -> void:
	if _started:
		_steam.call(&"run_callbacks")


## タイトルに Steam の項目を足す（TitleMenu.add_entry）。Steam が使えるときだけ GameRoot が呼ぶ。
func add_title_entries(title: Control) -> void:
	title.call(&"add_entry", "Steam で部屋を作る（フレンドを招待）", host_lobby)
	title.call(&"add_note", "Steam のフレンドの部屋には、Steam の招待から入れます")


## フレンドだけのロビーを作る。できたら lobby_created から peer_ready が出る。
func host_lobby() -> void:
	if _started:
		_steam.call(&"createLobby", LOBBY_FRIENDS_ONLY, MAX_MEMBERS)


func join_lobby(target_lobby: int) -> void:
	if _started and target_lobby != 0:
		_steam.call(&"joinLobby", target_lobby)


## 友だちを招待する画面（Steam のオーバーレイ）を開く。
func invite() -> void:
	if _started and lobby_id != 0:
		_steam.call(&"activateGameOverlayInviteDialog", lobby_id)


func leave() -> void:
	if _started and lobby_id != 0:
		_steam.call(&"leaveLobby", lobby_id)
	lobby_id = 0


## 今のロビーの持ち主の SteamID（ホスト移譲で新しいホストを決める。分からなければ 0）。
func lobby_owner() -> int:
	if not _started or lobby_id == 0:
		return 0
	return int(_steam.call(&"getLobbyOwner", lobby_id))


func local_steam_id() -> int:
	return int(_steam.call(&"getSteamID")) if _started else 0


## ホストの peer（P2P で待ち受ける）。Steam を初期化できていなければ null（落ちないように呼ばない）。
func make_host_peer() -> MultiplayerPeer:
	var peer := _new_peer()
	if peer == null or int(peer.call(&"create_host", VIRTUAL_PORT)) != OK:
		return null
	peer.set(&"server_relay", true)
	return peer


func make_client_peer(host_steam_id: int) -> MultiplayerPeer:
	var peer := _new_peer()
	if peer == null or host_steam_id == 0:
		return null
	if int(peer.call(&"create_client", host_steam_id, VIRTUAL_PORT)) != OK:
		return null
	peer.set(&"server_relay", true)
	return peer


## ホスト: {プレイヤー ID: SteamID}（ホスト移譲の荷物に入れる。新しいロビーの持ち主がどのプレイヤーかを知るため）。
func steam_ids_by_player(session: NetSession, local_player: int) -> Dictionary:
	var result := {local_player: local_steam_id()}
	var peer := session.multiplayer.multiplayer_peer
	if not _started or peer == null or not peer.has_method(&"get_steam_id_for_peer_id"):
		return result
	for remote: int in session.multiplayer.get_peers():
		var player := session.player_of_peer(remote)
		if player != -1:
			result[player] = int(peer.call(&"get_steam_id_for_peer_id", remote))
	return result


## 起動引数の「+connect_lobby <ロビー ID>」（招待から起動されたとき）。無ければ 0。純粋な関数。
static func lobby_from_args(args: PackedStringArray) -> int:
	var at := args.find(CONNECT_LOBBY_ARG)
	if at == -1 or at + 1 >= args.size() or not args[at + 1].is_valid_int():
		return 0
	return int(args[at + 1])


func _on_lobby_created(result: int, new_lobby: int) -> void:
	if result != RESULT_OK:
		failed.emit("Steam のロビーを作れませんでした（%d）" % result)
		return
	lobby_id = new_lobby
	var peer := make_host_peer()
	if peer == null:
		failed.emit("Steam の P2P で待ち受けられませんでした")
		return
	peer_ready.emit(peer, true)
	invite()


func _on_lobby_joined(joined: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != ENTER_SUCCESS:
		failed.emit("Steam のロビーに入れませんでした（%d）" % response)
		return
	lobby_id = joined
	var owner := lobby_owner()
	if owner == local_steam_id():
		return  # 自分で作ったロビー（_on_lobby_created で済んでいる）
	var peer := make_client_peer(owner)
	if peer == null:
		failed.emit("ホストへ Steam の P2P でつなげませんでした")
		return
	peer_ready.emit(peer, false)


func _on_join_requested(target_lobby: int, _friend: int) -> void:
	join_lobby(target_lobby)


func _new_peer() -> MultiplayerPeer:
	if not _started:
		return null
	return ClassDB.instantiate(PEER_CLASS) as MultiplayerPeer
