class_name RigAnimator
extends RefCounted
## 骨格付きのモデル（art/scripts/rig.py で作った glb）のアニメーションを、状態に合わせて切り替える係。
## 手足をコードで振らず、Blender で作ったアニメーション（idle / walk / happy、プレイヤーは jump・throw も）を
## AnimationPlayer で再生する（2026-11-21 本人の指示）。切り替えは少し重ねてなめらかにする。

const IDLE := &"idle"
const WALK := &"walk"
const JUMP := &"jump"
const HAPPY := &"happy"
## 1 回だけ再生する動き（プレイヤーの投げる。docs/adr/0017）。
const THROW := &"throw"
## 願いを持つ生き物の待っている間のしぐさ（1 回だけ。見回す・その場で跳ねる。docs/adr/0019）。
const LOOK := &"look"
const HOP := &"hop"
## 繰り返す動き（Blender 側は 1 周ぶんだけ作るので、ここでループにする）。
const LOOPED: Array[StringName] = [IDLE, WALK, HAPPY]
const BLEND: float = 0.18

var player: AnimationPlayer
var current: StringName = &""


## model の中の AnimationPlayer を使う。無ければ何もしない（古いモデル・テスト用の空の木）。
func _init(model: Node) -> void:
	if model == null:
		return
	var found := model.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		return
	player = found[0] as AnimationPlayer
	for clip in LOOPED:
		if player.has_animation(clip):
			player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	play(IDLE)


func has(clip: StringName) -> bool:
	return player != null and player.has_animation(clip)


## clip を再生する（同じなら速さだけ変える）。speed は再生の速さの倍率。
func play(clip: StringName, speed: float = 1.0) -> void:
	if not has(clip):
		return
	if clip != current:
		current = clip
		player.play(clip, BLEND)
	player.speed_scale = speed


## clip を最初から 1 回だけ再生する（同じ clip の途中でも頭から）。
func play_once(clip: StringName) -> void:
	if not has(clip):
		return
	current = clip
	player.play(clip, 0.06)
	player.seek(0.0, true)
	player.speed_scale = 1.0


## 歩きの見た目: 空中なら jump、進んでいれば速さに合わせた walk、止まっていれば idle。
func move(speed: float, grounded: bool) -> void:
	if not grounded and has(JUMP):
		play(JUMP)
	elif speed > 0.05:
		play(WALK, clampf(speed, 0.4, 1.6))
	else:
		play(IDLE)
