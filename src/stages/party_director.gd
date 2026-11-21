class_name PartyDirector
extends Node
## ハブとステージの進行役（引き継ぎ仕様 2・4・5。docs/adr/0010）。1人用でもオンラインでも同じ仕組み。
## ルールを決めるのは「権威」（1人用なら自分、オンラインならホスト）。参加者はホストから届く
## ステージ・チーム進行の状態を表示し、操作（投票・退出・報酬の受け取り）をホストへ送る。
##
## - ステージに入る: StageWorld を組み立て、開始時の持ち物と人数別補助を置き、開始時点を記録する
## - 死亡: 落ちたら死亡観戦（台帳はそのまま。貸したものも手元のものも残る）。1人用・全滅は自動で戻る
## - チェックポイント: 1人が触れたらチーム共通。その時点の世界を記録する。台座の上の F で全員復活
## - チェックポイントからやり直す（全員リセット）: V 長押し・メニューで投票（過半数、または死亡観戦がいるとき
##   生存者全員）。成立したら世界を丸ごと戻し、
##   途中参加の人を合流させ、人数が変わっていれば人数別補助を作り直す
## - 投票の時間切れ: 開いた投票は PartyLifecycle.VOTE_TIME_LIMIT 秒（仮 30 秒）で権威が閉じる（試遊 G4）
## - 投票の始まりと時間切れは、全員の画面でお知らせの音（ui_notice）を鳴らす
## - ゴールにまだ来ていない人: 協力中、島の条件がそろうか誰かがゴールに入ったら HUD に名前を出す
##   （試遊 G5。情報だけで、外したり止めたりはしない）
## - クリア: ステージのクリア条件を満たしたら、資格のある人に報酬を配り、しばらくしてハブへ戻る
## - 広場へ戻ると、入ったステージのポータルの前に立つ（PortalReturn）。メニューの「このステージから出る」
##   「このステージを最初から」は、ひとり・ホストならすぐ全員で、参加者は投票（StageLeaveVote）。
##   最初からは、この回の世界だけを作り直す（進行・報酬には触らない）。目的の一覧の進み具合はホストが数えて配る
##   （docs/adr/0020）
## 子ノード名は固定（"Director"）。RPC のパスを両側でそろえるため。

signal world_changed(world: StageWorld)
## チーム進行の状態が変わった（HUD の表示用）。
signal party_changed
## 参加者: 部屋を出たことをホストが受け付けた（PartyExit が待つ。届いてから通信を閉じる）。
signal left_room

## クリアしてからハブへ戻るまでの秒数。
const RETURN_DELAY: float = 4.0
## 全員リセット（V 長押し・メニューの「チェックポイントからやり直す」）の投票の、画面での呼び名（docs/adr/0020）。
const RESET_VOTE_TITLE := "チェックポイントからやり直す投票"

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
## ゴールにまだ来ていない生きている人（ホストが決めて party の配信で参加者へも届く。HUD の表示用）。
var goal_missing: PackedInt32Array = PackedInt32Array()
## ステージの目的の一覧（StageObjectives。広場では空）。進み具合はホストが数え、参加者へは party で届く。
var objectives: Array[StageObjectives.Item] = []
## 広場へ戻ったときの立ち位置（入ったステージのポータルの前）と、メニューの「広場へもどる」の投票。
var portal_return: PortalReturn = PortalReturn.new()
var leave_vote: StageLeaveVote = StageLeaveVote.new()
## ステージの島を置く親（既定は自分。物理の世界を分けたいときは SubViewport を渡す）。
var world_parent: Node
## ハブの入口を最初から全部開けておく（試遊の版。本人が全部を順に試せるように）。
## 製品版では false にして、目安時間の短い順に、前のステージをクリアしたら次が開く（2026-11-20 本人の判断）。
var all_stages_open: bool = true
## 広場の地方を最初から全部つなぐ（試遊の版・デバッグ。橋と階段を全部出し、岩をどける。docs/adr/0013）。
## 製品版では false にして、ワールドの最後のステージをクリアすると次の地方への道が開く。
var all_regions_open: bool = true
## デバッグ: 広場で使える能力を全部持たせる（ふだんはクリアで開いた分だけ。コマンドラインの --open-all）。
var all_abilities_unlocked: bool = false
## 部屋のオプション: 禁止をプレイヤーへ直接渡せる（ホストが部屋を作るときに選ぶ。既定は渡せない）。
var allow_prohibition_to_player: bool = false
## 寄り道の入口の発見を届けた人（ワールドの id → {プレイヤー: true}。OptionalSecrets が使う）。
var secrets_told: Dictionary[String, Dictionary] = {}

