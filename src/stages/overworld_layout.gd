class_name OverworldLayout
extends RefCounted
## 広場（オーバーワールド）の見た目と小さな発見の置き場所（純粋なデータ。Overworld が作り、
## OverworldDressing がノードにする）。どれも当たり判定やルールを持たない（地形・ブロック・鐘は StageDef）。

var portals: Array[PortalSpec] = []
## 寄り道のワールドの入口（まだステージが無いので、閉じた門だけ）
var teasers: Array[TeaserSpec] = []
## クリアしたステージの生き物（広場に住む）
var residents: Array[ResidentSpec] = []
## 建物・木・草花などの置物
var props: Array[PropSpec] = []
## 小さな発見（入ると知らせが出るだけ）
var secrets: Array[SecretSpec] = []
## 立て札（地方の名前・閉じた道の説明）
var signs: Array[SignSpec] = []


class PortalSpec:
	var stage_id: String
	var label: String
	var title: String
	var target_minutes: int
	var position: Vector3
	var facing: float
	var open: bool
	var cleared: bool
	var hard: bool
	var first: bool = false
	## はじまりの草原（W1）で次に遊ぶステージ（開いていて、まだクリアしていない最初の枠）。光の柱で示す
	## （docs/w1-teaching.md。初めての人が広場で迷わないように。W1 をクリアしきったら、どの門にも付かない）。
	var next: bool = false
	## ステージから戻ったときに立つ場所（4 人分。ポータルの前、入口の箱の外。PortalSpots）と、そこで向く向き
	## （ポータルに背を向けて広場の側）。空なら出現地点へ戻す。
	var returns: Array[Vector3] = []
	var return_yaw: float = PI
	## 戻ったときに体と視点を向ける向き（PortalSpots.view_yaw）。視点のカメラがポータルの門に入り込まず、
	## 門が人の横に見える向き（「いまこの門から出てきた」）。広場の側を向くのは return_yaw と同じ。
	var return_view_yaw: float = PI


class TeaserSpec:
	var title: String
	var position: Vector3
	var facing: float = PI


class ResidentSpec:
	var stage_id: String
	var species: String
	var tint: Color
	var home: Vector3


class PropSpec:
	var model: String
	var position: Vector3
	var yaw: float
	var scale: float = 1.0
	## 0 でなければ、軸ごとの大きさ（島の底の岩を地方の大きさに合わせる）
	var size: Vector3 = Vector3.ZERO
	## クリアで建った建物か（テスト・スクリーンショットで見分ける）
	var building: bool = false

	func _init(p_model: String, at: Vector3, p_yaw: float, p_scale: float = 1.0) -> void:
		model = p_model
		position = at
		yaw = p_yaw
		scale = p_scale


class SecretSpec:
	var key: String
	var area: AABB
	var text: String

	func _init(p_key: String, p_area: AABB, p_text: String) -> void:
		key = p_key
		area = p_area
		text = p_text


class SignSpec:
	var position: Vector3
	var text: String

	func _init(at: Vector3, p_text: String) -> void:
		position = at
		text = p_text


## 次に遊ぶとよいポータル（広場へ戻ったとき、体と視点をこれへ向ける。PortalSpots.face_next）。
## はじまりの草原の「つぎはここ」（next。光の柱の門）があればそれ。無ければ、本編のワールドの順で、開いていて
## まだクリアしていない最初のポータル。どれも無ければ null。
func recommended() -> PortalSpec:
	for p in portals:
		if p.next:
			return p
	for p in portals:
		var slot := CampaignPlan.slot(p.stage_id)
		if slot == null or not p.open or p.cleared:
			continue
		var world := CampaignPlan.world(slot.world_id)
		if world != null and not world.optional:
			return p
	return null


func portal(stage_id: String) -> PortalSpec:
	for p in portals:
		if p.stage_id == stage_id:
			return p
	return null


func resident(stage_id: String) -> ResidentSpec:
	for r in residents:
		if r.stage_id == stage_id:
			return r
	return null


func buildings() -> Array[PropSpec]:
	var result: Array[PropSpec] = []
	for p in props:
		if p.building:
			result.append(p)
	return result
