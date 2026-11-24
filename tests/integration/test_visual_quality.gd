extends TestCase
## 見た目の仕上げ（docs/adr/0022）: 画質の設定がすぐ島の効果に効くこと・保存されること、
## 手応えの効果が見た目だけを動かして元に戻ること（当たり判定・位置・台帳を変えない）、ステージの幕が自分で消えること。

const PATH := "user://zz_test_visual_quality.cfg"

var island: PrototypeIsland


func before_each() -> void:
	GameSettings.current = GameSettings.new(PATH)
	island = PrototypeIsland.new()
	tree.root.add_child(island)
	await wait_physics_frames(5)


func after_each() -> void:
	VisualQuality.override({})
	GameSettings.current = null
	VisualQuality.apply_all(tree)
	island.queue_free()
	for path: String in [PATH, PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	await tree.process_frame


func test_default_is_the_safe_middle_level() -> void:
	assert_eq(GameSettings.new(PATH).visual_quality, VisualQuality.Level.MID)
	var flags := VisualQuality.flags()
	assert_false(bool(flags["ssao"]), "SSAO is only on 高")
	assert_false(bool(flags["dof"]), "miniature blur starts off")
	assert_true(bool(flags["glow"]))


func test_quality_applies_to_the_current_island_at_once() -> void:
	var look := WorldLook.of(island)
	assert_true(look != null, "every island gets its WorldLook")
	GameSettings.current.set_visual_quality(VisualQuality.Level.LOW)
	VisualQuality.apply_all(tree)
	assert_false(look.environment.glow_enabled)
	assert_false(look.environment.ssao_enabled)
	assert_false(Foliage.is_enabled())
	assert_false(look.juice.bursts)
	GameSettings.current.set_visual_quality(VisualQuality.Level.HIGH)
	VisualQuality.apply_all(tree)
	assert_true(look.environment.glow_enabled)
	assert_true(look.environment.ssao_enabled)
	assert_true(Foliage.is_enabled())
	assert_true(look.juice.bursts)
	GameSettings.current.miniature_dof = true
	VisualQuality.apply_all(tree)
	assert_true(look.world_environment.camera_attributes != null)


func test_quality_round_trips_through_the_file() -> void:
	var settings := GameSettings.new(PATH)
	settings.set_visual_quality(VisualQuality.Level.HIGH)
	settings.miniature_dof = true
	assert_eq(settings.save_file(), OK)
	var loaded := GameSettings.new(PATH)
	assert_eq(loaded.load_file(), OK)
	assert_eq(loaded.visual_quality, VisualQuality.Level.HIGH)
	assert_true(loaded.miniature_dof)
	loaded.set_visual_quality(99)
	assert_eq(loaded.visual_quality, VisualQuality.Level.HIGH, "clamped")


func test_settings_menu_switches_quality() -> void:
	var hud := Hud.new()
	hud.world = island
	tree.root.add_child(hud)
	var menu := hud.pause_menu.settings_menu
	menu.settings = GameSettings.current
	menu.open()
	menu.choose_quality(VisualQuality.Level.LOW)
	assert_false(WorldLook.of(island).environment.glow_enabled)
	menu.choose_miniature_dof(true)
	assert_true(GameSettings.current.miniature_dof)
	menu.close()
	hud.queue_free()


func test_lend_squash_is_visual_only_and_settles_back() -> void:
	var block: RuleBlock = island.row[0]
	var model := block.get_node("Model") as Node3D
	var body_before := block.global_position
	island.player.global_position = Vector3(3.0, 0.0, -2.5)
	await wait_physics_frames(5)
	island.select_slot(4)
	assert_eq(island.lend_to(block, false), RuleLedger.LendResult.OK)
	await tree.process_frame
	assert_lt(model.scale.y, 0.99, "the model squashes when it receives a medal")
	assert_eq(block.global_position, body_before, "the body (collision) does not move")
	await wait_physics_frames(60)
	assert_almost(model.scale.y, 1.0, 0.001)
	assert_almost(model.position.y, 0.0, 0.001)


func test_landing_dust_does_not_pile_up() -> void:
	var juice := WorldLook.of(island).juice
	for i in 40:
		juice.dust(Vector3(0.0, 0.0, 4.0), 8, 0.7)
	var bursts := juice.find_children("*", "CPUParticles3D", false, false)
	assert_lt(bursts.size(), WorldJuice.MAX_BURSTS + 1, "bursts are capped")


func test_stage_transition_opens_and_frees_itself() -> void:
	var holder := Node.new()
	tree.root.add_child(holder)
	var transition := StageTransition.play_on(holder)
	assert_almost(transition.progress(), 0.0, 0.001)
	var again := StageTransition.play_on(holder)
	assert_eq(holder.get_child_count(), 1, "a new transition replaces the old one")
	await wait_physics_frames(
		int((StageTransition.OPEN_SECONDS + StageTransition.HOLD_SECONDS) * 60) + 10
	)
	assert_false(is_instance_valid(again), "the curtain frees itself once open")
	holder.queue_free()