## 参加者: ホストから届いた広場の様子（OverworldState.to_dict）。協力中はホストの進行で広場が決まる。
var _remote_overworld: Dictionary = {}
## チェックポイント ID → その時点の記録 {"world": WorldSnapshot, "loadout": StageLoadout の状態}
var _snapshots: Dictionary = {}
var _run_serial: int = 0
var _clear_timer: float = -1.0
## 報酬を配った回（再接続した人へ後から渡すため、部屋がある間は残す）。
var _runs: Array[StageRunRewards] = []
## 一度でもこの部屋に来たプレイヤー（初めて来たときだけ出現地点へ動かす。再接続・ホスト移譲では動かさない）。
var _known_players: Dictionary[int, bool] = {}
## 「チェックポイントにできない」を一度伝えた人（台座の上で毎フレーム出さないため）。
var _warned_checkpoint: Dictionary[int, int] = {}
## 目的の一覧の数（StageObjectives.measure の形）。変わったら配る。
var _objective_counts: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	name = "Director"
	var loaded := store.load_progress(profile)
	progress = loaded.progress
	portal_return.portal = progress.last_portal()


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
	var from_stage := in_stage()
	var first_visit := world == null
	_run_serial += 1
	var run_id := "%s#%d-%d" % [new_stage_id, Time.get_unix_time_from_system(), _run_serial]
	_build(new_stage_id, run_id)
	# ステージから出てきた（または起動して最初の広場）なら、入ったステージのポータルの前へ
	portal_return.choose(world.def, from_stage, first_visit)
	if in_stage() and portal_return.remember(new_stage_id, progress):
		store.save(profile, progress)
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
	# 先にステージを組み立てさせてから出現地点へ動かす（逆だと参加者の新しい世界では、
	# 古い世界へ届いた移動が失われ、全員が1人目の出現地点に重なる）
	if _online():
		_enter.rpc(new_stage_id, run_id, overworld_state().to_dict())
	for player_id in players:
		_teleport(player_id, arrival_for(player_id), portal_return.yaw)
	_broadcast_party()


## その人が広場・ステージで立つ場所（広場でポータルの前に戻ったなら、出現地点と同じ並びでその前）。
func arrival_for(player_id: int) -> Vector3:
	var spawn := world.spawn_for(player_id)
	return spawn if in_stage() else portal_return.spot_for(player_id, spawn)


## クリアして、広場へ戻るのを待っているか。
func is_cleared() -> bool:
	return _clear_timer >= 0.0


func _build(new_stage_id: String, run_id: String) -> void:
	var me := local_id()
	if world != null:
		world.queue_free()
		world.name = "Leaving"
	stage_id = new_stage_id
	stage_run_id = run_id
	last_clear_text = ""
	goal_missing = PackedInt32Array()
	leave_vote = StageLeaveVote.new()
	world = StageWorld.new()
	world.setup(_def_for(new_stage_id))
	objectives = StageObjectives.build(world.def)
	_objective_counts = PackedInt32Array()
	world.vote_request = request_vote
	world.restart_request = request_restart
	world.ledger.allow_prohibition_to_player = allow_prohibition_to_player
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
			func(player_id: int) -> void: _teleport(player_id, arrival_for(player_id))
		)
		world.ledger.changed.connect(func() -> void: tracker.observe(world.ledger))
	world.message_posted.emit(
		(
			"%s に来ました" % world.def.display_name
			if in_stage()
			else "広場: ポータルで %s を押すとステージへ" % InputMode.token(&"interact")
		)
	)
	world_changed.emit(world)


