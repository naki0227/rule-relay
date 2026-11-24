extends SceneTree
## 重い場面の性能を測る（docs/reports/2026-11-24-performance.md）。ふつうは包みの tools/perf_bench.sh から呼ぶ:
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##     godot --rendering-driver vulkan --resolution 1280x720 --fixed-fps 60 \
##     --script res://tools/perf_bench.gd -- <scene> <seconds> <out.json> [quality]
## scene: SCENES のどれか。決まったカメラの道筋で seconds 秒（--fixed-fps 60 なので 60×seconds コマ）動かし、
## 1 コマごとに Godot の Performance の値を記録して、平均・p95・p99 を JSON に書く。
## quality: low / medium / high（せってい → 画質。VisualQuality）。省略か none なら、ゲームが選んだ画質のまま
## （はじめての起動の既定は中）。
##
## lavapipe は CPU で描くラスタライザなので、フレーム時間の絶対値（特に描画の重さ）は実機の GPU と比べられない。
## 比べてよいのは、描画の呼び出し回数・描いた物体と三角形の数・ノードの数・CPU（process）と物理の時間。

const PROFILE := "zz_perf_bench"
const SCENES: PackedStringArray = [
	"hub",
	"long_expedition",
	"w7_summit_6",
	"w6_peak_bells",
	"w4_herd_path",
	"o2_5",
	"coop4",
	"range_lend",
]
const FPS := 60.0
## 測る前に流すコマ（読み込み直後の作り直し・影の初回の描画を外す）。
const WARMUP_FRAMES := 30
const COOP_STAGE := "w7_summit_6"

var game: Node
var director: PartyDirector
var w: StageWorld
var _cine: Camera3D
var _party: RefCounted
var _test: TestCase
## 範囲で渡した場面: 範囲付与の瞬間（地形の作り直し）にかかった時間（ミリ秒）。
var _commit_ms: float = -1.0
var _range_cells: int = 0
var _frame_bytes: Array[int] = []
var _quality: String = "none"
## WorldFrame.Sender（改善の前の版には無いので、あるときだけ作る。無ければ毎回全部を送っていた）
var _sender: RefCounted


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene := args[0] if not args.is_empty() else "hub"
	var seconds := float(args[1]) if args.size() > 1 else 10.0
	var out := args[2] if args.size() > 2 else "user://perf_%s.json" % scene
	var quality := args[3] if args.size() > 3 else ""
	if quality == "none":
		quality = ""  # ゲームが自分で選んだ画質のまま（性能の改善の前と比べるとき）
	var level := ["low", "medium", "high"].find(quality)
	if quality != "" and level < 0:
		printerr("perf_bench: quality must be low / medium / high / none")
		quit(2)
		return
	if level >= 0:
		_quality = quality
	if not SCENES.has(scene):
		printerr("perf_bench: scene must be one of %s" % ", ".join(SCENES))
		quit(2)
		return
	var load_start := Time.get_ticks_usec()
	match scene:
		"coop4":
			await _open_coop()
		"hub", "range_lend":
			await _open_hub()
		_:
			await _open_stage(scene)
	var load_ms := (Time.get_ticks_usec() - load_start) / 1000.0
	if level >= 0:
		_apply_quality(level)
	for i in WARMUP_FRAMES:
		await process_frame
	var path := _camera_path(scene)
	var samples := await _measure(scene, path, int(seconds * FPS))
	var report := _summary(scene, samples, load_ms)
	if scene == "hub":
		report["promote_cell_ms"] = _promote_cost()
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("perf_bench: %s -> %s" % [scene, out])
	print(JSON.stringify(report))
	await _close()
	quit()


## 画質（せってい → 画質 の 低・中・高）を選んで反映する（GameSettings.set_visual_quality と
## VisualQuality.apply_all）。改善の前の版には VisualQuality が無いので、名前で探す。
func _apply_quality(level: int) -> void:
	GameSettings.get_current().set_visual_quality(level)
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if entry["class"] == &"VisualQuality":
			(load(String(entry["path"])) as Script).call(&"apply_all", self)
			return
	printerr("perf_bench: this version has no VisualQuality")


# --- 場面を開く ----------------------------------------------------------------


