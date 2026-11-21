extends TestCase
## 一時停止のメニュー（PauseMenu。docs/adr/0020）: ステージの中は「つづける」「チェックポイントからやり直す」
## 「このステージを最初から」「このステージから出る」「せってい」「ゲームをやめる」。広場は「つづける」「せってい」
## 「ゲームをやめる」だけ。最初から・出るは、もう一度えらんで確定する。最初からはこの回だけを作り直し、
## 進行（クリア・報酬・最後に入ったポータル）は変えない。保存を消すような言い方はしない。

const PROFILE := "zz_test_pause_menu_stage"
const ROLLING := "w2_rolling_shots"
const STAGE_MENU: PackedStringArray = ["resume", "latest", "restart", "leave", "settings", "quit"]
const HUB_MENU: PackedStringArray = ["resume", "settings", "quit"]

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


func _menu() -> PauseMenu:
	return game.current_hud().pause_menu


func _enter(stage_id: String) -> void:
	game.director.enter_stage(stage_id)
	await wait_physics_frames(5)


func _put(at: Vector3) -> void:
	game.director.world.player.global_position = at
	game.director.world.player.velocity = Vector3.ZERO
	await wait_physics_frames(4)


func _clear_intro() -> void:
	await _enter(StageCatalog.INTRO_ID)
	var goal := game.director.world.def.clear_condition.goal_area()
	await _put(Vector3(goal.get_center().x, goal.position.y + 0.2, goal.get_center().z))
	await wait_physics_frames(int(PartyDirector.RETURN_DELAY * 60.0) + 20)
	assert_false(game.director.in_stage(), "back in the overworld after the clear")


func test_the_hub_menu_has_no_stage_items() -> void:
	var menu := _menu()
	menu.open()
	assert_eq(menu.visible_items(), HUB_MENU)
	menu.choose("restart")
	menu.choose("restart")
	assert_true(menu.is_open(), "a hidden item does nothing")
	assert_false(game.director.in_stage())


func test_the_stage_menu_items_and_words() -> void:
	await _enter(ROLLING)
	var menu := _menu()
	menu.open()
	assert_eq(menu.visible_items(), STAGE_MENU)
	assert_eq(menu.item_text("latest"), "チェックポイントからやり直す")
	assert_eq(menu.item_text("restart"), "このステージを最初から")
	assert_eq(menu.item_text("leave"), "このステージから出る")
	for item: Array in PauseMenu.ITEMS:
		var words := "%s %s" % [item[1], item[2]]
		assert_false(words.contains("保存"), "no word about saves: %s" % words)
		assert_false(words.contains("消"), "nothing sounds like deleting: %s" % words)
		assert_false(words.contains("ひとつ前"), "the previous-save item is gone")
	menu.choose("restart")
	assert_eq(menu.item_text("restart"), "もう一度えらぶと、このステージを最初から")
	menu.choose("leave")
	assert_eq(menu.item_text("restart"), "このステージを最初から", "choosing another item disarms")
	assert_eq(menu.item_text("leave"), "もう一度えらぶと、このステージから出る")
	menu.choose("resume")
	assert_false(menu.is_open())
	assert_eq(game.director.stage_id, ROLLING, "nothing happened")


## 「チェックポイントからやり直す」: ひとりなら 1 票で決まり、チェックポイント（無ければステージの始め）へ戻る。
func test_restarting_from_the_checkpoint() -> void:
	await _enter(ROLLING)
	var run := game.director.stage_run_id
	var spawn := game.director.world.spawn_for(RuleLedger.PLAYER_ID)
	await _put(spawn + Vector3(3.0, 0.0, 0.0))
	_menu().open()
	_menu().choose("latest")
	await wait_physics_frames(5)
	assert_false(_menu().is_open())
	assert_eq(game.director.lifecycle.reset_count(), 1, "the reset went through")
	assert_eq(game.director.stage_run_id, run, "the same run")
	assert_lt(game.director.world.player.global_position.distance_to(spawn), 1.2, "back at start")


## 「このステージを最初から」: 鳴らした鐘も戻る新しい回になるが、クリア・報酬・最後に入ったポータルは同じ。
func test_restarting_the_stage_keeps_campaign_progress() -> void:
	await _clear_intro()
	var before := game.director.progress.to_dict()
	assert_true(game.director.progress.has_cleared(StageCatalog.INTRO_ID))
	await _enter(ROLLING)
	before["last_portal"] = ROLLING
	var run := game.director.stage_run_id
	var on_disk := ProgressStore.new().load_progress(PROFILE).progress.to_dict()
	game.director.world.bells_by_key["isle_bell"].ring()
	await wait_physics_frames(3)
	assert_true(game.director.world.activated.has("isle_bell"))
	var menu := _menu()
	menu.open()
	menu.choose("restart")
	assert_true(menu.is_open(), "the first press only asks again")
	assert_eq(game.director.stage_run_id, run)
	menu.choose("restart")
	await wait_physics_frames(5)
	assert_eq(game.director.stage_id, ROLLING, "still on this stage")
	assert_ne(game.director.stage_run_id, run, "a fresh run")
	assert_false(game.director.world.activated.has("isle_bell"), "the bell is quiet again")
	assert_eq(game.director.progress.to_dict(), before, "campaign progress is untouched")
	var saved := ProgressStore.new().load_progress(PROFILE).progress
	assert_eq(saved.to_dict(), on_disk, "the save on disk is untouched too")
	assert_true(saved.has_cleared(StageCatalog.INTRO_ID))
	assert_eq(saved.clear_count(StageCatalog.INTRO_ID), 1, "no extra clear and no lost clear")


## 「このステージから出る」: 二度えらぶと、このステージのポータルの前へ。
func test_leaving_the_stage_from_the_menu() -> void:
	await _enter(ROLLING)
	var menu := _menu()
	menu.open()
	menu.choose("leave")
	await wait_physics_frames(3)
	assert_eq(game.director.stage_id, ROLLING, "the first press only asks again")
	menu.choose("leave")
	await wait_physics_frames(5)
	assert_eq(game.director.stage_id, StageCatalog.HUB_ID)
	var spot := game.director.world.def.overworld.portal(ROLLING).returns[0]
	var at := game.director.world.player.global_position
	assert_lt(Vector2(at.x - spot.x, at.z - spot.z).length(), 0.3, "in front of the portal")
	_menu().open()
	assert_eq(_menu().visible_items(), HUB_MENU, "the new hub menu has no stage items")
