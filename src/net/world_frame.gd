class_name WorldFrame
extends RefCounted
## ホストが 1 秒に 20 回配る「世界のいまの様子」（位置と見た目だけ。ルールの状態は台帳で別に配る）。
## {"block_ids": PackedInt32Array, "block_pos": PackedVector3Array（同じ順。動いたブロックだけ）,
##  "promoted": PackedInt32Array（動くブロックにした地形のセルの x, y, z の並び。変わったときと全部を送る回だけ）,
##  "creatures": {id: [位置, 向き, 持ち物, 頭の上の吹き出しの鍵, [見た目の動き, 回数, 体の向き]]},
##  "avatars": {player_id: [位置, 向き, 歩いているか, 床にいるか]}, "bells": [残り時間...],
##  "balls": [位置...], "medals": 投げたメダル（MedalThrow.capture_frame）,
##  "nature": 自然の仕掛けの時計（脈打つ風の拍子をそろえる）}
## アバターの5番目は投げた回数（変わったら投げる動きを再生する）。
## 送る量（2026-11-24 の性能の測定）: 範囲で 80 マスを動くブロックにすると、辞書のままでは 1 回 約 4 KB
## （1 秒 20 回 × 参加者 3 人で 約 1.9 Mbps、1 回が UDP の 1 パケットに収まらず分割される）だった。
## ブロックは前に送った位置から動いたものだけ（FULL_EVERY 回に 1 回は全部）、地形のセルは変わったときだけ送り、
## 配列は Packed にする。信頼性なしで届くので、落ちた回の分は次の「全部」の回（0.5 秒以内）で戻る。

## この回数に 1 回は、動いていないブロックとセルの一覧も全部送る（落ちたパケット・途中から入った人の分を戻す）。
const FULL_EVERY: int = 10
## これより動いていなければ「動いていない」とみなす（m）。
const MOVED_EPSILON: float = 0.001
## 止まった（変わった）あとも、この回数は続けて送る（止まった位置・新しいセルの一覧が 1 回落ちても届く）。
const REPEAT_AFTER_CHANGE: int = 2


## ホストが送る側の覚え（前に送ったブロックの位置・セルの一覧）。世界を差し替えたら作り直す。
class Sender:
	var serial: int = 0
	var sent_blocks: Dictionary[int, Vector3] = {}
	## ブロック → 止まってからあと何回送るか
	var repeats: Dictionary[int, int] = {}
	var sent_promoted_hash: int = 0
	var promoted_repeats: int = 0

	## 次の回を全部送る回にする（新しい参加者が入ったとき）。
	func force_full() -> void:
		serial = 0


## sender を渡すと、前に送ってから動いたブロックだけを入れる（渡さなければ全部）。
static func capture(w: GameWorld, sender: Sender = null) -> Dictionary:
	var full := sender == null or sender.serial % FULL_EVERY == 0
	if sender != null:
		sender.serial += 1
	var block_ids := PackedInt32Array()
	var block_pos := PackedVector3Array()
	for id in w.blocks:
		var at := w.blocks[id].global_position
		if sender != null:
			var moved := (
				not sender.sent_blocks.has(id)
				or sender.sent_blocks[id].distance_squared_to(at) >= MOVED_EPSILON * MOVED_EPSILON
			)
			var left := REPEAT_AFTER_CHANGE if moved else int(sender.repeats.get(id, 0)) - 1
			sender.repeats[id] = maxi(left, 0)
			if not full and not moved and left < 0:
				continue
			sender.sent_blocks[id] = at
		block_ids.append(id)
		block_pos.append(at)
	var creature_states := {}
	for id in w.creatures:
		var c := w.creatures[id]
		creature_states[id] = [
			c.global_position, c.facing, c.held_item, c.bubble_key(), c.act_state()
		]
	var avatar_states := {}
	if w.player != null:
		avatar_states[w.player.player_id] = w.player.remote_state()
	for player_id in w.avatars:
		var a := w.avatars[player_id]
		avatar_states[player_id] = [
			a.remote_position, a.remote_yaw, a.remote_moving, true, a.throw_serial
		]
	var bell_states: Array[float] = []
	for bell in w.bells:
		bell_states.append(bell.remaining)
	var balls: Array[Vector3] = []
	for ball in w.get_tree().get_nodes_in_group(&"thrown_balls"):
		balls.append((ball as Node3D).global_position)
	var frame := {
		"block_ids": block_ids,
		"block_pos": block_pos,
		"creatures": creature_states,
		"avatars": avatar_states,
		"bells": bell_states,
		"balls": balls,
		"medals": MedalThrow.capture_frame(w),
		"nature": w.nature.clock,
		"mechanisms": MechanismSet.capture_frame(w),
	}
	var promoted := PackedInt32Array()
	for cell: Vector3i in w.promoted:
		promoted.append_array([cell.x, cell.y, cell.z])
	var promoted_hash := hash(promoted)
	if sender != null and sender.sent_promoted_hash != promoted_hash:
		sender.sent_promoted_hash = promoted_hash
		sender.promoted_repeats = REPEAT_AFTER_CHANGE + 1
	if full or sender.promoted_repeats > 0:
		frame["promoted"] = promoted
	if sender != null:
		sender.promoted_repeats -= 1
	return frame


