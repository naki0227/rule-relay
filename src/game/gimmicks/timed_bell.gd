class_name TimedBell
extends Bell
## 時の鐘（docs/adr/0014）。鳴る時間（ring_time）を決められる鐘。ほかは鐘（Bell）と同じで、
## F・投げた玉で鳴り、信号の方式・扉の源・ACTIVATE のクリア条件に使える。
## 残り時間を見せる: 足もとの輪が鳴った瞬間に最大で、残りに合わせて縮み、終わりぎわは夕日色になる。
## 鐘の台の脇の砂時計（bell_timer.glb）は、鳴らすたびにひっくり返る（アニメーション「flip」）。
## 残り時間（remaining）は鐘と同じく WorldFrame で配られるので、参加者の画面でも同じ輪が縮む。

## 輪のいちばん大きい半径（鳴った瞬間）。
const DIAL_RADIUS: float = 1.1
## 残りがこの秒数より短いと、輪を夕日色にする（もうすぐ止まる）。
const WARN_TIME: float = 1.0

var _dial: MeshInstance3D
var _dial_material: StandardMaterial3D
var _timer_player: AnimationPlayer
var _shown_ringing: bool = false


func _ready() -> void:
	super._ready()
	for child in get_children():
		if child is KeyLabel3D:
			(child as KeyLabel3D).template = (
				"時の鐘 %.0f 秒（%s で鳴らす）" % [ring_time, InputMode.token(&"interact")]
			)
	var hourglass := ModelLibrary.instantiate("bell_timer")
	hourglass.position = Vector3(0.62, 0.0, 0.0)
	add_child(hourglass)
	_timer_player = RigPose.player_of(hourglass)
	_build_dial()


## 残りの割合（0〜1）。鳴っていなければ 0。
func remaining_fraction() -> float:
	return clampf(remaining / ring_time, 0.0, 1.0) if ring_time > 0.0 else 0.0


func ring() -> void:
	super.ring()
	_shown_ringing = true
	RigPose.play_once(_timer_player, &"flip")


func _process(_delta: float) -> void:
	var ringing := is_ringing()
	_dial.visible = ringing
	if ringing and not _shown_ringing:
		# 参加者の画面では ring() を通らないので、鳴り始めを見て砂時計を返す
		RigPose.play_once(_timer_player, &"flip")
	_shown_ringing = ringing
	if not ringing:
		return
	var r := maxf(0.05, DIAL_RADIUS * remaining_fraction())
	_dial.scale = Vector3(r, 1.0, r)
	_dial_material.albedo_color = Color(UiTheme.SUN if remaining < WARN_TIME else UiTheme.SKY, 0.85)


func _build_dial() -> void:
	_dial = MeshInstance3D.new()
	_dial.name = "Dial"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 48
	_dial.mesh = torus
	_dial_material = StandardMaterial3D.new()
	_dial_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dial_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dial.material_override = _dial_material
	_dial.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dial.position.y = 0.06
	_dial.visible = false
	add_child(_dial)
