class_name OverworldDressing
extends RefCounted
## 広場（オーバーワールド）の見た目を StageWorld に置く: ポータル・寄り道の門・住む生き物・建物・置物・
## 立て札。データは OverworldLayout（Overworld が OverworldState から作る）。どれも当たり判定を持たない。

const SIGN_HEIGHT: float = 1.6


static func build(world: Node3D, layout: OverworldLayout) -> void:
	_soften_fog(world)
	var root := Node3D.new()
	root.name = "OverworldDressing"
	world.add_child(root)
	for p in layout.portals:
		var portal := OverworldPortal.new()
		portal.setup_portal(p)
		root.add_child(portal)
	for t in layout.teasers:
		var teaser := OverworldPortal.new()
		teaser.setup_teaser(t)
		root.add_child(teaser)
	for r in layout.residents:
		var resident := OverworldResident.new()
		resident.setup(r)
		root.add_child(resident)
	var props := Node3D.new()
	props.name = "Props"
	root.add_child(props)
	for spec in layout.props:
		var model := ModelLibrary.instantiate(spec.model)
		model.position = spec.position
		model.rotation.y = spec.yaw
		model.scale = spec.size if spec.size != Vector3.ZERO else Vector3.ONE * spec.scale
		if spec.building:
			model.name = "Building_%s" % spec.model
			_play_loops(model)
		props.add_child(model)
	for sign in layout.signs:
		var post := ModelLibrary.instantiate("hub_lamp")
		post.position = sign.position
		root.add_child(post)
		PrototypeIsland.add_label(
			root, sign.position + Vector3(0.0, SIGN_HEIGHT + 1.0, 0.0), sign.text
		)


## 進行が変わった（寄り道のワールドの入口を見つけた）ときに、ポータルの開き方を作り直す。
static func refresh_portals(world: Node3D, state: OverworldState) -> void:
	var root := world.get_node_or_null("OverworldDressing")
	if root == null:
		return
	for portal: OverworldPortal in root.find_children("Portal_*", "OverworldPortal", false, false):
		var open := state.is_stage_open(portal.spec.stage_id)
		if portal.spec.open != open:
			portal.spec.open = open
			portal.refresh()


## 広場は広いので、霧を薄くして遠くの地方まで見えるようにする（島の霧は近くの島に合わせた濃さ）。
## 空と霧の色は島と同じ（WorldLook）。色だけ少し鮮やかにする（環境は広場の島ごとに作り直すので、ほかの島には
## 影響しない）。
static func _soften_fog(world: Node) -> void:
	for node in world.find_children("*", "WorldEnvironment", false, false):
		var env := (node as WorldEnvironment).environment
		env.fog_density = 0.0016
		env.adjustment_saturation = 1.12


## 建物に動く部分（風車の羽根など）のアニメーションがあれば、繰り返し再生する。
static func _play_loops(model: Node) -> void:
	var found := model.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return
	var player := found[0] as AnimationPlayer
	for clip: StringName in player.get_animation_list():
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		player.play(clip)
		return
