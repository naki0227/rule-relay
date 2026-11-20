extends TestCase
## BGM: 場面ごとの曲・同じ曲を頼んでも鳴らし直さない・入れ替え・メニュー中のダッキング・
## タイトル → ハブ → 島の切り替えに付いていくこと。ヘッドレスでは実際の再生はしない（MusicPlayer._start）。

const PROFILE := "zz_test_music"

var music: MusicPlayer


func before_each() -> void:
	music = MusicPlayer.new()
	tree.root.add_child(music)
	await tree.process_frame


func after_each() -> void:
	music.queue_free()
	await tree.process_frame


func test_each_scene_has_its_track() -> void:
	assert_eq(MusicPlayer.scene_for_stage(StageCatalog.HUB_ID), MusicPlayer.HUB)
	for stage: StageDef in StageCatalog.all_stages():
		assert_eq(MusicPlayer.scene_for_stage(stage.stage_id), MusicPlayer.STAGE, stage.stage_id)
	assert_eq(MusicPlayer.track_for(MusicPlayer.TITLE), "res://assets/audio/music/title_1.ogg")
	assert_eq(MusicPlayer.track_for(MusicPlayer.HUB), "res://assets/audio/music/hub_1.ogg")
	assert_eq(MusicPlayer.track_for(MusicPlayer.STAGE), "res://assets/audio/music/think_1.ogg")
	assert_eq(MusicPlayer.track_for(&"nope"), "")


func test_tracks_load_as_seamless_loops() -> void:
	for scene: StringName in MusicPlayer.TRACKS:
		var stream := load(MusicPlayer.track_for(scene)) as AudioStreamOggVorbis
		assert_ne(stream, null, String(scene))
		assert_true(stream.loop, "%s loops" % scene)
		assert_almost(stream.loop_offset, 0.0, 0.0001, "%s loops from the very start" % scene)
		assert_gt(stream.get_length(), 30.0)


func test_music_uses_its_own_bus_next_to_the_sfx_bus() -> void:
	for bus: StringName in [AudioBuses.MUSIC, AudioBuses.SFX, AudioBuses.UI, AudioBuses.WORLD]:
		assert_ne(AudioServer.get_bus_index(bus), -1, String(bus))
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(AudioBuses.UI)), AudioBuses.SFX)
	assert_eq(AudioServer.get_bus_send(AudioServer.get_bus_index(AudioBuses.WORLD)), AudioBuses.SFX)
	assert_lt(
		AudioServer.get_bus_index(AudioBuses.SFX),
		AudioServer.get_bus_index(AudioBuses.UI),
		"a bus can only send to an earlier one"
	)
	for player: Node in music.get_children():
		assert_eq((player as AudioStreamPlayer).bus, AudioBuses.MUSIC)


func test_same_track_does_not_restart() -> void:
	assert_true(music.play_scene(MusicPlayer.HUB))
	assert_eq(music.starts, 1)
	assert_false(music.play_scene(MusicPlayer.HUB), "asking again keeps it playing")
	assert_eq(music.starts, 1)
	assert_true(music.play_scene(MusicPlayer.STAGE))
	assert_false(music.play_scene(MusicPlayer.scene_for_stage(StageCatalog.INTRO_ID)))
	assert_eq(music.starts, 2)
	assert_eq(music.current_track, MusicPlayer.track_for(MusicPlayer.STAGE))


func test_crossfade_swaps_the_two_voices() -> void:
	music.play_scene(MusicPlayer.TITLE)
	await wait_physics_frames(roundi(MusicPlayer.FADE_SECONDS * 60.0) + 20)
	music.play_scene(MusicPlayer.HUB)
	await wait_physics_frames(roundi(MusicPlayer.FADE_SECONDS * 30.0))
	var middle: Array[float] = [music._gains[0], music._gains[1]]
	assert_gt(middle[0], 0.05, "the title is still fading out halfway: %s" % str(middle))
	assert_gt(middle[1], 0.05, "the hub is already fading in halfway: %s" % str(middle))
	await wait_physics_frames(roundi(MusicPlayer.FADE_SECONDS * 30.0) + 20)
	# 最初の曲は枠 1、次の曲は枠 0 で鳴る（交互に使う）
	assert_almost(music._gains[1], 0.0, 0.01)
	assert_almost(music._gains[0], 1.0, 0.01)
	var players := music.get_children()
	assert_true((players[1] as AudioStreamPlayer).stream == null, "the faded voice is released")
	assert_true((players[0] as AudioStreamPlayer).stream != null)


func test_menus_duck_the_music() -> void:
	var open := [false]
	music.duck_source = func() -> bool: return bool(open[0])
	music.play_scene(MusicPlayer.HUB)
	await wait_physics_frames(120)
	var player := music.get_children()[1] as AudioStreamPlayer
	assert_almost(player.volume_db, 0.0, 0.1)
	open[0] = true
	await wait_physics_frames(60)
	assert_true(music.is_ducked())
	assert_almost(player.volume_db, MusicPlayer.DUCK_DB, 0.1)
	open[0] = false
	await wait_physics_frames(60)
	assert_almost(player.volume_db, 0.0, 0.1)


## GameRoot が タイトル → ハブ → 島 → ハブ の切り替えに曲を合わせ、メニューで下げること。
func test_game_root_follows_title_hub_and_stage() -> void:
	ProgressStore.new().delete(PROFILE)
	var root := GameRoot.new()
	tree.root.add_child(root)
	await tree.process_frame
	assert_eq(root.music.current_scene, MusicPlayer.TITLE)
	root.start_solo(PROFILE)
	await wait_physics_frames(5)
	assert_eq(root.music.current_scene, MusicPlayer.HUB)
	root.director.enter_stage(StageCatalog.INTRO_ID)
	await wait_physics_frames(5)
	assert_eq(root.music.current_scene, MusicPlayer.STAGE)
	var starts := root.music.starts
	root.director.request_restart()
	await wait_physics_frames(5)
	assert_eq(root.music.starts, starts, "restarting the island keeps the same song going")
	var hud := _live_hud(root)
	assert_false(root.music.is_ducked())
	hud.pause_menu.open()
	assert_true(root.music.is_ducked(), "the pause menu lowers the music")
	hud.pause_menu.close()
	root.director.enter_stage(StageCatalog.HUB_ID)
	await wait_physics_frames(5)
	assert_eq(root.music.current_scene, MusicPlayer.HUB)
	root.shutdown()
	root.queue_free()
	await tree.process_frame
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSettings.current = null
	KeyBindings.new().apply()
	ProgressStore.new().delete(PROFILE)


func _live_hud(root: GameRoot) -> Hud:
	for child: Node in root.get_children():
		if child is Hud and not child.is_queued_for_deletion():
			return child as Hud
	return null
