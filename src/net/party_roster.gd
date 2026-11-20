class_name PartyRoster
extends RefCounted
## 部屋の参加者の対応表（ホストが持つ）。通信の peer ID は再接続のたびに変わるので、
## 参加者が持ち続ける session_key でプレイヤー ID を決める（同じ人が別人として二重に能力を持たない）。
## 上限は 4 人（仮。引き継ぎ仕様 2-1 で最終人数は未決）。
## session_key を知っていればその人として入れるので、ENet 版では推測できない乱数にする。
## Steam 版では Steam が確かめた SteamID を key にする（docs/adr/0006）。

const MAX_PLAYERS: int = 4

var _player_of_key: Dictionary[String, int] = {}
var _player_of_peer: Dictionary[int, int] = {}
var _next_player_id: int = RuleLedger.PLAYER_ID + 1


## ホスト自身を登録する（ホストは PLAYER_ID）。
func add_host(session_key: String, peer_id: int) -> void:
	_player_of_key[session_key] = RuleLedger.PLAYER_ID
	_player_of_peer[peer_id] = RuleLedger.PLAYER_ID


## 参加・再接続。プレイヤー ID を返す。満員なら -1。同じ key なら前と同じ ID。
## 新しい人なら台帳に登録し、退出していた人なら参加中に戻す。
func join(ledger: RuleLedger, session_key: String, peer_id: int) -> int:
	if session_key.is_empty():
		return -1
	var player_id := int(_player_of_key.get(session_key, -1))
	if player_id == RuleLedger.PLAYER_ID:
		return -1  # ホストの名乗りで入ってくることはできない
	if player_id == -1:
		if _player_of_key.size() >= MAX_PLAYERS:
			return -1
		player_id = _next_player_id
		_next_player_id += 1
		_player_of_key[session_key] = player_id
		ledger.register_player(player_id)
	elif not ledger.players().has(player_id):
		ledger.set_player_present(player_id, true)
	for old_peer: int in _player_of_peer.keys():
		if _player_of_peer[old_peer] == player_id:
			_player_of_peer.erase(old_peer)
	_player_of_peer[peer_id] = player_id
	return player_id


## 通信が切れた。台帳は動かさない（明示的な退出とは区別する。切断中の扱いは未決: ADR 0006）。
func disconnect_peer(peer_id: int) -> void:
	_player_of_peer.erase(peer_id)


## peer に対応するプレイヤー ID（知らない peer なら -1）。
func player_of_peer(peer_id: int) -> int:
	return int(_player_of_peer.get(peer_id, -1))


func is_connected_player(player_id: int) -> bool:
	return _player_of_peer.values().has(player_id)
