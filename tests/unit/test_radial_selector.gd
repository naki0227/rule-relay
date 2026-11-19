extends TestCase
## 円形 UI の方向判定。


func test_directions_pick_options_clockwise_from_top() -> void:
	var n := RadialSelector.MODES.size()
	assert_eq(RadialSelector.pick(Vector2(0, -100), n), 0, "up = single shot")
	assert_eq(RadialSelector.pick(Vector2(87, 50), n), 1, "lower right = repeat")
	assert_eq(RadialSelector.pick(Vector2(-87, 50), n), 2, "lower left = signal")


func test_short_drag_selects_nothing() -> void:
	assert_eq(RadialSelector.pick(Vector2(10, -20), 3), -1)
	assert_eq(RadialSelector.pick(Vector2.ZERO, 3), -1)


func test_sector_boundaries() -> void:
	# 真上(0)と右下(1)の境界は右上60度付近。少し手前なら0、少し先なら1
	assert_eq(RadialSelector.pick(Vector2.from_angle(deg_to_rad(-35.0)) * 100.0, 3), 0)
	assert_eq(RadialSelector.pick(Vector2.from_angle(deg_to_rad(-25.0)) * 100.0, 3), 1)


func test_no_options() -> void:
	assert_eq(RadialSelector.pick(Vector2(0, -100), 0), -1)
