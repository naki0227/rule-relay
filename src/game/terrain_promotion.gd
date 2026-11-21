class_name TerrainPromotion
extends RefCounted
## 地形のセルを動くブロックにする／地形へ戻す（2026-11-19 本人の判断: どのブロックにも渡せる）。
## GameWorld から切り出した。ブロックの ID はセルの並び順で決まるので、復元しても同じ ID になる。

const MODELS := {
	"grass": "grass_cell", "rock": "rock_cell", "sand": "sandstone_cell", "ice": "ice_cell"
}


static func build(w: GameWorld, boxes: Array) -> void:
	w.terrain = TerrainGrid.new()
	w.terrain.name = "Terrain"
	w.add_child(w.terrain)
	w.terrain.build(boxes)
	var sorted := w.terrain.cells.keys()
	sorted.sort()
	for i in sorted.size():
		w._terrain_ids[sorted[i]] = GameWorld.FIRST_TERRAIN_ID + i
		w._terrain_kinds[sorted[i]] = w.terrain.cells[sorted[i]]
	w._terrain_target = TerrainCell.new()
	w._terrain_target.name = "AimedCell"
	w.add_child(w._terrain_target)


## 地形のセルを、動くブロックにする（能力を渡すとき）。見た目は同じ種類のセルの形。
static func promote(w: GameWorld, cell: Vector3i) -> RuleBlock:
	if w.promoted.has(cell):
		return w.blocks[w.promoted[cell]]
	var kind := w.terrain.remove_cell(cell)
	var model := String(MODELS.get(kind, "rock_cell"))
	var block := w.add_block(cell, Color.WHITE, model, w._terrain_ids[cell])
	w.promoted[cell] = block.entity_id
	return block


## 動くブロックにしたセルを地形へ戻す（チェックポイントの復元）。
static func demote(w: GameWorld, cell: Vector3i) -> void:
	if not w.promoted.has(cell):
		return
	var id := w.promoted[cell]
	w.promoted.erase(cell)
	w.blocks[id].queue_free()
	w.blocks.erase(id)
	w._home_cells.erase(id)
	w._repeat_cursors.erase(id)
	w._repeat_timers.erase(id)
	w._signal_cursors.erase(id)
	w._signal_timers.erase(id)
	w.move_buffer.forget(id)
	w.ledger.unregister_entity(id)
	w.terrain.restore_cell(cell, w._terrain_kinds[cell])
