class_name OverworldPortal
extends Node3D
## 広場のワープの門（ポータル）。F で入る場所は StageDef.EntranceSpec が決め、これは見た目だけ。
## - 開いている門: 空色の渦が回る（アニメーション「swirl」）。上に番号・名前・目安時間・F の文字
## - 閉じている門: 渦を灰色にして止める。「まだ開いていない」
## - クリアした門: てっぺんに金色の花の印（ClearedMark）
## - 上の文字は、カメラが近いと大きくなりすぎないように、LABEL_FULL_AT より近いと画面での大きさを止め
##   （近づくほど小さく描く）、LABEL_FADE_FROM より近いと薄くして消す（戻った直後・門のそばを通ったとき）
## モデルは art/scripts/build_overworld.py の portal_arch。

const MODEL := "portal_arch"
const LABEL_HEIGHT: float = 3.55
const DIM_SWIRL := Color("#a9a39a")
const DIM_GLOW := Color("#8f8a83")
## カメラからこのきょりより近いと、文字の画面での大きさをこのきょりのときのままにする。
const LABEL_FULL_AT: float = 8.0
## カメラからこのきょりより近いと文字を薄くし、LABEL_GONE_AT で消す。
const LABEL_FADE_FROM: float = 3.5
const LABEL_GONE_AT: float = 2.0

var spec: OverworldLayout.PortalSpec
## 寄り道のワールドの入口（まだステージが無い）なら、その名前
var teaser_title: String = ""
var label: KeyLabel3D

var _model: Node3D


func setup_portal(p_spec: OverworldLayout.PortalSpec) -> void:
	spec = p_spec
	name = "Portal_%s" % spec.stage_id
	position = spec.position
	rotation.y = spec.facing - PI


func setup_teaser(t: OverworldLayout.TeaserSpec) -> void:
	teaser_title = t.title
	name = "Teaser_%s" % t.title
	position = t.position
	rotation.y = t.facing - PI


func _ready() -> void:
	_build_look()


## 開き方が変わったら、見た目を作り直す（寄り道のワールドの入口を見つけたとき）。
func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build_look()


func _build_look() -> void:
	_model = ModelLibrary.instantiate(MODEL)
	# モデルの正面（Blender の +Y）は -Z。南（+Z）から近づくので半回転させる
	_model.rotation.y = PI
	add_child(_model)
	var mark := _model.find_child("ClearedMark", true, false) as Node3D
	if mark != null:
		mark.visible = is_cleared()
	if is_open():
		var rig := RigAnimator.new(_model)
		if rig.has(&"swirl"):
			rig.player.get_animation(&"swirl").loop_mode = Animation.LOOP_LINEAR
			rig.play(&"swirl")
	else:
		ModelLibrary.tint_material(_model, "SwirlDeep", DIM_SWIRL)
		ModelLibrary.tint_material(_model, "SwirlLight", DIM_SWIRL.lightened(0.2))
		ModelLibrary.tint_material(_model, "PortalGlow", DIM_GLOW)
		_unlit(_model)
	label = PrototypeIsland.add_label(self, Vector3(0.0, LABEL_HEIGHT, 0.0), caption())


func _process(_delta: float) -> void:
	if label == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	fit_label(cam.global_position.distance_to(label.global_position))


## カメラとのきょりに合わせて、文字の大きさと濃さを決める（テストからも呼ぶ）。
func fit_label(distance: float) -> void:
	label.scale = Vector3.ONE * clampf(distance / LABEL_FULL_AT, 0.05, 1.0)
	var alpha := clampf((distance - LABEL_GONE_AT) / (LABEL_FADE_FROM - LABEL_GONE_AT), 0.0, 1.0)
	label.modulate.a = alpha
	label.outline_modulate.a = 0.95 * alpha
	label.visible = alpha > 0.0


func is_open() -> bool:
	return spec != null and spec.open


func is_cleared() -> bool:
	return spec != null and spec.cleared


## 門の上に浮かべる文字。
func caption() -> String:
	if spec == null:
		return "寄り道のワールド\n%s（準備中）" % teaser_title
	var head := "%s %s%s" % [spec.label, spec.title, "（むずかしい）" if spec.hard else ""]
	if not spec.open:
		return "%s\nまだ開いていない" % head
	var lines := "%s\n目安 %d 分（仮）・%s" % [head, spec.target_minutes, InputMode.token(&"interact")]
	if spec.cleared:
		lines += "\nクリア済み"
	if spec.first:
		lines = "はじめはここから\n" + lines
	return lines


## 閉じた門は光らせない（灰色の渦が光ると、開いているように見える）。
static func _unlit(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for i in mesh_instance.mesh.get_surface_count():
			var tinted := mesh_instance.get_surface_override_material(i) as StandardMaterial3D
			if tinted != null:
				tinted.emission_enabled = false
