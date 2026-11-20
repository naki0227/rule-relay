class_name NetSession
extends Node
## オンライン協力の部屋（ホスト権威。docs/adr/0006）。
## - ホスト: 依頼を PartyCommand で検証して台帳へ適用し、世代番号つきで台帳の状態を全員へ配る
## - 参加者: 依頼を送るだけ。台帳はホストから届いた状態で置き換える（自分では変えない）
## 通信の下回り（MultiplayerPeer）は外から渡す。開発・CI・提出版は ENet、Steam 版は Steam の P2P。
## 同じ依頼の再送（同じ seq）は一度しか適用しない。古い世代の状態は捨てる。

signal joined(player_id: int)
signal join_refused
signal state_changed(generation: int)
signal result_received(seq: int, result: Dictionary)

var ledger: RuleLedger
## 自分のプレイヤー ID（参加前は -1）。
var player_id: int = -1
## 最後に確定した（受け取った）状態の世代。
var generation: int = 0

var _roster: PartyRoster
var _next_seq: int = 1
## ホストが覚えておく「プレイヤーごとに最後に処理した seq とその結果」（再送対策）。
var _last_seq: Dictionary[int, int] = {}
var _last_result: Dictionary[int, Dictionary] = {}
var _session_key: String = ""


func is_host() -> bool:
	return _roster != null


## 部屋を作る。台帳はホストが正本として持つ。
func host(peer: MultiplayerPeer, host_ledger: RuleLedger, session_key: String) -> void:
	ledger = host_ledger
	_roster = PartyRoster.new()
	_roster.add_host(session_key, 1)
	player_id = RuleLedger.PLAYER_ID
	multiplayer.multiplayer_peer = peer
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	joined.emit(player_id)


## 部屋に入る。接続できたら session_key を名乗って参加を頼む。
func join(peer: MultiplayerPeer, session_key: String) -> void:
	ledger = RuleLedger.new()
	_session_key = session_key
	multiplayer.multiplayer_peer = peer
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)


## 依頼を出す。ホストならその場で適用する。seq を返す（結果は result_received で届く）。
func send(command: Dictionary) -> int:
	var seq := _next_seq
	_next_seq += 1
	if is_host():
		_handle(player_id, seq, command)
	else:
		_request.rpc_id(1, seq, command)
	return seq


## 同じ seq で送り直す（通信の再送をまねる。テスト・再接続用）。
func resend(seq: int, command: Dictionary) -> void:
	if is_host():
		_handle(player_id, seq, command)
	else:
		_request.rpc_id(1, seq, command)


## ホストが台帳を直接変えたあと（ステージの初期配置など）に、全員へ配る。
func publish() -> void:
	assert(is_host(), "only the host publishes")
	generation += 1
	_broadcast()


func close() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null


# --- 通信 --------------------------------------------------------------------


func _on_connected() -> void:
	_request_join.rpc_id(1, _session_key)


@rpc("any_peer", "call_remote", "reliable")
func _request_join(session_key: String) -> void:
	if not is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	var id := _roster.join(ledger, session_key, peer)
	if id == -1:
		_refuse.rpc_id(peer)
		return
	generation += 1
	_welcome.rpc_id(peer, id)
	_broadcast()


@rpc("authority", "call_remote", "reliable")
func _welcome(assigned_id: int) -> void:
	player_id = assigned_id
	joined.emit(player_id)


@rpc("authority", "call_remote", "reliable")
func _refuse() -> void:
	join_refused.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request(seq: int, command: Dictionary) -> void:
	if not is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	var sender := _roster.player_of_peer(peer)
	if sender == -1:
		return
	_handle(sender, seq, command)


@rpc("authority", "call_remote", "reliable")
func _result(seq: int, result: Dictionary) -> void:
	result_received.emit(seq, result)


@rpc("authority", "call_remote", "reliable")
func _state(state_generation: int, snapshot: Dictionary) -> void:
	if state_generation <= generation:
		return
	generation = state_generation
	ledger.restore(snapshot)
	state_changed.emit(generation)


func _handle(sender: int, seq: int, command: Dictionary) -> void:
	var result: Dictionary
	if seq <= int(_last_seq.get(sender, 0)):
		# 再送: 二度は適用しない。同じ seq なら前の結果を返し直す
		result = _last_result.get(sender, {}) if seq == _last_seq.get(sender, 0) else {}
		if result.is_empty():
			return
	else:
		result = PartyCommand.apply(ledger, sender, command)
		_last_seq[sender] = seq
		_last_result[sender] = result
		if result["result"] == PartyCommand.Result.OK:
			generation += 1
			_broadcast()
	_reply(sender, seq, result)


func _reply(sender: int, seq: int, result: Dictionary) -> void:
	if sender == player_id:
		result_received.emit(seq, result)
		return
	for peer in multiplayer.get_peers():
		if _roster.player_of_peer(peer) == sender:
			_result.rpc_id(peer, seq, result)


func _broadcast() -> void:
	state_changed.emit(generation)
	_state.rpc(generation, ledger.snapshot())


func _on_peer_disconnected(peer: int) -> void:
	if is_host():
		_roster.disconnect_peer(peer)
