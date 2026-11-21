class_name FloorBans
extends RefCounted
## 足もとのブロックに付いた禁止は、その上に立っている人にも効く（2026-11-21 本人「ジャンプ禁止ってさ、
## そのブロックに働く感じになってるから、その上に乗ってもジャンプ禁止は適用してほしい」→「基本的に禁止は
## その上も禁止にしよう」。docs/adr/0003 決定 7）。
## 「立っている」は、床に着いていて（is_on_floor）、足の下へ少し動かしたときに当たるブロック。地形のセルに
## 渡した禁止も、そのセルが動くブロックになるので同じ扱い。跳んでいる間・降りた後は効かない。
## 乗っているブロックが動いていても（持ち上げ・1マス移動）、上に立っている間は効く。
##
## 立っている人への効き方（RuleAction ごと）:
## - JUMP: 跳べない（ジャンプブーツの高跳びも）。HIGH_JUMP: ブーツの高跳びが効かない（ふつうのジャンプは跳べる）
## - DASH: ダッシュを始められない（地上から。空中のダッシュは足もとが無いので効かない）
## - FORWARD / LEFT / BACK / RIGHT: その人の W/A/S/D（カメラ基準。プレイヤー自身に付いた禁止と同じ意味）で
##   歩けない。ブロックの世界の方角ではない
## - CLIMB: 登り始められない。THROW: 投げる届き方が使えない（触るだけ）。生き物は木の実を投げない
## - HEAVY / FLOAT / SWIM: 立っている人には意味が無いので効かせない（持っているだけの性質で、床に立って
##   いる間は水・落下に関わらない）

## 足の下を調べる距離（m）。床に立っていれば、この中で床に当たる。
const PROBE: float = 0.08
## これより上を向いた面だけを床とみなす（壁の横を擦っているだけのブロックは数えない）。
const FLOOR_NORMAL_Y: float = 0.7
## 立っている人に効かせる禁止の種類。
const RIDER_KINDS: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD,
	RuleAction.Kind.LEFT,
	RuleAction.Kind.BACK,
	RuleAction.Kind.RIGHT,
	RuleAction.Kind.JUMP,
	RuleAction.Kind.HIGH_JUMP,
	RuleAction.Kind.DASH,
	RuleAction.Kind.CLIMB,
	RuleAction.Kind.THROW,
]


## body が床として立っているブロック（無ければ空）。継ぎ目に立てば両方。
static func blocks_under(body: CharacterBody3D) -> Array[RuleBlock]:
	var found: Array[RuleBlock] = []
	if not body.is_on_floor():
		return found
	var hit := KinematicCollision3D.new()
	if not body.test_move(body.global_transform, Vector3.DOWN * PROBE, hit, 0.001, true, 4):
		return found
	for i in hit.get_collision_count():
		var block := hit.get_collider(i) as RuleBlock
		if block != null and hit.get_normal(i).y > FLOOR_NORMAL_Y and not found.has(block):
			found.append(block)
	return found


## body の足もとのブロックに付いた禁止のうち、立っている人に効くもの {RuleAction.Kind: true}。
static func under(ledger: RuleLedger, body: CharacterBody3D) -> Dictionary:
	var bans := {}
	if ledger == null:
		return bans
	for block in blocks_under(body):
		for action in RIDER_KINDS:
			if ledger.entity_prohibited(block.entity_id, action):
				bans[action] = true
	return bans


## ブロックの上面の高さごとに、そのマスに立つ人に効く禁止 {Vector2i(x, z): {"top": float, "bans": {Kind: true}}}。
## 生き物の道探しで、禁止の付いたブロックから跳ぶ道を選ばないために使う。
static func survey(ledger: RuleLedger, blocks: Dictionary) -> Dictionary:
	var result := {}
	for id: int in blocks:
		var bans := {}
		for action in RIDER_KINDS:
			if ledger.entity_prohibited(id, action):
				bans[action] = true
		if bans.is_empty():
			continue
		var block := blocks[id] as RuleBlock
		var c := block.cell()
		result[Vector2i(c.x, c.z)] = {
			"top": block.global_position.y + RuleBlock.SIZE * 0.5, "bans": bans
		}
	return result