## 次のステージに連れていく人（参加中の全員。1人用なら自分だけ）。
func _present_players() -> PackedInt32Array:
	if world == null:
		return PackedInt32Array([RuleLedger.PLAYER_ID])
	return world.ledger.players()


func _on_entrance_chosen(_player_id: int, chosen: String) -> void:
	if in_stage():
		return
	if portal_return.blocks(chosen):
		return  # 戻ったばかりのポータル（クリアの直後の連打で、また入らないように）
	var state := overworld_state()
	if not state.is_stage_open(chosen):
		world.message_posted.emit(CampaignPlan.lock_reason(chosen, state.cleared, state.found))
		return
	enter_stage(chosen)


## 広場の様子を決める入力。権威（1人用・ホスト）は自分の進行と試遊の設定から作り、参加者はホストから
## 届いたものを使う（協力中の広場はホストの進行で決まる。docs/adr/0013）。
func overworld_state() -> OverworldState:
	if not is_authority():
		return OverworldState.from_dict(_remote_overworld)
	return OverworldState.of(
		progress.cleared_stages(),
		all_stages_open,
		all_regions_open,
		all_abilities_unlocked,
		progress.found_secrets()
	)


## ステージの定義。広場だけは、いまの進行から組み立てる。
func _def_for(new_stage_id: String) -> StageDef:
	if new_stage_id == StageCatalog.HUB_ID:
		return Overworld.build(overworld_state())
	return StageCatalog.by_id(new_stage_id)


# --- 毎フレーム（権威） --------------------------------------------------------


func _physics_process(delta: float) -> void:
	if world == null:
		return
	_update_spectate()
	if not is_authority():
		if in_stage():
			lifecycle.tick_vote(delta)  # 表示用に残り秒数だけ進める（閉じるのはホスト）
		return
	if _clear_timer >= 0.0:
		_clear_timer -= delta
		if _clear_timer < 0.0:
			enter_stage(StageCatalog.HUB_ID)
		return
	if not in_stage():
		portal_return.tick(delta)
		_rescue_in_hub()
		OptionalSecrets.check(self)  # 寄り道のワールドの秘密の入口（docs/campaign-plan.md）
		return
	tracker.seconds += delta
	# 時間切れを死亡より先に見る（切れた票が、同じコマの死亡で成立しないように）
	var changed := _check_vote_timeout(delta)
	if leave_vote.tick(delta):
		tell_everyone(StageLeaveVote.title(leave_vote.action) + "は時間切れになりました")
	changed = _check_deaths() or changed
	changed = _check_checkpoints() or changed
	if lifecycle.has_pending_reset():
		_apply_reset(lifecycle.take_pending_reset())
		changed = true
	changed = _check_clear() or changed
	if changed:
		_broadcast_party()


## 全員リセットの投票の時間切れ（試遊 G4、2026-11-20 本人の判断）。権威だけが閉じて知らせる。
func _check_vote_timeout(delta: float) -> bool:
	if not lifecycle.tick_vote(delta):
		return false
	lifecycle.cancel_vote()
	world.message_posted.emit(RESET_VOTE_TITLE + "は時間切れになりました")
	notice_everyone()
	return true


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
	return CheckpointWatch.check(self)


