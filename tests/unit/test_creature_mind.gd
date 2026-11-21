extends TestCase
## 生き物の判断（企画書 6）: 願いへ向かう／別ルートを探す／待つ／禁止は願いより優先。

const W := RuleAction.Kind.FORWARD
const A := RuleAction.Kind.LEFT
const S := RuleAction.Kind.BACK
const D := RuleAction.Kind.RIGHT
const JUMP := RuleAction.Kind.JUMP
## ステージにある能力（足りない能力を言うときの候補）。
const ALL_STAGE: Array = [W, A, S, D, JUMP]

var walk: Dictionary = {W: true, A: true, S: true, D: true}


## 東西に並んだ地形。x=0 から順に高さを指定する（z は 0 だけ）。
func line(values: Array) -> Dictionary:
	var heights := {}
	for x in values.size():
		heights[Vector2i(x, 0)] = float(values[x])
	return heights


func with_jump() -> Dictionary:
	var abilities := walk.duplicate()
	abilities[JUMP] = true
	return abilities


func test_waits_when_a_step_is_too_high_without_jump() -> void:
	var plan := CreatureMind.plan(Vector2i(0, 0), line([0, 0, 1, 2]), walk, 1.3, false)
	assert_eq(plan.stage, CreatureMind.Stage.WAIT)
	assert_true(plan.sees_unreachable_height, "it can see a higher place")


func test_walks_up_low_steps_and_jumps_one_block_with_jump() -> void:
	var plan := CreatureMind.plan(Vector2i(0, 0), line([0, 0, 1, 2]), with_jump(), 1.3, false)
	assert_eq(plan.stage, CreatureMind.Stage.SEEK)
	assert_eq(plan.path, [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)] as Array[Vector2i])
	assert_almost(plan.goal_height, 2.0, 0.001)


func test_prohibition_wins_over_the_wish() -> void:
	var abilities := with_jump()
	abilities[JUMP] = false  # ジャンプ禁止を持っている（呼び出し側が禁止を差し引く）
	var plan := CreatureMind.plan(Vector2i(0, 0), line([0, 1]), abilities, 1.3, false)
	assert_eq(plan.stage, CreatureMind.Stage.WAIT)


func test_cannot_walk_without_any_move_ability() -> void:
	var only_jump := {JUMP: true}
	var plan := CreatureMind.plan(Vector2i(0, 0), line([0, 0.3]), only_jump, 1.3, false)
	assert_eq(plan.stage, CreatureMind.Stage.WAIT)


func test_moves_are_relative_to_where_it_faces() -> void:
	var north := Vector2i(0, -1)
	var east := Vector2i(1, 0)
	assert_eq(CreatureMind.direction_of(W, north), north)
	assert_eq(CreatureMind.direction_of(D, north), east, "right of north is east")
	assert_eq(CreatureMind.direction_of(A, east), north, "left of east is north")
	assert_eq(CreatureMind.direction_of(S, east), Vector2i(-1, 0))


func test_only_a_means_walking_sideways() -> void:
	var only_a := {A: true}
	var plan := CreatureMind.plan(Vector2i(0, 0), line([0, 0.3]), only_a, 1.3, false)
	assert_eq(plan.path, [Vector2i(1, 0)] as Array[Vector2i], "still reaches the east")
	var move := CreatureMind.choose_move(Vector2i(0, -1), Vector2i(1, 0), only_a)
	assert_eq(move["action"], A)
	assert_eq(move["facing"], Vector2i(0, 1), "faces south so that its left is east")


func test_prefers_not_turning_then_forward() -> void:
	var move := CreatureMind.choose_move(Vector2i(0, -1), Vector2i(1, 0), walk)
	assert_eq(move["action"], D, "already facing north: step right without turning")
	var no_right := {W: true, S: true}
	move = CreatureMind.choose_move(Vector2i(0, -1), Vector2i(1, 0), no_right)
	assert_eq(move["action"], W)
	assert_eq(move["facing"], Vector2i(1, 0), "turns to face east, then forward")
	assert_true(CreatureMind.choose_move(Vector2i(0, -1), Vector2i(1, 0), {}).is_empty())


