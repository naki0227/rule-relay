class_name WarpStone
extends Node3D
## ワープの石（docs/adr/0014）。床のセル 1 つに貼りつく平たい石で、当たり判定は持たない。
## 乗ったもの（プレイヤー・ブロック・生き物）を相手の石（partner）へ移す。移す判断はホスト（MechanismSet）。
## 見た目: 浮かぶ結晶がゆれる「hover」（繰り返し）と、移したときに光って跳ねる「warp」（warp_stone.glb）。
## 光った回数 flashes を WorldFrame で配り、参加者の画面でも同じ石が光る。

const MODEL := "warp_stone"
const STAND_TOLERANCE: float = 0.35

var spec: MechanismSpecs.WarpSpec
## 移した（光った）回数。参加者は増えたら光らせる。
var flashes: int = 0

var _player: AnimationPlayer


func setup(p_spec: MechanismSpecs.WarpSpec) -> void:
	spec = p_spec
	name = "Warp_%s" % spec.key
	position = floor_point() + Vector3(0.0, 0.005, 0.0)


func _ready() -> void:
	var model := ModelLibrary.instantiate(MODEL)
	add_child(model)
	_player = RigPose.player_of(model)
	if _player != null:
		_player.animation_finished.connect(func(_clip: StringName) -> void: _hover())
	_hover()
	var text := "ワープの石" if spec.partner != "" else "ワープの石（出口）"
	PrototypeIsland.add_label(self, Vector3(0.0, 1.15, 0.0), text)


## 移した先に立つ位置（セルの床の中心）。
func floor_point() -> Vector3:
	return Vector3(spec.cell.x + 0.5, spec.cell.y, spec.cell.z + 0.5)


func covers(feet: Vector3) -> bool:
	return (
		floori(feet.x) == spec.cell.x
		and floori(feet.z) == spec.cell.z
		and absf(feet.y - spec.cell.y) <= STAND_TOLERANCE
	)


## 移したとき（ホスト）。光る回数を数え、光らせる。
func flash() -> void:
	flashes += 1
	show_flash()


func show_flash() -> void:
	RigPose.play_once(_player, &"warp")


func _hover() -> void:
	RigPose.loop(_player, &"hover")
