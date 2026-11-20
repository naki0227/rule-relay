class_name SteamTransport
extends RefCounted
## Steam 版の通信の差し替え口（docs/adr/0006）。**未検証**: GodotSteam が入った Godot と Steamworks の
## App ID が無いと動かないので、この環境・CI では一度も動かしていない。提出版（ENet）では使わない。
##
## 使い方（GodotSteam を入れたあと）:
##   if SteamTransport.is_available() and SteamTransport.start():
##       var peer := SteamTransport.make_host_peer()   # 部屋を作る（ロビーを作って友だちを招待）
##       var peer := SteamTransport.make_client_peer(host_steam_id)   # 招待から入る
##   あとは ENet の peer と同じく NetWorld.start_host / start_client に渡す。ゲームのコードは変えない。
## GodotSteam の関数名は版ごとに変わることがあるので、名前で呼んで、無ければ null を返す（ここで止めない）。
## ホスト移譲: Steam のロビーは持ち主が抜けると自動で別の人に移る。新しい持ち主の SteamID へ
## make_client_peer でつなぎ直す（HostMigration の IP アドレスの代わり）。これも未実装・未検証。

const VIRTUAL_PORT: int = 0


static func is_available() -> bool:
	return Engine.has_singleton("Steam") and ClassDB.class_exists("SteamMultiplayerPeer")


## Steam を初期化する（Steam クライアントが起動していて、App ID が設定されている必要がある）。
static func start() -> bool:
	if not is_available():
		return false
	var steam := Engine.get_singleton("Steam")
	var result: Variant = steam.call("steamInitEx") if steam.has_method("steamInitEx") else null
	if result is Dictionary:
		return int((result as Dictionary).get("status", 1)) == 0
	return steam.has_method("isSteamRunning") and bool(steam.call("isSteamRunning"))


static func make_host_peer() -> MultiplayerPeer:
	var peer := _new_peer()
	if peer == null or not peer.has_method("create_host"):
		return null
	return peer if int(peer.call("create_host", VIRTUAL_PORT)) == OK else null


static func make_client_peer(host_steam_id: int) -> MultiplayerPeer:
	var peer := _new_peer()
	if peer == null or not peer.has_method("create_client"):
		return null
	return peer if int(peer.call("create_client", host_steam_id, VIRTUAL_PORT)) == OK else null


## 友だちを招待する画面（Steam のオーバーレイ）を開く。
static func open_invite_dialog(lobby_id: int) -> void:
	if is_available():
		Engine.get_singleton("Steam").call("activateGameOverlayInviteDialog", lobby_id)


static func _new_peer() -> MultiplayerPeer:
	if not is_available():
		return null
	return ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer
