class_name PartyLifecycle
extends RefCounted
## ステージ1回分の参加者の状態（生存・死亡観戦・途中待機・退出・通信切断）と、共通チェックポイント・
## 全員復活・全員リセット投票を扱う純粋なルール（2026-11-20 引き継ぎ仕様 4.1〜4.3）。
## ノード・物理・通信・能力台帳には触らない。死亡でも蘇生でも RuleLedger は一切動かさない。
## 全員リセットが決まったら参加者の状態だけを切り替え、世界と台帳を戻す指示を
## PartyResetDecision として残す（take_pending_reset）。判断の記録は docs/adr/0007-party-lifecycle.md。
##
## スナップショットの順序（仕様 4.2 の未決点への対応）: チェックポイントのスナップショットは
## activate_checkpoint が true を返したその場で採る。そのとき死亡観戦中の人（players_in(DEAD_SPECTATING)）
## を、死んだ場所に生きている人として記録しない（呼び出し側はチェックポイントの出現位置で記録する）。
## 全員復活はスナップショットを採らず、戻しもしない（蘇生だけ）。

enum State {
	## 正式参加・生存・操作中
	ACTIVE,
	## 正式参加・死亡して味方を観戦中
	DEAD_SPECTATING,
	## ステージの途中で入室し、操作せずに観戦中。投票の母数に入らず、次の全員リセットで合流する
	WAITING_SPECTATOR,
	## 明示的に退出した（参加していない人も LEFT として返す）
	LEFT,
	## 正式参加・意図しない通信切断中（LEFT とは別。報酬の対象に残る）
	DISCONNECTED,
}

## チェックポイントをまだ1つも有効にしていないときの戻り先（ステージに入った時点）
const STAGE_START: String = ""

## 仮（引き継ぎ仕様 7-2）: 一度有効にした古いチェックポイントでも全員復活できる。
## false にすると最新のチェックポイントだけで復活できる。既定はこの定数1か所で変える。
const REVIVE_AT_OLDER_CHECKPOINTS: bool = true
## 仮（7-3）: 死亡観戦者も通常の過半数投票に票を持ち、母数にも入る。
const DEAD_CAN_VOTE: bool = true
## 仮（7-3）: 死亡観戦者がいるとき、生存者全員の賛成でも全員リセットが成立する（過半数と並ぶ経路）。
const SURVIVORS_CAN_RESET_EARLY: bool = true
## 仮（2026-11-20 本人の判断・試遊 G4）: 全員リセットの投票は、開いてからこの秒数で時間切れになる。
## 後から入った票では延びない。時間切れで票は消え、次の V 長押しが新しい投票の提案になる。
const VOTE_TIME_LIMIT: float = 30.0

## 上の仮の既定値。テストや将来の設定で部屋ごとに切り替えられるように変数にしてある。
var revive_at_older_checkpoints: bool = REVIVE_AT_OLDER_CHECKPOINTS
var dead_can_vote: bool = DEAD_CAN_VOTE
var survivors_can_reset_early: bool = SURVIVORS_CAN_RESET_EARLY
var vote_time_limit: float = VOTE_TIME_LIMIT

var _states: Dictionary[int, State] = {}
## 通信切断中の人が、切れる前に生きていたか死んでいたか（再接続で戻す）
var _state_before_disconnect: Dictionary[int, State] = {}
## 有効にしたチェックポイント（有効にした順。重複なし）
var _checkpoints: PackedStringArray = PackedStringArray()
var _vote_open: bool = false
var _yes_votes: Dictionary[int, bool] = {}
## 開いている投票の残り秒数。時刻ではなく残りを持つので、ホスト移譲で別の PC へ渡しても同じ意味になる。
var _vote_seconds_left: float = 0.0
var _reset_count: int = 0
## 人数別補助をいま何人用に組んでいるか（ステージ開始と全員リセットのときだけ変わる）
var _headcount: int = 0
var _pending_reset: PartyResetDecision = null

# --- ステージ開始・入退室 -------------------------------------------------------


## ステージに入る。全員が正式参加・生存になり、チェックポイント・投票は空になる。
## 呼び出し側はここでステージ開始時点のスナップショットを採る（STAGE_START の戻り先）。
func start_stage(player_ids: PackedInt32Array) -> void:
	_states.clear()
	_state_before_disconnect.clear()
	_checkpoints.clear()
	_close_vote()
	_reset_count = 0
	_pending_reset = null
	for id: int in player_ids:
		_states[id] = State.ACTIVE
	_headcount = players_in(State.ACTIVE).size()


