class_name OverworldDressing
extends RefCounted
## 広場（オーバーワールド）の見た目を StageWorld に置く: ポータル・寄り道の門・住む生き物・建物・置物・
## 立て札。データは OverworldLayout（Overworld が OverworldState から作る）。どれも当たり判定を持たない。

const SIGN_HEIGHT: float = 1.6
## 置物をまとめて描く区画の大きさ（マス）。同じモデルの置物は、この区画ごとに 1 つの MultiMesh にする
## （広場の置物は約 330 個・約 1200 の面で、1 つずつのノードだと描画の呼び出しが面の数だけ要った。
## 区画に分けるのは、カメラ・影の範囲の外の区画を描かないため。2026-11-24 の性能の測定）。
const PROP_BATCH: float = 32.0


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
	# 動く部分（風車の羽根など）のあるモデルはノードのまま、ほかは MultiMesh にまとめる
	var batches: Dictionary = {}
	for spec in layout.props:
		var size := spec.size if spec.size != Vector3.ZERO else Vector3.ONE * spec.scale
		# Node3D の rotation と scale と同じ順（向きを変えてから、モデルの軸ごとに伸ばす）
		var place := Transform3D(
			Basis(Vector3.UP, spec.yaw) * Basis.from_scale(size), spec.position
		)
		if spec.building and not ModelLibrary.parts(spec.model).is_empty():
			# 動く部分の無い建物もまとめて描き、どこに建ったかは空の目印のノードで残す
			var marker := Node3D.new()
			marker.name = "Building_%s" % spec.model
			marker.transform = place
			props.add_child(marker)
		if not ModelLibrary.parts(spec.model).is_empty():
			var key := (
				"%s_%d_%d"
				% [
					spec.model,
					floori(spec.position.x / PROP_BATCH),
					floori(spec.position.z / PROP_BATCH)
				]
			)
			if not batches.has(key):
				batches[key] = [spec.model, []]
			(batches[key][1] as Array).append(place)
			continue
		var model := ModelLibrary.instantiate(spec.model)
		model.transform = place
		if spec.building:
			model.name = "Building_%s" % spec.model
			_play_loops(model)
		props.add_child(model)
	for key: String in batches:
		var batch := batches[key] as Array
		_add_batch(props, String(batch[0]), key, batch[1] as Array)
	for sign in layout.signs:
		var post := ModelLibrary.instantiate("hub_lamp")
		post.position = sign.position
		root.add_child(post)
		PrototypeIsland.add_label(
			root, sign.position + Vector3(0.0, SIGN_HEIGHT + 1.0, 0.0), sign.text
		)


## 同じモデルの置物をまとめて 1 つの MultiMesh で描く（モデルの部品ごとに 1 つ）。
static func _add_batch(props: Node3D, model_name: String, label: String, places: Array) -> void:
	var index := 0
	for part: Array in ModelLibrary.parts(model_name):
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = part[0] as Mesh
		multimesh.instance_count = places.size()
		for i in places.size():
			multimesh.set_instance_transform(
				i, (places[i] as Transform3D) * (part[1] as Transform3D)
			)
		var view := MultiMeshInstance3D.new()
		view.name = "Batch_%s_%d" % [label, index]
		view.multimesh = multimesh
		view.set_meta(&"prop_instances", places.size() if index == 0 else 0)
		if not bool(part[2]):
			view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		props.add_child(view)
		index += 1


## 置いた置物の数（ノードの置物と、MultiMesh で並べた置物。テスト用）。
static func prop_count(dressing: Node) -> int:
	var count := 0
	for child in dressing.get_node("Props").get_children():
		var batch := child as MultiMeshInstance3D
		if batch == null:
			count += 1 if child.get_child_count() > 0 else 0  # 建物の目印（空のノード）は数えない
		else:
			count += int(batch.get_meta(&"prop_instances", 0))
	return count


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
