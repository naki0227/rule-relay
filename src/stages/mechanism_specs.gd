class_name MechanismSpecs
extends RefCounted
## スイッチの仕掛けの定義（StageDef.mechanisms。純粋なデータ。docs/adr/0014）。
## 重さの板・スイッチの扉・レバー・時の鐘・ワープの石。組み立ては MechanismSet（src/game/gimmicks/）が行う。
##
## 座標は StageDef と同じ（1 ブロック = 1m、北 = -Z）。「床のセル」は、その上面に立つセル（地面の上面が
## y = 0 なら y = 0 のセル）。板・石は床に貼りつく薄い置物で当たり判定を持たない（ブロック・生き物の道を変えない）。
## 扉だけが当たり判定（地形と同じ層）を持ち、開くと床へ沈む。
##
## 信号の源（扉の sources に書ける key）: 板・レバー・時の鐘・StageDef.bells の鐘。
## 板とレバーは signal_radius > 0 なら、作動中は鐘と同じ「音波」も出す（信号の方式で渡したブロックが動く）。

## 扉の開き方。
enum DoorMode {
	## 源が作動している間だけ開く（鐘・板から離れると閉まる）
	HELD,
	## 源が作動し始めるたびに、開く ↔ 閉じるが切り替わる（持続）
	TOGGLE,
}

var plates: Array[PlateSpec] = []
var doors: Array[DoorSpec] = []
var levers: Array[LeverSpec] = []
var timed_bells: Array[TimedBellSpec] = []
var warps: Array[WarpSpec] = []


## 重さの板: footprint（床のセルから x・z へ size）に、立っている重さの合計が required_weight 以上の間、押される。
## 重さは、プレイヤー・ブロック・生き物がどれも 1（「重い」は別の作業で足す。docs/adr/0014）。
class PlateSpec:
	var key: String
	var cell: Vector3i
	var size: Vector2i = Vector2i.ONE
	var required_weight: int = 1
	## 0 なら扉を動かすだけ。正なら押されている間、この半径に音波を出す（押し続ける鐘）。
	var signal_radius: float = 0.0

	func _init(p_key: String, p_cell: Vector3i) -> void:
		key = p_key
		cell = p_cell


## スイッチの扉: cell（最小の角のセル）から size の箱。開くと高さ分だけ床へ沈む。
## sources のどれか（require_all なら全部）が作動していることを「入力」とする。
## inverted なら、入力が無いときに開いていて、入力で閉じる。
## 閉じる途中・閉じる前に、閉じた箱の中に誰か（プレイヤー・ブロック・生き物）がいれば、出るまで待つ（挟まない）。
class DoorSpec:
	var key: String
	var cell: Vector3i
	var size: Vector3i = Vector3i(1, 2, 1)
	var sources: PackedStringArray = PackedStringArray()
	var mode: DoorMode = DoorMode.HELD
	var require_all: bool = false
	var inverted: bool = false

	func _init(p_key: String, p_cell: Vector3i, p_sources: PackedStringArray) -> void:
		key = p_key
		cell = p_cell
		sources = p_sources


## レバー: 近くで F を押すと、入る ↔ 切れるが切り替わる（持続）。
class LeverSpec:
	var key: String
	var position: Vector3
	var start_on: bool = false
	var signal_radius: float = 0.0

	func _init(p_key: String, p_position: Vector3) -> void:
		key = p_key
		position = p_position


## 時の鐘: 鳴る時間を決められる鐘（Bell）。鳴っている間は足もとの輪が縮んで残りを見せる。
## 信号の方式・扉の源・ACTIVATE のクリア条件のどれにも、ふつうの鐘と同じように使える。
class TimedBellSpec:
	var key: String
	var position: Vector3
	var ring_time: float = 3.0

	func _init(p_key: String, p_position: Vector3, p_ring_time: float = 3.0) -> void:
		key = p_key
		position = p_position
		ring_time = p_ring_time


## ワープの石: 床のセル 1 つ。乗ったもの（プレイヤー・ブロック・生き物）を partner の石へ移す。
## partner が空なら出口だけの石。互いを partner にすれば往復できる。
class WarpSpec:
	var key: String
	var cell: Vector3i
	var partner: String = ""

	func _init(p_key: String, p_cell: Vector3i, p_partner: String = "") -> void:
		key = p_key
		cell = p_cell
		partner = p_partner


func is_empty() -> bool:
	return (
		plates.is_empty()
		and doors.is_empty()
		and levers.is_empty()
		and timed_bells.is_empty()
		and warps.is_empty()
	)


## 仕掛けの key（定義の順）。
func keys() -> PackedStringArray:
	var result := PackedStringArray()
	for p in plates:
		result.append(p.key)
	for d in doors:
		result.append(d.key)
	for l in levers:
		result.append(l.key)
	for b in timed_bells:
		result.append(b.key)
	for w in warps:
		result.append(w.key)
	return result


## 扉の源になれる key（板・レバー・時の鐘と、ステージの鐘 bell_keys）。
func source_keys(bell_keys: PackedStringArray) -> PackedStringArray:
	var result := bell_keys.duplicate()
	for p in plates:
		result.append(p.key)
	for l in levers:
		result.append(l.key)
	for b in timed_bells:
		result.append(b.key)
	return result


## 定義の矛盾（StageDef.problems から呼ぶ）。taken はステージの他の key（ブロック・生き物・鐘）。
func problems(taken: PackedStringArray, bell_keys: PackedStringArray) -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	for key in taken:
		seen[key] = true
	for key in keys():
		if seen.has(key):
			errors.append("key %s is used twice" % key)
		seen[key] = true
	var sources := source_keys(bell_keys)
	for d in doors:
		if d.sources.is_empty():
			errors.append("door %s has no source" % d.key)
		for s in d.sources:
			if not sources.has(s):
				errors.append("door %s listens to unknown source %s" % [d.key, s])
		if d.size.x < 1 or d.size.y < 1 or d.size.z < 1:
			errors.append("door %s has an empty size" % d.key)
	for p in plates:
		if p.required_weight < 1 or p.size.x < 1 or p.size.y < 1:
			errors.append("plate %s needs a weight and a size" % p.key)
	for b in timed_bells:
		if b.ring_time <= 0.0:
			errors.append("timed bell %s needs a ring time" % b.key)
	var warp_keys := PackedStringArray()
	for w in warps:
		warp_keys.append(w.key)
	for w in warps:
		if w.partner == w.key or (w.partner != "" and not warp_keys.has(w.partner)):
			errors.append("warp %s has a bad partner %s" % [w.key, w.partner])
	return errors
