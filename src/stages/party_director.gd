class_name PartyDirector
extends Node
## ハブとステージの進行役（引き継ぎ仕様 2・4・5。docs/adr/0010）。1人用でもオンラインでも同じ仕組み。
## ルールを決めるのは「権威」（1人用なら自分、オンラインならホスト）。参加者はホストから届く
## ステージ・チーム進行の状態を表示し、操作（投票・退出・報酬の受け取り）をホストへ送る。
##
## - ステージに入る: StageWorld を組み立て、開始時の持ち物と人数別補助を置き、開始時点を記録する
## - 死亡: 落ちたら死亡観戦（台帳はそのまま。貸したものも手元のものも残る）。1人用・全滅は自動で戻る
## - チェックポイント: 1人が触れたらチーム共通。その時点の世界を記録する。台座の上の F で全員復活
## - 全員リセット: V 長押しで投票（過半数、または死亡観戦がいるとき生存者全員）。成立したら世界を丸ごと戻し、
##   途中参加の人を合流させ、人数が変わっていれば人数別補助を作り直す
## - クリア: ステージのクリア条件を満たしたら、資格のある人に報酬を配り、しばらくしてハブへ戻る
## 子ノード名は固定（"Director"）。RPC のパスを両側でそろえるため。

signal world_changed(world: StageWorld)
## チーム進行の状態が変わった（HUD の表示用）。
signal party_changed

## クリアしてからハブへ戻るまでの秒数。
const RETURN_DELAY: float = 4.0

var world: StageWorld
## オンラインのとき（1人用なら null）。
var net: NetWorld
var lifecycle: PartyLifecycle = PartyLifecycle.new()
var loadout: StageLoadout
var tracker: RunTracker = RunTracker.new()
var progress: PlayerProgress = PlayerProgress.new()
var store: ProgressStore = ProgressStore.new()
## 自分の進行を保存する名前（同じ PC で2つ起動して試すときは別の名前にする）。
var profile: String = "player"
var table: RewardTable = RewardTable.provisional()
var stage_id: String = ""
var stage_run_id: String = ""
## 最後にクリアした結果の文（HUD の表示用）。
var last_clear_text: String = ""
## ステージの島を置く親（既定は自分。物理の世界を分けたいときは SubViewport を渡す）。
var world_parent: Node

## チェックポイント ID → その時点の記録 {"world": WorldSnapshot, "loadout": StageLoadout の状態}
var _snapshots: Dictionary = {}
var _run_serial: int = 0
var _clear_timer: float = -1.0
## 報酬を配った回（再接続した人へ後から渡すため、部屋がある間は残す）。
var _runs: Array[StageRunRewards] = []
## 一度でもこの部屋に来たプレイヤー（初めて来たときだけ出現地点へ動かす。再接続・ホスト移譲では動かさない）。
var _known_players: Dictionary[int, bool] = {}
## 「チェックポイントにできない」を一度伝えた人（台座の上で毎フレーム出さないため）。
var _warned_checkpoint: Dictionary[int, bool] = {}


func _ready() -> void:
	name = "Director"
	var loaded := store.load_progress(profile)
	progress = loaded.progress


## 1人用・ホストか（ルールを決める側か）。
func is_authority() -> bool:
	return net == null or net.is_host()


func local_id() -> int:
	return (
		world.player.player_id if world != null and world.player != null else RuleLedger.PLAYER_ID
	)


func in_stage() -> bool:
	return world != null and not world.def.is_hub()


## 自分がいま観戦中か（死亡観戦・途中参加の待機）。
func is_spectating() -> bool:
	if not in_stage():
		return false
	var state := lifecycle.state_of(local_id())
	return (
		state == PartyLifecycle.State.DEAD_SPECTATING
		or state == PartyLifecycle.State.WAITING_SPECTATOR
	)


# --- ステージの出入り --------------------------------------------------------


