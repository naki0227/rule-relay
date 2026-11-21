class_name PortalReturn
extends RefCounted
## 広場へ戻ったときに立つ場所（docs/adr/0020。PartyDirector が持つ）。
## - ステージから戻ったら（クリア・メニューの「広場へもどる」・投票のどれでも）、入ったステージのポータルの前に、
##   ポータルに背を向けて（広場の側を向いて）立つ。4 人は出現地点と同じ 1 m おきに横へ並ぶ
## - 立ち位置はポータルの場所と向きと地形だけで決まる（PortalSpots）。広場が育って建物が建っても同じ
## - 戻ってから GRACE 秒は、そのポータルに入り直さない（クリアの直後の連打で、また入らないように）。
##   立ち位置は入口の箱の外なので、もともと一歩も動かずに入り直すことはない
## - 最後に入ったステージは自分の進行に保存し（PlayerProgress.last_portal）、次に起動したときも、
##   そのポータルが開いていればその前から始める
## 協力中はホストが決め、参加者の画面へは PartyDirector._moved で位置と向きを送る。

## 戻ってから、戻ったポータルに入り直せるようになるまでの秒数。
const GRACE: float = 1.5

## 次に広場へ戻ったときに前に立つポータル（最後に入ったステージ）。
var portal: String = ""
## いまの広場での立ち位置（4 人分）と向き。ポータルの前に戻ったときだけ入る（空なら出現地点）。
var spots: Array[Vector3] = []
var yaw: float = NAN
## 戻ったポータルと、入り直せるようになるまでの残り秒数。
var grace_portal: String = ""
var grace_left: float = 0.0


## 新しい島（def）での立ち位置を決める。ステージから戻った（from_stage）なら、入ったステージのポータルの前。
## 起動して最初の広場（first_visit）なら、前回最後に入ったステージのポータルが開いていればその前。
func choose(def: StageDef, from_stage: bool, first_visit: bool) -> void:
	spots = []
	yaw = NAN
	grace_portal = ""
	grace_left = 0.0
	if def.overworld == null or portal == "" or not (from_stage or first_visit):
		return
	var spec := def.overworld.portal(portal)
	if spec == null or spec.returns.size() < StageDef.MAX_PLAYERS:
		return
	if first_visit and not spec.open:
		return
	spots = spec.returns.duplicate()
	yaw = spec.return_yaw  # ポータルに背を向けて広場の側を見る
	grace_portal = portal
	grace_left = GRACE


## 入ったステージを覚え、進行にも書く。進行が変わったら true（呼び出し側が保存する）。
func remember(stage_id: String, progress: PlayerProgress) -> bool:
	portal = stage_id
	return progress.set_last_portal(stage_id)


## その人の立ち位置（ポータルの前に戻っていなければ fallback ＝ 出現地点）。
func spot_for(player_id: int, fallback: Vector3) -> Vector3:
	if spots.size() < StageDef.MAX_PLAYERS:
		return fallback
	return spots[clampi(player_id - RuleLedger.PLAYER_ID, 0, StageDef.MAX_PLAYERS - 1)]


## そのポータルに、いまは入り直さないか（戻ったばかり）。
func blocks(stage_id: String) -> bool:
	return stage_id == grace_portal and grace_left > 0.0


func tick(delta: float) -> void:
	grace_left = maxf(0.0, grace_left - delta)


## 自分の体と視点を向ける（NAN なら何もしない）。
static func face(world: GameWorld, toward: float) -> void:
	if is_nan(toward) or world == null or world.player == null:
		return
	world.player.face(toward)
	world.player.view_yaw = toward
	if world.camera_rig != null:
		world.camera_rig.yaw = toward
