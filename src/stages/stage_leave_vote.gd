class_name StageLeaveVote
extends RefCounted
## メニューの「このステージから出る」「このステージを最初から」の協力中の投票（docs/adr/0020。PartyDirector が持ち、
## 権威だけが数える）。
## - ひとり・ホストが選んだら投票しない（PartyDirector がその場で全員を動かす。ホストが決める）
## - 参加者が選ぶと投票が開く。母数と過半数は「チェックポイントからやり直す」投票と同じ
##   （PartyLifecycle.eligible_voters・majority_of）。揃ったら全員で、出る（ポータルの前へ）か最初からやり直す
## - 開いてから「チェックポイントからやり直す」投票と同じ秒数（PartyLifecycle.vote_time_limit、30 秒）で閉じる
## - 開いている投票と違う方を選んだら、新しい投票に置き換える（2 つを同時に数えない）
## - クリアした後は数えない（お祝いのあとに自動で戻る）
## 自由な遊びは止めない（投票しない人は何も変わらない。ステージの中のルールにも触らない）。

enum Result { IGNORED, OPENED, COUNTED, PASSED }
enum Action { LEAVE, RESTART }

## 賛成した人
var votes: Dictionary[int, bool] = {}
var seconds_left: float = 0.0
## いま開いている投票の中身
var action: Action = Action.LEAVE


## 1 票入れる。voters は母数（eligible_voters）。
func cast(
	player_id: int, voters: PackedInt32Array, time_limit: float, wanted: Action = Action.LEAVE
) -> Result:
	if not voters.has(player_id):
		return Result.IGNORED
	if not votes.is_empty() and wanted != action:
		votes.clear()  # 違う方を選んだ: 新しい投票に置き換える
	action = wanted
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


func is_open() -> bool:
	return not votes.is_empty()


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


## 投票の名前（知らせに出す）。
static func title(of: Action) -> String:
	return "このステージから出る投票" if of == Action.LEAVE else "このステージを最初からやり直す投票"


## メニューの項目の名前（賛成のしかたの案内に出す）。
static func menu_label(of: Action) -> String:
	return "このステージから出る" if of == Action.LEAVE else "このステージを最初から"


## 権威: 出る・最初からやり直すを全員で行う（ホストが選んだとき・投票が揃ったとき）。
## 最初からは、同じステージを新しい回として作り直す。進行（クリア・報酬・最後に入ったポータル）には触らない
## （enter_stage は進行を書き換えず、報酬はクリアのときだけ配るので）。
static func carry_out(director: PartyDirector, wanted: Action) -> void:
	if not director.in_stage() or director.is_cleared():
		return
	director.leave_vote = StageLeaveVote.new()
	if wanted == Action.LEAVE:
		if director.net != null and director.net.is_online():
			director.tell_everyone("広場へもどります")
		director.enter_stage(StageCatalog.HUB_ID)
	else:
		director.enter_stage(director.stage_id)
		director.tell_everyone("このステージを最初からやり直します")


## 権威: player_id の票を数え、知らせを出し、揃ったら全員で出る・最初からやり直す。
static func vote(director: PartyDirector, player_id: int, wanted: Action) -> void:
	if not director.in_stage() or director.is_cleared():
		return
	var voters := director.lifecycle.eligible_voters()
	var leave_vote := director.leave_vote
	var result := leave_vote.cast(player_id, voters, director.lifecycle.vote_time_limit, wanted)
	if result == Result.IGNORED:
		return
	if result == Result.PASSED:
		director.carry_out(wanted)
		return
	if result == Result.OPENED:
		director.notice_everyone()
	var tally := leave_vote.counts(voters)
	director.tell_everyone(
		"%s %d / %d（メニューの「%s」で賛成）" % [title(wanted), tally.x, tally.y, menu_label(wanted)]
	)
