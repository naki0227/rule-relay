extends TestCase
## 画質（低・中・高。VisualQuality）の、描画の重さに効く項目（docs/adr/0023-performance-and-render-quality.md）:
## 低いほど重くならない順・画面への反映・日の光の影の分割と距離。

const RENDER_KEYS: PackedStringArray = [
	"shadow_mode",
	"shadow_distance",
	"shadow_atlas",
	"shadow_filter",
	"msaa",
	"fxaa",
	"render_scale",
	"lod_threshold",
]

var _nodes: Array[Node] = []


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	GameSettings.current = null
	VisualQuality.apply_all(tree)
	await tree.process_frame


func _row(level: int) -> Dictionary:
	var values := {}
	for key: String in VisualQuality.TABLE:
		values[key] = (VisualQuality.TABLE[key] as Array)[level]
	return values


func test_every_render_item_has_three_levels() -> void:
	for key in RENDER_KEYS:
		assert_true(VisualQuality.TABLE.has(key), key)
		assert_eq((VisualQuality.TABLE[key] as Array).size(), VisualQuality.NAMES.size(), key)


func test_lower_levels_are_never_heavier() -> void:
	var low := _row(VisualQuality.Level.LOW)
	var mid := _row(VisualQuality.Level.MID)
	var high := _row(VisualQuality.Level.HIGH)
	for pair: Array in [[low, mid], [mid, high]]:
		var a := pair[0] as Dictionary
		var b := pair[1] as Dictionary
		assert_true(int(a["shadow_mode"]) <= int(b["shadow_mode"]), "shadow splits")
		assert_true(float(a["shadow_distance"]) <= float(b["shadow_distance"]), "shadow distance")
		assert_true(int(a["shadow_atlas"]) <= int(b["shadow_atlas"]), "shadow atlas")
		assert_true(int(a["msaa"]) <= int(b["msaa"]), "msaa")
		assert_true(float(a["render_scale"]) <= float(b["render_scale"]), "render scale")
		assert_true(float(a["lod_threshold"]) >= float(b["lod_threshold"]), "LOD threshold")
	assert_almost(float(high["render_scale"]), 1.0, 0.001, "high draws at full resolution")


func test_apply_render_sets_the_viewport() -> void:
	var view := SubViewport.new()
	_nodes.append(view)
	tree.root.add_child(view)
	VisualQuality.apply_render(view, _row(VisualQuality.Level.LOW))
	assert_almost(view.scaling_3d_scale, 0.75, 0.001)
	assert_eq(view.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR)
	assert_eq(view.msaa_3d, Viewport.MSAA_DISABLED)
	VisualQuality.apply_render(view, _row(VisualQuality.Level.MID))
	assert_eq(view.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA)
	assert_almost(view.scaling_3d_scale, 1.0, 0.001)
	VisualQuality.apply_render(view, _row(VisualQuality.Level.HIGH))
	assert_eq(view.msaa_3d, Viewport.MSAA_2X)
	assert_eq(view.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED)


## 島の日の光は、画質を変えるとすぐ影の分割と距離が変わる（せっていで選んだとき）。
func test_changing_quality_updates_the_sun_shadows() -> void:
	var world := Node3D.new()
	_nodes.append(world)
	tree.root.add_child(world)
	PrototypeIsland.build_environment(world)
	var look := WorldLook.of(world)
	assert_ne(look, null)
	GameSettings.current = GameSettings.new("user://zz_test_render_quality.cfg")
	GameSettings.current.set_visual_quality(VisualQuality.Level.LOW)
	VisualQuality.apply_all(tree)
	assert_eq(look.sun.directional_shadow_mode, DirectionalLight3D.SHADOW_ORTHOGONAL)
	assert_almost(look.sun.directional_shadow_max_distance, 32.0, 0.001)
	assert_almost(tree.root.scaling_3d_scale, 0.75, 0.001, "low draws 3D at 75%")
	GameSettings.current.set_visual_quality(VisualQuality.Level.HIGH)
	VisualQuality.apply_all(tree)
	assert_eq(look.sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_almost(look.sun.directional_shadow_max_distance, 60.0, 0.001)
	assert_eq(tree.root.msaa_3d, Viewport.MSAA_2X)
