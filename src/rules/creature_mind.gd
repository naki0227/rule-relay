class_name CreatureMind
extends RefCounted
## 生き物の判断（企画書 6）。願い「高いところへ行きたい」に向かって、持っている能力と周りの地形から
## 自分で道を選ぶ。プレイヤーは命令できず、能力と地形を変えて行動を誘導する。
## 物理・ノードに依存しない純粋な判断で、地形は「マスごとの立てる高さ」として受け取る。
##
## 4段階:
## 1. SEEK: 願いへ向かう（いまより高く立てるマスへの道があれば進む）
## 2. SEARCH: 別ルートを探す（進めなかった道を除いて探し直す）
## 3. WAIT: 待つ（道が無いので、見回し・休息をしながら待つ）
## 4. 環境が変わったら（足場の接近・能力の変化など）判断を更新して再挑戦する（呼び出し側が replan する）
## 禁止は願いより優先する（abilities には禁止を差し引いた「自分から始められる行動」を渡す）。

enum Stage { SEEK, SEARCH, WAIT }

## 探す範囲（マス）。企画書の仮値は 5〜10。
const SEARCH_RADIUS: int = 8
## 歩いて上がれる段差（プレイヤーの段差補助と同じ）
const STEP_HEIGHT: float = 0.45
## 自分から降りてよい高さ（それより深い所へは飛び降りない）
const SAFE_DROP: float = 2.5
## 跳んで上がるときの余裕（跳ぶ高さちょうどの段には届かない）
const JUMP_MARGIN: float = 0.2


## 判断の結果。
class Plan:
	extends RefCounted
	var stage: Stage = Stage.WAIT
	## 進むマスの列（いまのマスは含まない）。WAIT では空。
	var path: Array[Vector2i] = []
	var goal_height: float = 0.0
	## 見えているが、いまの能力では行けない高い場所があるか（「行きたいけど行けない」の表示用）
	var sees_unreachable_height: bool = false


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
		for action: RuleAction.Kind in [
			RuleAction.Kind.FORWARD,
			RuleAction.Kind.BACK,
			RuleAction.Kind.LEFT,
			RuleAction.Kind.RIGHT
		]:
			if not bool(abilities.get(action, false)):
				continue
			var dir := RuleAction.world_direction(action)
			var next := cell + Vector2i(dir.x, dir.z)
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


## 一歩の向きに対応する行動（世界の方角に固定。ブロックと同じく W = 北）。
static func action_for_step(from: Vector2i, to: Vector2i) -> RuleAction.Kind:
	var d := to - from
	if d.y < 0:
		return RuleAction.Kind.FORWARD
	if d.y > 0:
		return RuleAction.Kind.BACK
	if d.x < 0:
		return RuleAction.Kind.LEFT
	return RuleAction.Kind.RIGHT


static func stage_label(stage: Stage) -> String:
	match stage:
		Stage.SEEK:
			return "高いところへ向かう"
		Stage.SEARCH:
			return "別の道を探す"
	return "待っている"
