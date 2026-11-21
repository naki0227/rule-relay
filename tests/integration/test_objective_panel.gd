extends TestCase
## 画面の目的の一覧（ObjectivePanel。docs/adr/0020）: ステージに入ると大きく出て、少しすると右上の隅へ縮む。
## 目的を見るキー・一時停止のメニューでもう一度大きく出る。メニューの「このステージから出る」でポータルの前へ戻る。
## 広場では出さない。

const PROFILE := "zz_test_objective_panel"
const ROLLING := "w2_rolling_shots"

var game: GameRoot


func before_each() -> void:
	ProgressStore.new().delete(PROFILE)
	InputMap.load_from_project_settings()
	game = GameRoot.new()
	tree.root.add_child(game)
	game.start_solo(PROFILE)
	await wait_physics_frames(5)


func after_each() -> void:
	tree.paused = false
	game.shutdown()
	game.queue_free()
	await tree.process_frame
	ProgressStore.new().delete(PROFILE)


func _panel() -> ObjectivePanel:
	return game.current_hud().get_node("Objectives") as ObjectivePanel


func _wait_seconds(seconds: float) -> void:
	await wait_physics_frames(int(seconds * 60.0))


func test_hidden_in_the_overworld() -> void:
	await wait_physics_frames(3)
	assert_false(_panel().visible, "no objectives in the overworld")
	assert_false(game.current_hud().pause_menu.leave_request.is_valid(), "no leave item there")


func test_entering_a_stage_shows_the_objectives_big_then_in_the_corner() -> void:
	game.director.enter_stage(ROLLING)
	await wait_physics_frames(3)
	var panel := _panel()
	assert_true(panel.visible)
	assert_true(panel.is_big(), "big right after entering")
	assert_eq(panel.lines().size(), 3, str(panel.lines()))
	await _wait_seconds(ObjectivePanel.BIG_SECONDS + 1.2)
	assert_false(panel.is_big(), "shrunk after a few seconds")
	assert_true(panel.is_corner_shown(), "kept small in the corner")
	# 目的を見るキーで、もう一度大きく
	var press := InputEventAction.new()
	press.action = &"show_objectives"
	press.pressed = true
	Input.parse_input_event(press)
	await wait_physics_frames(3)
	assert_true(panel.is_big(), "the key shows them again")


func test_the_pause_menu_shows_them_and_can_leave_the_stage() -> void:
	game.director.enter_stage(ROLLING)
	await wait_physics_frames(3)
	await _wait_seconds(ObjectivePanel.BIG_SECONDS + 1.2)
	var menu := game.current_hud().pause_menu
	menu.open()
	await tree.process_frame
	await tree.process_frame
	assert_true(_panel().is_big(), "shown next to the pause menu")
	assert_true(menu.leave_request.is_valid(), "the leave item is there in a stage")
	menu.choose("leave")
	assert_true(menu.is_open(), "leaving needs a second press")
	menu.choose("leave")
	await wait_physics_frames(5)
	assert_false(tree.paused)
	assert_eq(game.director.stage_id, StageCatalog.HUB_ID, "left the stage")
	var portal := game.director.world.def.overworld.portal(ROLLING)
	var at := game.director.world.player.global_position
	assert_lt(Vector2(at.x - portal.returns[0].x, at.z - portal.returns[0].z).length(), 0.3)


func test_checks_fill_live_on_screen() -> void:
	game.director.enter_stage(ROLLING)
	await wait_physics_frames(3)
	game.director.world.bells_by_key["isle_bell"].ring()
	await wait_physics_frames(3)
	assert_true(_panel().lines().has("[x] 鐘を鳴らす"), str(_panel().lines()))