func test_finds_another_route_when_a_step_was_blocked() -> void:
	# 2列の地形。北の列は直進、南の列は回り道。直進の一歩が塞がれていたら回り道を選ぶ
	var heights := {}
	for x in 3:
		heights[Vector2i(x, 0)] = 0.0
		heights[Vector2i(x, 1)] = 0.0
	heights[Vector2i(2, 0)] = 0.4
	var blocked := {CreatureMind.step_key(Vector2i(1, 0), Vector2i(2, 0)): true}
	var plan := CreatureMind.plan(Vector2i(0, 0), heights, walk, 1.3, false, blocked, true)
	assert_eq(plan.stage, CreatureMind.Stage.SEARCH)
	assert_eq(plan.path.back(), Vector2i(2, 0))
	assert_false(
		(
			plan.path.has(Vector2i(1, 0))
			and plan.path.find(Vector2i(2, 0)) == plan.path.find(Vector2i(1, 0)) + 1
		)
	)


func test_high_jump_and_climb_open_higher_steps() -> void:
	var heights := line([0, 2])
	assert_eq(
		CreatureMind.plan(Vector2i(0, 0), heights, with_jump(), 1.3, false).stage,
		CreatureMind.Stage.WAIT
	)
	assert_eq(
		CreatureMind.plan(Vector2i(0, 0), heights, with_jump(), 2.3, false).stage,
		CreatureMind.Stage.SEEK,
		"high jump"
	)
	assert_eq(
		CreatureMind.plan(Vector2i(0, 0), heights, walk, 1.3, true).stage,
		CreatureMind.Stage.SEEK,
		"climb"
	)


func test_stays_within_the_search_radius_and_avoids_deep_drops() -> void:
	var far := {}
	for x in 12:
		far[Vector2i(x, 0)] = 0.0
	far[Vector2i(11, 0)] = 0.4
	assert_eq(
		CreatureMind.plan(Vector2i(0, 0), far, walk, 1.3, false).stage,
		CreatureMind.Stage.WAIT,
		"beyond 8 cells"
	)
	var cliff := line([3, 0, 0.4])
	assert_false(CreatureMind.can_step(-3.0, walk, 1.3, false), "does not jump down 3")
	assert_eq(
		CreatureMind.plan(Vector2i(0, 0), cliff, walk, 1.3, false).stage, CreatureMind.Stage.WAIT
	)


# --- 道が足りないとき、行ける所まで向かう（2026-11-21 本人「向かってくれればいいのに」。ADR 0019） ----------


## 平らな原（高さ 0、z = 0〜4）の北に、高さ 1 の台（z = -4〜-1）。巣は台の上（x = 4〜5、z = -3〜-2）。
func field(wall_height: float = 1.0, gap: bool = false) -> Dictionary:
	var heights := {}
	for x in 8:
		for z in range(-4, 5):
			if gap and z == -1:
				continue
			heights[Vector2i(x, z)] = 0.0 if z >= 0 else wall_height
	return heights


func situation(
	heights: Dictionary, start: Vector2i, abilities: Dictionary
) -> CreatureBrain.Situation:
	var s := CreatureBrain.Situation.new()
	s.start = start
	s.heights = heights
	s.ground = heights
	s.abilities = abilities
	s.nest = Rect2(4, -3, 2, 2)
	s.available = ALL_STAGE
	s.anchor = start
	return s


## W だけで、巣にはジャンプが要る: 巣にいちばん近い壁のふもとまで歩き、そこでジャンプが足りないと言う。
func test_walks_to_the_wall_foot_nearest_the_nest_and_names_the_jump() -> void:
	var brain := CreatureBrain.new(1)
	var heights := field()
	var only_w := {W: true}
	var d := brain.decide(situation(heights, Vector2i(0, 3), only_w))
	assert_eq(d.choice, CreatureBrain.Choice.APPROACH, "heads toward the nest")
	assert_eq(d.stage, CreatureMind.Stage.WAIT, "no full route")
	var stop: Vector2i = d.path.back()
	assert_eq(stop.y, 0, "the foot of the wall")
	assert_true(stop.x == 4 or stop.x == 5, "the foot nearest the nest")
	d = brain.decide(situation(heights, stop, only_w))
	assert_eq(d.choice, CreatureBrain.Choice.WAIT_AT_STOP)
	assert_eq(d.needs, [JUMP] as Array[RuleAction.Kind], "a jump medal in the bubble")
	assert_false(d.needs_path)


## ジャンプを渡されたら、止まった所から判断し直して壁を上がる。
func test_replans_after_a_jump_is_lent() -> void:
	var brain := CreatureBrain.new(1)
	var heights := field()
	var d := brain.decide(situation(heights, Vector2i(4, 0), {W: true, JUMP: true}))
	assert_eq(d.choice, CreatureBrain.Choice.FOLLOW_ROUTE, "a full route now")
	assert_eq(d.stage, CreatureMind.Stage.SEEK)
	assert_eq(d.path[0], Vector2i(4, -1), "hops straight up the wall")
	assert_true(d.needs.is_empty())


