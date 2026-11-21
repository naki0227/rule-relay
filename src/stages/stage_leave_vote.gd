class_name StageLeaveVote
extends RefCounted
## メニューの「広場へもどる」（docs/adr/0018。PartyDirector が持ち、権威だけが数える）。
## - ひとりなら 1 票ですぐ戻る
## - 協力中は投票。母数と過半数は全員リセットの投票と同じ（PartyLifecycle.eligible_voters・majority_of）。
##   揃ったら全員で、入ったステージのポータルの前へ戻る（PortalReturn）
## - 開いてから全員リセットの投票と同じ秒数（PartyLifecycle.vote_time_limit）で閉じる
## - クリアした後は数えない（お祝いのあとに自動で戻る）
## 自由な遊びは止めない（投票しない人は何も変わらない。ステージの中のルールにも触らない）。

enum Result { IGNORED, OPENED, COUNTED, PASSED }

## 賛成した人
var votes: Dictionary[int, bool] = {}
var seconds_left: float = 0.0


## 1 票入れる。voters は母数（eligible_voters）。
func cast(player_id: int, voters: PackedInt32Array, time_limit: float) -> Result:
	if not voters.has(player_id):
		return Result.IGNORED
	var opened := votes.is_empty()
	votes[player_id] = true
	var tally := counts(voters)
	if tally.x >= tally.y:
		votes.clear()
		return Result.PASSED
	if opened:
		seconds_left = time_limit
		return Result.OPENED
	return Result.COUNTED


## 賛成の数と、成立に要る数（投票していなければ 0 / 0）。
func counts(voters: PackedInt32Array) -> Vector2i:
	if votes.is_empty():
		return Vector2i.ZERO
	var yes := 0
	for player_id in voters:
		if votes.has(player_id):
			yes += 1
	return Vector2i(yes, PartyLifecycle.majority_of(voters.size()))


## 時間を進める。時間切れで閉じたら true。
func tick(delta: float) -> bool:
	if votes.is_empty():
		return false
	seconds_left -= delta
	if seconds_left > 0.0:
		return false
	votes.clear()
	return true


## 権威: player_id の票を数え、知らせを出し、揃ったら全員で広場へ戻る。
static func vote(director: PartyDirector, player_id: int) -> void:
	if not director.in_stage() or director.is_cleared():
		return
	var voters := director.lifecycle.eligible_voters()
	var result := director.leave_vote.cast(player_id, voters, director.lifecycle.vote_time_limit)
	if result == Result.IGNORED:
		return
	if result == Result.PASSED:
		director.tell_everyone("広場へもどります")
		director.enter_stage(StageCatalog.HUB_ID)
		return
	if result == Result.OPENED:
		director.notice_everyone()
	var tally := director.leave_vote.counts(voters)
	director.tell_everyone(
		(
			"広場へもどる投票 %d / %d（%s メニューの「広場へもどる」で賛成）"
			% [tally.x, tally.y, InputMode.token(&"restore_checkpoint")]
		)
	)