## ステージ（またはハブ）に入る。権威だけが呼ぶ。参加者へも同じステージを組み立てさせる。
func enter_stage(new_stage_id: String) -> void:
	if not is_authority() or StageCatalog.by_id(new_stage_id) == null:
		return
	var players := _present_players()
	_run_serial += 1
	var run_id := "%s#%d-%d" % [new_stage_id, Time.get_unix_time_from_system(), _run_serial]
	_build(new_stage_id, run_id)
	for player_id in players:
		if not world.ledger.has_entity(player_id):
			world.ledger.register_player(player_id)
	loadout = StageLoadout.new(world.def, world.entity_ids)
	loadout.apply(world.ledger, players)
	lifecycle = PartyLifecycle.new()
	if in_stage():
		lifecycle.start_stage(players)
	tracker.reset(world.ledger)
	_clear_timer = -1.0
	_snapshots = {PartyLifecycle.STAGE_START: _capture()}
	for player_id in players:
		_teleport(player_id, world.spawn_for(player_id))
	if _online():
		_enter.rpc(new_stage_id, run_id)
	_broadcast_party()


func _build(new_stage_id: String, run_id: String) -> void:
	var me := local_id()
	if world != null:
		world.queue_free()
		world.name = "Leaving"
	stage_id = new_stage_id
	stage_run_id = run_id
	last_clear_text = ""
	world = StageWorld.new()
	world.setup(StageCatalog.by_id(new_stage_id))
	world.vote_request = request_vote
	world.restart_request = request_restart
	(world_parent if world_parent != null else self).add_child(world)
	world.player.player_id = me
	world.ledger_actions.player_id = me
	if net != null:
		net.manage_falls = false
		net.bind(world)
	if is_authority():
		world.checkpoint_interacted.connect(_on_checkpoint_interacted)
		world.entrance_chosen.connect(_on_entrance_chosen)
		world.return_chosen.connect(
			func(player_id: int) -> void: _teleport(player_id, world.spawn_for(player_id))
		)
		world.ledger.changed.connect(func() -> void: tracker.observe(world.ledger))
	world.message_posted.emit(
		"%s に来ました" % world.def.display_name if in_stage() else "ハブ: 入口で F を押すとステージへ"
	)
	world_changed.emit(world)


## 次のステージに連れていく人（参加中の全員。1人用なら自分だけ）。
func _present_players() -> PackedInt32Array:
	if world == null:
		return PackedInt32Array([RuleLedger.PLAYER_ID])
	return world.ledger.players()


func _on_entrance_chosen(_player_id: int, chosen: String) -> void:
	if not in_stage():
		enter_stage(chosen)


# --- 毎フレーム（権威） --------------------------------------------------------


func _physics_process(delta: float) -> void:
	if world == null:
		return
	_update_spectate()
	if not is_authority():
		return
	if _clear_timer >= 0.0:
		_clear_timer -= delta
		if _clear_timer < 0.0:
			enter_stage(StageCatalog.HUB_ID)
		return
	if not in_stage():
		_rescue_in_hub()
		return
	tracker.seconds += delta
	var changed := _check_deaths()
	changed = _check_checkpoints() or changed
	if lifecycle.has_pending_reset():
		_apply_reset(lifecycle.take_pending_reset())
		changed = true
	if changed:
		_broadcast_party()
	_check_clear()


func _check_deaths() -> bool:
	var changed := false
	for player_id in lifecycle.players_in(PartyLifecycle.State.ACTIVE):
		var avatar := world.avatar_of(player_id)
		if avatar != null and avatar.global_position.y < Tuning.FALL_LIMIT_Y:
			if lifecycle.die(player_id):
				world.message_posted.emit(_name(player_id) + "が落ちました（観戦中）")
				changed = true
	return changed


func _check_checkpoints() -> bool:
	var changed := false
	for player_id in lifecycle.players_in(PartyLifecycle.State.ACTIVE):
		var avatar := world.avatar_of(player_id)
		var cp := "" if avatar == null else world.checkpoint_at(avatar.global_position)
		if cp != "" and not _safe_to_save(player_id, avatar):
			_warn_unsafe_checkpoint(player_id)
			continue
		if cp != "" and lifecycle.activate_checkpoint(player_id, cp):
			_snapshots[cp] = _capture()
			world.message_posted.emit("チェックポイントがチーム共通になりました（台座で F: 全員復活）")
			world.sound_requested.emit(&"save", Vector3.ZERO, false)
			changed = true
	return changed


