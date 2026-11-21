class_name DirectorHandover
extends RefCounted
## ホスト移譲のときの、進行役（PartyDirector）の状態の書き出しと引き継ぎ（docs/adr/0010）。
## PartyDirector.export_state / adopt_state から呼ぶ（進行役のファイルを短く保つために分けた。中身は元のまま）。


## 進行の状態をまるごと書き出す（ホストが参加者へ定期的に配る）。
static func export(d: PartyDirector) -> Dictionary:
	var runs: Array[Dictionary] = []
	for rewards in d._runs:
		runs.append(rewards.to_dict())
	return {
		"stage_id": d.stage_id,
		"run_id": d.stage_run_id,
		"world": WorldSnapshot.capture(d.world),
		"loadout": d.loadout.capture_state() if d.loadout != null else {},
		"lifecycle": d.lifecycle.to_dict(),
		"snapshots": d._snapshots,
		"tracker": d.tracker.to_dict(),
		"allow_prohibition_to_player": d.allow_prohibition_to_player,
		"activated": d.world.activated.duplicate(),
		"overworld": d.overworld_state().to_dict(),
		"runs": runs,
		"host_id": d.local_id(),
	}


## 新しいホストになった自分が、前のホストの最後の状態から続ける。
## 世界を権威として作り直し、台帳・ブロック・進行を戻す（自分のアバターの位置はいまの位置のまま）。
## 前のホストは「通信が切れた人」になる（戻ってくれば同じプレイヤーに戻る）。
static func adopt(d: PartyDirector, state: Dictionary) -> void:
	var here := d.world.player.global_position if d.world != null else Vector3.ZERO
	d.allow_prohibition_to_player = bool(state.get("allow_prohibition_to_player", false))
	# 広場の試遊の設定は前のホストのものを引き継ぐ（クリアの記録は、新しいホストの進行を使う）
	var overworld := OverworldState.from_dict(state.get("overworld", {}) as Dictionary)
	d.all_stages_open = overworld.all_stages_open
	d.all_regions_open = overworld.all_regions_open
	d.all_abilities_unlocked = overworld.all_abilities
	d._build(String(state["stage_id"]), String(state["run_id"]))
	var world := d.world
	WorldSnapshot.apply(world, state["world"] as Dictionary)
	world.player.global_position = here
	world.player.velocity = Vector3.ZERO
	d.loadout = StageLoadout.new(world.def, world.entity_ids)
	if not (state["loadout"] as Dictionary).is_empty():
		d.loadout.restore_state(state["loadout"] as Dictionary)
	var restored := PartyLifecycle.from_dict(state["lifecycle"] as Dictionary)
	d.lifecycle = restored if restored != null else PartyLifecycle.new()
	d._snapshots = state["snapshots"] as Dictionary
	d.tracker.restore(state["tracker"] as Dictionary, world.ledger)
	world.activated = (state.get("activated", PackedStringArray()) as PackedStringArray).duplicate()
	d._runs.clear()
	for data: Dictionary in state["runs"] as Array:
		var rewards := StageRunRewards.from_dict(data)
		if rewards != null:
			d._runs.append(rewards)
	for player_id in world.ledger.players():
		d._known_players[player_id] = true
	# 前のホストも、つなぎ直してくる人も、入ってくるまでは「通信が切れた人」
	if d.in_stage():
		for player_id in d.lifecycle.formal_participants():
			if player_id != d.local_id():
				d.lifecycle.disconnect_player(player_id)
	world.message_posted.emit("あなたがホストになりました")
	d._broadcast_party()
