class_name CreatureMind
extends RefCounted
## 生き物の判断（企画書 6）。願い「高いところへ行きたい」に向かって、持っている能力と周りの地形から
## 自分で道を選ぶ。プレイヤーは命令できず、能力と地形を変えて行動を誘導する。
## 物理・ノードに依存しない純粋な判断で、地形は「マスごとの立てる高さ」として受け取る。
##
## 道が無いとき（2026-11-21 本人「完全に道見つかるまで動かへん。向かってくれればいいのに」。ADR 0019）:
## いまの能力で行ける範囲で、行き先（巣、無ければいちばん近い高い地形）にいちばん近いマスまで歩き（best_effort）、
## そこで何が足りないか（missing）を出す。どの順で何をするかは CreatureBrain（小さなビヘイビアツリー）が決める。
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
## 待っている間に散歩する範囲（止まった所から東西南北・斜めとも、このマス数まで）。
const WANDER_RADIUS: int = 2
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


## 完全な道が無いとき、いまの能力だけで行ける範囲で、行き先 target（マスの x・z の四角。巣の床など）に
## いちばん近づけるマスへの道（いまのマスは含まない。近づけないなら空）。
## 「近い」は四角までの水平の距離で、同じなら高いほう、それも同じなら近い（先に見つかった）ほう。
## - 自分から降りる段は STEP_HEIGHT まで（跳び降りない。前より低い所へ行って戻れなくならない）
## - avoid のマス（板・ワープの石・扉・レバーなどの仕掛け）は通らない（仕掛けを勝手に動かさない）
## - ground（地形だけの高さ）を渡すと、止まる所はふつうの地形だけ（発射台・石などのブロックの上では止まらない）
## - 段の縁（となりがいまより低い）に立っているなら、同じ高さの縁のマスだけを通る。下にいるプレイヤーが
##   F で能力を取り戻せる所から離れない（1-3 持ち上げ台の段々の「段の縁にいる間は取り戻せる」を守る）
static func best_effort(
	start: Vector2i,
	heights: Dictionary,
	abilities: Dictionary,
	jump_height: float,
	can_climb: bool,
	target: Rect2,
	blocked_steps: Dictionary = {},
	avoid: Dictionary = {},
	ground: Dictionary = {}
) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if not heights.has(start) or not can_walk(abilities):
		return none
	var here := float(heights[start])
	var rim := is_rim(start, heights)
	var came_from := {start: start}
	var queue: Array[Vector2i] = [start]
	var best := start
	var best_distance := target_distance(start, target)
	var best_height := here
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for dir: Vector2i in DIRECTIONS:
			var next := cell + dir
			if came_from.has(next) or not heights.has(next) or avoid.has(next):
				continue
			if absi(next.x - start.x) > SEARCH_RADIUS or absi(next.y - start.y) > SEARCH_RADIUS:
				continue
			if blocked_steps.has(step_key(cell, next)):
				continue
			var h := float(heights[next])
			var rise := h - float(heights[cell])
			if rise < -STEP_HEIGHT or not can_step(rise, abilities, jump_height, can_climb):
				continue
			if rim and (absf(h - here) > 0.1 or not is_rim(next, heights)):
				continue
			came_from[next] = cell
			queue.append(next)
			if not ground.is_empty() and absf(h - float(ground.get(next, -INF))) > 0.06:
				continue  # ブロックや置物の上では止まらない（通るのはよい）
			var d := target_distance(next, target)
			if (
				d < best_distance - 0.001
				or (absf(d - best_distance) <= 0.001 and h > best_height + 0.1)
			):
				best = next
				best_distance = d
				best_height = h
	var path: Array[Vector2i] = []
	while best != start:
		path.push_front(best)
		best = came_from[best]
	return path


## もう壁の前にいるか: 行き先に近づく向きのとなりが、いまの能力では上がれない高さか、穴（谷・島の外）。
## 壁の前に着いた生き物は、壁ぞいに横へ歩いてまで近づかない（本人の例「W で壁の前まで行って」。
## 2-5「鳴りつづける鐘」の子どもは最初から段の壁の前にいて、横へ歩くと信号の石の最初の位置が 8 マスに入り、
## 鐘を鳴らす前に段へ上がってしまう）。
static func at_wall(
	start: Vector2i,
	heights: Dictionary,
	abilities: Dictionary,
	jump_height: float,
	can_climb: bool,
	target: Rect2
) -> bool:
	if not heights.has(start):
		return false
	var here_distance := target_distance(start, target)
	for dir: Vector2i in DIRECTIONS:
		var next := start + dir
		if target_distance(next, target) >= here_distance - 0.001:
			continue
		if not heights.has(next):
			return true
		var rise := float(heights[next]) - float(heights[start])
		if rise > STEP_HEIGHT and not can_step(rise, abilities, jump_height, can_climb):
			return true
	return false


## マス cell の中心から、行き先の四角 target までの水平の距離（中なら 0）。
static func target_distance(cell: Vector2i, target: Rect2) -> float:
	var c := Vector2(cell.x + 0.5, cell.y + 0.5)
	var nearest := Vector2(
		clampf(c.x, target.position.x, target.end.x), clampf(c.y, target.position.y, target.end.y)
	)
	return c.distance_to(nearest)


## 段の縁か（東西南北のとなりに、歩いて降りられないほど低いマスがある）。穴（マスが無い）は数えない。
static func is_rim(cell: Vector2i, heights: Dictionary) -> bool:
	var here := float(heights.get(cell, 0.0))
	for dir: Vector2i in DIRECTIONS:
		var next := cell + dir
		if heights.has(next) and float(heights[next]) < here - STEP_HEIGHT:
			return true
	return false