## 詰みにつながる状態（自分で一歩も歩けない・空中）では、チェックポイントを有効にしない
## （2026-11-20 試遊で、歩けないままダッシュで台座に入ると抜け出せない状態が保存された）。
func _safe_to_save(player_id: int, avatar: PlayerAvatar) -> bool:
	var on_floor := avatar.is_on_floor() if avatar == world.player else avatar.remote_on_floor
	return CheckpointPolicy.save_blockers(world.ledger, on_floor, 0, player_id).is_empty()


func _warn_unsafe_checkpoint(player_id: int) -> void:
	if _warned_checkpoint.has(player_id):
		return
	_warned_checkpoint[player_id] = true
	var why := "W/A/S/D のどれかを手元に戻してから台座に触れてください"
	world.message_posted.emit("チェックポイントにできません（%s）" % why)


func _check_clear() -> void:
	var snapshot := world.clear_snapshot(
		lifecycle.formal_participants(), lifecycle.players_in(PartyLifecycle.State.ACTIVE)
	)
	if world.def.clear_condition.is_met(snapshot):
		_on_clear()


## ハブで落ちたら出現地点へ戻すだけ（ハブに死亡はない）。
func _rescue_in_hub() -> void:
	for player_id in world.ledger.players():
		var avatar := world.avatar_of(player_id)
		if avatar != null and avatar.global_position.y < Tuning.FALL_LIMIT_Y:
			_teleport(player_id, world.spawn_for(player_id))


# --- 全員復活・全員リセット ------------------------------------------------


func _on_checkpoint_interacted(player_id: int, cp: String) -> void:
	if lifecycle.players_in(PartyLifecycle.State.DEAD_SPECTATING).is_empty():
		world.message_posted.emit("チェックポイント（全員そろっています）")
		return
	var revived := lifecycle.revive_all(player_id, cp)
	if revived.is_empty():
		world.message_posted.emit("このチェックポイントでは全員復活できません")
		return
	for i in revived.size():
		_teleport(revived[i], world.checkpoint_position(cp) + Vector3(0.8 * (i + 1), 0.3, 0.0))
	world.message_posted.emit("%d 人が復活しました" % revived.size())
	world.sound_requested.emit(&"goal", Vector3.ZERO, false)
	_broadcast_party()


## メニューの「島のはじめから」: ひとりならステージを最初から作り直す。協力中は、
## 全員の世界を勝手に巻き戻さないよう、チェックポイントへの全員リセットの投票にする。
func request_restart() -> void:
	if not in_stage():
		return
	if net == null:
		enter_stage(stage_id)
	else:
		world.message_posted.emit("協力中は、はじめからではなくチェックポイントへの投票になります")
		request_vote()


## V 長押し: 全員リセットの投票（無ければ提案）。参加者はホストへ送る。
func request_vote() -> void:
	if not in_stage():
		return
	if is_authority():
		_vote_as(local_id())
	else:
		_vote.rpc_id(1)


func _vote_as(player_id: int) -> void:
	if lifecycle.vote_reset(player_id):
		world.message_posted.emit(
			"全員リセットの投票 %d / %d（V 長押しで賛成）" % [lifecycle.yes_vote_count(), lifecycle.required_votes()]
		)
	_broadcast_party()


func _apply_reset(decision: PartyResetDecision) -> void:
	var start: Dictionary = _snapshots[PartyLifecycle.STAGE_START]
	var saved: Dictionary = _snapshots.get(decision.checkpoint_id, start)
	var at := (
		world.checkpoint_position(decision.checkpoint_id)
		if decision.checkpoint_id != PartyLifecycle.STAGE_START
		else world.spawn_for(RuleLedger.PLAYER_ID)
	)
	WorldSnapshot.apply(world, saved["world"] as Dictionary)
	loadout.restore_state(saved["loadout"] as Dictionary)
	# 鳴らした鐘も、その時点に戻す（やり直したのに「鳴らした」まま数えない）
	world.activated = (saved.get("activated", PackedStringArray()) as PackedStringArray).duplicate()
	for player_id in decision.active_player_ids:
		if not world.ledger.has_entity(player_id):
			world.ledger.register_player(player_id)
		elif not world.ledger.players().has(player_id):
			world.ledger.set_player_present(player_id, true)
	for player_id in world.ledger.players():
		if not decision.active_player_ids.has(player_id):
			world.ledger.set_player_present(player_id, false)
	for player_id in decision.joined_player_ids:
		loadout.give_start(world.ledger, player_id, decision.active_player_ids.find(player_id))
	if decision.headcount_changed():
		loadout.rebuild_helpers(world.ledger, decision.headcount)
	for i in decision.active_player_ids.size():
		_teleport(decision.active_player_ids[i], at + Vector3(0.8 * i, 0.3, 0.0))
	world.message_posted.emit("チェックポイントからやり直します（世界も元に戻りました）")


