extends TestCase
## 長押し操作（V 長押しで全員リセットの投票）。短く押しただけでは発火しない。


func test_short_tap_does_not_fire() -> void:
	var hold := HoldAction.new(0.8)
	for i in 10:
		assert_false(hold.update(true, 0.05))
	assert_false(hold.update(false, 0.05))
	for i in 10:
		assert_false(hold.update(true, 0.05), "released in between, so the count restarts")


func test_fires_once_after_holding() -> void:
	var hold := HoldAction.new(0.8)
	var fired := 0
	for i in 60:
		if hold.update(true, 1.0 / 60.0):
			fired += 1
	assert_eq(fired, 1, "fires exactly once at 0.8 s, not again while held")
	assert_eq(hold.progress(), 1.0)
	hold.update(false, 0.016)
	assert_eq(hold.progress(), 0.0)