## 間に谷があると、どの能力でも越えられない: 「道が要る」（吹き出しに階段）。
func test_a_gap_needs_a_path() -> void:
	var brain := CreatureBrain.new(1)
	var heights := field(1.0, true)
	var d := brain.decide(situation(heights, Vector2i(4, 0), {W: true, JUMP: true}))
	assert_eq(d.choice, CreatureBrain.Choice.WAIT_AT_STOP)
	assert_true(d.needs.is_empty(), "no ability helps")
	assert_true(d.needs_path, "it needs a path")


## 段が高すぎて、ジャンプでも届かない（このステージに高跳びも登るも無い）: 「道が要る」。
func test_a_wall_too_high_even_with_a_jump_needs_a_path() -> void:
	var brain := CreatureBrain.new(1)
	var d := brain.decide(situation(field(2.0), Vector2i(4, 0), {W: true}))
	assert_true(d.needs_path)
	var s := situation(field(2.0), Vector2i(4, 0), {W: true})
	s.available = [W, JUMP, RuleAction.Kind.HIGH_JUMP]
	d = brain.decide(s)
	assert_eq(
		d.needs,
		[JUMP, RuleAction.Kind.HIGH_JUMP] as Array[RuleAction.Kind],
		"with high jump in the stage, both medals"
	)


## 完全な道があれば、いままでどおりの道（CreatureMind.plan と同じ）。
func test_a_full_route_is_unchanged() -> void:
	var heights := line([0, 0, 1, 2])
	var brain := CreatureBrain.new(1)
	var s := situation(heights, Vector2i(0, 0), with_jump())
	s.nest = Rect2()
	var d := brain.decide(s)
	var plan := CreatureMind.plan(Vector2i(0, 0), heights, with_jump(), 1.3, false)
	assert_eq(d.choice, CreatureBrain.Choice.FOLLOW_ROUTE)
	assert_eq(d.path, plan.path)
	assert_eq(d.stage, plan.stage)


## 段の縁（下にプレイヤーがいる段）からは、縁のマスだけを歩く（下から F で取り戻せる所を離れない。1-3）。
func test_from_a_ledge_edge_it_walks_only_along_the_edge() -> void:
	var heights := {}
	for x in range(-6, 7):
		for z in range(-14, 6):
			heights[Vector2i(x, z)] = 0.0 if z >= 1 else (2.0 if z >= -6 else 4.0)
	assert_true(CreatureMind.is_rim(Vector2i(3, 0), heights))
	assert_false(CreatureMind.is_rim(Vector2i(3, -1), heights))
	var path := CreatureMind.best_effort(
		Vector2i(3, 0), heights, with_jump(), 1.3, false, Rect2(-1, -14, 2, 2)
	)
	assert_false(path.is_empty(), "moves along the edge toward the nest")
	for cell in path:
		assert_eq(cell.y, 0, "stays on the edge row")


## 穴（マスが無い）は段の縁に数えない。跳び降りて近づかない。
func test_best_effort_never_drops_down() -> void:
	var heights := line([2, 2, 0, 0])
	var path := CreatureMind.best_effort(
		Vector2i(0, 0), heights, walk, 1.3, false, Rect2(3, 0, 1, 1)
	)
	assert_eq(path, [Vector2i(1, 0)] as Array[Vector2i], "stops at the top of the drop")
	var hole := {Vector2i(0, 0): 0.0, Vector2i(1, 0): 0.0}
	assert_false(CreatureMind.is_rim(Vector2i(1, 0), hole), "the island edge is not a ledge")


# --- ビヘイビアツリーの葉の選び方 -------------------------------------------------------


func test_tree_celebrates_once_then_idles_at_the_nest() -> void:
	var brain := CreatureBrain.new(3)
	var s := situation(field(), Vector2i(4, -2), {W: true})
	s.wish_met = true
	var d := brain.decide(s)
	assert_eq(d.choice, CreatureBrain.Choice.CELEBRATE)
	assert_eq(d.act, CreatureBrain.ACT_HAPPY)
	s.celebrated = true
	for i in 20:
		d = brain.decide(s)
		assert_eq(d.choice, CreatureBrain.Choice.NEST_IDLE)
		for cell in d.path:
			assert_eq(CreatureMind.target_distance(cell, s.nest), 0.0, "never leaves the nest")