func _capture() -> Dictionary:
	return {
		"world": WorldSnapshot.capture(world),
		"loadout": loadout.capture_state(),
		"activated": world.activated.duplicate(),
	}


# --- クリアと報酬 -----------------------------------------------------------


func _on_clear() -> void:
	var rewards := StageRunRewards.new(stage_id, stage_run_id)
	var statuses: Dictionary[String, int] = {}
	for player_id in world.ledger.players():
		statuses[str(player_id)] = _reward_status(player_id)
	for player_id in lifecycle.players_in(PartyLifecycle.State.LEFT):
		statuses[str(player_id)] = StageRunRewards.Status.LEFT_BEFORE_CLEAR
	rewards.settle(statuses, tracker.metrics(), int(Time.get_unix_time_from_system()))
	_runs.append(rewards)
	_clear_timer = RETURN_DELAY
	var seconds := int(tracker.seconds)
	var text := (
		"クリア！ %d 分 %02d 秒（目安 %d 分）・付与 %d 回・受け渡し %d 回"
		% [
			seconds / 60,
			seconds % 60,
			world.def.target_minutes,
			tracker.abilities_used,
			tracker.hand_offs,
		]
	)
	_show_clear(text)
	if _online():
		_cleared.rpc(text)
	deliver_rewards()


func _reward_status(player_id: int) -> int:
	match lifecycle.state_of(player_id):
		PartyLifecycle.State.ACTIVE:
			return StageRunRewards.Status.ACTIVE
		PartyLifecycle.State.DEAD_SPECTATING:
			return StageRunRewards.Status.DEAD_SPECTATING
		PartyLifecycle.State.DISCONNECTED:
			return StageRunRewards.Status.DISCONNECTED
		PartyLifecycle.State.WAITING_SPECTATOR:
			return StageRunRewards.Status.WAITING_SPECTATOR
	return StageRunRewards.Status.LEFT_BEFORE_CLEAR


func _show_clear(text: String) -> void:
	last_clear_text = text
	world.message_posted.emit(text)
	world.sound_requested.emit(&"goal", Vector3.ZERO, false)
	world.goal_reached.emit()


## まだ受け取っていない報酬を、つながっている人へ配る（再接続した人にも、部屋がある間は渡す）。
func deliver_rewards() -> void:
	if not is_authority():
		return
	var connected := PackedStringArray([str(local_id())])
	if net != null:
		for player_id in world.ledger.players():
			if net.session.peer_of_player(player_id) != -1:
				connected.append(str(player_id))
	for rewards in _runs:
		for event in rewards.events_to_send(connected):
			var key := String(event["player_key"])
			if key == str(local_id()):
				if _apply_reward(event):
					rewards.acknowledge(key, String(event["reward_event_id"]))
			else:
				_reward.rpc_id(net.session.peer_of_player(int(key)), event)


## 自分の進行に報酬を入れて保存する。同じ報酬は二度入らない（PlayerProgress が覚えている）。
func _apply_reward(event: Dictionary) -> bool:
	var result := progress.apply_reward_event(event, table)
	if result.outcome == PlayerProgress.Outcome.APPLIED:
		store.save(profile, progress)
		var got := "、".join(result.granted) if not result.granted.is_empty() else "記録"
		var head := "初回クリア" if result.first_clear else "クリア"
		world.message_posted.emit("%s の報酬: %s" % [head, got])
	return result.should_acknowledge()


# --- 観戦（自分の画面） -------------------------------------------------------


