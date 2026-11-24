class_name WorldSnapshot
extends RefCounted
## チェックポイント用に、世界をまるごと記録・復元する（企画書 9）。GameWorld から切り出した。
## 記録するもの: 能力と器の所有（台帳）、プレイヤーの位置、ブロックの位置・速度・移動と周期の途中、
## 生き物、鐘の鳴っている残り時間、発射台の周期、選んでいる枠と付与方式、到達済みか。
## 自然の仕掛けの時計と、ブロック・器を運ぶ途中の経過時間（NatureField.to_dict）も残す。
## 飛んでいる途中の玉と、ブロックの W/A/S/D の予約（BlockMoveBuffer）は記録しない（復元したら消える）。
## 投げたメダル（ThrownMedal）も記録しない。飛んでいる間も能力は手元にあるので、復元すると手元に戻っている。


static func capture(w: GameWorld) -> Dictionary:
	var block_states := {}
	for id in w.blocks:
		var state := w.blocks[id].capture_state()
		state["cursor"] = w._repeat_cursors[id].get_index()
		state["timer"] = w._repeat_timers[id]
		state["signal_cursor"] = w._signal_cursors[id].get_index()
		state["signal_timer"] = w._signal_timers[id]
		block_states[id] = state
	var creature_states := {}
	for id in w.creatures:
		creature_states[id] = w.creatures[id].capture_state()
	var bell_states: Array[Dictionary] = []
	for bell in w.bells:
		bell_states.append(bell.capture_state())
	return {
		"promoted": w.promoted.duplicate(),
		"ledger": w.ledger.snapshot(),
		"creatures": creature_states,
		"bells": bell_states,
		"launch_timers": w._launch_timers.duplicate(),
		"player_position": w.player.global_position,
		"blocks": block_states,
		"selected_slot": w.selected_slot,
		"lend_mode": w.lend_mode,
		"goal_cleared": w.goal_cleared,
		"nature": w.nature.to_dict(),
		"mechanisms": MechanismSet.capture(w),
	}


static func apply(w: GameWorld, snapshot: Dictionary) -> void:
	# 地形から動くブロックにしたセル: 保存時に地形だったものは地形へ戻し、保存時にブロックだったものはブロックにする
	var saved := snapshot.get("promoted", {}) as Dictionary
	if w.terrain != null:
		w.terrain.begin_batch()  # 当たり判定の作り直しを 1 回にまとめる
	for cell: Vector3i in w.promoted.keys():
		if not saved.has(cell):
			TerrainPromotion.demote(w, cell)
	for cell: Vector3i in saved:
		if not w.promoted.has(cell):
			TerrainPromotion.promote(w, cell)
	if w.terrain != null:
		w.terrain.end_batch()
	w.ledger.restore(snapshot["ledger"] as Dictionary)
	# W/A/S/D の予約はホストの一時的な状態なので、保存せず復元で消す（貸した単発は残り、もう一度押せる）
	w.move_buffer.clear()
	w.player.global_position = snapshot["player_position"] as Vector3
	w.player.velocity = Vector3.ZERO
	w.player.slide = Vector2.ZERO
	w.nature.restore(snapshot.get("nature", {}) as Dictionary)
	var block_states := snapshot["blocks"] as Dictionary
	for id: int in block_states:
		var state := block_states[id] as Dictionary
		w.blocks[id].restore_state(state)
		w._repeat_cursors[id].set_index(int(state["cursor"]))
		w._repeat_timers[id] = float(state["timer"])
		w._signal_cursors[id].set_index(int(state.get("signal_cursor", 0)))
		w._signal_timers[id] = float(state.get("signal_timer", 0.0))
	var bell_states := snapshot.get("bells", []) as Array
	for i in mini(bell_states.size(), w.bells.size()):
		w.bells[i].restore_state(bell_states[i] as Dictionary)
	var timers := snapshot.get("launch_timers", {}) as Dictionary
	for id: int in timers:
		w._launch_timers[id] = float(timers[id])
	for ball in w.get_tree().get_nodes_in_group(&"thrown_balls"):
		ball.queue_free()
	MedalThrow.clear(w)
	var creature_states := snapshot.get("creatures", {}) as Dictionary
	for id: int in creature_states:
		w.creatures[id].restore_state(creature_states[id] as Dictionary)
	w.selected_slot = int(snapshot["selected_slot"])
	w.lend_mode = int(snapshot["lend_mode"]) as TriggerMode.Kind
	w.goal_cleared = bool(snapshot["goal_cleared"])
	MechanismSet.restore(w, snapshot.get("mechanisms", {}) as Dictionary)
