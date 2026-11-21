class_name SummitFestival
extends Node3D
## 最終ステージ（7-6 頂の祭り）のささやかなお祝い（docs/campaign-plan.md の W7）。見た目と知らせだけで、
## 当たり判定・台帳・ルールを持たない（自由な遊びを止めない）。
## - はじめから: ゴールの窪みの四隅の外に、祭りの提灯の柱（summit_lantern。提灯が揺れる「sway」）を立てる
## - 全員がそろってクリアした瞬間（GameWorld.goal_reached。協力中も、どの画面でもクリアの知らせと一緒に届く）:
##   これまでの本編のステージで願いをかなえた生き物（CampaignPlan の枠の住む生き物。作ってあるステージの分）が、
##   ゴールの南の広場に並んで現れて喜び、特別な知らせが出る
## どの画面でも同じ定義から同じ並びで作るので、通信で同期しない（広場の住む生き物と同じ扱い）。

const NODE_NAME := "SummitFestival"
const MESSAGE := "頂の祭り！ 願いをかなえた生き物たちが、お祝いに集まってきた。ここまでの旅、おつかれさま！"
## 並べる生き物の数の上限（多すぎると頂がいっぱいになる）。
const MAX_GUESTS := 28
const COLUMNS := 7
const SPACING := 1.15
## ゴールの窪みの南の縁から、最初の列までの距離（窪みの縁に重ならない）。
const FIRST_ROW := 1.6

var goal: AABB
var guests: Array[OverworldResident] = []
var lanterns: Array[Node3D] = []
var started: bool = false

var _world: GameWorld


## world にお祝いを置く（StageDef.festival のステージで StageWorld._ready から呼ぶ）。
static func build(world: GameWorld, p_goal: AABB) -> SummitFestival:
	var festival := SummitFestival.new()
	festival.name = NODE_NAME
	festival.goal = p_goal
	festival._world = world
	world.add_child(festival)
	world.goal_reached.connect(festival.start)
	return festival


## world のお祝い（無ければ null）。
static func of(world: Node) -> SummitFestival:
	return world.get_node_or_null(NODE_NAME) as SummitFestival if world != null else null


## お祝いに来る生き物（作ってある本編のステージの枠の、住む生き物。最終ステージ自身は除く）。
static func guest_specs(p_goal: AABB) -> Array[OverworldLayout.ResidentSpec]:
	var specs: Array[OverworldLayout.ResidentSpec] = []
	var top := p_goal.position.y + 1.1  # 窪みのまわりの床（窪みの床より 1 段高い）
	var south := p_goal.end.z + FIRST_ROW
	var center_x := p_goal.get_center().x
	for w in CampaignPlan.main_worlds():
		for s in CampaignPlan.built_slots(w):
			if s.stage_id == World7Finale.SUMMIT_6 or specs.size() >= MAX_GUESTS:
				continue
			var i := specs.size()
			var spec := OverworldLayout.ResidentSpec.new()
			spec.stage_id = "festival_%s" % s.stage_id
			spec.species = s.species
			spec.tint = s.tint
			var col := float(i % COLUMNS) - float(COLUMNS - 1) * 0.5
			var row := float(i / COLUMNS)
			spec.home = Vector3(center_x + col * SPACING, top, south + row * SPACING)
			specs.append(spec)
	return specs


func _ready() -> void:
	var floor_y := goal.position.y + 1.1
	var corners: Array[Vector3] = [
		Vector3(goal.position.x - 1.5, floor_y, goal.position.z - 0.5),
		Vector3(goal.end.x + 1.5, floor_y, goal.position.z - 0.5),
		Vector3(goal.position.x - 1.5, floor_y, goal.end.z + 0.5),
		Vector3(goal.end.x + 1.5, floor_y, goal.end.z + 0.5),
	]
	for at in corners:
		var lantern := ModelLibrary.instantiate("summit_lantern")
		lantern.position = at
		add_child(lantern)
		lanterns.append(lantern)
		_play_loop(lantern, &"sway")


## 全員がそろってクリアした（一度だけ）。生き物を並べ、特別な知らせを出す。
func start() -> void:
	if started:
		return
	started = true
	for spec in guest_specs(goal):
		var guest := OverworldResident.new()
		guest.setup(spec)
		add_child(guest)
		guests.append(guest)
	if _world != null:
		_world.message_posted.emit(MESSAGE)
		_world.sound_requested.emit(&"bell", goal.get_center(), false)


static func _play_loop(model: Node, clip: StringName) -> void:
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var player := players[0] as AnimationPlayer
	if player.has_animation(clip):
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		player.play(clip)
