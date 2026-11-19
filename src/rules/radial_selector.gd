class_name RadialSelector
extends RefCounted
## 中央の円形 UI（ホイール押し込み＋ドラッグ）で、ドラッグした向きから選択肢を決める。
## 画面座標（y が下向き）で、最初の選択肢を真上に置き、時計回りに等間隔で並べる。

## 円形 UI に並べる発動方式（企画書 5.2 の3方式）。信号は P1 まで選べない（表示はする）。
const MODES: Array[TriggerMode.Kind] = [
	TriggerMode.Kind.SINGLE_SHOT, TriggerMode.Kind.REPEAT, TriggerMode.Kind.SIGNAL
]
## これより短いドラッグは「選ばない」（誤操作で方式が変わらないように）。単位はピクセル。
const DEADZONE: float = 40.0


## index 番目の選択肢の方向（ラジアン、画面座標）。
static func option_angle(index: int, count: int) -> float:
	return -PI * 0.5 + TAU * float(index) / float(count)


## ドラッグ量 offset から選択肢の番号を返す。デッドゾーン内なら -1。
static func pick(offset: Vector2, count: int, deadzone: float = DEADZONE) -> int:
	if count <= 0 or offset.length() < deadzone:
		return -1
	var best := -1
	var best_distance := INF
	for i in count:
		var distance := absf(angle_difference(offset.angle(), option_angle(i, count)))
		if distance < best_distance:
			best_distance = distance
			best = i
	return best
