class_name CreatureMind
extends RefCounted
## 生き物の判断（企画書 6）。願い「高いところへ行きたい」に向かって、持っている能力と周りの地形から
## 自分で道を選ぶ。プレイヤーは命令できず、能力と地形を変えて行動を誘導する。
## 物理・ノードに依存しない純粋な判断で、地形は「マスごとの立てる高さ」として受け取る。
##
## 見せ方（2026-11-21、本人の試遊「能力あげても動かん」を受けて）: 移動の能力があっても高い所への道が無いとき、
## 同じ高さのまま APPROACH_STEPS 歩以内でふもとに着けるなら、いちばん近い高い場所のふもとまで歩いて止まる
## （Plan.approach。段階は WAIT のまま）。同じ高さしか歩かないので、前より高い所・遠い所へは行かない。
## 遠くの崖へは歩かない（段の縁で待っている生き物から、下のプレイヤーが能力を取り戻せる状態を崩さない）。
##
## 4段階:
## 1. SEEK: 願いへ向かう（いまより高く立てるマスへの道があれば進む）
## 2. SEARCH: 別ルートを探す（進めなかった道を除いて探し直す）
## 3. WAIT: 待つ（道が無いので、見回し・休息をしながら待つ）
## 4. 環境が変わったら（足場の接近・能力の変化など）判断を更新して再挑戦する（呼び出し側が replan する）
## 禁止は願いより優先する（abilities には禁止を差し引いた「自分から始められる行動」を渡す）。
##
## W/A/S/D は、その生き物が向いている向きが基準（2026-11-19 本人の判断。ブロックの世界方角とは違う）。
## 体の向きは自由に変えられる（プレイヤーが視点を回せるのと同じ扱い）ので、移動の能力が1つでもあれば
## どの方角へも進める。そのとき、向きを変えずに済む能力 → 前（W）→ 左右 → 後ろ の順に選ぶ。

enum Stage { SEEK, SEARCH, WAIT }

## 探す範囲（マス）。企画書の仮値は 5〜10。
const SEARCH_RADIUS: int = 8
## 道が無いとき、高い場所のふもとへ歩いて近づく最大の歩数（同じ高さのマスだけを通る）。
const APPROACH_STEPS: int = 4
## 歩いて上がれる段差（プレイヤーの段差補助と同じ）
const STEP_HEIGHT: float = 0.45
## 自分から降りてよい高さ（それより深い所へは飛び降りない）
const SAFE_DROP: float = 2.5
## 跳んで上がるときの余裕（跳ぶ高さちょうどの段には届かない）
const JUMP_MARGIN: float = 0.2
## 世界の4方角（x = 東、y = 南。北 = -z）。
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
]
const MOVES: Array[RuleAction.Kind] = [
	RuleAction.Kind.FORWARD, RuleAction.Kind.LEFT, RuleAction.Kind.RIGHT, RuleAction.Kind.BACK
]


## 判断の結果。
class Plan:
	extends RefCounted
	var stage: Stage = Stage.WAIT
	## 進むマスの列（いまのマスは含まない）。WAIT では空。
	var path: Array[Vector2i] = []
	var goal_height: float = 0.0
	## 見えているが、いまの能力では行けない高い場所があるか（「行きたいけど行けない」の表示用）
	var sees_unreachable_height: bool = false
	## WAIT のとき、いちばん近い高い場所のふもとへ同じ高さのまま近づく道（無ければ空。いまのマスは含まない）
	var approach: Array[Vector2i] = []


## 道を選ぶ。
## heights: {Vector2i(マスの x, z): 立てる高さ}。無いマスは穴（立てない）
## abilities: {RuleAction.Kind: bool} 自分から始められる行動（禁止を差し引いたもの）
## jump_height: 跳べる高さ（高跳びがあれば高い）。can_climb: 登る（どの段差も上がれる）
## blocked_steps: 進もうとして進めなかった一歩 {"x,z>x,z": true}（別ルートを探すときに除く）
static func plan(
	start: Vector2i,
	heights: Dictionary,
	abilities: Dictionary,
	jump_height: float,
	can_climb: bool,
	blocked_steps: Dictionary = {},
	searching: bool = false
) -> Plan:
	var result := Plan.new()
	if not heights.has(start):
		return result
	var here := float(heights[start])
	var came_from := {start: start}
	var queue: Array[Vector2i] = [start]
	var best := start
	var best_height := here
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if not can_walk(abilities):
			break
		for dir: Vector2i in DIRECTIONS:
			var next := cell + dir
			if came_from.has(next) or not heights.has(next):
				continue
			if absi(next.x - start.x) > SEARCH_RADIUS or absi(next.y - start.y) > SEARCH_RADIUS:
				continue
			if blocked_steps.has(step_key(cell, next)):
				continue
			var rise := float(heights[next]) - float(heights[cell])
			if not can_step(rise, abilities, jump_height, can_climb):
				continue
			came_from[next] = cell
			queue.append(next)
			# 幅優先なので、同じ高さなら先に見つかった（近い）マスが残る
			var h := float(heights[next])
			if h > best_height + 0.1:
				best = next
				best_height = h
	for cell: Vector2i in heights:
		var dx := absi(cell.x - start.x)
		var dz := absi(cell.y - start.y)
		if dx <= SEARCH_RADIUS and dz <= SEARCH_RADIUS and float(heights[cell]) > best_height + 0.5:
			result.sees_unreachable_height = true
			break
	if best == start:
		result.stage = Stage.WAIT
		result.goal_height = here
		if result.sees_unreachable_height and can_walk(abilities):
			result.approach = approach_path(start, heights, blocked_steps)
		return result
	var path: Array[Vector2i] = []
	var cursor := best
	while cursor != start:
		path.push_front(cursor)
		cursor = came_from[cursor]
	result.path = path
	result.goal_height = best_height
	result.stage = Stage.SEARCH if searching else Stage.SEEK
	return result


