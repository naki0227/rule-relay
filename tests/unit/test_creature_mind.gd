extends TestCase
## 生き物の判断（企画書 6）: 願いへ向かう／別ルートを探す／待つ／禁止は願いより優先。

const W := RuleAction.Kind.FORWARD
const A := RuleAction.Kind.LEFT
const S := RuleAction.Kind.BACK
const D := RuleAction.Kind.RIGHT
const JUMP := RuleAction.Kind.JUMP

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


# --- 道が無いとき、高い場所のふもとまで歩いて見せる（2026-11-21） ---------------------


## 移動だけで段差 2 は上がれないが、同じ高さのまま壁のふもとまで歩いて止まる（段階は WAIT のまま）。
func test_walks_to_the_foot_of_a_wall_it_cannot_climb() -> void:
	var plan := CreatureMind.plan(Vector2i(0, 0), line([0, 0, 0, 2]), walk, 1.3, false)
	assert_eq(plan.stage, CreatureMind.Stage.WAIT, "still waiting: no way up")
	assert_eq(plan.path.size(), 0)
	assert_eq(plan.approach, [Vector2i(1, 0), Vector2i(2, 0)] as Array[Vector2i], "to the foot")


## ふもとに着いていれば、もう歩かない。
func test_does_not_approach_when_already_at_the_foot() -> void:
	var plan := CreatureMind.plan(Vector2i(2, 0), line([0, 0, 0, 2]), walk, 1.3, false)
	assert_eq(plan.approach.size(), 0)


## 移動の能力が無ければ歩かない。
func test_does_not_approach_without_a_move() -> void:
	var plan := CreatureMind.plan(Vector2i(0, 0), line([0, 0, 0, 2]), {JUMP: true}, 1.3, false)
	assert_eq(plan.approach.size(), 0)
	assert_true(plan.sees_unreachable_height)


## 遠い崖（ふもとまで APPROACH_STEPS 歩より先）へは歩き出さない（段の縁で待つ生き物から、
## 下のプレイヤーが能力を取り戻せる状態を崩さない）。
func test_does_not_walk_towards_a_far_wall() -> void:
	var plan := CreatureMind.plan(Vector2i(0, 0), line([0, 0, 0, 0, 0, 0, 0, 2]), walk, 1.3, false)
	assert_eq(plan.stage, CreatureMind.Stage.WAIT)
	assert_eq(plan.approach.size(), 0, "the foot is 6 steps away")


## 同じ高さのマスしか通らない（降りてから近づく道は使わない。前より低い所・遠い所へ行かない）。
func test_approach_stays_on_the_same_height() -> void:
	var plan := CreatureMind.plan(Vector2i(0, 0), line([1, 0, 0, 3]), walk, 1.3, false)
	assert_eq(plan.approach.size(), 0, "the only way closer goes down")
