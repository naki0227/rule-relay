class_name WorldFrame
extends RefCounted
## ホストが 1 秒に 20 回配る「世界のいまの様子」（位置と見た目だけ。ルールの状態は台帳で別に配る）。
## {"blocks": {id: [位置, 光っているか(信号)]}, "creatures": {id: [位置, 向き, 持ち物]},
##  "avatars": {player_id: [位置, 向き, 歩いているか, 床にいるか]}, "bells": [残り時間...],
##  "balls": [位置...]}


static func capture(w: GameWorld) -> Dictionary:
	var block_states := {}
	for id in w.blocks:
		block_states[id] = w.blocks[id].global_position
	var creature_states := {}
	for id in w.creatures:
		var c := w.creatures[id]
		creature_states[id] = [c.global_position, c.facing, c.held_item]
	var avatar_states := {}
	if w.player != null:
		avatar_states[w.player.player_id] = w.player.remote_state()
	for player_id in w.avatars:
		var a := w.avatars[player_id]
		avatar_states[player_id] = [a.remote_position, a.remote_yaw, a.remote_moving, true]
	var bell_states: Array[float] = []
	for bell in w.bells:
		bell_states.append(bell.remaining)
	var balls: Array[Vector3] = []
	for ball in w.get_tree().get_nodes_in_group(&"thrown_balls"):
		balls.append((ball as Node3D).global_position)
	return {
		"promoted": w.promoted.keys(),
		"blocks": block_states,
		"creatures": creature_states,
		"avatars": avatar_states,
		"bells": bell_states,
		"balls": balls,
	}


## 参加者の画面に反映する。知らない ID・壊れた値は無視する（通信から来た値なので信用しない）。
static func apply(w: GameWorld, data: Dictionary, ghosts: Array[MeshInstance3D]) -> void:
	_apply_promoted(w, data.get("promoted", []) as Array)
	var block_states := data.get("blocks", {}) as Dictionary
	for id: int in block_states:
		if w.blocks.has(id) and typeof(block_states[id]) == TYPE_VECTOR3:
			w.blocks[id].set_remote_target(block_states[id] as Vector3)
	var creature_states := data.get("creatures", {}) as Dictionary
	for id: int in creature_states:
		var c := creature_states[id] as Array
		if w.creatures.has(id) and c.size() >= 3:
			w.creatures[id].set_remote_state(c[0] as Vector3, c[1] as Vector2i, String(c[2]))
	_apply_avatars(w, data.get("avatars", {}) as Dictionary)
	var bell_states := data.get("bells", []) as Array
	for i in mini(bell_states.size(), w.bells.size()):
		w.bells[i].remaining = float(bell_states[i])
	_apply_balls(w, data.get("balls", []) as Array, ghosts)


## ホストで動くブロックになった地形のセルを、参加者の画面でもブロックにする（戻ったセルは地形へ）。
static func _apply_promoted(w: GameWorld, cells: Array) -> void:
	if w.terrain == null:
		return
	var wanted := {}
	for value: Variant in cells:
		if typeof(value) == TYPE_VECTOR3I:
			wanted[value] = true
	for cell: Vector3i in wanted:
		if not w.promoted.has(cell) and w.terrain.has_cell(cell):
			TerrainPromotion.promote(w, cell).remote = true
	for cell: Vector3i in w.promoted.keys():
		if not wanted.has(cell):
			TerrainPromotion.demote(w, cell)


static func _apply_avatars(w: GameWorld, states: Dictionary) -> void:
	var me := w.player.player_id if w.player != null else -1
	for player_id: int in states:
		var s := states[player_id] as Array
		if player_id == me or not w.avatars.has(player_id) or s.size() < 4:
			continue
		w.avatars[player_id].apply_remote(s[0] as Vector3, float(s[1]), bool(s[2]), bool(s[3]))


## 飛んでいる玉は見た目だけ（参加者の画面では当たり判定をしない）。
static func _apply_balls(w: GameWorld, balls: Array, ghosts: Array[MeshInstance3D]) -> void:
	while ghosts.size() < balls.size():
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.15
		sphere.height = 0.3
		mesh.mesh = sphere
		w.add_child(mesh)
		ghosts.append(mesh)
	for i in ghosts.size():
		ghosts[i].visible = i < balls.size()
		if i < balls.size():
			ghosts[i].global_position = balls[i] as Vector3
