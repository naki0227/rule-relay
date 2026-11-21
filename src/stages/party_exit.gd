class_name PartyExit
extends RefCounted
## 部屋の出方と、その報酬の扱い（docs/adr/0008・0010、2026-11-21 の v0.2.0 レビュー）。
##
## 本人の確定仕様: 自分で部屋を出た人（退出）は、クリア前ならその回の報酬を受け取らない。意図しない通信切断の人は、
## 部屋が残っている間に戻れば受け取れる。なので、メニューの「ゲームをやめる」を通信切断として扱ってはいけない。
##
## - 参加者がやめる: ホストへ退出を送り、ホストの受け付け（PartyDirector.left_room）を待ってから通信を閉じて終わる。
##   受け付けが LEAVE_TIMEOUT 秒（2 秒）来なくても、待ち続けずに閉じる（ゲームが固まらない）。その場合ホスト側には
##   通信切断として残ることがある（退出が届かなかったのか、ホストが落ちたのか、こちらからは区別できないため）。
## - ホストがやめる: 退出は送らずに通信を閉じる（ホストは自分あての退出を受け付ける相手がいない）。残った人が
##   ホスト移譲で部屋を続け、新しいホストは前のホストを「通信が切れた人」として扱う（PartyDirector.adopt_state）。
##   つまりホストのやめるは通信切断と同じ扱いで、部屋が残っている間に同じ記録の名前で戻れば報酬は届く
##   （ホストの報酬はクリアの瞬間に自分の PC へ入るので、クリア後にやめても失うものはない）。参加者の退出として
##   数えないのは、PartyDirector.leave_room がホスト（権威）では何も送らないから。
## - 1人用: そのまま終わる。

## 退出の受け付けを待つ最長の秒数。
const LEAVE_TIMEOUT: float = 2.0


## 参加者なら退出をホストへ送り、受け付けを待つ（最長 timeout 秒）。受け付けが届いたら true。
## 送らなかった（ホスト・1人用・つながっていない）ときと、時間切れのときは false。
static func leave_and_wait(director: PartyDirector, timeout: float = LEAVE_TIMEOUT) -> bool:
	if director == null or not director.leave_room():
		return false
	var done: Array[bool] = [false]
	var on_left := func() -> void: done[0] = true
	director.left_room.connect(on_left)
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	var tree := director.get_tree()
	while not done[0] and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	director.left_room.disconnect(on_left)
	return done[0]


## メニューの「ゲームをやめる」。参加者は退出を伝えてから、通信を閉じ、finish（既定はゲームの終了）を呼ぶ。
static func quit(director: PartyDirector, finish: Callable) -> void:
	if director != null:
		await leave_and_wait(director)
		if director.net != null:
			director.net.close()
	finish.call()


## クリア時の報酬の状態（player key → StageRunRewards.Status）。present はいま部屋にいる人。
## 自分で出た人（LEFT）はクリア前の退出、通信が切れた人（DISCONNECTED）は報酬の対象に残る。
static func reward_statuses(
	lifecycle: PartyLifecycle, present: PackedInt32Array
) -> Dictionary[String, int]:
	var statuses: Dictionary[String, int] = {}
	for player_id in present:
		statuses[str(player_id)] = reward_status(lifecycle.state_of(player_id))
	for player_id in lifecycle.players_in(PartyLifecycle.State.LEFT):
		statuses[str(player_id)] = StageRunRewards.Status.LEFT_BEFORE_CLEAR
	return statuses


static func reward_status(state: int) -> int:
	match state:
		PartyLifecycle.State.ACTIVE:
			return StageRunRewards.Status.ACTIVE
		PartyLifecycle.State.DEAD_SPECTATING:
			return StageRunRewards.Status.DEAD_SPECTATING
		PartyLifecycle.State.DISCONNECTED:
			return StageRunRewards.Status.DISCONNECTED
		PartyLifecycle.State.WAITING_SPECTATOR:
			return StageRunRewards.Status.WAITING_SPECTATOR
	return StageRunRewards.Status.LEFT_BEFORE_CLEAR


## 抜けた人の手元を置く場所: 地面に立っていればその足もと、空中・谷の上なら最後のチェックポイント
## （無ければ出発点）。誰でも歩いて拾いに行ける場所にする。
static func drop_point(director: PartyDirector, player_id: int) -> Vector3:
	var world := director.world
	var avatar := world.avatar_of(player_id)
	if avatar != null:
		var on_floor := avatar.is_on_floor() if avatar == world.player else avatar.remote_on_floor
		if on_floor and avatar.global_position.y > -0.5:
			return avatar.global_position
	var cp := director.lifecycle.latest_checkpoint()
	if cp != "" and cp != PartyLifecycle.STAGE_START:
		return world.checkpoint_position(cp)
	return world.spawn_for(RuleLedger.PLAYER_ID)