## 死亡観戦・待機中は自分のアバターを隠して止め、生きている仲間を映す。
func _update_spectate() -> void:
	if world.player == null:
		return
	var spectating := is_spectating()
	world.player.visible = not spectating
	world.player.set_physics_process(not spectating)
	world.player.collision_layer = 0 if spectating else Tuning.LAYER_PLAYER
	if world.camera_rig == null:
		return
	var target: Node3D = world.player
	if spectating:
		for player_id in lifecycle.players_in(PartyLifecycle.State.ACTIVE):
			var avatar := world.avatar_of(player_id)
			if avatar != null and avatar != world.player:
				target = avatar
				break
	world.camera_rig.target = target


# --- オンライン -------------------------------------------------------------


## ホスト移譲に備えて、進行の状態をまるごと書き出す（ホストが参加者へ定期的に配る）。
func export_state() -> Dictionary:
	var runs: Array[Dictionary] = []
	for rewards in _runs:
		runs.append(rewards.to_dict())
	return {
		"stage_id": stage_id,
		"run_id": stage_run_id,
		"world": WorldSnapshot.capture(world),
		"loadout": loadout.capture_state() if loadout != null else {},
		"lifecycle": lifecycle.to_dict(),
		"snapshots": _snapshots,
		"tracker": tracker.to_dict(),
		"activated": world.activated.duplicate(),
		"runs": runs,
		"host_id": local_id(),
	}


## ホスト移譲: 新しいホストになった自分が、前のホストの最後の状態から続ける。
## 世界を権威として作り直し、台帳・ブロック・進行を戻す（自分のアバターの位置はいまの位置のまま）。
## 前のホストは「通信が切れた人」になる（戻ってくれば同じプレイヤーに戻る）。
func adopt_state(state: Dictionary) -> void:
	var here := world.player.global_position if world != null else Vector3.ZERO
	_build(String(state["stage_id"]), String(state["run_id"]))
	WorldSnapshot.apply(world, state["world"] as Dictionary)
	world.player.global_position = here
	world.player.velocity = Vector3.ZERO
	loadout = StageLoadout.new(world.def, world.entity_ids)
	if not (state["loadout"] as Dictionary).is_empty():
		loadout.restore_state(state["loadout"] as Dictionary)
	var restored := PartyLifecycle.from_dict(state["lifecycle"] as Dictionary)
	lifecycle = restored if restored != null else PartyLifecycle.new()
	_snapshots = state["snapshots"] as Dictionary
	tracker.restore(state["tracker"] as Dictionary, world.ledger)
	world.activated = (state.get("activated", PackedStringArray()) as PackedStringArray).duplicate()
	_runs.clear()
	for data: Dictionary in state["runs"] as Array:
		var rewards := StageRunRewards.from_dict(data)
		if rewards != null:
			_runs.append(rewards)
	for player_id in world.ledger.players():
		_known_players[player_id] = true
	# 前のホストも、つなぎ直してくる人も、入ってくるまでは「通信が切れた人」
	if in_stage():
		for player_id in lifecycle.formal_participants():
			if player_id != local_id():
				lifecycle.disconnect_player(player_id)
	world.message_posted.emit("あなたがホストになりました")
	_broadcast_party()


## 参加者: ホストから「このステージへ」と届くまで、仮のハブを作っておく（NetWorld をつなぐ先）。
func prepare_client() -> void:
	_build(StageCatalog.HUB_ID, "")


## NetWorld をつなぐ（オンラインのとき、ステージを作る前に呼ぶ）。
func attach_net(new_net: NetWorld) -> void:
	net = new_net
	net.manage_falls = false
	net.give_starting_items = _give_join_items
	if net.is_host():
		if not net.session.player_joined.is_connected(_on_player_joined):
			net.session.player_joined.connect(_on_player_joined)
		if not net.session.player_disconnected.is_connected(_on_player_disconnected):
			net.session.player_disconnected.connect(_on_player_disconnected)


func _give_join_items(player_id: int) -> void:
	if loadout != null and not in_stage():
		loadout.give_start(world.ledger, player_id, world.ledger.players().find(player_id))


