class_name Tuning
extends RefCounted
## 操作感の調整値。企画書で確定していない値はすべて仮値で、プレイテストで見直す。

# 物理レイヤー（project.godot の layer_names と対応）
const LAYER_TERRAIN: int = 1
const LAYER_BLOCKS: int = 2
const LAYER_PLAYER: int = 4
const LAYER_TRIGGERS: int = 8

# 重力はプレイヤーとブロックで同じにする。乗っている間に足場から離れないため。
const GRAVITY: float = 20.0

# プレイヤー（仮値）
const PLAYER_SPEED: float = 5.0
const PLAYER_JUMP_HEIGHT: float = 1.3  # 1ブロックの段差を登れ、2ブロックは登れない
const STEP_ASSIST_HEIGHT: float = 0.4  # 企画書 4-6: P0 の初期値 0.4 ブロック
const FALL_LIMIT_Y: float = -12.0

# ブロック（仮値）
const BLOCK_JUMP_HEIGHT: float = 2.5  # 乗ったプレイヤーが高さ3の高台へ移れる
const BLOCK_STEP_DURATION: float = 0.45  # W/A/S/D で1ブロック動く時間
const REPEAT_PERIOD: float = 1.4  # 繰り返しの周期。ジャンプの滞空（約1.0秒）より長くする

# 付与（仮値）
const TOUCH_REACH: float = 3.5
const THROW_REACH: float = 20.0


static func jump_velocity(height: float) -> float:
	return sqrt(2.0 * GRAVITY * height)
