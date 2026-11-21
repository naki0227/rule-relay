class_name Tuning
extends RefCounted
## 操作感の調整値。企画書で確定していない値はすべて仮値で、プレイテストで見直す。

# 物理レイヤー（project.godot の layer_names と対応）
const LAYER_TERRAIN: int = 1
const LAYER_BLOCKS: int = 2
const LAYER_PLAYER: int = 4
const LAYER_TRIGGERS: int = 8
const LAYER_CREATURES: int = 16
## 仲間のアバター（通信で位置を受け取る操り人形）。照準で狙えるが、ぶつからない。
const LAYER_AVATARS: int = 32

# 重力はプレイヤーとブロックで同じにする。乗っている間に足場から離れないため。
const GRAVITY: float = 20.0

# プレイヤー（仮値）
const PLAYER_SPEED: float = 5.0
const PLAYER_JUMP_HEIGHT: float = 1.3  # 1ブロックの段差を登れ、2ブロックは登れない
const STEP_ASSIST_HEIGHT: float = 0.4  # 企画書 4-6: P0 の初期値 0.4 ブロック
const BOOTS_JUMP_HEIGHT: float = 2.3  # ジャンプブーツ: 企画書 7「約2ブロック」。2段の段差に上がれる
const CLIMB_SPEED: float = 2.5  # クライミンググローブで壁を登る速さ（m/秒）
const DASH_CELLS: int = 3  # ダッシュの基礎距離（マス）。n 個持てば 3n マス（仮値）
const DASH_SPEED: float = 14.0  # ダッシュの速さ（m/秒、仮値）
const FALL_LIMIT_Y: float = -12.0
## いちばん低い床（谷底）の上面。これより下にあるブロックは「落ちている途中」とみなす。
const LOWEST_FLOOR_Y: float = -1.0

# ブロック（仮値）
const BLOCK_JUMP_HEIGHT: float = 2.5  # 乗ったプレイヤーが高さ3の高台へ移れる
const BLOCK_HIGH_JUMP_HEIGHT: float = 4.0  # 高跳びを渡したブロック（固定の強化。倍率は選べない）
const BLOCK_STEP_DURATION: float = 0.45  # W/A/S/D で1ブロック動く時間
const REPEAT_PERIOD: float = 1.4  # 繰り返しの周期。ジャンプの滞空（約1.0秒）より長くする
const SIGNAL_RADIUS: float = 6.0  # 音源の音波が届く距離（仮値。企画書 5.4 は要検証）
const SIGNAL_PULSE_PERIOD: float = 0.7  # 鳴っている鐘が音波の輪を出す間隔（見た目）
const BELL_RING_TIME: float = 5.0  # 鐘を1回鳴らすと音波が出ている時間（仮値）
const THROW_SPEED: float = 7.0  # 投げた玉の水平の速さ（m/秒）

# 付与（仮値）
const TOUCH_REACH: float = 3.5
const THROW_REACH: float = 20.0
## 落ちている器を F で拾える距離（足もとからの距離）
const PICKUP_REACH: float = 1.8
## この距離まで生き物に近づくと、その願いの一文を出す（狙ったときも出す）。
const WISH_NEAR: float = 4.0


## 同じ能力を n 個持ったときの効果の倍率（2026-11-19 本人確定: 数に比例して強まる）。
## ジャンプは到達高度が n 倍（初速は √n 倍）、移動は速さが n 倍、投げるは射程が n 倍。
## 上限は付けない（2026-11-20 本人の決定。人数が4人までなので、補助を除けば最大 ×4）。クリアは
## 「生きている全員がゴールに集まる」なので、×4 で1人だけ跳んでもクリアしない（docs/adr/0011 決定 11）。
static func stack_factor(count: int) -> float:
	return float(maxi(count, 1))


static func jump_velocity(height: float) -> float:
	return sqrt(2.0 * GRAVITY * height)