func _start_game() -> void:
	ProgressStore.new().delete(PROFILE)
	game = (load("res://scenes/prototype_island.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame


## 全部のステージをクリアした記録（広場に住む生き物と建物が全部そろう）。
func _save_all_cleared() -> void:
	var stages := {}
	for def in StageCatalog.all_stages():
		stages[def.stage_id] = {
			"first_cleared_at": 1, "clear_count": 1, "records": {}, "party_sizes": [1]
		}
	var progress := PlayerProgress.from_dict({"stages": stages})
	ProgressStore.new().save(PROFILE, progress)


func _open_hub() -> void:
	await _start_game()
	_save_all_cleared()
	game.call(&"start_solo", PROFILE)
	director = game.get("director") as PartyDirector
	director.all_abilities_unlocked = true
	director.enter_stage(StageCatalog.HUB_ID)
	await _physics(20)
	w = director.world


func _open_stage(stage_id: String) -> void:
	await _start_game()
	game.call(&"start_solo", PROFILE)
	director = game.get("director") as PartyDirector
	await _physics(10)
	director.enter_stage(stage_id)
	await _physics(20)
	w = director.world


## 4 人の協力（同じプロセスにホストと参加者 3 人。ENet 127.0.0.1。tests/integration/net_party.gd）。
## 画面に出すのはホストの世界だけ（参加者の世界は 16x16 の SubViewport で、描画はほぼ 0）。
## 参加者 3 人分の物理と process も同じプロセスで動くので、CPU の時間は 1 台の PC の 4 倍近くになる。
func _open_coop() -> void:
	ProgressStore.new().delete(PROFILE)
	_test = TestCase.new()
	_test.tree = self
	var script := load("res://tests/integration/net_party.gd") as GDScript
	_party = script.new(_test, 4, PROFILE) as RefCounted
	await _party.call(&"open")
	await _party.call(&"join_all")
	await _party.call(&"enter", COOP_STAGE)
	var directors := _party.get("directors") as Array
	director = directors[0] as PartyDirector
	w = director.world
	# ホストの世界を画面いっぱいに描く（実際のホストの PC と同じ描画の量にする）
	var view := director.get_parent() as SubViewport
	view.size = Vector2i(root.get_visible_rect().size)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var picture := TextureRect.new()
	picture.texture = view.get_texture()
	picture.size = Vector2(view.size)
	layer.add_child(picture)
	if not _test.get_failures().is_empty():
		printerr("perf_bench: coop setup: %s" % "; ".join(_test.get_failures()))


func _close() -> void:
	if _party != null:
		await _party.call(&"close")
	ProgressStore.new().delete(PROFILE)
	if game != null:
		game.queue_free()
	await process_frame


# --- カメラの道筋 --------------------------------------------------------------


## 道筋の前半はプレイヤーの肩越しの視点で 1 周見回し、後半は島の上を回る撮影用のカメラで全体を見る。
## 範囲で渡す場面は、範囲付与のあと跳ねるブロックを見続ける。
func _camera_path(scene: String) -> Dictionary:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for cell: Vector3i in w.terrain.cells:
		lo = lo.min(Vector3(cell))
		hi = hi.max(Vector3(cell))
	var center := (lo + hi) * 0.5
	var extent := maxf(hi.x - lo.x, hi.z - lo.z)
	return {
		"center": center,
		"radius": clampf(extent * 0.45, 12.0, 48.0),
		"height": clampf(extent * 0.3, 10.0, 30.0),
		"range": scene == "range_lend",
	}


func _place_camera(path: Dictionary, t: float) -> void:
	if bool(path["range"]):
		w.camera_rig.yaw = deg_to_rad(20.0) + sin(t * TAU) * 0.6
		w.camera_rig.pitch = deg_to_rad(-30.0)
		return
	if t < 0.5:
		if _cine != null:
			_cine.current = false
		w.camera_rig.yaw = t * 2.0 * TAU
		w.camera_rig.pitch = deg_to_rad(-14.0)
		return
	if _cine == null:
		_cine = Camera3D.new()
		_cine.far = 400.0
		_cine.fov = 55.0
		w.add_child(_cine)
	_cine.current = true
	var angle := (t - 0.5) * 2.0 * TAU
	var center := path["center"] as Vector3
	var radius := float(path["radius"])
	_cine.global_position = (
		center + Vector3(cos(angle) * radius, float(path["height"]), sin(angle) * radius)
	)
	_cine.look_at(center)


# --- 測る -----------------------------------------------------------------------


func _measure(scene: String, path: Dictionary, frames: int) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	if scene == "range_lend":
		_commit_ms = _range_lend()
	var last := Time.get_ticks_usec()
	for f in frames:
		_place_camera(path, float(f) / float(frames))
		if (_party != null or scene == "range_lend") and f % 3 == 0:
			_frame_bytes.append(var_to_bytes(_capture_frame()).size())
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(_sample((now - last) / 1000.0))
		last = now
	return samples


## 広場の草原で、足もとの先の地面へジャンプを「繰り返し」で範囲に渡す（半径 5 の円の中のセルが全部、
## 動くブロックになって跳ね続ける）。かかった時間（ミリ秒）を返す。
func _range_lend() -> float:
	w.player.global_position = Vector3(2.5, 0.2, 18.5)
	w.player.velocity = Vector3.ZERO
	w.camera_rig.yaw = deg_to_rad(20.0)
	var jump := -1
	for slot in RuleLedger.HOTBAR_SIZE:
		var v := w.ledger.hotbar_vessel(slot, w.acting_id())
		if v != null and w.ledger.token(v.token_id).action == RuleAction.Kind.JUMP:
			jump = slot
	if jump < 0:
		printerr("perf_bench: no jump in the hotbar")
		return -1.0
	w.select_slot(jump)
	w.set_lend_mode(TriggerMode.Kind.REPEAT)
	var target := w.terrain_target(Vector3i(2, -1, 15))
	_range_cells = (w.range_selection(target)["cells"] as Array).size()
	var start := Time.get_ticks_usec()
	var result := w.lend_to(target, true)
	var spent := (Time.get_ticks_usec() - start) / 1000.0
	if result != RuleLedger.LendResult.OK:
		printerr("perf_bench: range lend failed: %s" % result)
	return spent


## ホストが 1 秒に 20 回配る世界の様子（NetWorld と同じく、前に送った分を覚えて動いた分だけを入れる）。
func _capture_frame() -> Dictionary:
	var script := WorldFrame as Script
	var constants := script.get_script_constant_map()
	if not constants.has("Sender"):
		return script.call(&"capture", w) as Dictionary
	if _sender == null:
		_sender = (constants["Sender"] as GDScript).new() as RefCounted
	return script.call(&"capture", w, _sender) as Dictionary


## 1 マスを動くブロックにして、地形の見た目と当たり判定を作り直すまでの時間（ミリ秒。10 マスの中央値）。
## 改善の前は見た目の作り直しがそのコマの終わりに遅れて走るので、ここで rebuild を呼んで同じ量を測る。
func _promote_cost() -> float:
	var spent := PackedFloat64Array()
	var cells: Array[Vector3i] = []
	for cell: Vector3i in w.terrain.cells:
		if cell.y == -1 and Vector2(cell.x - 8, cell.z - 8).length() < 3.0:
			cells.append(cell)
	cells.sort()
	for cell: Vector3i in cells.slice(0, 10):
		var start := Time.get_ticks_usec()
		TerrainPromotion.promote(w, cell)
		w.terrain.call(&"flush" if w.terrain.has_method(&"flush") else &"rebuild")
		spent.append((Time.get_ticks_usec() - start) / 1000.0)
	spent.sort()
	return snappedf(spent[spent.size() / 2], 0.1) if not spent.is_empty() else -1.0


func _sample(frame_ms: float) -> Dictionary:
	return {
		"frame_ms": frame_ms,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
	}


func _summary(scene: String, samples: Array[Dictionary], load_ms: float) -> Dictionary:
	var report := {
		"scene": scene,
		"frames": samples.size(),
		"quality": _quality,
		"load_ms": snappedf(load_ms, 0.1),
	}
	for key: String in ["frame_ms", "process_ms", "physics_ms"]:
		var values := PackedFloat64Array()
		for s in samples:
			values.append(float(s[key]))
		report[key] = _stats(values)
	for key: String in ["draw_calls", "objects", "primitives"]:
		var values := PackedFloat64Array()
		for s in samples:
			values.append(float(s[key]))
		var stats := _stats(values)
		report[key] = {"avg": stats["avg"], "max": stats["max"]}
	report["video_mem_mb"] = snappedf(
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1
	)
	report["static_mem_mb"] = snappedf(
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1
	)
	report["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	report["objects_alive"] = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	report["physics_active"] = int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	report["collision_pairs"] = int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
	report["scene_counts"] = PerfCounts.of(w)
	if scene == "range_lend":
		report["range_commit_ms"] = snappedf(_commit_ms, 0.1)
		report["range_cells"] = _range_cells
	if not _frame_bytes.is_empty():
		var total := 0
		for b in _frame_bytes:
			total += b
		var avg := float(total) / _frame_bytes.size()
		report["net_frame_bytes"] = snappedf(avg, 1.0)
		# ホストは 1 秒に 20 回、参加者 3 人へ配る（NetWorld.SEND_PERIOD）
		report["net_host_upload_kbps"] = snappedf(avg * 20.0 * 3.0 * 8.0 / 1000.0, 0.1)
	return report


static func _stats(values: PackedFloat64Array) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in sorted:
		total += v
	return {
		"avg": snappedf(total / sorted.size(), 0.01),
		"p95": snappedf(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], 0.01),
		"p99": snappedf(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))], 0.01),
		"max": snappedf(sorted[sorted.size() - 1], 0.01),
	}


func _physics(frames: int) -> void:
	for i in frames:
		await physics_frame
