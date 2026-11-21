class_name AimAssist
extends RefCounted
## 照準の補助（2026-11-21 本人: 「判定むずくてブロックと動物に与えるの大変」）。
## カメラの光線が付与先に当たらなかった（何にも当たらない・地形に当たった）ときだけ、画面の中央に近い
## 付与先（ブロック・生き物・鐘・発射台・仲間）を選ぶ。条件は3つ:
## - 画面での照準からの距離が、画面の高さの RADIUS_RATIO 以内（いちばん近いもの）
## - いまの届き方（触る／投げる）で届く（GameWorld.is_within_reach。届く距離の規則は変えない）
## - カメラから見えている（地形やほかのブロックに隠れていない。壁越しには渡せない）
## 地形のセルは候補にしない（地形に当たっていても、近くに生き物やブロックがあればそちらを優先する）。
## 地形から動くブロックにしたセルも候補にしない（見た目が地面なので、地面を狙ったつもりで吸い寄せない）。

## 画面の高さに対する、補助が効く半径の割合。
const RADIUS_RATIO: float = 0.06


## 補助で選ぶ付与先（無ければ null）。
static func pick(w: GameWorld, cam: Camera3D) -> Node3D:
	var size := cam.get_viewport().get_visible_rect().size
	var center := size * 0.5
	var limit := size.y * RADIUS_RATIO
	var best: Node3D = null
	var best_distance := limit
	for target in candidates(w):
		var point := aim_point(target)
		if cam.is_position_behind(point) or not w.is_within_reach(target):
			continue
		var d := cam.unproject_position(point).distance_to(center)
		if d > best_distance or not is_visible_from(w, cam.global_position, target):
			continue
		best = target
		best_distance = d
	return best


## 補助の候補: 動くブロック（地形から作ったものを除く）・生き物・鐘・仲間のアバター。
static func candidates(w: GameWorld) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var from_terrain := {}
	for cell: Vector3i in w.promoted:
		from_terrain[w.promoted[cell]] = true
	for id: int in w.blocks:
		if not from_terrain.has(id):
			result.append(w.blocks[id])
	for creature: Creature in w.creatures.values():
		result.append(creature)
	for bell: Bell in w.bells:
		result.append(bell)
	for avatar: PlayerAvatar in w.avatars.values():
		if avatar != w.player:
			result.append(avatar)
	return result


## 狙う点（足もとが原点のものは体の真ん中）。
static func aim_point(target: Node3D) -> Vector3:
	if target is Creature:
		return target.global_position + Vector3(0.0, Creature.HEIGHT * 0.5, 0.0)
	if target is Bell:
		return target.global_position + Vector3(0.0, Bell.HEIGHT * 0.5, 0.0)
	if target is PlayerAvatar:
		return target.global_position + Vector3(0.0, 0.9, 0.0)
	return target.global_position


## from から target の真ん中（ブロックなら上面の真ん中も）まで、地形やほかのブロックに遮られていないか。
## 上面も見るのは、地面と同じ高さに沈んだブロック（窪みのブロック）の真ん中は、浅い角度だと
## まわりの地面の陰になるため（上面が見えていれば狙える）。
static func is_visible_from(w: GameWorld, from: Vector3, target: Node3D) -> bool:
	var points: Array[Vector3] = [aim_point(target)]
	if target is RuleBlock:
		points.append(target.global_position + Vector3(0.0, RuleBlock.SIZE * 0.49, 0.0))
	var body := target as CollisionObject3D
	var space := w.get_world_3d().direct_space_state
	for point in points:
		var query := PhysicsRayQueryParameters3D.create(
			from, point, Tuning.LAYER_TERRAIN | Tuning.LAYER_BLOCKS
		)
		if body != null:
			query.exclude = [body.get_rid()]
		if space.intersect_ray(query).is_empty():
			return true
	return false
