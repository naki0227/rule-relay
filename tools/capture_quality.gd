extends SceneTree
## 見た目の仕上げ（docs/quality/research.md）の前後を同じ場面で撮り、描画の重さを測る。
## 撮り方（lavapipe ＋ xvfb で Forward+。数値は CPU で描く lavapipe のものなので、効果どうしの比べ方にだけ使う）:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver vulkan --resolution 1280x720 \
##     --script res://tools/capture_quality.gd -- shot <場面> <出力.png> [低|中|高]
##   … -- measure [場面,場面,…] [枚数]   効果ごとのフレーム時間を表にして出す。lavapipe は 1280×720 で
##   1 枚 1 秒ほどかかるので、--resolution 480x270 と 12 枚くらいで測る（比べ方は同じ）
## 場面: hub（広場の出現地点）/ w1（1-1 跳ぶ力を貸す）/ w4（4 森の奥）/ w6（6 霧の段丘）/
##       expedition（遠征。いちばん大きい）/ summit（7-6 頂の祭り）/ lend（能力を渡した直後）/ clear（クリアの瞬間）

const SCENES := {
	"hub": "",
	"w1": "intro_jump_lend",
	"w4": "w4_deep_forest",
	"w6": "w6_misty_terraces",
	"expedition": "long_expedition",
	"summit": "w7_summit_6",
}
const WARMUP_FRAMES := 4

var _world: GameWorld
var _hud: Hud


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if not args.is_empty() else "shot"
	if mode == "measure":
		var names := (args[1] if args.size() > 1 else "hub,expedition,summit").split(",")
		await _measure(names, int(args[2]) if args.size() > 2 else 12)
		quit()
		return
	var scene := args[1] if args.size() > 1 else "hub"
	var out := args[2] if args.size() > 2 else "quality.png"
	if args.size() > 3:
		_set_quality(args[3])
	await _open(scene)
	await _stage_moment(scene)
	await _frames(4)
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()


func _set_quality(text: String) -> void:
	var settings := GameSettings.get_current()
	var index := ["低", "中", "高"].find(text)
	if index >= 0 and settings.has_method(&"set_visual_quality"):
		settings.call(&"set_visual_quality", index)


func _open(scene: String) -> void:
	if _world != null:
		_world.queue_free()
		if _hud != null:
			_hud.queue_free()
		await _frames(2)
	if scene in ["lend", "clear"]:
		_world = PrototypeIsland.new()
	else:
		var stage := StageWorld.new()
		var stage_id := String(SCENES.get(scene, ""))
		stage.setup(
			(
				Overworld.build(OverworldState.everything(true))
				if stage_id == ""
				else StageCatalog.by_id(stage_id)
			)
		)
		_world = stage
	root.add_child(_world)
	_hud = Hud.new()
	_hud.world = _world
	root.add_child(_hud)
	await _frames(30)
	if _world.camera_rig != null:
		_world.camera_rig.pitch = deg_to_rad(-22.0)
	await _physics(60)


func _stage_moment(scene: String) -> void:
	var island := _world as PrototypeIsland
	if scene == "lend" and island != null:
		island.camera_rig.yaw = deg_to_rad(8.0)
		island.camera_rig.pitch = deg_to_rad(-24.0)
		island.player.global_position = Vector3(2.4, 0.0, -2.0)
		await _physics(30)
		island.select_slot(4)
		island.lend_to(island.row[0], false)
		await _physics(4)
	elif scene == "clear" and island != null:
		island.player.global_position = Vector3(5.0, 3.0, -8.5)
		island.camera_rig.yaw = deg_to_rad(10.0)
		await _physics(40)
		island.goal_reached.emit()
		await _physics(30)


## 効果ごとの重さ。同じ場面・同じ視点で、設定だけを変えて count 枚の平均を取る。
func _measure(names: PackedStringArray, count: int) -> void:
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var configs := VisualQuality.measure_configs()
	var lines := PackedStringArray()
	lines.append("| 場面 | 設定 | フレーム（ms） | CPU 描画（ms） | GPU 描画（ms） |")
	lines.append("|---|---|---|---|---|")
	for scene in names:
		await _open(scene)
		for config: Array in configs:
			VisualQuality.override(config[1], self)
			await _frames(WARMUP_FRAMES)
			var cpu := 0.0
			var gpu := 0.0
			var started := Time.get_ticks_usec()
			for i in count:
				await process_frame
				cpu += RenderingServer.viewport_get_measured_render_time_cpu(
					root.get_viewport_rid()
				)
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(
					root.get_viewport_rid()
				)
			var frame := float(Time.get_ticks_usec() - started) / 1000.0 / count
			lines.append(
				(
					"| %s | %s | %.1f | %.1f | %.1f |"
					% [scene, config[0], frame, cpu / count, gpu / count]
				)
			)
			print(lines[lines.size() - 1])
	VisualQuality.override({}, self)
	print("\n".join(lines))


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _physics(count: int) -> void:
	for i in count:
		await physics_frame
