class_name CheckpointWatch
extends RefCounted
## チェックポイントの台座の見張り（PartyDirector が権威として毎フレーム呼ぶ。進行役のファイルを短く保つために
## 分けた。中身は元の PartyDirector._check_checkpoints のまま）。


## チェックポイントの台座に乗った人を調べ、チーム共通のチェックポイントにする（権威が毎フレーム）。
## 詰みにつながる状態（自分で一歩も歩けない・空中・ジャンプを遠くへ貸したまま）では有効にしない
## （2026-11-20 試遊 F4・F8）。理由が変わったとき・台座に乗り直したときだけ伝える。変わったら true。
static func check(d: PartyDirector) -> bool:
	var world := d.world
	var changed := false
	for player_id in d.lifecycle.players_in(PartyLifecycle.State.ACTIVE):
		var avatar := world.avatar_of(player_id)
		var cp := "" if avatar == null else world.checkpoint_at(avatar.global_position)
		if cp == "":
			d._warned_checkpoint.erase(player_id)
		elif d.lifecycle.activated_checkpoints().has(cp):
			# もう有効なチェックポイント。台座の上で能力を貸しても「できません」と言わない（何もしていないのに
			# 断られたように読めた。2026-11-22 の通し）
			continue
		elif not _save_blockers(world, player_id, avatar).is_empty():
			_warn_unsafe_checkpoint(d, player_id, avatar)
			continue
		if cp != "" and d.lifecycle.activate_checkpoint(player_id, cp):
			d._snapshots[cp] = d._capture()
			world.message_posted.emit(activated_text(world.ledger.players().size()))
			world.sound_requested.emit(&"save", Vector3.ZERO, false)
			changed = true
	return changed


## 台座に乗って有効にしたときの知らせ。ひとりなら「チーム」「全員復活」を言わない。
static func activated_text(players: int) -> String:
	if players <= 1:
		return "チェックポイント: 落ちたらここから"
	return "チェックポイントがチーム共通になりました（台座で %s: 全員復活）" % InputMode.token(&"interact")


static func _save_blockers(
	world: StageWorld, player_id: int, avatar: PlayerAvatar
) -> Array[CheckpointPolicy.Blocker]:
	var on_floor := avatar.is_on_floor() if avatar == world.player else avatar.remote_on_floor
	return CheckpointPolicy.save_blockers(world.ledger, on_floor, 0, player_id)


static func _warn_unsafe_checkpoint(d: PartyDirector, player_id: int, avatar: PlayerAvatar) -> void:
	var blockers := _save_blockers(d.world, player_id, avatar)
	if blockers.is_empty() or blockers[0] == CheckpointPolicy.Blocker.AIRBORNE:
		return
	if d._warned_checkpoint.get(player_id, -1) == blockers[0]:
		return
	d._warned_checkpoint[player_id] = blockers[0]
	d.world.message_posted.emit("チェックポイントにできません（%s）" % CheckpointPolicy.describe(blockers[0]))
