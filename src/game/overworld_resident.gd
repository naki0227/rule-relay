class_name OverworldResident
extends Node3D
## 広場に住む生き物（クリアしたステージの、願いをかなえた生き物）。見た目だけで、当たり判定・台帳・
## ルールを持たない。家のまわりを少し歩き回り、ときどき立ち止まる。来たばかりのときは喜ぶ。
## 動きはどれも骨格のアニメーション（idle / walk / happy。art/scripts/build_cast.py）。
## 歩く先は家の位置から決まる乱数なので、協力中もどの画面でもだいたい同じ動きになる（同期はしない）。

## 種類 → モデル（art/scripts/build_cast.py）
const SPECIES: Dictionary[String, String] = {
	"wish": "creature_wish",
	"kit": "creature_kit",
	"bunny": "critter_bunny",
	"lamb": "critter_lamb",
}
## 色を変えるマテリアル（種類ごと）
const FUR: Dictionary[String, String] = {
	"wish": "Fur", "kit": "Fur", "bunny": "Fur", "lamb": "Wool"
}
const WANDER_RADIUS: float = 1.6
const SPEED: float = 0.9
const ARRIVE_CHEER: float = 2.4
## この距離より遠いと描かない（FAR_FADE の幅で薄くしてから消す）。広場には生き物が最大 57 匹住み、1 匹で
## 描画の呼び出しが約 13 回要る。体長 0.5 m ほどなので、45 m 先では 1080p で 10 ピクセルほどしかない
## （2026-11-24 の性能の測定）。
const FAR: float = 45.0
const FAR_FADE: float = 8.0

var spec: OverworldLayout.ResidentSpec
var rig: RigAnimator

var _rng := RandomNumberGenerator.new()
var _target: Vector3
var _pause: float = 0.0
var _cheer: float = ARRIVE_CHEER
var _model: Node3D


func setup(p_spec: OverworldLayout.ResidentSpec) -> void:
	spec = p_spec
	name = "Resident_%s" % spec.stage_id
	position = spec.home
	_target = spec.home
	_rng.seed = hash(spec.stage_id)
	rotation.y = _rng.randf() * TAU


func _ready() -> void:
	_model = ModelLibrary.instantiate(String(SPECIES.get(spec.species, "critter_bunny")))
	_model.rotation.y = PI  # モデルの正面（-Z）を、この節の +Z（進む向き）にそろえる
	add_child(_model)
	if spec.tint != Color.WHITE:
		ModelLibrary.tint_material(_model, String(FUR.get(spec.species, "Fur")), spec.tint)
	for node in _model.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		geometry.visibility_range_end = FAR
		geometry.visibility_range_end_margin = FAR_FADE
		geometry.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	rig = RigAnimator.new(_model)
	_pause = 0.5 + _rng.randf() * 1.5


func _physics_process(delta: float) -> void:
	if _cheer > 0.0:
		_cheer -= delta
		rig.play(RigAnimator.HAPPY)
		return
	if _pause > 0.0:
		_pause -= delta
		rig.play(RigAnimator.IDLE)
		if _pause <= 0.0:
			_pick_target()
		return
	var to := _target - position
	to.y = 0.0
	if to.length() < 0.05:
		_pause = 1.5 + _rng.randf() * 3.0
		if _rng.randf() < 0.25:
			_cheer = 1.2  # ときどき、うれしそうに跳ねる
		return
	var step := to.normalized() * minf(SPEED * delta, to.length())
	position += step
	rotation.y = lerp_angle(rotation.y, atan2(step.x, step.z), minf(1.0, delta * 8.0))
	rig.play(RigAnimator.WALK, 0.8)


func _pick_target() -> void:
	var angle := _rng.randf() * TAU
	var dist := _rng.randf_range(0.4, WANDER_RADIUS)
	_target = spec.home + Vector3(cos(angle), 0.0, sin(angle)) * dist