## 参加者の画面に反映する。知らない ID・壊れた値は無視する（通信から来た値なので信用しない）。
static func apply(
	w: GameWorld, data: Dictionary, ghosts: Array[MeshInstance3D], medal_ghosts: Dictionary = {}
) -> void:
	if typeof(data.get("promoted")) == TYPE_PACKED_INT32_ARRAY:
		_apply_promoted(w, data["promoted"] as PackedInt32Array)
	if (
		typeof(data.get("block_ids")) == TYPE_PACKED_INT32_ARRAY
		and typeof(data.get("block_pos")) == TYPE_PACKED_VECTOR3_ARRAY
	):
		var ids := data["block_ids"] as PackedInt32Array
		var positions := data["block_pos"] as PackedVector3Array
		for i in mini(ids.size(), positions.size()):
			if w.blocks.has(ids[i]):
				w.blocks[ids[i]].set_remote_target(positions[i])
	var creature_states := data.get("creatures", {}) as Dictionary
	for id: int in creature_states:
		var c := creature_states[id] as Array
		if w.creatures.has(id) and c.size() >= 3:
			var key := String(c[3]) if c.size() >= 4 else ""
			var act := c[4] as Array if c.size() >= 5 and typeof(c[4]) == TYPE_ARRAY else []
			w.creatures[id].set_remote_state(
				c[0] as Vector3, c[1] as Vector2i, String(c[2]), key, act
			)
	_apply_avatars(w, data.get("avatars", {}) as Dictionary)
	var bell_states := data.get("bells", []) as Array
	for i in mini(bell_states.size(), w.bells.size()):
		w.bells[i].remaining = float(bell_states[i])
	_apply_balls(w, data.get("balls", []) as Array, ghosts)
	MedalThrow.apply_frame(w, data.get("medals", []) as Array, medal_ghosts)
	if typeof(data.get("nature")) == TYPE_FLOAT:
		w.nature.clock = float(data["nature"])
	MechanismSet.apply_frame(w, data.get("mechanisms", {}) as Dictionary)


## ホストで動くブロックになった地形のセルを、参加者の画面でもブロックにする（戻ったセルは地形へ）。
static func _apply_promoted(w: GameWorld, flat: PackedInt32Array) -> void:
	if w.terrain == null:
		return
	var wanted := {}
	for i in range(0, flat.size() - 2, 3):
		wanted[Vector3i(flat[i], flat[i + 1], flat[i + 2])] = true
	w.terrain.begin_batch()  # 当たり判定の作り直しを 1 回にまとめる
	for cell: Vector3i in wanted:
		if not w.promoted.has(cell) and w.terrain.has_cell(cell):
			TerrainPromotion.promote(w, cell).remote = true
	for cell: Vector3i in w.promoted.keys():
		if not wanted.has(cell):
			TerrainPromotion.demote(w, cell)
	w.terrain.end_batch()


static func _apply_avatars(w: GameWorld, states: Dictionary) -> void:
	var me := w.player.player_id if w.player != null else -1
	for player_id: int in states:
		var s := states[player_id] as Array
		if player_id == me or not w.avatars.has(player_id) or s.size() < 4:
			continue
		var serial := int(s[4]) if s.size() >= 5 else -1
		w.avatars[player_id].apply_remote(
			s[0] as Vector3, float(s[1]), bool(s[2]), bool(s[3]), serial
		)


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