func test_tree_without_a_move_stays_and_asks_for_one() -> void:
	var brain := CreatureBrain.new(3)
	var s := situation(field(), Vector2i(1, 3), {JUMP: true})
	s.players = [Vector2(3.5, 3.5)]
	var d := brain.decide(s)
	assert_eq(d.choice, CreatureBrain.Choice.STAY)
	assert_true(d.path.is_empty())
	assert_eq(d.needs, [W] as Array[RuleAction.Kind], "the move medal")
	assert_true(d.has_gaze, "looks at the nearby player")
	assert_eq(d.gaze, Vector2(3.5, 3.5))


func test_tree_with_a_move_and_no_target_wanders() -> void:
	var flat := {}
	for x in 9:
		for z in 9:
			flat[Vector2i(x, z)] = 0.0
	var brain := CreatureBrain.new(3)
	var s := situation(flat, Vector2i(4, 4), walk)
	s.nest = Rect2()
	assert_eq(brain.decide(s).choice, CreatureBrain.Choice.WANDER)


## 散歩は止まった所から 2 マス以内の、同じ高さのふつうの地形だけ（ブロック・仕掛け・崖の下へは行かない）。
func test_wander_stays_in_its_radius_and_on_safe_cells() -> void:
	var heights := {}
	for x in 9:
		for z in 9:
			heights[Vector2i(x, z)] = 0.0 if x >= 2 else -2.0  # 西は崖の下
	var ground := heights.duplicate()
	heights[Vector2i(5, 4)] = 1.0  # ブロック
	heights[Vector2i(4, 5)] = 0.0
	ground[Vector2i(4, 5)] = -1.0  # 窪みのブロック（上面は同じ高さ）
	var brain := CreatureBrain.new(11)
	var walked := 0
	for i in 60:
		var s := situation(heights, Vector2i(3, 4), walk)
		s.ground = ground
		s.nest = Rect2()
		s.avoid = {Vector2i(3, 3): true}  # 板
		var d := brain.decide(s)
		assert_eq(d.choice, CreatureBrain.Choice.WANDER)
		walked += 1 if not d.path.is_empty() else 0
		for cell in d.path:
			assert_lt(maxi(absi(cell.x - 3), absi(cell.y - 4)), 3, "within 2 cells")
			assert_eq(float(heights[cell]), 0.0, "same height")
			assert_false(cell == Vector2i(5, 4) or cell == Vector2i(4, 5), "not on blocks")
			assert_ne(cell, Vector2i(3, 3), "not on the plate")
			assert_gt(cell.x, 1, "not off the cliff")
	assert_gt(walked, 5, "it does wander sometimes")


## 同じ種なら同じふるまい（テストと通信のため）。
func test_same_seed_gives_the_same_behaviour() -> void:
	var one := CreatureBrain.new(5)
	var two := CreatureBrain.new(5)
	var flat := {}
	for x in 9:
		for z in 9:
			flat[Vector2i(x, z)] = 0.0
	for i in 30:
		var s1 := situation(flat, Vector2i(4, 4), walk)
		var s2 := situation(flat, Vector2i(4, 4), walk)
		s1.nest = Rect2()
		s2.nest = Rect2()
		var d1 := one.decide(s1)
		var d2 := two.decide(s2)
		assert_eq(d1.choice, d2.choice)
		assert_eq(d1.act, d2.act)
		assert_eq(d1.path, d2.path)
	one.reset()
	var again := CreatureBrain.new(5)
	var s := situation(flat, Vector2i(4, 4), walk)
	s.nest = Rect2()
	assert_eq(one.decide(s).path, again.decide(s).path, "reset starts the same sequence again")


## もう壁の前にいれば、壁ぞいに横へ歩いてまで近づかない（2-5 の子ども）。足りないものを出して待つ。
func test_already_at_the_wall_it_does_not_slide_along_it() -> void:
	var brain := CreatureBrain.new(1)
	var heights := field(2.0)
	assert_true(CreatureMind.at_wall(Vector2i(0, 0), heights, walk, 1.3, false, Rect2(4, -3, 2, 2)))
	assert_false(
		CreatureMind.at_wall(Vector2i(0, 3), heights, walk, 1.3, false, Rect2(4, -3, 2, 2))
	)
	var d := brain.decide(situation(heights, Vector2i(0, 0), with_jump()))
	assert_eq(d.choice, CreatureBrain.Choice.WAIT_AT_STOP, "waits at the wall")
	assert_true(d.path.is_empty())
	assert_true(d.needs_path)
