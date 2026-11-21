class_name NatureTuning
extends RefCounted
## 風・氷・水の仕掛けと、重い・浮く・泳ぐの調整値（どれも仮値。プレイテストで見直す。docs/adr/0015）。
## Tuning と分けたのは、並行で仕掛けを作る別の作業と同じ場所を書き換えないため。

# 風
## 風がプレイヤー・生き物を押す速さ（m/秒）。歩く速さ 5 より遅いので、逆らえば遅くても進める。
const WIND_STRENGTH: float = 3.0
## 風・流れがブロックと落ちている器を 1 マス運ぶ間隔（秒）。
const DRIFT_PERIOD: float = 0.9

# 氷
## 氷の上で、自分の速さを望む速さへ寄せる加速度（m/秒²）。小さいほど止まれない。
const ICE_GRIP: float = 2.0
## 氷の上をすべるブロックの 1 マスの時間（秒）。ふつうの 1 マス（0.45 秒）より速い。
const ICE_STEP_DURATION: float = 0.3

# 水
## 水面は水のセルの上面よりこれだけ低い（浮いたブロックの上面が岸の地面とそろう）。
const WATER_FREEBOARD: float = 0.2
## 浮いている・泳いでいる人の足が、水面からこれだけ下（頭は水の上に出る）。
const AFLOAT_DEPTH: float = 0.45
## 水に浮く力で上へ戻す速さの上限（m/秒）。跳んだ勢い（約 5 m/秒）は打ち消さない。
const SURFACE_PUSH: float = 4.0
## 水に入ったときの落ちる速さの上限（m/秒。浮く人が飛び込んでも、ゆっくり沈んでから浮かぶ）。
const WATER_DRAG_FALL: float = 2.0
## 泳げない・重い人が沈む速さ（m/秒）。水の底は無い（底なしの谷と同じ）ので、沈むと落ちたのと同じ扱い。
const SINK_SPEED: float = 6.0
## 沈むブロックの落ちる速さの上限（m/秒。見た目でゆっくり沈む）。
const BLOCK_SINK_SPEED: float = 3.0
## 泳ぐ ×1 の水の中の速さ（m/秒）。×n で n 倍。流れ（既定 3 m/秒）に ×1 では逆らえない。
const SWIM_SPEED: float = 2.5
## 流れの既定の速さ（m/秒）。
const CURRENT_SPEED: float = 3.0

# 浮く
## 浮く ×1 の、落ちる速さの上限（m/秒）。×n で 1/n（n 倍ゆっくり落ち、同じ高さから n 倍遠くへ渡れる）。
const FLOAT_FALL_SPEED: float = 1.6


## 浮く強さ level のときの落ちる速さの上限（浮かなければ INF）。
static func fall_limit(level: int) -> float:
	if level <= 0:
		return INF
	return FLOAT_FALL_SPEED / Tuning.stack_factor(level)