## クリアを調べ、ゴールにまだ来ていない人の一覧も更新する。一覧が変わったら true（配信する）。
## 一覧はひとり（1人用・部屋に正式参加者が1人）では出さず、クリアしたら空にする。
func _check_clear() -> bool:
	var snapshot := world.clear_snapshot(
		lifecycle.formal_participants(), lifecycle.players_in(PartyLifecycle.State.ACTIVE)
	)
	var missing := PackedInt32Array()
	var counts := StageObjectives.measure(objectives, snapshot)
	var counts_changed := counts != _objective_counts
	_objective_counts = counts
	if world.def.clear_condition.is_met(snapshot):
		_on_clear()
	elif net != null and lifecycle.formal_participants().size() > 1:
		missing = world.def.clear_condition.goal_stragglers(snapshot)
	if missing == goal_missing:
		return counts_changed
	goal_missing = missing
	return true


## HUD の「ゴールにまだ来ていない: …」の文。出さないときは空。
func goal_missing_text() -> String:
	if goal_missing.is_empty() or last_clear_text != "" or not in_stage():
		return ""
	var names := PackedStringArray()
	for player_id in goal_missing:
		names.append(_name(player_id))
	return "ゴールにまだ来ていない: " + "、".join(names)


## ハブで落ちたら出現地点へ戻すだけ（ハブに死亡はない）。
func _rescue_in_hub() -> void:
	for player_id in world.ledger.players():
		var avatar := world.avatar_of(player_id)
		if avatar != null and avatar.global_position.y < Tuning.FALL_LIMIT_Y:
			_teleport(player_id, arrival_for(player_id), portal_return.yaw)


# --- このステージから出る・最初から ------------------------------------------


## メニューの「このステージから出る」。ひとり・ホストならすぐ全員で、入ったステージのポータルの前へ戻る。
## 参加者はホストへ送り、投票になる（過半数。「チェックポイントからやり直す」と同じ母数・30 秒）。
func request_leave_stage() -> void:
	_request_stage_action(StageLeaveVote.Action.LEAVE)


## ホスト・ひとりはすぐ実行、参加者は投票（StageLeaveVote）。
func _request_stage_action(action: StageLeaveVote.Action) -> void:
	if not in_stage() or is_cleared():
		return
	if is_authority():
		carry_out(action)
	else:
		_vote_stage_action.rpc_id(1, int(action))


## 権威: 出る・最初からやり直すを全員で行う（StageLeaveVote.carry_out）。
func carry_out(action: StageLeaveVote.Action) -> void:
	StageLeaveVote.carry_out(self, action)


## 全員の画面に知らせる（権威の知らせを参加者にも出す）。
func tell_everyone(text: String) -> void:
	world.message_posted.emit(text)
	if _online() and net.is_host():
		_say.rpc(text)


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


## メニューの「このステージを最初から」: ひとり・ホストなら、このステージに入ったときの状態から全員でやり直す。
## 参加者は投票（StageLeaveVote）。進行と報酬はそのまま。
func request_restart() -> void:
	_request_stage_action(StageLeaveVote.Action.RESTART)


## V 長押し・メニューの「チェックポイントからやり直す」: 全員リセットの投票（無ければ提案）。参加者はホストへ送る。
## 票には「見ていたリセットの回数」を添える。同時に届いた票の途中でリセットが決まったとき、
## 残りの票が次の投票の提案として数えられないようにするため。
func request_vote() -> void:
	if not in_stage():
		return
	if is_authority():
		_vote_as(local_id(), lifecycle.reset_count())
	else:
		_vote.rpc_id(1, lifecycle.reset_count())