## ステージの途中で入室した。操作させずに待機観戦にする。入室だけでは誰も巻き戻さない。
## 新しい人か、明示的に退出していた人だけが対象（退出した人は報酬資格を失っているので待機からやり直す）。
func join(player_id: int) -> bool:
	if _states.has(player_id) and _states[player_id] != State.LEFT:
		return false
	_states[player_id] = State.WAITING_SPECTATOR
	return true


## 明示的な退出。投票は取り消す。正式参加者の退出で操作できる人がいなくなれば自動リセットする。
func leave(player_id: int) -> bool:
	if not _states.has(player_id) or _states[player_id] == State.LEFT:
		return false
	_states[player_id] = State.LEFT
	_state_before_disconnect.erase(player_id)
	_yes_votes.erase(player_id)
	_after_change()
	return true


## 意図しない通信切断。正式参加者は DISCONNECTED（報酬の対象に残る）。
## 待機観戦の人はまだ参加していないので、記録から外す。
func disconnect_player(player_id: int) -> bool:
	var state := state_of(player_id)
	if state == State.WAITING_SPECTATOR:
		_states.erase(player_id)
		return true
	if not _is_formal_present(state):
		return false
	_state_before_disconnect[player_id] = state
	_states[player_id] = State.DISCONNECTED
	_yes_votes.erase(player_id)
	_after_change()
	return true


## 通信切断から戻った。切れる前の生死に戻す（切断中に全員リセットがあれば生存）。
func reconnect(player_id: int) -> bool:
	if state_of(player_id) != State.DISCONNECTED:
		return false
	var before := State.ACTIVE
	if _state_before_disconnect.has(player_id):
		before = _state_before_disconnect[player_id]
	_states[player_id] = before
	_state_before_disconnect.erase(player_id)
	return true


# --- 死亡・チェックポイント・全員復活 -------------------------------------------


## 死亡。死亡観戦にする。貸している能力も手元の能力も台帳では何も変えず、どこへも移さない。
## 操作できる人がいなくなれば（全員死亡・ソロの死亡）、最新のチェックポイントへ自動で全員リセットする。
func die(player_id: int) -> bool:
	if state_of(player_id) != State.ACTIVE:
		return false
	_states[player_id] = State.DEAD_SPECTATING
	_after_change()
	return true


## 生存者がチェックポイントに着いた。1人到達でパーティー共通のチェックポイントになる。
## 初めて有効にしたときだけ true（= 呼び出し側はいまスナップショットを採る）。
## 既に有効なチェックポイントへの再到達は何も変えない（最新の戻り先も変わらない）。
func activate_checkpoint(player_id: int, checkpoint_id: String) -> bool:
	if state_of(player_id) != State.ACTIVE or checkpoint_id == STAGE_START:
		return false
	if _checkpoints.has(checkpoint_id):
		return false
	_checkpoints.append(checkpoint_id)
	return true


## player_id がこのチェックポイントで全員復活を選べるか。
func can_revive_at(player_id: int, checkpoint_id: String) -> bool:
	if state_of(player_id) != State.ACTIVE or not _checkpoints.has(checkpoint_id):
		return false
	return revive_at_older_checkpoints or checkpoint_id == latest_checkpoint()


## 全員復活。死亡観戦中の全員をこのチェックポイントで生存に戻し、戻した人を返す。
## 蘇生だけで、世界・台帳・他の人の位置は何も戻さない（全員リセットとは別の操作）。
## 通信切断中の人は戻さない（再接続すると死亡観戦に戻り、次の全員復活で戻る）。
func revive_all(player_id: int, checkpoint_id: String) -> PackedInt32Array:
	if not can_revive_at(player_id, checkpoint_id):
		return PackedInt32Array()
	var revived := players_in(State.DEAD_SPECTATING)
	for id: int in revived:
		_states[id] = State.ACTIVE
	_evaluate_vote()
	return revived


## 最新の有効なチェックポイント。無ければ STAGE_START。
func latest_checkpoint() -> String:
	return _checkpoints[-1] if not _checkpoints.is_empty() else STAGE_START


## 有効にしたチェックポイント（有効にした順）。
func activated_checkpoints() -> PackedStringArray:
	return _checkpoints.duplicate()