func _on_player_joined(player_id: int) -> void:
	if _online():
		_enter.rpc_id(net.session.peer_of_player(player_id), stage_id, stage_run_id)
	if in_stage():
		if (
			not lifecycle.has_player(player_id)
			or lifecycle.state_of(player_id) == PartyLifecycle.State.LEFT
		):
			lifecycle.join(player_id)
			world.message_posted.emit(_name(player_id) + "が来ました（次の全員リセットで合流）")
		else:
			lifecycle.reconnect(player_id)
	if not _known_players.has(player_id):
		_known_players[player_id] = true
		_teleport(player_id, world.spawn_for(player_id))
	_broadcast_party()
	deliver_rewards()


func _on_player_disconnected(player_id: int) -> void:
	if in_stage():
		lifecycle.disconnect_player(player_id)
	world.message_posted.emit(_name(player_id) + "の通信が切れました")
	_broadcast_party()


## 部屋を出る（明示的な退出。クリア前ならその回の報酬は受け取らない）。
func leave_room() -> void:
	if net == null or is_authority():
		return
	_leave.rpc_id(1)


func _broadcast_party() -> void:
	party_changed.emit()
	if _online() and net.is_host():
		_party.rpc(lifecycle.to_dict())


## 権威がプレイヤーを動かす。自分ならその場で、仲間ならその人の画面へ頼む（アバターは各自が動かすため）。
func _teleport(player_id: int, at: Vector3) -> void:
	if player_id == local_id():
		world.player.global_position = at
		world.player.velocity = Vector3.ZERO
		return
	var avatar := world.avatar_of(player_id)
	if avatar != null:
		avatar.global_position = at
		avatar.apply_remote(at, avatar.remote_yaw, false, true)
	if _online() and net.session.peer_of_player(player_id) != -1:
		_moved.rpc_id(net.session.peer_of_player(player_id), at)


func _online() -> bool:
	return net != null and net.is_online()


func _name(player_id: int) -> String:
	return "あなた" if player_id == local_id() else "プレイヤー%d" % player_id


@rpc("authority", "call_remote", "reliable")
func _enter(new_stage_id: String, run_id: String) -> void:
	if StageCatalog.by_id(new_stage_id) == null:
		return
	if new_stage_id != stage_id or run_id != stage_run_id or world == null:
		_build(new_stage_id, run_id)
		lifecycle = PartyLifecycle.new()
		party_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _party(state: Dictionary) -> void:
	var replica := PartyLifecycle.from_dict(state)
	if replica != null:
		lifecycle = replica
		party_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _moved(at: Vector3) -> void:
	if world != null and world.player != null:
		world.player.global_position = at
		world.player.velocity = Vector3.ZERO


@rpc("authority", "call_remote", "reliable")
func _cleared(text: String) -> void:
	if world != null:
		_show_clear(text)


@rpc("authority", "call_remote", "reliable")
func _reward(event: Dictionary) -> void:
	if world != null and _apply_reward(event):
		_ack.rpc_id(
			1, String(event.get("player_key", "")), String(event.get("reward_event_id", ""))
		)


@rpc("any_peer", "call_remote", "reliable")
func _ack(player_key: String, reward_event_id: String) -> void:
	var sender := net.session.player_of_peer(multiplayer.get_remote_sender_id())
	if not is_authority() or str(sender) != player_key:
		return
	for rewards in _runs:
		rewards.acknowledge(player_key, reward_event_id)


@rpc("any_peer", "call_remote", "reliable")
func _vote() -> void:
	var sender := net.session.player_of_peer(multiplayer.get_remote_sender_id())
	if is_authority() and sender != -1 and in_stage():
		_vote_as(sender)


@rpc("any_peer", "call_remote", "reliable")
func _leave() -> void:
	var sender := net.session.player_of_peer(multiplayer.get_remote_sender_id())
	if not is_authority() or sender == -1 or sender == local_id():
		return
	if in_stage():
		lifecycle.leave(sender)
	for rewards in _runs:
		if rewards.is_settled():
			rewards.mark_left_after_clear(str(sender))
	world.ledger.set_player_present(sender, false)
	world.message_posted.emit(_name(sender) + "が部屋を出ました")
	_broadcast_party()