func _vote_as(player_id: int, seen_resets: int) -> void:
	if seen_resets < lifecycle.reset_count():
		return  # 賛成したリセットはもう決まった
	var was_open := lifecycle.is_vote_open()
	if lifecycle.vote_reset(player_id):
		# 新しく開いた投票だけ知らせる（2票目以降と、1票でその場で決まったときは鳴らさない）
		if not was_open and lifecycle.is_vote_open():
			notice_everyone()
		world.message_posted.emit(
			(
				"%s %d / %d（%s 長押しで賛成）"
				% [
					RESET_VOTE_TITLE,
					lifecycle.yes_vote_count(),
					lifecycle.required_votes(),
					InputMode.token(&"vote_reset")
				]
			)
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
	# いない人（抜けた・通信が切れたまま）の手元は、戻った先のチェックポイントに置く（拾える）
	for player_id in world.ledger.players():
		if not decision.active_player_ids.has(player_id):
			world.ledger.set_player_present(player_id, false, at)
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
	var statuses := PartyExit.reward_statuses(lifecycle, world.ledger.players())
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


func _show_clear(text: String) -> void:
	last_clear_text = text
	if world.player != null:
		world.player.celebrate()
	for player_id: int in world.avatars:
		world.avatars[player_id].celebrate()
	world.message_posted.emit(text)
	world.sound_requested.emit(&"goal", Vector3.ZERO, false)
	world.goal_reached.emit()


## まだ受け取っていない報酬を、つながっている人へ配る（再接続した人にも、部屋がある間は渡す）。
func deliver_rewards() -> void:
	if not is_authority():
		return
	var connected := PackedStringArray()
	for player_id in connected_players():
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


## いまつながっている人（自分を含む。1人用なら自分だけ）。報酬と寄り道の入口の発見を届ける相手。
func connected_players() -> PackedInt32Array:
	var result := PackedInt32Array([local_id()])
	if _online():
		for player_id in world.ledger.players():
			if player_id != local_id() and net.session.peer_of_player(player_id) != -1:
				result.append(player_id)
	return result


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
	return DirectorHandover.export(self)


## ホスト移譲: 新しいホストになった自分が、前のホストの最後の状態から続ける（DirectorHandover.adopt）。
func adopt_state(state: Dictionary) -> void:
	DirectorHandover.adopt(self, state)


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
		_enter.rpc_id(
			net.session.peer_of_player(player_id),
			stage_id,
			stage_run_id,
			overworld_state().to_dict()
		)
	if in_stage():
		if (
			not lifecycle.has_player(player_id)
			or lifecycle.state_of(player_id) == PartyLifecycle.State.LEFT
		):
			lifecycle.join(player_id)
			world.message_posted.emit(_name(player_id) + "が来ました（次にチェックポイントからやり直すと合流）")
		else:
			lifecycle.reconnect(player_id)
	if not _known_players.has(player_id):
		_known_players[player_id] = true
		_teleport(player_id, arrival_for(player_id), portal_return.yaw)
	_broadcast_party()
	deliver_rewards()


func _on_player_disconnected(player_id: int) -> void:
	if not world.ledger.players().has(player_id):
		return  # 自分で部屋を出た後に通信を閉じただけ（退出のまま。報酬の扱いは変えない）
	if in_stage():
		lifecycle.disconnect_player(player_id)
	world.message_posted.emit(_name(player_id) + "の通信が切れました（部屋があるうちに戻れば、報酬は届きます）")
	_broadcast_party()


## 部屋を出る（明示的な退出。クリア前ならその回の報酬は受け取らない）。参加者だけが送れる。
## 送ったら true。ホストの受け付けは left_room で届く（メニューの「やめる」は PartyExit で待ってから閉じる）。
func leave_room() -> bool:
	if not _online() or is_authority():
		return false
	_leave.rpc_id(1)
	return true


func _broadcast_party() -> void:
	party_changed.emit()
	if _online() and net.is_host():
		_party.rpc(lifecycle.to_dict(), goal_missing, _objective_counts)


## 全員に関わるお知らせの音（投票の開始・時間切れ）。権威が鳴らし、参加者の画面へも頼む。
## 投票の文言はホストにしか出ないが、参加者は札（PartyBanner）で投票を見ているので、音だけを送る。
func notice_everyone() -> void:
	world.sound_requested.emit(&"ui_notice", Vector3.ZERO, false)
	if _online() and net.is_host():
		_notice_sound.rpc()


## 権威がプレイヤーを動かす。自分ならその場で、仲間ならその人の画面へ頼む（アバターは各自が動かすため）。
## yaw があれば（NAN でなければ）、その向きに体と視点を向ける（ポータルの前に戻ったとき）。
func _teleport(player_id: int, at: Vector3, yaw: float = NAN) -> void:
	if player_id == local_id():
		world.player.global_position = at
		world.player.velocity = Vector3.ZERO
		PortalReturn.face(world, yaw)
		return
	var avatar := world.avatar_of(player_id)
	if avatar != null:
		avatar.global_position = at
		avatar.apply_remote(at, avatar.remote_yaw, false, true)
	if _online() and net.session.peer_of_player(player_id) != -1:
		_moved.rpc_id(net.session.peer_of_player(player_id), at, yaw)


func _online() -> bool:
	return net != null and net.is_online()


func _name(player_id: int) -> String:
	return "あなた" if player_id == local_id() else "プレイヤー%d" % player_id


@rpc("authority", "call_remote", "reliable")
func _enter(new_stage_id: String, run_id: String, overworld: Dictionary) -> void:
	if StageCatalog.by_id(new_stage_id) == null:
		return
	_remote_overworld = overworld
	if new_stage_id != stage_id or run_id != stage_run_id or world == null:
		_build(new_stage_id, run_id)
		lifecycle = PartyLifecycle.new()
		party_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _party(state: Dictionary, missing: PackedInt32Array, counts: PackedInt32Array) -> void:
	var replica := PartyLifecycle.from_dict(state)
	if replica != null:
		lifecycle = replica
		goal_missing = missing
		_objective_counts = counts
		StageObjectives.apply(objectives, counts)
		party_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _say(text: String) -> void:
	if world != null:
		world.message_posted.emit(text)


@rpc("authority", "call_remote", "reliable")
func _notice_sound() -> void:
	if world != null:
		world.sound_requested.emit(&"ui_notice", Vector3.ZERO, false)


@rpc("authority", "call_remote", "reliable")
func _moved(at: Vector3, yaw: float) -> void:
	if world != null and world.player != null:
		world.player.global_position = at
		world.player.velocity = Vector3.ZERO
		PortalReturn.face(world, yaw)


@rpc("authority", "call_remote", "reliable")
func _cleared(text: String) -> void:
	if world != null:
		_show_clear(text)


@rpc("authority", "call_remote", "reliable")
func _left() -> void:
	left_room.emit()


## 寄り道のワールドの入口の発見（ホストから、その場にいた人へ。何度届いても同じ）。
@rpc("authority", "call_remote", "reliable")
func _secret(world_id: String) -> void:
	if world != null and CampaignPlan.world(world_id) != null:
		OptionalSecrets.record(self, world_id)


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
func _vote(seen_resets: int) -> void:
	var sender := net.session.player_of_peer(multiplayer.get_remote_sender_id())
	if is_authority() and sender != -1 and in_stage():
		_vote_as(sender, seen_resets)


@rpc("any_peer", "call_remote", "reliable")
func _vote_stage_action(action: int) -> void:
	var sender := net.session.player_of_peer(multiplayer.get_remote_sender_id())
	if is_authority() and sender != -1 and in_stage() and action in StageLeaveVote.Action.values():
		StageLeaveVote.vote(self, sender, action as StageLeaveVote.Action)


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
	var drop_at := PartyExit.drop_point(self, sender)
	world.ledger.set_player_present(sender, false, drop_at)
	world.message_posted.emit(_name(sender) + "が部屋を出ました（持っていた物はその場に落ちています）")
	if in_stage():
		world.message_posted.emit(
			"人数が変わりました。%s 長押しで、今の人数に合わせてやり直せます" % InputMode.token(&"vote_reset")
		)
	_broadcast_party()
	_left.rpc_id(multiplayer.get_remote_sender_id())  # 受け付けた（参加者はこれを待ってから閉じる）