## 探す範囲の中で、いまより 0.5 以上高い、いちばん近いマスを、1 マスの四角で（無ければ大きさ 0）。
## 巣の無い生き物の行き先（heights には地形だけを渡す。ブロックや鐘の上は選ばない。ADR 0016）。
static func nearest_higher_target(start: Vector2i, heights: Dictionary, here: float) -> Rect2:
	var wish := start
	var wish_distance := INF
	for cell: Vector2i in heights:
		if absi(cell.x - start.x) > SEARCH_RADIUS or absi(cell.y - start.y) > SEARCH_RADIUS:
			continue
		var d := Vector2(cell - start).length()
		if float(heights[cell]) > here + 0.5 and d < wish_distance:
			wish = cell
			wish_distance = d
	if wish == start:
		return Rect2()
	return Rect2(Vector2(wish), Vector2.ONE)


## 止まった所 stop から、まだ行き先へ進めるか（完全な道があるか、いまより行き先に近づけるか）。
static func makes_progress(
	stop: Vector2i,
	heights: Dictionary,
	abilities: Dictionary,
	jump_height: float,
	can_climb: bool,
	target: Rect2,
	avoid: Dictionary = {}
) -> bool:
	if not plan(stop, heights, abilities, jump_height, can_climb).path.is_empty():
		return true
	if not target.has_area():
		return false
	var path := best_effort(stop, heights, abilities, jump_height, can_climb, target, {}, avoid)
	return not path.is_empty()


## 止まった所で、何が足りないか。{"needs": Array[RuleAction.Kind]（足りない能力。多くて 2 つ）,
## "path": bool（どの能力でも進めない＝道が要る）}。
## - 移動が無い → 移動（移動だけでは進めず、ジャンプもあれば進めるならジャンプも）
## - 移動はある → available（このステージにある能力）のうち、足すと進めるもの: ジャンプ → 高跳び（ジャンプも
##   無ければ両方）→ 登る。どれでも進めなければ「道が要る」
## 高跳びを足したときの跳ぶ高さは high_jump_height。
static func missing(
	stop: Vector2i,
	heights: Dictionary,
	abilities: Dictionary,
	jump_height: float,
	high_jump_height: float,
	can_climb: bool,
	target: Rect2,
	available: Array,
	avoid: Dictionary = {}
) -> Dictionary:
	var needs: Array[RuleAction.Kind] = []
	var have := abilities.duplicate()
	if not can_walk(have):
		needs.append(RuleAction.Kind.FORWARD)
		for move in MOVES:
			have[move] = true
		if makes_progress(stop, heights, have, jump_height, can_climb, target, avoid):
			return {"needs": needs, "path": false}
		var jump := RuleAction.Kind.JUMP
		if not bool(have.get(jump, false)) and available.has(jump):
			have[jump] = true
			if makes_progress(stop, heights, have, jump_height, can_climb, target, avoid):
				needs.append(jump)
		return {"needs": needs, "path": false}
	var options: Array[Array] = []
	var has_jump := bool(have.get(RuleAction.Kind.JUMP, false))
	if not has_jump and available.has(RuleAction.Kind.JUMP):
		options.append([RuleAction.Kind.JUMP])
	if available.has(RuleAction.Kind.HIGH_JUMP) and jump_height < high_jump_height:
		if has_jump:
			options.append([RuleAction.Kind.HIGH_JUMP])
		elif available.has(RuleAction.Kind.JUMP):
			options.append([RuleAction.Kind.JUMP, RuleAction.Kind.HIGH_JUMP])
	if available.has(RuleAction.Kind.CLIMB) and not can_climb:
		options.append([RuleAction.Kind.CLIMB])
	for option: Array in options:
		var trial := have.duplicate()
		var height := jump_height
		var climb := can_climb
		for kind: RuleAction.Kind in option:
			trial[kind] = true
			if kind == RuleAction.Kind.HIGH_JUMP:
				height = high_jump_height
			climb = climb or kind == RuleAction.Kind.CLIMB
		if makes_progress(stop, heights, trial, height, climb, target, avoid):
			for kind: RuleAction.Kind in option:
				needs.append(kind)
			return {"needs": needs, "path": false}
	return {"needs": needs, "path": true}


## 待っている間の散歩の道: anchor から WANDER_RADIUS マス以内（東西南北・斜めとも）の、いまと同じ高さの
## 「ふつうの地形」のマス（safe に入っているマス。ブロックや仕掛けの上は呼び出し側が除く）へ、同じ高さの
## safe のマスだけを通って行く道。行き先は pick（0〜1）で選ぶ。行ける所が無ければ空。
## 段の縁に立っているなら、縁のマスだけを選ぶ（下のプレイヤーから取り戻せる所を離れない）。
static func wander_path(
	start: Vector2i, anchor: Vector2i, heights: Dictionary, safe: Dictionary, pick: float
) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if not heights.has(start):
		return none
	var here := float(heights[start])
	var rim := is_rim(start, heights)
	var came_from := {start: start}
	var queue: Array[Vector2i] = [start]
	var options: Array[Vector2i] = []
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for dir: Vector2i in DIRECTIONS:
			var next := cell + dir
			if came_from.has(next) or not heights.has(next) or not safe.has(next):
				continue
			if maxi(absi(next.x - anchor.x), absi(next.y - anchor.y)) > WANDER_RADIUS:
				continue
			if absf(float(heights[next]) - here) > 0.1:
				continue
			if rim and not is_rim(next, heights):
				continue
			came_from[next] = cell
			queue.append(next)
			options.append(next)
	if options.is_empty():
		return none
	var chosen := options[clampi(floori(pick * options.size()), 0, options.size() - 1)]
	var path: Array[Vector2i] = []
	while chosen != start:
		path.push_front(chosen)
		chosen = came_from[chosen]
	return path


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