# --- 全員リセット投票 -------------------------------------------------------------


## 全員リセットに賛成する。投票が開いていなければこれが提案になる。同じ人の2回目は数えない。
## 提案・投票できるのは、いま部屋にいる正式参加者（生存・死亡観戦）だけ。
func vote_reset(player_id: int) -> bool:
	if not _is_formal_present(state_of(player_id)):
		return false
	if not _vote_open:
		_vote_seconds_left = vote_time_limit
	_vote_open = true
	_yes_votes[player_id] = true
	_evaluate_vote()
	return true


## 賛成を取り下げる。賛成が誰もいなくなれば投票を閉じる。
func withdraw_vote(player_id: int) -> bool:
	if not _yes_votes.has(player_id):
		return false
	_yes_votes.erase(player_id)
	if _yes_votes.is_empty():
		_close_vote()
	return true


## 投票を打ち切る（時間切れなど）。
func cancel_vote() -> void:
	_close_vote()


func is_vote_open() -> bool:
	return _vote_open


## 開いている投票の残り秒数（閉じていれば 0）。
func vote_seconds_left() -> float:
	return _vote_seconds_left if _vote_open else 0.0


## 投票の残り時間を delta 秒進める。開いている投票の残りが 0 になったら true
## （閉じるのは呼び出し側。権威は cancel_vote して知らせ、参加者は表示を 0 で止めてホストを待つ）。
func tick_vote(delta: float) -> bool:
	if not _vote_open:
		return false
	_vote_seconds_left = maxf(_vote_seconds_left - delta, 0.0)
	return _vote_seconds_left <= 0.0


## いま数えている賛成票（投票権のある人の票だけ）。
func yes_vote_count() -> int:
	var count := 0
	var voters := eligible_voters()
	for id: int in _yes_votes:
		if voters.has(id):
			count += 1
	return count


## 投票の母数。生存者と（dead_can_vote なら）死亡観戦者。途中待機・退出・切断中は入らない。
func eligible_voters() -> PackedInt32Array:
	var voters := players_in(State.ACTIVE)
	if dead_can_vote:
		voters.append_array(players_in(State.DEAD_SPECTATING))
		voters.sort()
	return voters


## いまの母数で成立に必要な票数。
func required_votes() -> int:
	return majority_of(eligible_voters().size())


## 過半数: 1→1、2→2、3→2、4→3。
static func majority_of(voter_count: int) -> int:
	return floori(voter_count / 2.0) + 1


# --- 全員リセットの結果 -----------------------------------------------------------


func has_pending_reset() -> bool:
	return _pending_reset != null


## 決まった全員リセットを受け取る（受け取ると消える）。無ければ null。
## 続けて2回決まった場合は新しい方だけが残る（戻す先の世界は同じ1つのスナップショット）。
func take_pending_reset() -> PartyResetDecision:
	var d := _pending_reset
	_pending_reset = null
	return d


## これまでの全員リセットの回数。
func reset_count() -> int:
	return _reset_count


## 人数別補助をいま何人用に組んでいるか。途中の入退室・蘇生では変わらない（仕様 2-7）。
func headcount() -> int:
	return _headcount


# --- 問い合わせ -------------------------------------------------------------------


func state_of(player_id: int) -> State:
	if _states.has(player_id):
		return _states[player_id]
	return State.LEFT


func has_player(player_id: int) -> bool:
	return _states.has(player_id)


## その状態の人（ID 昇順）。
func players_in(state: State) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for id: int in _states:
		if _states[id] == state:
			ids.append(id)
	ids.sort()
	return ids


## 正式参加者（生存・死亡観戦・通信切断中）。
func formal_participants() -> PackedInt32Array:
	var ids := PackedInt32Array()
	for id: int in _states:
		if _states[id] in [State.ACTIVE, State.DEAD_SPECTATING, State.DISCONNECTED]:
			ids.append(id)
	ids.sort()
	return ids


## いまステージがクリアされたら報酬・進行の対象になる人（仕様 5.2 の真理値表）。
## 生存・死亡観戦・通信切断中は対象、途中待機と明示的な退出は対象外。
func reward_eligible_players() -> PackedInt32Array:
	return formal_participants()


# --- 保存（ホスト移譲用） ---------------------------------------------------------


