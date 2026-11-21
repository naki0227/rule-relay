class_name CreatureBrain
extends RefCounted
## 生き物のふるまい（2026-11-21 本人「ビヘイビアツリーみたいな感じで動けるんやったら動かしてほしいな、普通に」。
## ADR 0019）。動ける生き物が固まって立っていないように、小さなビヘイビアツリーで次にすることを選ぶ。
## 上から順に試し、最初に当てはまったものをする:
## 1. 願いがかなった（巣の中）: 一度だけ喜び、そのあとは巣の中で見回したり、巣の中を少し歩いたりする
## 2. 行き先への完全な道がある: たどる（いままでどおり。CreatureMind.plan）
## 3. 行き先はあるが道が足りない: いまの能力でいちばん近づける所まで歩き（CreatureMind.best_effort）、
##    そこで足りない能力（または「道が要る」）を出して待つ。待つ間は壁や近くのプレイヤーを見たり、
##    役に立たないジャンプを持っていればその場で小さく跳ねたりする（見た目だけ）
## 4. 移動はあるが行き先が無い: 止まった所から 2 マス以内の、同じ高さのふつうの地形だけを少し歩く
## 5. 移動が無い: その場で近くのプレイヤーのほうを向き、移動のメダルを吹き出しに出す
## 判断は純粋（物理・ノードに依存しない）で、乱数は生き物の ID を種にする（同じ入力なら同じふるまい。
## テストと通信の同期のため）。見回す・跳ねるは見た目だけで、向き（W/A/S/D の基準）も位置も変えない。

## 選んだ葉。
enum Choice { CELEBRATE, NEST_IDLE, FOLLOW_ROUTE, APPROACH, WAIT_AT_STOP, WANDER, STAY }

## 見た目の動き（RigAnimator の動きの名前。空なら歩き・立ち止まりのまま）。
const ACT_NONE := &""
const ACT_LOOK := &"look"
const ACT_HOP := &"hop"
const ACT_HAPPY := &"happy"
## 近くのプレイヤーのほうを向く距離（m）。
const LOOK_AT_PLAYER_RANGE: float = 8.0


## 判断の材料。
class Situation:
	extends RefCounted
	var start: Vector2i = Vector2i.ZERO
	## マスごとの立てる高さ（地形とブロック）と、地形だけの高さ。
	var heights: Dictionary = {}
	var ground: Dictionary = {}
	## 通らないマス（板・ワープの石・扉・レバー・時の鐘などの仕掛け）。{Vector2i: true}
	var avoid: Dictionary = {}
	var abilities: Dictionary = {}
	var jump_height: float = 1.3
	var high_jump_height: float = 2.3
	var can_climb: bool = false
	var blocked: Dictionary = {}
	var searching: bool = false
	## 巣（クリア条件「巣へ運ぶ」の箱を真上から見た四角。マスの x・z）。無ければ大きさ 0。
	var nest: Rect2 = Rect2()
	var wish_met: bool = false
	var celebrated: bool = false
	## 散歩の中心（最後に止まった所）。
	var anchor: Vector2i = Vector2i.ZERO
	## このステージにある能力（足りない能力を言うとき、無い能力は言わない）。
	var available: Array = []
	## プレイヤーの位置（x・z）。
	var players: Array[Vector2] = []
	## 判断の結果（ツリーの葉が書く）。
	var decision: Decision = null


## 判断の結果。
class Decision:
	extends RefCounted
	var choice: Choice = Choice.STAY
	var stage: CreatureMind.Stage = CreatureMind.Stage.WAIT
	var path: Array[Vector2i] = []
	## 吹き出しに出す、足りない能力（多くて 2 つ）と「道が要る」。
	var needs: Array[RuleAction.Kind] = []
	var needs_path: bool = false
	var act: StringName = ACT_NONE
	## 見る先（x・z）。has_gaze が false なら向いている向きのまま。
	var has_gaze: bool = false
	var gaze: Vector2 = Vector2.ZERO
	## 行き先（巣、無ければいちばん近い高い地形）。無ければ大きさ 0。
	var target: Rect2 = Rect2()


var rng := RandomNumberGenerator.new()
var _seed: int = 0
var _tree: BehaviorTree.BTNode


func _init(seed_value: int) -> void:
	_seed = seed_value
	reset()
	_tree = BehaviorTree.selector(
		"creature",
		[
			BehaviorTree.sequence(
				"wish met",
				[
					BehaviorTree.leaf(
						"is the wish met", func(s: Situation) -> bool: return s.wish_met
					),
					(
						BehaviorTree
						. selector(
							"at the nest",
							[
								BehaviorTree.leaf("celebrate", _celebrate),
								BehaviorTree.leaf("idle at the nest", _nest_idle),
							]
						)
					),
				]
			),
			BehaviorTree.leaf("follow the route", _follow_route),
			(
				BehaviorTree
				. sequence(
					"partial route",
					[
						BehaviorTree.leaf("can walk", _can_walk),
						BehaviorTree.leaf("has a target", _has_target),
						(
							BehaviorTree
							. selector(
								"toward the target",
								[
									BehaviorTree.leaf("approach", _approach),
									BehaviorTree.leaf("wait at the stop", _wait_at_stop),
								]
							)
						),
					]
				)
			),
			BehaviorTree.sequence(
				"free to roam",
				[BehaviorTree.leaf("can walk", _can_walk), BehaviorTree.leaf("wander", _wander)]
			),
			BehaviorTree.leaf("stay", _stay),
		]
	)


## 乱数を最初に戻す（チェックポイントから戻したときなど。同じ種なら同じふるまい）。
func reset() -> void:
	rng.seed = hash("creature:%d" % _seed)