## 同じ高さのマスだけを APPROACH_STEPS 歩まで歩いて、いちばん近い高い場所（いまより 0.5 以上高い
## マス）のとなり（ふもと）へ行く道。ふもとまで届かない・もう着いているなら空。
## wish_heights を渡すと、行き先の「高い場所」はその中からだけ選ぶ（例: 地形だけ。ブロックや鐘の上は選ばない）。
static func approach_path(
	start: Vector2i,
	heights: Dictionary,
	blocked_steps: Dictionary = {},
	wish_heights: Variant = null
) -> Array[Vector2i]:
	var here := float(heights[start])
	var wish := _nearest_higher(start, heights if wish_heights == null else wish_heights, here)
	var none: Array[Vector2i] = []
	if wish == start:
		return none
	var came_from := {start: start}
	var steps := {start: 0}
	var queue: Array[Vector2i] = [start]
	var best := start
	var best_distance := Vector2(start - wish).length()
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if int(steps[cell]) >= APPROACH_STEPS:
			continue
		for dir: Vector2i in DIRECTIONS:
			var next := cell + dir
			if came_from.has(next) or not heights.has(next):
				continue
			if absf(float(heights[next]) - here) > 0.1 or blocked_steps.has(step_key(cell, next)):
				continue
			came_from[next] = cell
			steps[next] = int(steps[cell]) + 1
			queue.append(next)
			var d := Vector2(next - wish).length()
			if d < best_distance - 0.01:
				best = next
				best_distance = d
	if best_distance > 1.01:
		return none  # ふもと（高い場所のとなり）まで行けないなら歩かない（遠くの崖へ向かって歩き出さない）
	var path: Array[Vector2i] = []
	while best != start:
		path.push_front(best)
		best = came_from[best]
	return path


## 探す範囲の中で、いまより 0.5 以上高い、いちばん近いマス（無ければ start）。
static func _nearest_higher(start: Vector2i, heights: Dictionary, here: float) -> Vector2i:
	var wish := start
	var wish_distance := INF
	for cell: Vector2i in heights:
		if absi(cell.x - start.x) > SEARCH_RADIUS or absi(cell.y - start.y) > SEARCH_RADIUS:
			continue
		var d := Vector2(cell - start).length()
		if float(heights[cell]) > here + 0.5 and d < wish_distance:
			wish = cell
			wish_distance = d
	return wish


## 段差 rise（上がる高さ。負なら下がる）を、その能力で越えられるか。
static func can_step(
	rise: float, abilities: Dictionary, jump_height: float, can_climb: bool
) -> bool:
	if rise < -SAFE_DROP:
		return false
	if rise <= STEP_HEIGHT:
		return true
	if can_climb:
		return true
	return bool(abilities.get(RuleAction.Kind.JUMP, false)) and rise <= jump_height - JUMP_MARGIN


## 一歩を表すキー（別ルート探しで、進めなかった一歩を除くため）。
static func step_key(from: Vector2i, to: Vector2i) -> String:
	return "%d,%d>%d,%d" % [from.x, from.y, to.x, to.y]


## 移動の能力（W/A/S/D）が1つでもあるか。
static func can_walk(abilities: Dictionary) -> bool:
	for action in MOVES:
		if bool(abilities.get(action, false)):
			return true
	return false


## 向き facing のとき、行動 action で進む世界の方角。
static func direction_of(action: RuleAction.Kind, facing: Vector2i) -> Vector2i:
	match action:
		RuleAction.Kind.BACK:
			return -facing
		RuleAction.Kind.RIGHT:
			return turn_right(facing)
		RuleAction.Kind.LEFT:
			return turn_left(facing)
	return facing


static func turn_right(v: Vector2i) -> Vector2i:
	return Vector2i(-v.y, v.x)


static func turn_left(v: Vector2i) -> Vector2i:
	return Vector2i(v.y, -v.x)


## 世界の方角 step へ一歩進むときの {"action": 行動, "facing": 新しい向き}。進めなければ空。
static func choose_move(facing: Vector2i, step: Vector2i, abilities: Dictionary) -> Dictionary:
	for action in MOVES:
		if bool(abilities.get(action, false)) and direction_of(action, facing) == step:
			return {"action": action, "facing": facing}
	for action in MOVES:
		if not bool(abilities.get(action, false)):
			continue
		match action:
			RuleAction.Kind.FORWARD:
				return {"action": action, "facing": step}
			RuleAction.Kind.LEFT:
				return {"action": action, "facing": turn_right(step)}
			RuleAction.Kind.RIGHT:
				return {"action": action, "facing": turn_left(step)}
			_:
				return {"action": action, "facing": -step}
	return {}


static func stage_label(stage: Stage) -> String:
	match stage:
		Stage.SEEK:
			return "高いところへ向かう"
		Stage.SEARCH:
			return "別の道を探す"
	return "待っている"