func to_dict() -> Dictionary:
	var players: Array[Dictionary] = []
	for id: int in _states:
		var entry := {"id": id, "state": _states[id]}
		entry["before_disconnect"] = int(_state_before_disconnect.get(id, -1))
		players.append(entry)
	var votes := PackedInt32Array(_yes_votes.keys())
	votes.sort()
	return {
		"players": players,
		"checkpoints": _checkpoints.duplicate(),
		"vote_open": _vote_open,
		"vote_seconds_left": _vote_seconds_left,
		"yes_votes": votes,
		"reset_count": _reset_count,
		"headcount": _headcount,
		"pending_reset": _pending_reset.to_dict() if _pending_reset != null else {},
	}


## to_dict() の状態を復元する。仮の設定（revive_at_older_checkpoints など）は保存しない。
static func from_dict(data: Dictionary) -> PartyLifecycle:
	var lc := PartyLifecycle.new()
	for d: Dictionary in data["players"] as Array:
		var id := int(d["id"])
		lc._states[id] = int(d["state"]) as State
		var before := int(d["before_disconnect"])
		if before >= 0:
			lc._state_before_disconnect[id] = before as State
	lc._checkpoints = PackedStringArray(data["checkpoints"])
	lc._vote_open = bool(data["vote_open"])
	lc._vote_seconds_left = float(data.get("vote_seconds_left", VOTE_TIME_LIMIT))
	for id: int in PackedInt32Array(data["yes_votes"]):
		lc._yes_votes[id] = true
	lc._reset_count = int(data["reset_count"])
	lc._headcount = int(data["headcount"])
	var pending := data["pending_reset"] as Dictionary
	if not pending.is_empty():
		lc._pending_reset = PartyResetDecision.from_dict(pending)
	return lc


# --- 内部 ---------------------------------------------------------------------------


func _is_formal_present(state: State) -> bool:
	return state == State.ACTIVE or state == State.DEAD_SPECTATING


## 状態が変わった後の判定。操作できる人がいなくなったら投票を待たずに自動リセットする。
## 仮（7-2・4.3）: 生存者が0人で、死亡観戦か途中待機の人が部屋にいれば戻す
## （正式参加者が全員抜けて待機の人だけが残った場合も、待機の人を合流させて戻す）。
func _after_change() -> void:
	var waiting := players_in(State.WAITING_SPECTATOR).size()
	var someone_here := players_in(State.DEAD_SPECTATING).size() + waiting > 0
	if players_in(State.ACTIVE).is_empty() and someone_here:
		_full_reset(PartyResetDecision.Reason.NO_ONE_ALIVE)
		return
	_evaluate_vote()


func _evaluate_vote() -> void:
	if not _vote_open:
		return
	if yes_vote_count() >= required_votes():
		_full_reset(PartyResetDecision.Reason.MAJORITY)
	elif survivors_can_reset_early and _survivors_all_agree():
		_full_reset(PartyResetDecision.Reason.SURVIVORS_AGREED)


## 死亡観戦者がいて、生存者が1人以上いて、生存者全員が賛成している。
func _survivors_all_agree() -> bool:
	var alive := players_in(State.ACTIVE)
	if alive.is_empty() or players_in(State.DEAD_SPECTATING).is_empty():
		return false
	for id: int in alive:
		if not _yes_votes.has(id):
			return false
	return true


## 全員リセットを決める。部屋にいる正式参加者と途中待機の人を全員生存にし、
## 切断中の人は戻ったとき生存になるようにする。世界と台帳は呼び出し側が戻す。
func _full_reset(reason: PartyResetDecision.Reason) -> void:
	var d := PartyResetDecision.new()
	d.reason = reason
	d.checkpoint_id = latest_checkpoint()
	d.joined_player_ids = players_in(State.WAITING_SPECTATOR)
	for id: int in _states.keys():
		var state: State = _states[id]
		if _is_formal_present(state) or state == State.WAITING_SPECTATOR:
			_states[id] = State.ACTIVE
	for id: int in _state_before_disconnect.keys():
		_state_before_disconnect[id] = State.ACTIVE
	_close_vote()
	_reset_count += 1
	d.generation = _reset_count
	d.previous_headcount = _headcount
	d.active_player_ids = players_in(State.ACTIVE)
	_headcount = d.active_player_ids.size()
	d.headcount = _headcount
	_pending_reset = d


func _close_vote() -> void:
	_vote_open = false
	_vote_seconds_left = 0.0
	_yes_votes.clear()