## 次にすることを決める。
func decide(s: Situation) -> Decision:
	s.decision = Decision.new()
	s.decision.target = _target_of(s)
	_tree.tick(s)
	return s.decision


# --- 葉 ---------------------------------------------------------------------


func _celebrate(s: Situation) -> bool:
	if s.celebrated:
		return false
	s.decision.choice = Choice.CELEBRATE
	s.decision.act = ACT_HAPPY
	return true


## 巣の中で: 見回す・巣の中を少し歩く・近くのプレイヤーを見る（巣の外へは出ない）。
func _nest_idle(s: Situation) -> bool:
	var d := s.decision
	d.choice = Choice.NEST_IDLE
	var roll := rng.randf()
	var pick := rng.randf()
	if roll < 0.3 and CreatureMind.can_walk(s.abilities):
		var inside := {}
		for cell: Vector2i in safe_cells(s):
			if CreatureMind.target_distance(cell, s.nest) <= 0.0:
				inside[cell] = true
		d.path = CreatureMind.wander_path(s.start, s.start, s.heights, inside, pick)
	elif roll < 0.6:
		d.act = ACT_LOOK
	elif roll < 0.8:
		_look_at_player(s)
	return true


func _follow_route(s: Situation) -> bool:
	var plan := CreatureMind.plan(
		s.start, s.heights, s.abilities, s.jump_height, s.can_climb, s.blocked, s.searching
	)
	if plan.path.is_empty():
		return false
	s.decision.choice = Choice.FOLLOW_ROUTE
	s.decision.stage = plan.stage
	s.decision.path = plan.path
	return true


func _can_walk(s: Situation) -> bool:
	return CreatureMind.can_walk(s.abilities)


func _has_target(s: Situation) -> bool:
	return s.decision.target.has_area()


func _approach(s: Situation) -> bool:
	var target := s.decision.target
	if CreatureMind.at_wall(s.start, s.heights, s.abilities, s.jump_height, s.can_climb, target):
		return false  # もう壁の前にいる。壁ぞいに横へは歩かない
	var path := CreatureMind.best_effort(
		s.start,
		s.heights,
		s.abilities,
		s.jump_height,
		s.can_climb,
		s.decision.target,
		s.blocked,
		s.avoid,
		s.ground
	)
	if path.is_empty():
		return false
	s.decision.choice = Choice.APPROACH
	s.decision.path = path
	return true


## 止まった所で足りないものを出して待つ。待つ間は壁（行き先）や近くのプレイヤーを見る・小さく跳ねる。
func _wait_at_stop(s: Situation) -> bool:
	var d := s.decision
	d.choice = Choice.WAIT_AT_STOP
	_fill_needs(s)
	var roll := rng.randf()
	if roll < 0.35:
		d.has_gaze = true
		d.gaze = d.target.get_center()
	elif roll < 0.65:
		if not _look_at_player(s):
			d.act = ACT_LOOK
	elif roll < 0.8:
		d.act = ACT_HOP if bool(s.abilities.get(RuleAction.Kind.JUMP, false)) else ACT_LOOK
	return true


## 行き先の無い、動ける生き物: 止まった所の近く（同じ高さのふつうの地形）を少し歩く・見回す。
func _wander(s: Situation) -> bool:
	var d := s.decision
	d.choice = Choice.WANDER
	var roll := rng.randf()
	var pick := rng.randf()
	if roll < 0.4:
		d.path = CreatureMind.wander_path(s.start, s.anchor, s.heights, safe_cells(s), pick)
	elif roll < 0.7:
		if not _look_at_player(s):
			d.act = ACT_LOOK
	else:
		d.act = ACT_LOOK
	return true


## 移動が無い: その場で近くのプレイヤーのほうを向く。行き先があれば移動のメダルを出す。
func _stay(s: Situation) -> bool:
	var d := s.decision
	d.choice = Choice.STAY
	if d.target.has_area():
		_fill_needs(s)
	var roll := rng.randf()
	if not _look_at_player(s) and roll < 0.3:
		d.act = ACT_LOOK
	return true


# --- 道具 -------------------------------------------------------------------


## 行き先: 巣があれば巣（かなっていれば無し）、無ければいちばん近い高い地形。
func _target_of(s: Situation) -> Rect2:
	if s.nest.has_area():
		return Rect2() if s.wish_met else s.nest
	if not s.heights.has(s.start):
		return Rect2()
	return CreatureMind.nearest_higher_target(s.start, s.ground, float(s.heights[s.start]))


func _fill_needs(s: Situation) -> void:
	var found := CreatureMind.missing(
		s.start,
		s.heights,
		s.abilities,
		s.jump_height,
		s.high_jump_height,
		s.can_climb,
		s.decision.target,
		s.available,
		s.avoid
	)
	for kind: RuleAction.Kind in found["needs"] as Array:
		s.decision.needs.append(kind)
	s.decision.needs_path = bool(found["path"])


## いちばん近いプレイヤーが LOOK_AT_PLAYER_RANGE 以内なら、そちらを見る。
func _look_at_player(s: Situation) -> bool:
	var me := Vector2(s.start.x + 0.5, s.start.y + 0.5)
	var nearest := INF
	for p in s.players:
		var d := me.distance_to(p)
		if d < nearest and d <= LOOK_AT_PLAYER_RANGE:
			nearest = d
			s.decision.gaze = p
			s.decision.has_gaze = true
	return s.decision.has_gaze


## 散歩してよいマス: ブロックや置物の上ではない「ふつうの地形」で、仕掛けの無いマス。
static func safe_cells(s: Situation) -> Dictionary:
	var safe := {}
	for cell: Vector2i in s.heights:
		if s.avoid.has(cell) or not s.ground.has(cell):
			continue
		if absf(float(s.heights[cell]) - float(s.ground[cell])) <= 0.06:
			safe[cell] = true
	return safe
